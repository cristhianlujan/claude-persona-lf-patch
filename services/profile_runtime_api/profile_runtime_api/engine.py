from __future__ import annotations

import json
import time
from typing import Any

from jsonschema import Draft202012Validator

from .cache import StructuralCache
from .deployment import deployment_state
from .hashing import canonical_json_sha256, sha256_text
from .llama import (
    LlamaHTTPClient,
    LlamaTransportError,
    PersistentLlamaServerAdapter,
    PersistentLlamaServerVerifier,
    UI_PRODUCTION_SEMANTIC_TRANSPORT_VERSION,
    UI_PRODUCTION_SEMANTIC_TRANSPORT_VERSION_V2,
    decode_ui_production_transport,
    generate_research_baseline_snapshot,
)
from .models import (
    ArtifactSetExecuteRequest,
    BatchRequest,
    ExecuteRequest,
    ProfileTask,
    QueueExecuteRequest,
    ResearchBaselineRequest,
)
from .repository import RepositoryBindings
from .runtime_authority import resolve_typed_runtime_context
from .settings import Settings
from .structural import PreparedContext, StructuralContextPipeline
from .ui_semantic_quality import apply_ui_production_semantic_quality_v1
from .validation import OutputGates

RESULT_SCHEMA = "lf-profile-runtime-api-result/v1"


def _failure(exc: BaseException) -> tuple[str, str | None]:
    current: BaseException | None = exc
    seen: set[int] = set()
    fallback = type(exc).__name__.upper()
    selected: tuple[str, str | None] | None = None
    while current is not None and id(current) not in seen:
        seen.add(id(current))
        code = getattr(current, "code", None)
        if isinstance(code, str) and code:
            detail = getattr(current, "detail", None)
            selected = (code, str(detail)[:500] if detail else None)
        current = current.__cause__ or current.__context__
    return selected or (fallback, None)


def _not_evaluated(code: str) -> dict[str, Any]:
    return {"status": "NOT_EVALUATED", "blocking_codes": [code], "downstream_authorized": False}


def _snapshot_binding_paths(contract: dict[str, Any]) -> dict[str, list[str]]:
    raw = contract.get("snapshot_binding_paths") or {}
    if not isinstance(raw, dict):
        raise LlamaTransportError("RESEARCH_BASELINE_SNAPSHOT_BINDING_PATHS_INVALID")
    result: dict[str, list[str]] = {}
    for source, path in raw.items():
        if source not in {"input_digest", "profile_source_digest", "evidence_refs", "capture_stage"}:
            raise LlamaTransportError("RESEARCH_BASELINE_SNAPSHOT_BINDING_SOURCE_INVALID")
        if (
            not isinstance(path, list)
            or not path
            or len(path) > 12
            or any(not isinstance(item, str) or not item.strip() for item in path)
        ):
            raise LlamaTransportError("RESEARCH_BASELINE_SNAPSHOT_BINDING_PATH_INVALID")
        normalized = [item.strip() for item in path]
        if normalized in result.values():
            raise LlamaTransportError("RESEARCH_BASELINE_SNAPSHOT_BINDING_PATH_DUPLICATE")
        result[source] = normalized
    return result


def _schema_without_bound_paths(
    snapshot_schema: dict[str, Any], binding_paths: dict[str, list[str]]
) -> dict[str, Any]:
    projected = json.loads(json.dumps(snapshot_schema))

    def remove_leaf(node: dict[str, Any], path: list[str]) -> None:
        current = node
        for segment in path[:-1]:
            properties = current.get("properties")
            if not isinstance(properties, dict) or segment not in properties:
                raise LlamaTransportError("RESEARCH_BASELINE_SNAPSHOT_BINDING_SCHEMA_PATH_MISSING")
            child = properties[segment]
            if not isinstance(child, dict) or child.get("type") != "object":
                raise LlamaTransportError("RESEARCH_BASELINE_SNAPSHOT_BINDING_SCHEMA_PARENT_INVALID")
            current = child
        properties = current.get("properties")
        leaf = path[-1]
        if not isinstance(properties, dict) or leaf not in properties:
            raise LlamaTransportError("RESEARCH_BASELINE_SNAPSHOT_BINDING_SCHEMA_PATH_MISSING")
        properties.pop(leaf)
        required = current.get("required")
        if isinstance(required, list):
            current["required"] = [item for item in required if item != leaf]

    for path in binding_paths.values():
        remove_leaf(projected, path)
    return projected


def _inject_snapshot_binding(snapshot: dict[str, Any], path: list[str], value: Any) -> None:
    current = snapshot
    for segment in path[:-1]:
        child = current.get(segment)
        if child is None:
            child = {}
            current[segment] = child
        if not isinstance(child, dict):
            raise LlamaTransportError("RESEARCH_BASELINE_SNAPSHOT_BINDING_PARENT_INVALID")
        current = child
    current[path[-1]] = value


def _runtime_diagnostics(exc: BaseException) -> dict[str, Any] | None:
    current: BaseException | None = exc
    seen: set[int] = set()
    while current is not None and id(current) not in seen:
        seen.add(id(current))
        diagnostics = getattr(current, "diagnostics", None)
        if isinstance(diagnostics, dict) and diagnostics:
            return dict(diagnostics)
        current = current.__cause__ or current.__context__
    return None


def _post_generation_diagnostics(adapter: Any, model_raw_output: Any) -> dict[str, Any]:
    diagnostics: dict[str, Any] = {
        "usage": adapter.last_completion.get("usage", {}),
        "timings": adapter.last_completion.get("timings", {}),
        "finish_reason": adapter.last_completion.get("finish_reason") or "UNAVAILABLE",
        "generation_schema_sha256": adapter.last_completion.get("generation_schema_sha256"),
        "generation_schema_policy": adapter.last_completion.get("generation_schema_policy"),
    }
    if isinstance(model_raw_output, str):
        diagnostics.update({
            "model_raw_output": model_raw_output,
            "model_raw_output_sha256": sha256_text(model_raw_output),
            "model_raw_output_chars": len(model_raw_output),
        })
    return diagnostics


def _ui_hierarchy_depth(relations: Any) -> int:
    if not isinstance(relations, list):
        return 0
    graph: dict[str, list[str]] = {}
    for relation in relations:
        if not isinstance(relation, dict):
            continue
        parent = relation.get("parent_id")
        children = relation.get("child_ids")
        if isinstance(parent, str) and isinstance(children, list):
            graph.setdefault(parent, []).extend(
                child for child in children if isinstance(child, str) and child
            )
    best = 0
    stack: list[tuple[str, int, frozenset[str]]] = [("screen", 0, frozenset({"screen"}))]
    while stack:
        node, depth, seen = stack.pop()
        best = max(best, depth)
        for child in graph.get(node, []):
            if child not in seen:
                stack.append((child, depth + 1, seen | {child}))
    return best


def _ui_source_bindings_match(deliverable: dict[str, Any], acceptance: dict[str, Any]) -> bool:
    rows = deliverable.get("component_tree")
    if not isinstance(rows, list):
        return False
    components = {
        row.get("component_id"): row
        for row in rows
        if isinstance(row, dict) and isinstance(row.get("component_id"), str)
    }
    bindings = acceptance.get("required_source_bindings")
    if not isinstance(bindings, dict):
        return False
    for binding, expected in bindings.items():
        if not isinstance(binding, str) or "." not in binding:
            return False
        component_id, field = binding.split(".", 1)
        content = (components.get(component_id) or {}).get("content")
        if not isinstance(content, dict):
            return False
        observed = content.get(field)
        if field == "fields" and isinstance(expected, str):
            expected_value: Any = expected.split("|")
        else:
            expected_value = expected
        if observed != expected_value:
            return False
    return True


def _ui_layout_strategy_from_literal(value: str) -> str | None:
    text = " ".join(value.casefold().replace("-", " ").split())
    if any(k in text for k in ("mobile first", "mobile first priority", "prioridad mobile", "prioridad móvil")):
        return "MOBILE_PRIORITY_STACK"
    if any(k in text for k in ("three columns", "3 columns", "tres columnas", "dense cards", "tarjetas densas", "compact cards", "tarjetas compactas")):
        return "DENSE_GRID_STACK"
    if any(k in text for k in ("featured first", "featured emphasis", "destacados primero", "énfasis en destacados", "enfasis en destacados")):
        return "FEATURED_FIRST_GRID_STACK"
    if any(k in text for k in ("navigation first", "search first", "categories first", "buscador prioritario", "categorías prioritarias", "categorias prioritarias")):
        return "NAVIGATION_FIRST_GRID_STACK"
    return None


def _ui_layout_flow_matches_hierarchy(deliverable: dict[str, Any], acceptance: dict[str, Any]) -> bool:
    layout = deliverable.get("layout_grid")
    relations = deliverable.get("visual_hierarchy")
    if not isinstance(layout, dict) or not isinstance(layout.get("flow"), list) or not isinstance(relations, list):
        return False
    nested_children = {
        child
        for relation in relations
        if isinstance(relation, dict) and relation.get("parent_id") != "screen"
        for child in (relation.get("child_ids") or [])
        if isinstance(child, str)
    }
    required_order = [
        cid for cid in acceptance.get("required_component_ids") or []
        if isinstance(cid, str) and cid not in nested_children
    ]
    return layout["flow"] == required_order


def _ui_required_state_semantics_ok(state_map: Any, required_states: set[str]) -> bool:
    if not isinstance(state_map, dict) or not required_states.issubset(set(state_map)):
        return False
    for cid in required_states:
        states = state_map.get(cid)
        if not isinstance(states, dict):
            return False
        c = cid.casefold()
        if "search" in c and not {"default", "query_entered", "results_available", "no_results", "error"}.issubset(states):
            return False
        if ("navigation" in c or "category" in c) and not {"default", "selected"}.issubset(states):
            return False
        if "featured" in c and not {"populated", "empty", "source_designated", "not_source_designated"}.issubset(states):
            return False
        if (c.endswith("_cta") or "action" in c) and not {"available", "missing_source_action"}.issubset(states):
            return False
        if ("cards" in c or "collection" in c) and not {"populated", "empty"}.issubset(states):
            return False
    return True


def _deterministic_ui_outcome(
    *,
    deliverable: dict[str, Any],
    acceptance: dict[str, Any],
    composer_payload: dict[str, Any],
    strict_layout_coherence: bool = False,
    strict_semantic_repair: bool = False,
) -> dict[str, Any]:
    """Derive self-score/handoff from verifiable structure; model never self-certifies UICT2."""
    components = deliverable.get("component_tree")
    component_ids = {
        row.get("component_id") for row in components or []
        if isinstance(row, dict) and isinstance(row.get("component_id"), str)
    }
    required_ids = set(acceptance.get("required_component_ids") or [])
    required_states = set(acceptance.get("required_state_component_ids") or [])
    state_map = deliverable.get("state_map")
    risk_controls = deliverable.get("risk_controls")
    layout = deliverable.get("layout_grid")
    responsive_ok = isinstance(layout, dict) and all(
        isinstance(layout.get(mode), str) and bool(layout.get(mode).strip())
        for mode in acceptance.get("required_responsive_modes") or []
    )
    component_count_ok = (
        isinstance(components, list)
        and len(components) >= int(acceptance.get("minimum_component_count") or 0)
        and required_ids.issubset(component_ids)
    )
    variants_ok = isinstance(components, list) and all(
        isinstance(row, dict)
        and isinstance(row.get("allowed_variants"), list) and bool(row.get("allowed_variants"))
        and isinstance(row.get("blocked_variants"), list) and bool(row.get("blocked_variants"))
        for row in components
    )
    state_coverage_ok = isinstance(state_map, dict) and required_states.issubset(set(state_map))
    state_semantics_ok = _ui_required_state_semantics_ok(state_map, required_states)
    state_ok = state_coverage_ok and (state_semantics_ok if strict_semantic_repair else True)
    risk_ok = (
        isinstance(risk_controls, list)
        and len(risk_controls) >= int(acceptance.get("minimum_risk_control_count") or 0)
    )
    layout_flow_ok = (
        _ui_layout_flow_matches_hierarchy(deliverable, acceptance)
        if (strict_layout_coherence or strict_semantic_repair) else True
    )
    hierarchy_depth = _ui_hierarchy_depth(deliverable.get("visual_hierarchy"))
    minimum_hierarchy_depth = int(acceptance.get("minimum_hierarchy_depth_edges") or 0)
    minimum_risk_controls = int(acceptance.get("minimum_risk_control_count") or 0)
    binding_match = _ui_source_bindings_match(deliverable, acceptance)
    spacing_present = isinstance(deliverable.get("spacing_typography"), dict)
    hierarchy_present = isinstance(deliverable.get("visual_hierarchy"), list) and bool(deliverable.get("visual_hierarchy"))
    token_map_present = isinstance(deliverable.get("token_map"), dict) and bool(deliverable.get("token_map"))
    state_map_present = isinstance(state_map, dict) and bool(state_map)
    visual_priority_complete = isinstance(components, list) and bool(components) and all(
        isinstance(row, dict)
        and isinstance(row.get("visual_priority"), str)
        and bool(row.get("visual_priority").strip())
        and isinstance(row.get("role"), str)
        and bool(row.get("role").strip())
        for row in components
    )
    safety_text = " ".join(risk_controls).casefold() if isinstance(risk_controls, list) else ""
    lf_safety_explicit = all(token in safety_text for token in ("pressure", "urgency", "invent"))

    checks = {
        "layout_precision": responsive_ok and layout_flow_ok and spacing_present,
        "visual_hierarchy": hierarchy_depth >= minimum_hierarchy_depth and (
            visual_priority_complete if strict_semantic_repair else True
        ),
        "lf_system_fidelity": token_map_present and risk_ok and (
            lf_safety_explicit if strict_semantic_repair else True
        ),
        "state_mapping": state_ok,
        "handoff_quality": component_count_ok and variants_ok and binding_match and bool(composer_payload),
    }
    refs = {
        "layout_precision": ["layout_grid", "spacing_typography"],
        "visual_hierarchy": ["visual_hierarchy", "component_tree"],
        "lf_system_fidelity": ["token_map", "risk_controls"],
        "state_mapping": ["state_map"],
        "handoff_quality": ["component_tree", "handoff_to_next"],
    }

    def rubric_score(*, full: bool, partial: bool, minimal: bool) -> int:
        # Canonical UI Architect rubric uses 5/3/1/0. Never synthesize a constant 4.
        if full:
            return 5
        if partial:
            return 3
        if minimal:
            return 1
        return 0

    if strict_semantic_repair:
        criterion_scores = {
            "layout_precision": rubric_score(
                full=checks["layout_precision"],
                partial=responsive_ok and spacing_present,
                minimal=isinstance(layout, dict) or spacing_present,
            ),
            "visual_hierarchy": rubric_score(
                full=checks["visual_hierarchy"],
                partial=hierarchy_present and hierarchy_depth >= 1,
                minimal=hierarchy_present,
            ),
            "lf_system_fidelity": rubric_score(
                full=checks["lf_system_fidelity"],
                partial=token_map_present and isinstance(risk_controls, list) and bool(risk_controls),
                minimal=token_map_present or (isinstance(risk_controls, list) and bool(risk_controls)),
            ),
            "state_mapping": rubric_score(
                full=checks["state_mapping"],
                partial=state_coverage_ok,
                minimal=state_map_present,
            ),
            # A source-binding mismatch can expose an invented route/value downstream and therefore
            # is not a merely partial handoff; fail it closed at 0 even when the rest is structured.
            "handoff_quality": 0 if not binding_match else rubric_score(
                full=checks["handoff_quality"],
                partial=component_count_ok and bool(composer_payload),
                minimal=bool(composer_payload),
            ),
        }
    else:
        # Legacy UICT2 compatibility: historical artifacts were explicitly producer-capped at 4/5.
        # New UICT5 production runs must use the canonical 5/3/1/0 rubric above.
        criterion_scores = {key: 4 if checks[key] else 0 for key in checks}
    evidence_observed = {
        "layout_precision": {
            "responsive_modes_required": sorted(acceptance.get("required_responsive_modes") or []),
            "responsive_rules_present": responsive_ok,
            "layout_flow_matches_hierarchy": layout_flow_ok,
            "spacing_typography_present": spacing_present,
            "layout_grid_sha256": canonical_json_sha256(deliverable.get("layout_grid")),
            "spacing_typography_sha256": canonical_json_sha256(deliverable.get("spacing_typography")),
        },
        "visual_hierarchy": {
            "observed_depth_edges": hierarchy_depth,
            "required_depth_edges": minimum_hierarchy_depth,
            "visual_priority_and_roles_complete": visual_priority_complete,
            "visual_hierarchy_sha256": canonical_json_sha256(deliverable.get("visual_hierarchy")),
        },
        "lf_system_fidelity": {
            "token_map_present": token_map_present,
            "risk_controls_observed": len(risk_controls) if isinstance(risk_controls, list) else 0,
            "risk_controls_required": minimum_risk_controls,
            "lf_safety_explicit": lf_safety_explicit,
            "token_map_sha256": canonical_json_sha256(deliverable.get("token_map")),
            "risk_controls_sha256": canonical_json_sha256(deliverable.get("risk_controls")),
        },
        "state_mapping": {
            "required_state_components": sorted(required_states),
            "present_state_components": sorted(set(state_map) & required_states) if isinstance(state_map, dict) else [],
            "coverage_complete": state_coverage_ok,
            "required_state_semantics": state_semantics_ok if strict_semantic_repair else "LEGACY_COMPAT_NOT_ENFORCED",
            "state_map_sha256": canonical_json_sha256(deliverable.get("state_map")),
        },
        "handoff_quality": {
            "required_components_present": len(required_ids & component_ids),
            "required_components_total": len(required_ids),
            "variant_guards_present": variants_ok,
            "source_bindings_matched": binding_match,
            "composer_payload_present": bool(composer_payload),
            "component_tree_sha256": canonical_json_sha256(deliverable.get("component_tree")),
            "composer_payload_sha256": canonical_json_sha256(composer_payload),
        },
    }
    evidence_rules = {
        "layout_precision": "5=responsive modes + hierarchy-coherent flow + spacing/typography explicit; 3=responsive + spacing partial; 1=general layout evidence; 0=absent",
        "visual_hierarchy": "5=required hierarchy depth + explicit visual priority/role on every component; 3=explicit partial hierarchy; 1=generic hierarchy evidence; 0=absent",
        "lf_system_fidelity": "5=token map + minimum risk controls + explicit anti-invention/dark-pattern safety; 3=token+risk evidence partial; 1=generic fidelity evidence; 0=absent",
        "state_mapping": "5=required state coverage + strict semantics when applicable; 3=coverage present but semantics partial; 1=generic state evidence; 0=absent",
        "handoff_quality": "5=components + variant guards + exact source bindings + composer payload; source-binding mismatch=0 fail-closed; 3/1 only for non-source-critical partial structure",
    }
    score = dict(criterion_scores)
    score["total"] = sum(criterion_scores.values())
    score["evidence_by_criterion"] = {
        key: {
            "refs": refs[key],
            "rule": evidence_rules[key],
            "observed": evidence_observed[key],
            "result": "PASS" if checks[key] else ("PARTIAL" if criterion_scores[key] in {1, 3} else "FAIL"),
            "summary": (
                f"{('PASS' if checks[key] else ('PARTIAL' if criterion_scores[key] in {1, 3} else 'FAIL'))}: "
                f"score={criterion_scores[key]}; observed={json.dumps(evidence_observed[key], sort_keys=True, separators=(',', ':'))}"
            ),
        }
        for key in checks
    }
    passed = all(checks.values())
    return {
        "score": score,
        "handoff_to_next": {
            "recipient": "frontend_or_composer_agent",
            "payload_ref": "composer_payload",
            "status": (
                "READY_FOR_DETERMINISTIC_AND_SEMANTIC_VALIDATION"
                if passed else "BLOCKED_PENDING_REPAIR"
            ),
        },
        "self_verdict": "PASS_TO_QUALITY_PACK_CANDIDATE" if passed else "BLOCKED",
        "deterministic_acceptance": checks,
    }


def _governed_context(
    task: ProfileTask,
    prepared_pack: dict[str, Any],
    *,
    profile_sources: list[dict[str, str]],
    schema: Any,
) -> tuple[dict[str, Any], dict[str, Any]]:
    cards = [item.model_dump(mode="python") for item in task.lf_card_sources]
    adapters = [item.model_dump(mode="python") for item in task.lf_adapter_sources]
    card_receipts = [
        {"card_ref": item["card_ref"], "card_version": item["card_version"], "source_ref": item["source_ref"],
         "content_sha256": item["content_sha256"], "selected_sections": item["selected_sections"],
         "budget_chars": item["budget_chars"], "request_id": task.request_id}
        for item in cards
    ]
    adapter_receipts = [
        {"adapter_code": item["adapter_code"], "adapter_version": item["adapter_version"],
         "target_ref": item["target_ref"], "binding_ref": item["binding_ref"],
         "assurance_revision": item["assurance_revision"], "request_id": task.request_id}
        for item in adapters
    ]
    typed_context = resolve_typed_runtime_context(
        task,
        profile_sources=profile_sources,
        context_pack=prepared_pack,
        schema=schema,
    )
    pack = dict(prepared_pack)
    pack["lf_cards"] = [{k: v for k, v in item.items() if k != "content"} | {"content": item["content"]} for item in cards]
    pack["lf_card_receipts"] = card_receipts
    pack["lf_adapter_receipts"] = adapter_receipts
    pack["runtime_typed_context"] = typed_context
    governed_operation = (
        task.governed_operation.model_dump(mode="python")
        if task.governed_operation is not None
        else None
    )
    if governed_operation is not None:
        pack["governed_operation"] = governed_operation
    receipt = {
        "schema": "lf-governed-context-receipt/v2",
        "request_id": task.request_id,
        "profile_code": task.profile_code,
        "card_receipts": card_receipts,
        "adapter_receipts": adapter_receipts,
        "runtime_typed_context": typed_context,
        "runtime_typed_context_sha256": typed_context["typed_context_sha256"],
        "card_resolution": typed_context["card_resolution"],
        "authority_resolution": typed_context["authority_resolution"],
        "adapter_binding": typed_context["adapter_binding"],
        "runtime_schema": typed_context["runtime_schema"],
        "governed_operation": governed_operation,
    }
    receipt["context_fingerprint"] = canonical_json_sha256({
        "request_id": task.request_id,
        "cards": card_receipts,
        "adapters": adapter_receipts,
        "typed_context_sha256": typed_context["typed_context_sha256"],
        "structural_pack_sha256": prepared_pack.get("pack_sha256"),
    })
    return pack, receipt


class ProfileRuntimeEngine:
    def __init__(self, settings: Settings, *, llama_client: LlamaHTTPClient | None = None, cache: StructuralCache | None = None, structural_pipeline: StructuralContextPipeline | None = None) -> None:
        self.settings = settings
        self.repository = RepositoryBindings(settings.repo_root, max_prompt_chars=settings.max_prompt_chars)
        self.cache = cache or StructuralCache(settings.state_dir / "structural-cache", max_entries=settings.cache_max_entries)
        self.structural = structural_pipeline or StructuralContextPipeline(settings, self.cache)
        self.llama_client = llama_client or LlamaHTTPClient(settings)
        self.gates = OutputGates(self.repository)
        self.runner: Any = None

    def initialize(self) -> None:
        self.settings.validate(); self.repository.validate(); self.structural.validate(); self.cache.initialize(); self.runner = self.repository.load_runtime_runner()

    def run_execute(self, request: ExecuteRequest) -> dict[str, Any]:
        started = time.perf_counter()
        try:
            prepared = self.structural.prepare(request.artifact, request.input_governance)
        except Exception as exc:
            code, detail = _failure(exc); result = self._profile_failure(task=request.profile, code=code, detail=detail, stage="STRUCTURAL_CONTEXT", started=started)
        else:
            result = self._execute_profile(task=request.profile, artifact=request.artifact, prepared=prepared, context_reused_within_batch=False)
        return {"schema": RESULT_SCHEMA, "kind": "execute", "request_id": request.profile.request_id, "artifact_sha256": request.artifact.image_sha256, "result": result, "total_ms": round((time.perf_counter()-started)*1000,3), "downstream_authorized": False}

    def run_queue_execute(self, request: QueueExecuteRequest) -> dict[str, Any]:
        started=time.perf_counter(); task=request.profile
        context_pack={"schema":"lf-profile-runtime-queue-context/v1","source":"QUEUE_NATIVE_TEXT_PROFILE","screen_governance_applicable":False,"downstream_authorized":False}
        result=self._execute_queue_profile(task=task,context_pack=context_pack)
        return {"schema":RESULT_SCHEMA,"kind":"queue_execute","request_id":task.request_id,"artifact_sha256":None,"result":result,"total_ms":round((time.perf_counter()-started)*1000,3),"downstream_authorized":False}

    def run_research_baseline(self, request: ResearchBaselineRequest) -> dict[str, Any]:
        started = time.perf_counter()
        try:
            self.repository.validate_profile_identity(request.profile_slug, request.profile_code)
            sources = self.repository.profile_sources(
                request.profile_slug, request.profile_source_paths
            )
            source_manifest = [
                {"ref": item["ref"], "content_sha256": sha256_text(item["content"])}
                for item in sources
            ]
            observed_source_digest = "sha256:" + canonical_json_sha256(source_manifest)
            observed_input_digest = "sha256:" + sha256_text(request.input_literal)
            if observed_source_digest != request.profile_source_digest:
                raise LlamaTransportError(
                    "RESEARCH_BASELINE_PROFILE_SOURCE_DIGEST_MISMATCH"
                )
            if observed_input_digest != request.input_digest:
                raise LlamaTransportError("RESEARCH_BASELINE_INPUT_DIGEST_MISMATCH")
            contract = request.research_baseline_contract
            snapshot_schema = contract["snapshot_schema"]
            Draft202012Validator.check_schema(snapshot_schema)
            binding_paths = _snapshot_binding_paths(contract)
            generation_snapshot_schema = _schema_without_bound_paths(
                snapshot_schema, binding_paths
            )
            Draft202012Validator.check_schema(generation_snapshot_schema)
            evidence_refs = [
                "input:" + request.input_digest,
                "profile-source-manifest:" + request.profile_source_digest,
            ]
            deterministic_values = {
                "input_digest": request.input_digest,
                "profile_source_digest": request.profile_source_digest,
                "evidence_refs": evidence_refs,
                "capture_stage": contract["capture_stage"],
            }
            binding = self.repository.runtime_binding(request.profile_slug)
            model_sources = self.repository.profile_model_sources(request.profile_slug, sources)
            max_output_tokens = None
            if binding and isinstance(binding.execution_budget, dict):
                candidate = binding.execution_budget.get("max_output_tokens")
                if isinstance(candidate, int) and candidate > 0:
                    max_output_tokens = candidate
            generated = generate_research_baseline_snapshot(
                settings=self.settings,
                client=self.llama_client,
                profile_slug=request.profile_slug,
                profile_sources=model_sources,
                input_literal=request.input_literal,
                snapshot_schema=generation_snapshot_schema,
                capture_stage=contract["capture_stage"],
                max_output_tokens=max_output_tokens,
            )
            snapshot = generated["snapshot"]
            for source, path in binding_paths.items():
                _inject_snapshot_binding(snapshot, path, deterministic_values[source])
            validation_errors = sorted(
                Draft202012Validator(snapshot_schema).iter_errors(snapshot),
                key=lambda item: list(item.absolute_path),
            )
            if validation_errors:
                raise LlamaTransportError(
                    "RESEARCH_BASELINE_SNAPSHOT_SCHEMA_INVALID",
                    validation_errors[0].message[:300],
                )
            baseline_digest = "sha256:" + canonical_json_sha256(snapshot)
            envelope = {
                "snapshot": snapshot,
                "baseline_digest": baseline_digest,
                "capture_stage": contract["capture_stage"],
                "input_digest": request.input_digest,
                "profile_source_digest": request.profile_source_digest,
                "evidence_refs": evidence_refs,
            }
            result = {
                "status": "PASS",
                "blocking_codes": [],
                "baseline_envelope": envelope,
                "runtime_model_id": generated["model_id"],
                "usage": generated["usage"],
                "timings": generated["timings"],
                "finish_reason": generated["finish_reason"],
                "generation_schema_sha256": generated["generation_schema_sha256"],
                "generation_schema_policy": generated["generation_schema_policy"],
                "baseline_model_call_count": 1,
                "external_research_context_supplied": False,
            }
        except Exception as exc:
            code, detail = _failure(exc)
            result = {
                "status": "FAIL",
                "blocking_codes": [code],
                "detail": detail,
                "baseline_model_call_count": getattr(self.llama_client, "chat_calls", None),
                "external_research_context_supplied": False,
            }
        return {
            "schema": RESULT_SCHEMA,
            "kind": "research_baseline",
            "request_id": request.request_id,
            "result": result,
            "total_ms": round((time.perf_counter() - started) * 1000, 3),
            "downstream_authorized": False,
        }

    def run_artifact_set_execute(self, request: ArtifactSetExecuteRequest) -> dict[str, Any]:
        started = time.perf_counter()
        task = request.profile
        prepared_items: list[tuple[Any, PreparedContext]] = []
        try:
            for binding in request.artifact_set.artifacts:
                prepared_items.append(
                    (binding, self.structural.prepare(binding.artifact, request.input_governance))
                )
        except Exception as exc:
            code, detail = _failure(exc)
            result = self._profile_failure(
                task=task,
                code=code,
                detail=detail,
                stage="STRUCTURAL_CONTEXT",
                started=started,
            )
            fingerprint = canonical_json_sha256(
                {
                    "schema": request.artifact_set.contract_schema,
                    "subject_mode": request.artifact_set.subject_mode,
                    "artifacts": [
                        {
                            "artifact_ref": item.artifact_ref,
                            "artifact_sha256": item.artifact.image_sha256,
                            "width_px": item.artifact.width_px,
                            "height_px": item.artifact.height_px,
                        }
                        for item in request.artifact_set.artifacts
                    ],
                }
            )
        else:
            artifact_entries = []
            for binding, prepared in prepared_items:
                artifact_entries.append(
                    {
                        "artifact_ref": binding.artifact_ref,
                        "artifact_sha256": binding.artifact.image_sha256,
                        "width_px": binding.artifact.width_px,
                        "height_px": binding.artifact.height_px,
                        "filename": binding.artifact.filename,
                        "screen_code": binding.artifact.screen_code,
                        "structural_context": prepared.pack,
                    }
                )
            binding_summary = [
                {
                    "artifact_ref": item["artifact_ref"],
                    "artifact_sha256": item["artifact_sha256"],
                    "width_px": item["width_px"],
                    "height_px": item["height_px"],
                    "pack_sha256": item["structural_context"].get("pack_sha256"),
                }
                for item in artifact_entries
            ]
            fingerprint = canonical_json_sha256(
                {
                    "schema": request.artifact_set.contract_schema,
                    "subject_mode": request.artifact_set.subject_mode,
                    "artifacts": binding_summary,
                }
            )
            context_pack = {
                "schema": "lf-profile-runtime-artifact-set-context/v1",
                "contract": request.artifact_set.contract_schema,
                "subject_mode": request.artifact_set.subject_mode,
                "artifact_set_fingerprint": fingerprint,
                "artifact_count": len(artifact_entries),
                "artifacts": artifact_entries,
                "input_governance": {
                    "receipt_ref": request.input_governance.receipt_ref,
                    "current": request.input_governance.current,
                    "ready": request.input_governance.ready,
                    "status": request.input_governance.status,
                    "decision": request.input_governance.decision,
                    "subject_mode": request.input_governance.subject_mode,
                    "context_sha256": request.input_governance.context_sha256,
                    "required_artifact_binding": request.input_governance.required_artifact_binding,
                    "constraints": (
                        request.input_governance.constraints.model_dump(mode="python")
                        if request.input_governance.constraints is not None
                        else None
                    ),
                },
                "downstream_authorized": False,
            }
            context_pack["pack_sha256"] = canonical_json_sha256(context_pack)
            context = {
                "artifact_set_schema": request.artifact_set.contract_schema,
                "subject_mode": request.artifact_set.subject_mode,
                "artifact_set_fingerprint": fingerprint,
                "artifact_count": len(prepared_items),
                "artifacts": [
                    {
                        "artifact_ref": binding.artifact_ref,
                        "artifact_sha256": binding.artifact.image_sha256,
                        "cache_hit": prepared.cache_hit,
                        "prepare_ms": prepared.prepare_ms,
                        "pack_sha256": prepared.pack.get("pack_sha256"),
                    }
                    for binding, prepared in prepared_items
                ],
                "runtime_output_mode": task.runtime_output_mode,
            }
            result = self._execute_queue_profile(
                task=task,
                context_pack=context_pack,
                context_override=context,
            )
        return {
            "schema": RESULT_SCHEMA,
            "kind": "artifact_set_execute",
            "request_id": task.request_id,
            "artifact_set_fingerprint": fingerprint,
            "artifact_count": len(request.artifact_set.artifacts),
            "result": result,
            "total_ms": round((time.perf_counter() - started) * 1000, 3),
            "downstream_authorized": False,
        }

    def run_batch(self, request: BatchRequest) -> dict[str, Any]:
        started=time.perf_counter()
        if len(request.profiles)>self.settings.max_batch_size:
            failures=[self._profile_failure(task=t,code="BATCH_SIZE_EXCEEDS_RUNTIME_LIMIT",detail=None,stage="INPUT_GOVERNANCE",started=started) for t in request.profiles]
            return self._batch_result(request,failures,started,context=None)
        try: prepared=self.structural.prepare(request.artifact,request.input_governance)
        except Exception as exc:
            code,detail=_failure(exc); failures=[self._profile_failure(task=t,code=code,detail=detail,stage="STRUCTURAL_CONTEXT",started=started) for t in request.profiles]; return self._batch_result(request,failures,started,context=None)
        results=[self._execute_profile(task=t,artifact=request.artifact,prepared=prepared,context_reused_within_batch=i>0) for i,t in enumerate(request.profiles)]
        return self._batch_result(request,results,started,context=prepared)

    def runtime_snapshot(self) -> dict[str, Any]:
        llama = self.llama_client.health()
        state = deployment_state(self.settings)
        return {
            "schema": "lf-profile-runtime-api-snapshot/v1",
            "runtime_version": self.settings.runtime_version,
            "resolver_version": self.settings.resolver_version,
            "source_sha": self.settings.source_sha,
            "bind": {"host": self.settings.api_host, "port": self.settings.api_port},
            "llama_server": llama,
            "cache": self.cache.stats(),
            "max_workers": self.settings.max_workers,
            "max_batch_size": self.settings.max_batch_size,
            "full_image_model_enabled": self.settings.allow_model_image,
            **state,
        }

    def _materialize_runtime_output(
        self, *, task: ProfileTask, model_raw_output: Any, governed_receipt: dict[str, Any]
    ) -> tuple[Any, dict[str, Any]]:
        binding = self.repository.runtime_binding(task.profile_slug)
        if binding is not None and binding.execution_partition is not None:
            if not isinstance(model_raw_output, str):
                raise LlamaTransportError("PARTITIONED_MODEL_RAW_NOT_STRING")
            try:
                model_payload = json.loads(model_raw_output)
            except json.JSONDecodeError as exc:
                raise LlamaTransportError("PARTITIONED_MODEL_RAW_JSON_INVALID") from exc
            if not isinstance(model_payload, dict):
                raise LlamaTransportError("PARTITIONED_MODEL_RAW_ROOT_NOT_OBJECT")
            try:
                materialized_payload, added = self.repository.materialize_partitioned_output(
                    task.profile_slug, model_payload
                )
            except Exception as exc:
                code = getattr(exc, "code", "PROFILE_RUNTIME_PARTITION_MATERIALIZATION_FAILED")
                detail = getattr(exc, "detail", str(exc))
                raise LlamaTransportError(code, detail) from exc
            materialized = json.dumps(
                materialized_payload, ensure_ascii=False, separators=(",", ":")
            )
            return materialized, {
                "mode": "GENERIC_PARTITION_MATERIALIZATION_V1",
                "model_raw_output_sha256": sha256_text(model_raw_output),
                "materialized_output_sha256": sha256_text(materialized),
                "deterministic_fields_added": added,
            }
        if task.profile_slug != "ui_architect" or task.runtime_output_mode != "UI_PRODUCTION_SPEC":
            return model_raw_output, {
                "mode": "MODEL_RAW_UNCHANGED",
                "model_raw_output_sha256": sha256_text(model_raw_output) if isinstance(model_raw_output, str) else None,
                "materialized_output_sha256": sha256_text(model_raw_output) if isinstance(model_raw_output, str) else None,
                "deterministic_fields_added": [],
            }
        if not isinstance(model_raw_output, str):
            raise LlamaTransportError("UI_PRODUCTION_MODEL_RAW_NOT_STRING")
        try:
            payload = json.loads(model_raw_output)
        except json.JSONDecodeError as exc:
            raise LlamaTransportError("UI_PRODUCTION_MODEL_RAW_JSON_INVALID") from exc
        if not isinstance(payload, dict):
            raise LlamaTransportError("UI_PRODUCTION_MODEL_RAW_ROOT_NOT_OBJECT")
        model_transport_root_keys = sorted(payload)
        model_semantic_delta_keys = (
            sorted(payload["d"])
            if set(payload) == {"d"} and isinstance(payload.get("d"), dict)
            else []
        )
        acceptance = task.input_fields.get("gate_f_acceptance")
        literal_layout = _ui_layout_strategy_from_literal(task.input_literal)
        if (
            literal_layout is not None
            and payload.get("v") == 5
            and isinstance(payload.get("d"), dict)
            and "l" in payload["d"]
        ):
            payload["d"]["l"] = literal_layout
        semantic_layout_choice = (
            payload["d"].get("l")
            if payload.get("v") == 5 and isinstance(payload.get("d"), dict)
            else None
        )
        payload, transport_kind = decode_ui_production_transport(
            payload,
            acceptance if isinstance(acceptance, dict) else None,
            domain_scope=(
                task.input_fields.get("domain_scope")
                if isinstance(task.input_fields.get("domain_scope"), str)
                else None
            ),
        )

        boundary = self.repository.load_ui_composer_boundary()
        expected_version = task.input_fields.get("output_contract_version")
        if expected_version != getattr(boundary, "VERSION", None):
            raise LlamaTransportError(
                "UI_PRODUCTION_OUTPUT_CONTRACT_VERSION_MISMATCH", str(expected_version)
            )
        deliverable = payload.get("deliverable_created")
        if not isinstance(deliverable, dict):
            raise LlamaTransportError("UI_PRODUCTION_DELIVERABLE_MISSING")
        if transport_kind == UI_PRODUCTION_SEMANTIC_TRANSPORT_VERSION:
            if not isinstance(acceptance, dict) or not isinstance(semantic_layout_choice, str):
                raise LlamaTransportError("UI_PRODUCTION_SEMANTIC_QUALITY_INPUT_MISSING")
            deliverable = apply_ui_production_semantic_quality_v1(
                deliverable,
                acceptance,
                layout_choice=semantic_layout_choice,
            )
            payload["deliverable_created"] = deliverable
        composer_payload = boundary.build_composer_payload(deliverable)
        deterministic_outcome: dict[str, Any] | None = None
        if transport_kind in {UI_PRODUCTION_SEMANTIC_TRANSPORT_VERSION_V2, UI_PRODUCTION_SEMANTIC_TRANSPORT_VERSION}:
            if not isinstance(acceptance, dict):
                raise LlamaTransportError("UI_PRODUCTION_SEMANTIC_TRANSPORT_ACCEPTANCE_MISSING")
            deterministic_outcome = _deterministic_ui_outcome(
                deliverable=deliverable,
                acceptance=acceptance,
                composer_payload=composer_payload,
                strict_layout_coherence=(transport_kind == UI_PRODUCTION_SEMANTIC_TRANSPORT_VERSION),
                strict_semantic_repair=(transport_kind == UI_PRODUCTION_SEMANTIC_TRANSPORT_VERSION),
            )
        governance_context = {
            "request_id": task.request_id,
            "runtime_source_sha": self.settings.source_sha,
            "runtime_typed_context_sha256": governed_receipt.get("runtime_typed_context_sha256"),
            "input_sha256": sha256_text(task.input_literal),
        }
        for key in ("execution_mode", "policy_snapshot_sha256", "bootstrap_context_sha256"):
            value = task.input_fields.get(key)
            if value not in (None, ""):
                governance_context[key] = value
        deterministic = {
            "output_contract_version": expected_version,
            "governance_envelope": {
                "schema": getattr(boundary, "ENVELOPE_SCHEMA", "LF_UI_GOVERNANCE_ENVELOPE_V1"),
                "render_policy": "NON_RENDER",
                "context": governance_context,
            },
            "composer_payload": composer_payload,
        }
        deterministic_acceptance = None
        if deterministic_outcome is not None:
            deterministic_acceptance = deterministic_outcome.pop("deterministic_acceptance")
            deterministic.update(deterministic_outcome)
        for key, expected in deterministic.items():
            if key in payload and payload[key] != expected:
                raise LlamaTransportError("UI_PRODUCTION_DETERMINISTIC_FIELD_CONFLICT", key)
            payload[key] = expected
        errors = boundary.validate(payload)
        if errors:
            codes = ",".join(sorted({str(item.get("code")) for item in errors if isinstance(item, dict)}))
            raise LlamaTransportError("UI_PRODUCTION_DETERMINISTIC_MATERIALIZATION_INVALID", codes)
        materialized = json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
        deterministic_derivations = sorted(deterministic)
        if transport_kind in {UI_PRODUCTION_SEMANTIC_TRANSPORT_VERSION_V2, UI_PRODUCTION_SEMANTIC_TRANSPORT_VERSION}:
            deterministic_derivations = sorted(set(deterministic_derivations) | {
                "worker", "output_type", "component_ids", "source_bindings",
                "layout_base_order", "screen_task_mode", "required_sections",
                "design_intent", "risk_controls", "prompt_constraints",
                "token_map_projection", "variant_guards",
                "semantic_quality_projection_v1",
            })
        return materialized, {
            "mode": "UI_PRODUCTION_DETERMINISTIC_PROJECTION_V1",
            "model_raw_output_sha256": sha256_text(model_raw_output),
            "materialized_output_sha256": sha256_text(materialized),
            "deterministic_fields_added": sorted(deterministic),
            "deterministic_derivations": deterministic_derivations,
            "deterministic_first_policy": (
                "KNOWN_AUTHORITY_TO_GRAPH__MODEL_SEMANTIC_DELTA__DETERMINISTIC_MATERIALIZATION"
                if transport_kind in {UI_PRODUCTION_SEMANTIC_TRANSPORT_VERSION_V2, UI_PRODUCTION_SEMANTIC_TRANSPORT_VERSION}
                else "LEGACY_COMPATIBLE_MATERIALIZATION"
            ),
            "composer_payload_sha256": canonical_json_sha256(composer_payload),
            "governance_context_sha256": canonical_json_sha256(governance_context),
            "model_transport_root_keys": model_transport_root_keys,
            "model_semantic_delta_keys": model_semantic_delta_keys,
            "model_generated_root_keys": (
                [] if transport_kind in {UI_PRODUCTION_SEMANTIC_TRANSPORT_VERSION_V2, UI_PRODUCTION_SEMANTIC_TRANSPORT_VERSION}
                else sorted(key for key in payload if key not in deterministic)
            ),
            "semantic_payload_mutated": False,
            "semantic_transport": transport_kind or "CANONICAL_MODEL_RAW",
            "transport_decoded": transport_kind is not None,
            "deterministic_acceptance": deterministic_acceptance,
        }

    def _execute_queue_profile(
        self,
        *,
        task: ProfileTask,
        context_pack: dict[str, Any],
        context_override: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        started=time.perf_counter(); context=context_override or {"queue_native":True,"screen_governance_applicable":False,"cache_hit":False,"runtime_output_mode":task.runtime_output_mode}
        try:
            if task.send_image_to_model: raise LlamaTransportError("QUEUE_NATIVE_IMAGE_REQUIRES_GOVERNED_ENVELOPE")
            self.repository.validate_profile_identity(task.profile_slug, task.profile_code)
            sources=self.repository.profile_sources(task.profile_slug,task.profile_source_paths); schema=self.repository.runtime_schema(task.profile_slug, task.runtime_output_mode)
            binding=self.repository.runtime_binding(task.profile_slug)
            model_sources=self.repository.profile_model_sources(task.profile_slug,sources)
            generation_schema=self.repository.model_generation_schema(task.profile_slug,schema.payload)
            governed_pack, governed_receipt = _governed_context(task, context_pack, profile_sources=sources, schema=schema)
            adapter=PersistentLlamaServerAdapter(settings=self.settings,client=self.llama_client,schema=schema,structural_context=governed_pack,image_bytes=None,image_media_type=None,model_profile_sources=model_sources,generation_schema=generation_schema,execution_budget=(binding.execution_budget if binding else None))
            verifier=PersistentLlamaServerVerifier(settings=self.settings,schema=schema,structural_context=governed_pack,model_profile_sources=model_sources,generation_schema=generation_schema)
            runtime_package=self.runner.execute_profile_runtime(execution_id=f"EJECUCION_PERFIL_LF:{task.request_id}",profile_code=task.profile_code,profile_slug=task.profile_slug,profile_sources=sources,input_literal=task.input_literal,adapter=adapter,attestation_verifier=verifier,allow_test_doubles=False,lf_adapter_sources=[i.model_dump(mode="python") for i in task.lf_adapter_sources])
        except Exception as exc:
            code,detail=_failure(exc); return self._profile_failure(task=task,code=code,detail=detail,stage="RUNTIME_COMPLETION",started=started,context=context,runtime_diagnostics=_runtime_diagnostics(exc))
        model_raw_output=runtime_package.get("raw_output")
        try:
            materialized_output,materialization=self._materialize_runtime_output(task=task,model_raw_output=model_raw_output,governed_receipt=governed_receipt)
            contract,payload=self.gates.contract(profile_slug=task.profile_slug,raw_output=materialized_output,schema=schema); semantic=self.gates.semantic_utility(profile_slug=task.profile_slug,payload=payload,contract_gate=contract)
        except Exception as exc:
            code,detail=_failure(exc)
            diagnostics=_runtime_diagnostics(exc) or _post_generation_diagnostics(adapter, model_raw_output)
            return self._profile_failure(task=task,code=code,detail=detail,stage="POST_GENERATION_VALIDATION",started=started,context=context,runtime_diagnostics=diagnostics)
        completion={"status":"PASS","blocking_codes":[],"receipt":runtime_package.get("receipt"),"governed_context_receipt":governed_receipt,"attestation_verification":runtime_package.get("runtime_attestation_verification"),"llama_usage":adapter.last_completion.get("usage",{}),"llama_timings":adapter.last_completion.get("timings",{}),"output_materialization":materialization}
        return {"request_id":task.request_id,"profile_code":task.profile_code,"profile_slug":task.profile_slug,"context":context,"runtime_completion":completion,"profile_contract_valid":contract,"semantic_utility":semantic,"model_raw_output":model_raw_output,"raw_output":materialized_output,"elapsed_ms":round((time.perf_counter()-started)*1000,3),"downstream_authorized":False}

    def _execute_profile(self, *, task: ProfileTask, artifact: Any, prepared: PreparedContext, context_reused_within_batch: bool) -> dict[str, Any]:
        started=time.perf_counter(); context={"cache_key":prepared.cache_key,"cache_hit":prepared.cache_hit,"pack_sha256":prepared.pack.get("pack_sha256"),"prepare_ms":prepared.prepare_ms,"reused_within_batch":context_reused_within_batch,"runtime_output_mode":task.runtime_output_mode}
        try:
            self.repository.validate_profile_identity(task.profile_slug, task.profile_code)
            sources=self.repository.profile_sources(task.profile_slug,task.profile_source_paths); schema=self.repository.runtime_schema(task.profile_slug, task.runtime_output_mode)
            binding=self.repository.runtime_binding(task.profile_slug)
            model_sources=self.repository.profile_model_sources(task.profile_slug,sources)
            generation_schema=self.repository.model_generation_schema(task.profile_slug,schema.payload)
            if task.send_image_to_model and not self.settings.allow_model_image: raise LlamaTransportError("FULL_IMAGE_MODEL_PATH_DISABLED")
            image_bytes=artifact.image_bytes() if task.send_image_to_model else None
            governed_pack, governed_receipt = _governed_context(task, prepared.pack, profile_sources=sources, schema=schema)
            adapter=PersistentLlamaServerAdapter(settings=self.settings,client=self.llama_client,schema=schema,structural_context=governed_pack,image_bytes=image_bytes,image_media_type=artifact.image_media_type if image_bytes is not None else None,model_profile_sources=model_sources,generation_schema=generation_schema,execution_budget=(binding.execution_budget if binding else None))
            verifier=PersistentLlamaServerVerifier(settings=self.settings,schema=schema,structural_context=governed_pack,model_profile_sources=model_sources,generation_schema=generation_schema)
            runtime_package=self.runner.execute_profile_runtime(execution_id=f"EJECUCION_PERFIL_LF:{task.request_id}",profile_code=task.profile_code,profile_slug=task.profile_slug,profile_sources=sources,input_literal=task.input_literal,adapter=adapter,attestation_verifier=verifier,allow_test_doubles=False,lf_adapter_sources=[i.model_dump(mode="python") for i in task.lf_adapter_sources])
        except Exception as exc:
            code,detail=_failure(exc); return self._profile_failure(task=task,code=code,detail=detail,stage="RUNTIME_COMPLETION",started=started,context=context,runtime_diagnostics=_runtime_diagnostics(exc))
        model_raw_output=runtime_package.get("raw_output")
        try:
            materialized_output,materialization=self._materialize_runtime_output(task=task,model_raw_output=model_raw_output,governed_receipt=governed_receipt)
            contract,payload=self.gates.contract(profile_slug=task.profile_slug,raw_output=materialized_output,schema=schema); semantic=self.gates.semantic_utility(profile_slug=task.profile_slug,payload=payload,contract_gate=contract)
        except Exception as exc:
            code,detail=_failure(exc)
            diagnostics=_runtime_diagnostics(exc) or _post_generation_diagnostics(adapter, model_raw_output)
            return self._profile_failure(task=task,code=code,detail=detail,stage="POST_GENERATION_VALIDATION",started=started,context=context,runtime_diagnostics=diagnostics)
        completion={"status":"PASS","blocking_codes":[],"receipt":runtime_package.get("receipt"),"governed_context_receipt":governed_receipt,"attestation_verification":runtime_package.get("runtime_attestation_verification"),"llama_usage":adapter.last_completion.get("usage",{}),"llama_timings":adapter.last_completion.get("timings",{}),"output_materialization":materialization}
        return {"request_id":task.request_id,"profile_code":task.profile_code,"profile_slug":task.profile_slug,"context":context,"runtime_completion":completion,"profile_contract_valid":contract,"semantic_utility":semantic,"model_raw_output":model_raw_output,"raw_output":materialized_output,"elapsed_ms":round((time.perf_counter()-started)*1000,3),"downstream_authorized":False}

    @staticmethod
    def _profile_failure(*,task:ProfileTask,code:str,detail:str|None,stage:str,started:float,context:dict[str,Any]|None=None,runtime_diagnostics:dict[str,Any]|None=None)->dict[str,Any]:
        completion={"status":"FAIL","blocking_codes":[code],"stage":stage};
        if detail: completion["detail"]=detail
        if runtime_diagnostics: completion["diagnostics"]=runtime_diagnostics
        return {"request_id":task.request_id,"profile_code":task.profile_code,"profile_slug":task.profile_slug,"context":context,"runtime_completion":completion,"profile_contract_valid":_not_evaluated("RUNTIME_COMPLETION_FAILED"),"semantic_utility":_not_evaluated("RUNTIME_COMPLETION_FAILED"),"model_raw_output":(runtime_diagnostics or {}).get("model_raw_output"),"raw_output":None,"elapsed_ms":round((time.perf_counter()-started)*1000,3),"downstream_authorized":False}

    @staticmethod
    def _batch_result(request:BatchRequest,profile_results:list[dict[str,Any]],started:float,*,context:PreparedContext|None)->dict[str,Any]:
        passed=sum(i.get("runtime_completion",{}).get("status")=="PASS" for i in profile_results); contract_passed=sum(i.get("profile_contract_valid",{}).get("status")=="PASS" for i in profile_results); utility_passed=sum(i.get("semantic_utility",{}).get("status")=="PASS" for i in profile_results)
        return {"schema":RESULT_SCHEMA,"kind":"batch","batch_id":request.batch_id,"artifact_sha256":request.artifact.image_sha256,"status":"COMPLETED","context":None if context is None else {"cache_key":context.cache_key,"cache_hit":context.cache_hit,"pack_sha256":context.pack.get("pack_sha256"),"prepare_ms":context.prepare_ms,"prepared_once":True,"reuse_count":max(0,len(profile_results)-1)},"summary":{"profiles_total":len(profile_results),"runtime_completion_pass":passed,"profile_contract_valid_pass":contract_passed,"semantic_utility_floor_pass":utility_passed},"profile_results":profile_results,"total_ms":round((time.perf_counter()-started)*1000,3),"downstream_authorized":False}

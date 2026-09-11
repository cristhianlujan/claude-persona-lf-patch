from __future__ import annotations

import json
import time
from typing import Any

from .cache import StructuralCache
from .hashing import canonical_json_sha256, sha256_text
from .llama import (
    LlamaHTTPClient,
    LlamaTransportError,
    PersistentLlamaServerAdapter,
    PersistentLlamaServerVerifier,
    UI_PRODUCTION_SEMANTIC_TRANSPORT_VERSION,
    UI_PRODUCTION_SEMANTIC_TRANSPORT_VERSION_V2,
    decode_ui_production_transport,
)
from .models import BatchRequest, ExecuteRequest, ProfileTask, QueueExecuteRequest
from .repository import RepositoryBindings
from .runtime_authority import resolve_typed_runtime_context
from .settings import Settings
from .structural import PreparedContext, StructuralContextPipeline
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


def _deterministic_ui_outcome(
    *, deliverable: dict[str, Any], acceptance: dict[str, Any], composer_payload: dict[str, Any]
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
    state_ok = isinstance(state_map, dict) and required_states.issubset(set(state_map))
    risk_ok = (
        isinstance(risk_controls, list)
        and len(risk_controls) >= int(acceptance.get("minimum_risk_control_count") or 0)
    )
    checks = {
        "layout_precision": responsive_ok and isinstance(deliverable.get("spacing_typography"), dict),
        "visual_hierarchy": _ui_hierarchy_depth(deliverable.get("visual_hierarchy")) >= int(acceptance.get("minimum_hierarchy_depth_edges") or 0),
        "lf_system_fidelity": isinstance(deliverable.get("token_map"), dict) and risk_ok,
        "state_mapping": state_ok,
        "handoff_quality": component_count_ok and variants_ok and _ui_source_bindings_match(deliverable, acceptance) and bool(composer_payload),
    }
    refs = {
        "layout_precision": ["layout_grid", "spacing_typography"],
        "visual_hierarchy": ["visual_hierarchy"],
        "lf_system_fidelity": ["token_map", "risk_controls"],
        "state_mapping": ["state_map"],
        "handoff_quality": ["component_tree", "handoff_to_next"],
    }
    score = {key: 4 if checks[key] else 0 for key in checks}
    score["total"] = sum(score.values())
    score["evidence_by_criterion"] = {
        key: {
            "refs": refs[key],
            "summary": (
                f"Deterministic acceptance check passed for {key}."
                if checks[key]
                else f"Deterministic acceptance check failed for {key}."
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
        llama=self.llama_client.health(); return {"schema":"lf-profile-runtime-api-snapshot/v1","runtime_version":self.settings.runtime_version,"resolver_version":self.settings.resolver_version,"source_sha":self.settings.source_sha,"bind":{"host":self.settings.api_host,"port":self.settings.api_port},"llama_server":llama,"cache":self.cache.stats(),"max_workers":self.settings.max_workers,"max_batch_size":self.settings.max_batch_size,"full_image_model_enabled":self.settings.allow_model_image,"deployment_classification":"INSTALLED_NOT_INTEGRATED_PENDING_LIVE_REVERIFY","operational_ready":False,"downstream_authorized":False}

    def _materialize_runtime_output(
        self, *, task: ProfileTask, model_raw_output: Any, governed_receipt: dict[str, Any]
    ) -> tuple[Any, dict[str, Any]]:
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
        composer_payload = boundary.build_composer_payload(deliverable)
        deterministic_outcome: dict[str, Any] | None = None
        if transport_kind in {UI_PRODUCTION_SEMANTIC_TRANSPORT_VERSION_V2, UI_PRODUCTION_SEMANTIC_TRANSPORT_VERSION}:
            if not isinstance(acceptance, dict):
                raise LlamaTransportError("UI_PRODUCTION_SEMANTIC_TRANSPORT_ACCEPTANCE_MISSING")
            deterministic_outcome = _deterministic_ui_outcome(
                deliverable=deliverable,
                acceptance=acceptance,
                composer_payload=composer_payload,
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

    def _execute_queue_profile(self, *, task: ProfileTask, context_pack: dict[str, Any]) -> dict[str, Any]:
        started=time.perf_counter(); context={"queue_native":True,"screen_governance_applicable":False,"cache_hit":False,"runtime_output_mode":task.runtime_output_mode}
        try:
            if task.send_image_to_model: raise LlamaTransportError("QUEUE_NATIVE_IMAGE_REQUIRES_GOVERNED_ENVELOPE")
            sources=self.repository.profile_sources(task.profile_slug,task.profile_source_paths); schema=self.repository.runtime_schema(task.profile_slug, task.runtime_output_mode)
            governed_pack, governed_receipt = _governed_context(task, context_pack, profile_sources=sources, schema=schema)
            adapter=PersistentLlamaServerAdapter(settings=self.settings,client=self.llama_client,schema=schema,structural_context=governed_pack,image_bytes=None,image_media_type=None)
            verifier=PersistentLlamaServerVerifier(settings=self.settings,schema=schema,structural_context=governed_pack)
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
            sources=self.repository.profile_sources(task.profile_slug,task.profile_source_paths); schema=self.repository.runtime_schema(task.profile_slug, task.runtime_output_mode)
            if task.send_image_to_model and not self.settings.allow_model_image: raise LlamaTransportError("FULL_IMAGE_MODEL_PATH_DISABLED")
            image_bytes=artifact.image_bytes() if task.send_image_to_model else None
            governed_pack, governed_receipt = _governed_context(task, prepared.pack, profile_sources=sources, schema=schema)
            adapter=PersistentLlamaServerAdapter(settings=self.settings,client=self.llama_client,schema=schema,structural_context=governed_pack,image_bytes=image_bytes,image_media_type=artifact.image_media_type if image_bytes is not None else None)
            verifier=PersistentLlamaServerVerifier(settings=self.settings,schema=schema,structural_context=governed_pack)
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

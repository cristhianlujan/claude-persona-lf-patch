from __future__ import annotations

import inspect
import json
import re
from typing import Any

from jsonschema import Draft202012Validator, SchemaError

from .hashing import canonical_json_sha256
from .repository import RepositoryBindings, SchemaBinding

PASS_QUALITY_VERDICTS = {"PASS_TO_COMPOSER", "PASS_WITH_RESTRICTIONS"}
NOMINAL_EVIDENCE = {"ok", "pass", "passed", "valid", "done", "complete", "yes"}
UI_SCHEMA_ONLY_MODES = {"UI_FOCUSED_DECISION", "UI_MISSING_INPUT"}

REVIEWER_CONTEXT_MODE = "ISOLATED_NO_PRODUCER_PRIVATE_CONTEXT"
REVIEW_INPUT_CLASSES = (
    "CURRENT_AUTHORITY_REFS",
    "EVIDENCE_MANIFEST",
    "EXACT_CANDIDATE",
    "SCOPE_AUTHORITY_PACKET",
)


def independent_review_input_binding(
    candidate: dict[str, Any],
    evidence_manifest: dict[str, Any],
    scope_authority_packet: dict[str, Any],
) -> dict[str, Any]:
    binding = {
        "schema": "SRCR_INDEPENDENT_REVIEW_INPUT_V1",
        "candidate_sha256": canonical_json_sha256(candidate),
        "evidence_manifest_sha256": canonical_json_sha256(evidence_manifest),
        "scope_packet_sha256": canonical_json_sha256(scope_authority_packet),
        "reviewer_context_mode": REVIEWER_CONTEXT_MODE,
        "review_input_classes": list(REVIEW_INPUT_CLASSES),
        "forbidden_input_classes": [
            "PRODUCER_PRIVATE_REASONING",
            "PRODUCER_CHAT_TRANSCRIPT",
            "PRODUCER_HIDDEN_CONTEXT",
        ],
    }
    binding["review_input_sha256"] = canonical_json_sha256(binding)
    return binding


def strict_json_object(raw_output: Any) -> tuple[dict[str, Any] | None, list[str]]:
    if not isinstance(raw_output, str):
        return None, ["RAW_OUTPUT_NOT_STRING"]
    stripped = raw_output.strip()
    if not stripped:
        return None, ["RAW_OUTPUT_EMPTY"]
    if stripped.startswith("```") or stripped.endswith("```"):
        return None, ["FENCED_JSON_FORBIDDEN"]
    try:
        payload = json.loads(stripped)
    except json.JSONDecodeError:
        return None, ["RAW_OUTPUT_JSON_INVALID"]
    if not isinstance(payload, dict):
        return None, ["RAW_OUTPUT_ROOT_NOT_OBJECT"]
    return payload, []


def _quality_gate_errors(result: Any, prefix: str) -> list[str]:
    """A missing diagnostic must never turn a failed validator into acceptance."""
    if not isinstance(result, dict):
        return [prefix + "_RESULT_INVALID"]
    codes = result.get("blocking_codes")
    if not isinstance(codes, list) or any(not isinstance(code, str) or not code for code in codes):
        return [prefix + "_BLOCKING_CODES_INVALID"]
    if result.get("status") != "PASS":
        return codes or [prefix + "_NOT_PASS"]
    return codes


def _ui_focused_semantic_v3_errors(values: dict[str, str]) -> list[str]:
    """High-confidence semantic guardrails for Focused UI Decision.

    Strategy 26 v3b deliberately favors negative evidence over broad lexical
    allowlists. It rejects known weak shapes while allowing concrete design
    tokens, CSS values, component names, and bilingual wording to evolve.
    """
    import re

    errors: list[str] = []
    subject = values.get("decision_subject", "")
    selected = values.get("selected_visual_type", "")

    generic_subjects = {
        "ui decision", "visual decision", "design decision", "interface decision",
        "ui treatment", "decisión ui", "decision ui", "decisión visual",
        "decision visual", "decisión de diseño", "decision de diseño", "tratamiento ui",
        "non-canonical artifacts", "non canonical artifacts", "noncanonical artifacts",
        "artifact set", "artifact-set", "input governance", "advisory read only",
        "advisory_read_only",
    }
    if subject in generic_subjects:
        errors.append("UI_FOCUSED_DECISION_SUBJECT_NON_CONCRETE")

    generic_selected = {
        "horizontal overflow", "vertical overflow", "overflow", "ui treatment",
        "visual treatment", "standard treatment", "default treatment",
        "desbordamiento horizontal", "desbordamiento vertical", "tratamiento ui",
        "tratamiento visual",
    }
    if selected == subject or selected in generic_selected:
        errors.append("UI_FOCUSED_SELECTED_TREATMENT_NON_CONCRETE")

    surface = values.get("base_color_or_surface", "")
    surface_signals = (
        "#", "rgb", "hsl", "var(", "--", "token", "surface", "background",
        "color", "white", "black", "neutral", "gray", "grey", "canvas", "panel",
        "primary", "secondary", "accent", "error", "success", "warning", "brand",
        "superficie", "fondo", "color", "blanco", "negro", "neutro", "gris",
        "primario", "secundario", "acento", "error", "éxito", "exito", "advertencia",
    )
    structural_only = (
        "table", "screen", "button", "field", "selector", "cta", "layout",
        "tabla", "pantalla", "botón", "boton", "campo", "selector", "diseño",
    )
    token_like = bool(re.search(r"[a-záéíóúüñ]+[-_][a-záéíóúüñ0-9-]+", surface))
    if surface and surface == selected:
        errors.append("UI_FOCUSED_BASE_SURFACE_DUPLICATES_TREATMENT")
    if surface and any(m in surface for m in structural_only) and not (
        any(m in surface for m in surface_signals) or token_like
    ):
        errors.append("UI_FOCUSED_BASE_SURFACE_NON_CONCRETE")

    coverage = values.get("size_or_coverage", "")
    weak_coverage = {
        "horizontal overflow", "vertical overflow", "overflow", "medium", "small",
        "large", "contextual", "standard", "default", "desbordamiento horizontal",
        "desbordamiento vertical", "medio", "pequeño", "pequeno", "grande",
    }
    if coverage in weak_coverage:
        errors.append("UI_FOCUSED_SIZE_OR_COVERAGE_SCOPE_MISSING")

    density = values.get("density_limits", "")
    if density and re.fullmatch(r"\d+(?:\.\d+)?", density):
        errors.append("UI_FOCUSED_DENSITY_LIMITS_NUMERIC_ONLY")
    if density and re.fullmatch(r"\d+(?:\.\d+)?(?:%|px|rem|em)", density):
        errors.append("UI_FOCUSED_DENSITY_LIMITS_UNIT_ONLY")
    if density in {
        "subtle decoration", "decoration", "generic decoration", "decoración sutil",
        "decoracion sutil", "decoración", "decoracion",
    }:
        errors.append("UI_FOCUSED_DENSITY_LIMITS_NON_CONCRETE_V3")

    depth = values.get("depth_style", "")
    if depth in {
        "subtle", "elevation", "shadow", "standard", "default", "medium", "thin",
        "thick", "sutil", "elevación", "elevacion", "sombra", "estándar", "estandar",
    }:
        errors.append("UI_FOCUSED_DEPTH_STYLE_NON_CONCRETE")

    weight = values.get("visual_weight", "")
    if weight in {
        "primary", "secondary", "tertiary", "high", "low", "medium", "light", "dark",
        "standard", "default", "subtle", "primario", "secundario", "terciario", "alto",
        "bajo", "medio", "ligero", "oscuro", "sutil",
    }:
        errors.append("UI_FOCUSED_VISUAL_WEIGHT_NON_CONCRETE")

    relationship = values.get("relationship_to_main_element", "")
    business_only = (
        "business rule", "business rules", "regla de negocio", "reglas de negocio",
    )
    ui_targets = (
        "table", "content", "action", "cta", "control", "card", "component", "element",
        "navigation", "header", "row", "button", "field", "input", "search", "selector",
        "tab", "panel", "tabla", "contenido", "acción", "accion", "tarjeta", "componente",
        "elemento", "navegación", "navegacion", "encabezado", "fila", "botón", "boton",
        "campo", "entrada", "buscador", "selector", "pestaña", "pestana", "panel",
    )
    if relationship and any(m in relationship for m in business_only) and not any(
        m in relationship for m in ui_targets
    ):
        errors.append("UI_FOCUSED_RELATIONSHIP_NON_CONCRETE")

    implementation = values.get("implementation_format", "")
    weak_implementation = {
        "json object", "objeto json", "json", "object", "objeto", "string", "text",
        "texto", "markdown", "yaml", "xml", "css", "svg", "component", "componente",
        "css styling", "css style", "estilo css", "artifact", "artifact set",
        "non-canonical artifact", "non canonical artifact", "non_canonical_artifact",
        "advisory read only", "advisory_read_only",
    }
    if implementation in weak_implementation:
        errors.append("UI_FOCUSED_IMPLEMENTATION_FORMAT_NON_CONCRETE_V3")

    seen: dict[str, str] = {}
    for key in (
        "selected_visual_type", "size_or_coverage", "density_limits", "depth_style",
        "visual_weight", "relationship_to_main_element", "implementation_format",
    ):
        value = values.get(key, "")
        if not value:
            continue
        if value in seen:
            errors.append("UI_FOCUSED_CROSS_FIELD_DUPLICATION")
            break
        seen[value] = key

    return sorted(set(errors))


def _logical_failure_class(error: dict[str, Any]) -> str:
    code = str(error.get("code") or "UNKNOWN")
    path = str(error.get("path") or "$")
    if code == "JSON_SCHEMA_VALIDATION_FAILED":
        if any(path.endswith(f".test_protocol.{field}") for field in ("setup", "action", "assertions")):
            return "EXECUTABLE_TEST_PROTOCOL_INCOMPLETE"
        if path.endswith(".test_protocol.failure_signal"):
            return "EXECUTABLE_TEST_FAILURE_SIGNAL_REQUIRED"
    return code


def canonical_logical_findings(errors: list[dict[str, Any]]) -> list[dict[str, Any]]:
    grouped: dict[str, dict[str, Any]] = {}
    for raw in errors:
        if not isinstance(raw, dict):
            continue
        path = str(raw.get("path") or "$")
        failure_class = _logical_failure_class(raw)
        fingerprint = canonical_json_sha256(
            {"failure_class": failure_class, "candidate_path": path}
        )
        detector = str(raw.get("detector") or "UNKNOWN")
        item = grouped.setdefault(
            fingerprint,
            {
                "finding_id": "sha256:" + fingerprint,
                "failure_class": failure_class,
                "candidate_path": path,
                "detectors": [],
                "raw_codes": [],
            },
        )
        if detector not in item["detectors"]:
            item["detectors"].append(detector)
        code = str(raw.get("code") or "UNKNOWN")
        if code not in item["raw_codes"]:
            item["raw_codes"].append(code)
    for item in grouped.values():
        item["detectors"].sort()
        item["raw_codes"].sort()
    return sorted(grouped.values(), key=lambda row: (row["candidate_path"], row["failure_class"]))


class OutputGates:
    def __init__(self, repository: RepositoryBindings) -> None:
        self.repository = repository

    def contract(
        self,
        *,
        profile_slug: str,
        raw_output: Any,
        schema: SchemaBinding,
        evidence_manifest: dict[str, Any] | None = None,
    ) -> tuple[dict[str, Any], dict[str, Any] | None]:
        payload, parse_errors = strict_json_object(raw_output)
        errors: list[dict[str, Any]] = [
            {"code": code, "path": "$", "detector": "JSON_PARSE"} for code in parse_errors
        ]
        if payload is not None:
            try:
                Draft202012Validator.check_schema(schema.payload)
                validator = Draft202012Validator(schema.payload)
                validation_errors = sorted(
                    validator.iter_errors(payload), key=lambda error: list(error.path)
                )
                for item in validation_errors[:50]:
                    path = "$" + "".join(
                        f"[{part}]" if isinstance(part, int) else f".{part}"
                        for part in item.path
                    )
                    errors.append(
                        {
                            "code": "JSON_SCHEMA_VALIDATION_FAILED",
                            "path": path,
                            "message": item.message[:500],
                            "detector": "JSON_SCHEMA",
                        }
                    )
            except SchemaError as exc:
                errors.append(
                    {
                        "code": "CANONICAL_JSON_SCHEMA_INVALID",
                        "path": "$schema",
                        "message": str(exc)[:500],
                        "detector": "JSON_SCHEMA",
                    }
                )
            if not (
                profile_slug == "ui_architect" and schema.mode in UI_SCHEMA_ONLY_MODES
            ):
                canonical_errors = self._canonical_errors(
                    profile_slug, payload, evidence_manifest=evidence_manifest
                )
                for item in canonical_errors:
                    if isinstance(item, dict):
                        item = dict(item)
                        item.setdefault("detector", "PROFILE_VALIDATOR")
                    errors.append(item)
        logical_findings = canonical_logical_findings(errors)
        blocking = sorted({str(item.get("code")) for item in errors})
        return (
            {
                "status": "PASS" if not errors else "FAIL",
                "validator_scope": "CANONICAL_SCHEMA_PLUS_APPLICABLE_PROFILE_VALIDATOR",
                "schema_sha256": schema.sha256,
                "schema_source_refs": list(schema.source_refs),
                "schema_mode": schema.mode,
                "evidence_manifest_sha256": (canonical_json_sha256(evidence_manifest) if isinstance(evidence_manifest, dict) else None),
                "blocking_codes": blocking,
                "errors": errors,
                "logical_findings": logical_findings,
                "finding_count": len(logical_findings),
            },
            payload,
        )

    def semantic_utility(
        self,
        *,
        profile_slug: str,
        payload: dict[str, Any] | None,
        contract_gate: dict[str, Any],
        evidence_manifest: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        manifest_sha256 = canonical_json_sha256(evidence_manifest) if isinstance(evidence_manifest, dict) else None
        if contract_gate.get("status") != "PASS" or payload is None:
            return {
                "status": "NOT_EVALUATED",
                "evaluation_scope": "DETERMINISTIC_UTILITY_FLOOR",
                "blocking_codes": ["PROFILE_CONTRACT_INVALID"],
                "independent_semantic_judge": "NOT_EXECUTED",
                "evidence_manifest_sha256": manifest_sha256,
            }
        errors: list[str] = []
        local_utility = self.repository.load_semantic_utility(profile_slug)
        if local_utility is not None:
            module, callable_name = local_utility
            evaluator = getattr(module, callable_name, None)
            if not callable(evaluator):
                return {
                    "status": "FAIL",
                    "evaluation_scope": "PROFILE_LOCAL_DETERMINISTIC_UTILITY_FLOOR",
                    "blocking_codes": ["PROFILE_SEMANTIC_UTILITY_CALLABLE_MISSING"],
                    "independent_semantic_judge": "NOT_EXECUTED",
                    "evidence_manifest_sha256": manifest_sha256,
                    "downstream_authorized": False,
                }
            try:
                if self._supports_evidence_manifest(evaluator):
                    result = evaluator(
                        payload,
                        contract_gate,
                        evidence_manifest=evidence_manifest,
                    )
                else:
                    result = evaluator(payload, contract_gate)
            except Exception as exc:
                return {
                    "status": "FAIL",
                    "evaluation_scope": "PROFILE_LOCAL_DETERMINISTIC_UTILITY_FLOOR",
                    "blocking_codes": ["PROFILE_SEMANTIC_UTILITY_EXCEPTION"],
                    "message": type(exc).__name__,
                    "independent_semantic_judge": "NOT_EXECUTED",
                    "evidence_manifest_sha256": manifest_sha256,
                    "downstream_authorized": False,
                }
            if isinstance(result, dict):
                codes = result.get("blocking_codes", [])
                if not isinstance(codes, list):
                    codes = ["PROFILE_SEMANTIC_UTILITY_RESULT_INVALID"]
                status = "PASS" if result.get("status") == "PASS" and not codes else "FAIL"
                return {
                    "status": status,
                    "evaluation_scope": "PROFILE_LOCAL_DETERMINISTIC_UTILITY_FLOOR",
                    "blocking_codes": sorted({str(code) for code in codes}),
                    "independent_semantic_judge": "NOT_EXECUTED",
                    "evidence_manifest_sha256": manifest_sha256,
                    "downstream_authorized": False,
                }
            if isinstance(result, list):
                codes = sorted({str(code) for code in result})
                return {
                    "status": "PASS" if not codes else "FAIL",
                    "evaluation_scope": "PROFILE_LOCAL_DETERMINISTIC_UTILITY_FLOOR",
                    "blocking_codes": codes,
                    "independent_semantic_judge": "NOT_EXECUTED",
                    "evidence_manifest_sha256": manifest_sha256,
                    "downstream_authorized": False,
                }
            return {
                "status": "FAIL",
                "evaluation_scope": "PROFILE_LOCAL_DETERMINISTIC_UTILITY_FLOOR",
                "blocking_codes": ["PROFILE_SEMANTIC_UTILITY_RESULT_INVALID"],
                "independent_semantic_judge": "NOT_EXECUTED",
                "evidence_manifest_sha256": manifest_sha256,
                    "downstream_authorized": False,
            }
        if profile_slug == "product_director_lf":
            deliverable = payload.get("deliverable_created")
            if not isinstance(deliverable, dict):
                errors.append("PRODUCT_DELIVERABLE_MISSING")
            else:
                if not isinstance(deliverable.get("product_decision"), dict):
                    errors.append("PRODUCT_DECISION_MISSING")
                if not deliverable.get("acceptance_criteria"):
                    errors.append("PRODUCT_ACCEPTANCE_CRITERIA_EMPTY")
                if not isinstance(deliverable.get("decision_lineage"), dict):
                    errors.append("PRODUCT_DECISION_LINEAGE_MISSING")
        elif profile_slug == "ui_architect":
            mode = str(contract_gate.get("schema_mode") or "AUTO")
            if mode == "UI_FOCUSED_DECISION":
                required_text = (
                    "decision_subject",
                    "selected_visual_type",
                    "base_color_or_surface",
                    "size_or_coverage",
                    "density_limits",
                    "depth_style",
                    "visual_weight",
                    "relationship_to_main_element",
                    "implementation_format",
                )
                values: dict[str, str] = {}
                for key in required_text:
                    value = payload.get(key)
                    if not isinstance(value, str) or len(value.strip()) < 3:
                        errors.append(f"UI_FOCUSED_{key.upper()}_WEAK")
                    else:
                        values[key] = " ".join(value.lower().strip().split())

                exclusions = payload.get("hard_exclusions")
                if not isinstance(exclusions, list) or not exclusions:
                    errors.append("UI_FOCUSED_HARD_EXCLUSIONS_EMPTY")
                else:
                    selected = values.get("selected_visual_type", "")
                    governance_exclusion_markers = (
                        "non_canonical_artifact", "non-canonical artifact", "non canonical artifact",
                        "artifact_01", "artifact_02", "artifact set", "input governance",
                        "advisory_read_only", "advisory read only", "canonicalize",
                        "canonicalization", "register_screen", "resolve_screen",
                    )
                    for exclusion in exclusions:
                        if not isinstance(exclusion, str):
                            continue
                        normalized = " ".join(exclusion.lower().strip().split())
                        if any(marker in normalized for marker in governance_exclusion_markers):
                            errors.append("UI_FOCUSED_HARD_EXCLUSION_GOVERNANCE_ECHO")
                        if selected and normalized and (selected == normalized or selected in normalized):
                            errors.append("UI_FOCUSED_SELECTED_TREATMENT_EXCLUDED")
                    # Preserve all findings; do not stop after the first invalid exclusion.

                generic_only = {
                    "small", "medium", "large", "thin", "thick", "light", "dark",
                    "high", "low", "above", "below", "left", "right", "center",
                    "standard", "default", "normal", "css", "svg", "component", "visual", "ui",
                }
                specificity_fields = (
                    "size_or_coverage",
                    "density_limits",
                    "depth_style",
                    "visual_weight",
                    "relationship_to_main_element",
                    "implementation_format",
                )
                for key in specificity_fields:
                    normalized = values.get(key, "")
                    if normalized in generic_only:
                        errors.append(f"UI_FOCUSED_{key.upper()}_NON_CONCRETE")

                phrase_fields = (
                    "decision_subject", "selected_visual_type", "size_or_coverage",
                    "density_limits", "depth_style", "visual_weight",
                    "relationship_to_main_element", "implementation_format",
                )
                for key in phrase_fields:
                    normalized = values.get(key, "")
                    if normalized and re.fullmatch(r"[a-z0-9]+(?:_[a-z0-9]+)+", normalized):
                        errors.append(f"UI_FOCUSED_{key.upper()}_IDENTIFIER_ECHO")

                density = values.get("density_limits", "")
                density_markers = (
                    "one", "single", "two", "three", "per ", "max", "maximum",
                    "only", "no more", "at most", "level", "layer", "line", "element",
                    "cue", "viewport", "%", "px", "uno", "una", "dos", "tres", "por ",
                    "máximo", "maximo", "solo", "sola", "no más", "no mas", "como máximo",
                    "como maximo", "límite", "limite", "cantidad", "capa", "línea", "linea",
                    "elemento", "señal", "indicador",
                )
                if density and not any(char.isdigit() for char in density) and not any(
                    marker in density for marker in density_markers
                ):
                    errors.append("UI_FOCUSED_DENSITY_LIMITS_NON_CONCRETE")

                errors.extend(_ui_focused_semantic_v3_errors(values))
                if payload.get("status") in {"RETURN_TO_ORCHESTRATOR", "BLOCK_PIPELINE"}:
                    errors.append("UI_FOCUSED_STATUS_NOT_DECISION_READY")
            elif mode == "UI_MISSING_INPUT":
                verdict = payload.get("self_verdict")
                missing = payload.get("missing_inputs")
                if verdict in {"NEEDS_INPUT", "BLOCKED"} and (
                    not isinstance(missing, list) or not missing
                ):
                    errors.append("UI_MISSING_INPUT_LIST_EMPTY")
                if payload.get("blocked") is True and payload.get("pipeline_action") not in {
                    "RETURN_TO_ORCHESTRATOR",
                    "BLOCK_PIPELINE",
                }:
                    errors.append("UI_MISSING_INPUT_PIPELINE_ACTION_INVALID")
            else:
                deliverable = payload.get("deliverable_created")
                if not isinstance(deliverable, dict):
                    errors.append("UI_DELIVERABLE_MISSING")
                elif not deliverable.get("component_tree"):
                    errors.append("UI_COMPONENT_TREE_EMPTY")
        elif profile_slug == "quality_pack":
            evidence = payload.get("evidence_map")
            if not isinstance(evidence, list) or not evidence:
                errors.append("QUALITY_EVIDENCE_MAP_EMPTY")
            else:
                for item in evidence:
                    rendered = json.dumps(item, ensure_ascii=False, sort_keys=True).strip().lower()
                    if rendered in NOMINAL_EVIDENCE or len(rendered) < 12:
                        errors.append("QUALITY_EVIDENCE_NOMINAL")
                        break
            score = payload.get("score_breakdown")
            keys = (
                "contract_schema_compliance",
                "evidence_integrity",
                "lf_safety_governance",
                "handoff_readiness",
                "leakage_scope_control",
            )
            if isinstance(score, dict) and all(isinstance(score.get(key), int) for key in keys):
                if score.get("total") != sum(score[key] for key in keys):
                    errors.append("QUALITY_SCORE_TOTAL_MISMATCH")
            if payload.get("verdict") in PASS_QUALITY_VERDICTS and payload.get("blocking_codes"):
                errors.append("QUALITY_PASS_WITH_BLOCKING_CODES")
        else:
            return {
                "status": "NOT_EVALUATED",
                "evaluation_scope": "NO_PROFILE_UTILITY_POLICY",
                "blocking_codes": ["SEMANTIC_UTILITY_POLICY_NOT_BOUND"],
                "independent_semantic_judge": "NOT_EXECUTED",
                "evidence_manifest_sha256": manifest_sha256,
            }
        return {
            "status": "PASS" if not errors else "FAIL",
            "evaluation_scope": "DETERMINISTIC_UTILITY_FLOOR_NOT_FINAL_SEMANTIC_AUTHORITY",
            "blocking_codes": sorted(set(errors)),
            "independent_semantic_judge": "NOT_EXECUTED",
            "evidence_manifest_sha256": manifest_sha256,
                    "downstream_authorized": False,
        }

    @staticmethod
    def _supports_evidence_manifest(callable_obj: Any) -> bool:
        try:
            params = inspect.signature(callable_obj).parameters
        except (TypeError, ValueError):
            return False
        return (
            "evidence_manifest" in params
            or any(
                parameter.kind is inspect.Parameter.VAR_KEYWORD
                for parameter in params.values()
            )
        )

    def canonical_quality_boundary(
        self,
        *,
        profile_slug: str,
        candidate: dict[str, Any] | None,
        contract_gate: dict[str, Any],
        semantic_gate: dict[str, Any],
        evidence_manifest: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        manifest_sha256 = canonical_json_sha256(evidence_manifest) if isinstance(evidence_manifest, dict) else None
        binding = self.repository.runtime_binding(profile_slug)
        quality = binding.canonical_quality if binding is not None else None
        if not isinstance(quality, dict):
            return {
                "applicability": "NOT_APPLICABLE",
                "status": "NOT_BOUND",
                "deterministic_floors_can_accept_quality": False,
                "receipt_required_for_pass_to_quality_pack": False,
                "blocking_codes": ["CANONICAL_QUALITY_NOT_BOUND"],
                "canonical_quality_accepted": False,
                "evidence_manifest_sha256": manifest_sha256,
                "downstream_authorized": False,
            }
        pack_id = candidate.get("profile_pack_id") if isinstance(candidate, dict) else None
        required = pack_id in set(quality.get("required_for_profile_pack_ids") or [])
        if not required:
            return {
                "applicability": "NOT_APPLICABLE",
                "status": "NOT_REQUIRED_FOR_PROFILE_PACK",
                "deterministic_floors_can_accept_quality": False,
                "receipt_required_for_pass_to_quality_pack": bool(
                    quality.get("receipt_required_for_pass_to_quality_pack")
                ),
                "blocking_codes": [],
                "canonical_quality_accepted": False,
                "evidence_manifest_sha256": manifest_sha256,
                "downstream_authorized": False,
            }

        floors_clean = (
            contract_gate.get("status") == "PASS"
            and semantic_gate.get("status") == "PASS"
            and not contract_gate.get("blocking_codes")
            and not semantic_gate.get("blocking_codes")
        )
        return {
            "applicability": "REQUIRED",
            "profile_pack_id": pack_id,
            "semantic_judge_path": quality["semantic_judge_path"],
            "semantic_result_validator": dict(quality["semantic_result_validator"]),
            "quality_receipt_schema": quality["quality_receipt_schema"],
            "quality_receipt_validator": dict(quality["quality_receipt_validator"]),
            "status": (
                "PENDING_INDEPENDENT_SEMANTIC_REVIEW"
                if floors_clean
                else "BLOCKED_BY_DETERMINISTIC_FLOORS"
            ),
            "deterministic_floors_can_accept_quality": False,
            "receipt_required_for_pass_to_quality_pack": True,
            "blocking_codes": (
                []
                if floors_clean
                else sorted(
                    {
                        str(code)
                        for code in (
                            list(contract_gate.get("blocking_codes") or [])
                            + list(semantic_gate.get("blocking_codes") or [])
                        )
                    }
                )
            ),
            "canonical_quality_accepted": False,
            "evidence_manifest_sha256": manifest_sha256,
                "downstream_authorized": False,
        }

    def canonical_quality(
        self,
        *,
        profile_slug: str,
        candidate: dict[str, Any],
        evidence_manifest: dict[str, Any],
        semantic_result: dict[str, Any],
        quality_receipt: dict[str, Any],
        scope_authority_packet: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        manifest_sha256 = canonical_json_sha256(evidence_manifest)
        binding = self.repository.runtime_binding(profile_slug)
        quality = binding.canonical_quality if binding is not None else None
        if not isinstance(quality, dict):
            return {
                "status": "NOT_EVALUATED",
                "blocking_codes": ["CANONICAL_QUALITY_NOT_BOUND"],
                "canonical_quality_accepted": False,
                "evidence_manifest_sha256": manifest_sha256,
                "downstream_authorized": False,
            }

        pack_id = candidate.get("profile_pack_id")
        required = pack_id in set(quality.get("required_for_profile_pack_ids") or [])
        if not required:
            return {
                "status": "NOT_APPLICABLE",
                "blocking_codes": [],
                "canonical_quality_accepted": False,
                "evidence_manifest_sha256": manifest_sha256,
                "downstream_authorized": False,
            }

        errors: list[str] = []
        receipt_accepts_quality = False
        semantic_binding = self.repository.load_canonical_quality_validator(
            profile_slug, "semantic_result_validator"
        )
        receipt_binding = self.repository.load_canonical_quality_validator(
            profile_slug, "quality_receipt_validator"
        )
        receipt_schema = self.repository.canonical_quality_receipt_schema(profile_slug)
        if semantic_binding is None or receipt_binding is None or receipt_schema is None:
            return {
                "status": "FAIL",
                "blocking_codes": ["CANONICAL_QUALITY_BINDING_INCOMPLETE"],
                "canonical_quality_accepted": False,
                "evidence_manifest_sha256": manifest_sha256,
                "downstream_authorized": False,
            }

        semantic_module, semantic_callable_name = semantic_binding
        semantic_callable = getattr(semantic_module, semantic_callable_name, None)
        if not callable(semantic_callable):
            errors.append("CANONICAL_QUALITY_SEMANTIC_VALIDATOR_CALLABLE_MISSING")
        else:
            try:
                if scope_authority_packet is not None:
                    semantic_gate = semantic_callable(
                        semantic_result,
                        scope_packet=scope_authority_packet,
                        expected_candidate_sha256=canonical_json_sha256(candidate),
                        expected_scope_packet_sha256=canonical_json_sha256(
                            scope_authority_packet
                        ),
                        expected_evidence_manifest_sha256=manifest_sha256,
                    )
                else:
                    semantic_gate = semantic_callable(semantic_result)
            except Exception as exc:
                errors.append("CANONICAL_QUALITY_SEMANTIC_VALIDATOR_EXCEPTION:" + type(exc).__name__)
            else:
                errors.extend(_quality_gate_errors(
                    semantic_gate, "CANONICAL_QUALITY_SEMANTIC_VALIDATOR"
                ))

        try:
            Draft202012Validator.check_schema(receipt_schema.payload)
            receipt_schema_errors = list(
                Draft202012Validator(receipt_schema.payload).iter_errors(quality_receipt)
            )
        except SchemaError:
            errors.append("CANONICAL_QUALITY_RECEIPT_SCHEMA_INVALID")
        else:
            if receipt_schema_errors:
                errors.append("CANONICAL_QUALITY_RECEIPT_SCHEMA_FAILED")

        receipt_module, receipt_callable_name = receipt_binding
        receipt_callable = getattr(receipt_module, receipt_callable_name, None)
        if not callable(receipt_callable):
            errors.append("CANONICAL_QUALITY_RECEIPT_VALIDATOR_CALLABLE_MISSING")
        else:
            try:
                receipt_gate = receipt_callable(
                    quality_receipt,
                    candidate,
                    evidence_manifest,
                    semantic_result,
                )
            except Exception as exc:
                errors.append("CANONICAL_QUALITY_RECEIPT_VALIDATOR_EXCEPTION:" + type(exc).__name__)
            else:
                receipt_errors = _quality_gate_errors(
                    receipt_gate, "CANONICAL_QUALITY_RECEIPT_VALIDATOR"
                )
                errors.extend(receipt_errors)
                if not receipt_errors:
                    receipt_accepts_quality = (
                        receipt_gate.get("canonical_quality_accepted") is True
                    )

        codes = sorted(set(errors))
        return {
            "status": "PASS" if not codes else "FAIL",
            "blocking_codes": codes,
            "canonical_quality_accepted": not codes and receipt_accepts_quality,
            "receipt_schema_sha256": receipt_schema.sha256,
            "evidence_manifest_sha256": manifest_sha256,
                "downstream_authorized": False,
        }

    def canonical_quality_finalize(
        self,
        *,
        profile_slug: str,
        candidate: dict[str, Any],
        evidence_manifest: dict[str, Any],
        scope_authority_packet: dict[str, Any],
        semantic_result: dict[str, Any],
        candidate_revision: str,
        semantic_execution_receipt_ref: str,
        producer_execution_id: str,
        reviewer_execution_id: str,
        producer_execution_receipt_ref: str,
        issued_at: str,
    ) -> dict[str, Any]:
        expected_evidence_manifest_sha256 = canonical_json_sha256(evidence_manifest)
        binding = self.repository.runtime_binding(profile_slug)
        quality = binding.canonical_quality if binding is not None else None
        if not isinstance(quality, dict):
            return {
                "status": "FAIL",
                "blocking_codes": ["CANONICAL_QUALITY_NOT_BOUND"],
                "canonical_quality_accepted": False,
                "quality_receipt": None,
                "downstream_authorized": False,
            }

        pack_id = candidate.get("profile_pack_id")
        if pack_id not in set(quality.get("required_for_profile_pack_ids") or []):
            return {
                "status": "NOT_APPLICABLE",
                "blocking_codes": [],
                "canonical_quality_accepted": False,
                "quality_receipt": None,
                "downstream_authorized": False,
            }

        # The finalization endpoint is callable separately from execution. Recheck
        # the supplied candidate with the same bound floors before issuing a receipt.
        contract_gate, payload = self.contract(
            profile_slug=profile_slug,
            raw_output=json.dumps(candidate, ensure_ascii=False),
            schema=self.repository.runtime_schema(profile_slug),
            evidence_manifest=evidence_manifest,
        )
        utility_gate = self.semantic_utility(
            profile_slug=profile_slug,
            payload=payload,
            contract_gate=contract_gate,
            evidence_manifest=evidence_manifest,
        )
        floor_errors = _quality_gate_errors(contract_gate, "CANONICAL_QUALITY_CONTRACT_FLOOR")
        floor_errors.extend(_quality_gate_errors(utility_gate, "CANONICAL_QUALITY_UTILITY_FLOOR"))
        if floor_errors:
            return {
                "status": "FAIL",
                "blocking_codes": sorted(set(floor_errors)),
                "canonical_quality_accepted": False,
                "quality_receipt": None,
                "profile_contract_valid": contract_gate,
                "semantic_utility": utility_gate,
                "downstream_authorized": False,
            }

        semantic_binding = self.repository.load_canonical_quality_validator(
            profile_slug, "semantic_result_validator"
        )
        materializer_binding = self.repository.load_canonical_quality_validator(
            profile_slug, "quality_receipt_materializer"
        )
        if semantic_binding is None or materializer_binding is None:
            return {
                "status": "FAIL",
                "blocking_codes": ["CANONICAL_QUALITY_FINALIZER_BINDING_INCOMPLETE"],
                "canonical_quality_accepted": False,
                "quality_receipt": None,
                "downstream_authorized": False,
            }

        expected_candidate_sha256 = canonical_json_sha256(candidate)
        expected_scope_packet_sha256 = canonical_json_sha256(scope_authority_packet)
        review_input_binding = independent_review_input_binding(
            candidate, evidence_manifest, scope_authority_packet
        )
        expected_review_input_sha256 = review_input_binding["review_input_sha256"]
        semantic_module, semantic_callable_name = semantic_binding
        semantic_callable = getattr(semantic_module, semantic_callable_name, None)
        if not callable(semantic_callable):
            return {
                "status": "FAIL",
                "blocking_codes": ["CANONICAL_QUALITY_SEMANTIC_VALIDATOR_CALLABLE_MISSING"],
                "canonical_quality_accepted": False,
                "quality_receipt": None,
                "downstream_authorized": False,
            }

        try:
            semantic_gate = semantic_callable(
                semantic_result,
                scope_packet=scope_authority_packet,
                expected_candidate_sha256=expected_candidate_sha256,
                expected_scope_packet_sha256=expected_scope_packet_sha256,
                expected_evidence_manifest_sha256=expected_evidence_manifest_sha256,
                expected_reviewer_execution_id=reviewer_execution_id,
                expected_review_input_sha256=expected_review_input_sha256,
            )
        except Exception as exc:
            return {
                "status": "FAIL",
                "blocking_codes": [
                    "CANONICAL_QUALITY_SEMANTIC_VALIDATOR_EXCEPTION:" + type(exc).__name__
                ],
                "canonical_quality_accepted": False,
                "quality_receipt": None,
                "downstream_authorized": False,
            }
        semantic_errors = _quality_gate_errors(
            semantic_gate, "CANONICAL_QUALITY_SEMANTIC_VALIDATOR"
        )
        if semantic_errors:
            return {
                "status": "FAIL",
                "blocking_codes": sorted(set(semantic_errors)),
                "canonical_quality_accepted": False,
                "quality_receipt": None,
                "semantic_result_validation": semantic_gate,
                "downstream_authorized": False,
            }

        materializer_module, materializer_callable_name = materializer_binding
        materializer_callable = getattr(
            materializer_module, materializer_callable_name, None
        )
        if not callable(materializer_callable):
            return {
                "status": "FAIL",
                "blocking_codes": ["CANONICAL_QUALITY_MATERIALIZER_CALLABLE_MISSING"],
                "canonical_quality_accepted": False,
                "quality_receipt": None,
                "semantic_result_validation": semantic_gate,
                "downstream_authorized": False,
            }

        try:
            quality_receipt = materializer_callable(
                candidate,
                evidence_manifest,
                semantic_result,
                candidate_revision=candidate_revision,
                semantic_execution_receipt_ref=semantic_execution_receipt_ref,
                issued_at=issued_at,
                producer_execution_id=producer_execution_id,
                reviewer_execution_id=reviewer_execution_id,
                producer_execution_receipt_ref=producer_execution_receipt_ref,
                review_input_sha256=expected_review_input_sha256,
            )
        except Exception as exc:
            return {
                "status": "FAIL",
                "blocking_codes": [
                    "CANONICAL_QUALITY_MATERIALIZATION_FAILED:" + type(exc).__name__
                ],
                "canonical_quality_accepted": False,
                "quality_receipt": None,
                "semantic_result_validation": semantic_gate,
                "downstream_authorized": False,
            }

        quality_gate = self.canonical_quality(
            profile_slug=profile_slug,
            candidate=candidate,
            evidence_manifest=evidence_manifest,
            semantic_result=semantic_result,
            quality_receipt=quality_receipt,
            scope_authority_packet=scope_authority_packet,
        )
        return {
            **quality_gate,
            "quality_receipt": quality_receipt if quality_gate.get("status") == "PASS" else None,
            "profile_contract_valid": contract_gate,
            "semantic_utility": utility_gate,
            "semantic_result_validation": semantic_gate,
            "expected_candidate_sha256": expected_candidate_sha256,
            "expected_scope_packet_sha256": expected_scope_packet_sha256,
            "expected_evidence_manifest_sha256": expected_evidence_manifest_sha256,
            "review_input_binding": review_input_binding,
            "expected_review_input_sha256": expected_review_input_sha256,
            "downstream_authorized": False,
        }

    def _canonical_errors(
        self,
        profile_slug: str,
        payload: dict[str, Any],
        *,
        evidence_manifest: dict[str, Any] | None = None,
    ) -> list[dict[str, Any]]:
        module = self.repository.load_validator(profile_slug)
        if module is None:
            return []
        try:
            callable_name = self.repository.validator_callable_name(profile_slug)
            if callable_name is not None:
                validator = getattr(module, callable_name, None)
                if not callable(validator):
                    return [{"code": "CANONICAL_PROFILE_VALIDATOR_CALLABLE_MISSING", "path": "$"}]
                if self._supports_evidence_manifest(validator):
                    result = validator(payload, evidence_manifest=evidence_manifest)
                else:
                    result = validator(payload)
                if isinstance(result, dict):
                    raw_errors = result.get("errors")
                    if raw_errors is None:
                        raw_errors = result.get("blocking_codes")
                    if raw_errors is None:
                        explicitly_clean = result.get("status") == "PASS" or result.get("valid") is True
                        raw_errors = [] if explicitly_clean else ["CANONICAL_PROFILE_VALIDATOR_RESULT_INVALID"]
                    if not isinstance(raw_errors, list):
                        raw_errors = ["CANONICAL_PROFILE_VALIDATOR_RESULT_INVALID"]
                    else:
                        raw_errors = list(raw_errors)
                    declared_codes = result.get("blocking_codes", [])
                    if not isinstance(declared_codes, list):
                        raw_errors.append("CANONICAL_PROFILE_VALIDATOR_RESULT_INVALID")
                    else:
                        raw_errors.extend(declared_codes)
                    if result.get("valid") is False or ("status" in result and result["status"] != "PASS"):
                        if not raw_errors:
                            raw_errors.append("CANONICAL_PROFILE_VALIDATOR_NOT_PASS")
                elif isinstance(result, list):
                    raw_errors = result
                else:
                    raw_errors = ["CANONICAL_PROFILE_VALIDATOR_RESULT_INVALID"]
            elif profile_slug == "product_director_lf":
                result = module.validate(payload)
                raw_errors = result.get("errors", []) if isinstance(result, dict) else []
            elif profile_slug == "ui_architect":
                raw_errors = module.validate(payload)
            elif profile_slug == "quality_pack":
                raw_errors = module.validate_routing(payload.get("verdict"), payload.get("routing"))
            else:
                raw_errors = []
        except Exception as exc:
            return [
                {
                    "code": "CANONICAL_PROFILE_VALIDATOR_EXCEPTION",
                    "path": "$",
                    "message": type(exc).__name__,
                }
            ]
        normalized: list[dict[str, Any]] = []
        for item in raw_errors or []:
            if isinstance(item, dict):
                normalized.append(
                    {
                        "code": str(item.get("code", "PROFILE_VALIDATOR_ERROR")),
                        "path": str(item.get("path", item.get("detail", "$"))),
                        "message": str(item.get("message", item.get("detail", "")))[:500],
                    }
                )
            else:
                normalized.append({"code": str(item), "path": "$"})
        return normalized

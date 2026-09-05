from __future__ import annotations

import json
from typing import Any

from jsonschema import Draft202012Validator, SchemaError

from .repository import RepositoryBindings, SchemaBinding

PASS_QUALITY_VERDICTS = {"PASS_TO_COMPOSER", "PASS_WITH_RESTRICTIONS"}
NOMINAL_EVIDENCE = {"ok", "pass", "passed", "valid", "done", "complete", "yes"}
UI_SCHEMA_ONLY_MODES = {"UI_FOCUSED_DECISION", "UI_MISSING_INPUT"}


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


def _ui_focused_semantic_v3_errors(values: dict[str, str]) -> list[str]:
    """General field-semantic hardening for Focused UI Decision.

    Strategy 26: deterministic, bilingual, and independent from one concrete UI defect.
    The canonical schema remains unchanged; this only rejects semantically weak PASSes.
    """
    import re

    errors: list[str] = []

    def has_any(value: str, markers: tuple[str, ...]) -> bool:
        return any(marker in value for marker in markers)

    def tokens(value: str) -> list[str]:
        return re.findall(r"[a-záéíóúüñ0-9#%+_-]+", value.lower())

    subject = values.get("decision_subject", "")
    selected = values.get("selected_visual_type", "")
    generic_subjects = {
        "ui decision", "visual decision", "design decision", "interface decision",
        "ui treatment", "decisión ui", "decision ui", "decisión visual",
        "decision visual", "decisión de diseño", "decision de diseño",
        "tratamiento ui",
    }
    treatment_markers = (
        "affordance", "indicator", "cue", "icon", "outline", "border",
        "gradient", "fade", "shadow", "sticky", "divider", "badge",
        "highlight", "label", "tooltip", "scrollbar", "scroll bar",
        "handle", "rail", "tab", "chip", "card", "button", "link",
        "spacing", "layout", "alignment", "animation", "transition",
        "indicador", "señal", "icono", "ícono", "contorno", "borde",
        "gradiente", "sombra", "fijo", "divisor", "etiqueta", "resaltado",
        "barra", "desplazamiento", "tarjeta", "botón", "boton", "enlace",
        "espaciado", "alineación", "alineacion", "animación", "animacion",
        "transición", "transicion",
    )
    if subject in generic_subjects:
        errors.append("UI_FOCUSED_DECISION_SUBJECT_NON_CONCRETE")
    if selected and subject and (selected == subject or selected in subject):
        errors.append("UI_FOCUSED_SELECTED_TREATMENT_RESTATES_SUBJECT")
    if selected and len(tokens(selected)) < 3 and not has_any(selected, treatment_markers):
        errors.append("UI_FOCUSED_SELECTED_TREATMENT_NON_CONCRETE")

    surface = values.get("base_color_or_surface", "")
    surface_markers = (
        "#", "rgb", "hsl", "var(", "token", "surface", "background",
        "transparent", "white", "black", "neutral", "gray", "grey",
        "card", "panel", "canvas", "existing", "color", "superficie",
        "fondo", "transparente", "blanco", "negro", "neutro", "gris",
        "tarjeta", "existente",
    )
    if surface and not has_any(surface, surface_markers):
        errors.append("UI_FOCUSED_BASE_SURFACE_NON_CONCRETE")

    coverage = values.get("size_or_coverage", "")
    coverage_markers = (
        "only", "edge", "viewport", "region", "area", "component", "screen",
        "card", "table", "row", "column", "header", "footer", "panel",
        "section", "container", "boundary", "width", "height", "full", "%",
        "px", "solo", "borde", "región", "área", "componente", "pantalla",
        "tarjeta", "tabla", "fila", "columna", "encabezado", "pie", "sección",
        "seccion", "contenedor", "límite", "limite", "ancho", "alto", "completo",
    )
    if coverage and not has_any(coverage, coverage_markers):
        errors.append("UI_FOCUSED_SIZE_OR_COVERAGE_SCOPE_MISSING")

    density = values.get("density_limits", "")
    density_markers = (
        "one", "single", "two", "three", " per ", "max", "maximum", "only",
        "no more", "at most", "limit", "count", "layer", "line", "element",
        "cue", "viewport", "item", "%", "px", "uno", "una", "dos", "tres",
        " por ", "máximo", "maximo", "solo", "sola", "no más", "no mas",
        "como máximo", "como maximo", "límite", "limite", "cantidad", "capa",
        "línea", "linea", "elemento", "señal", "indicador",
    )
    if density:
        if re.fullmatch(r"\d+(?:\.\d+)?", density):
            errors.append("UI_FOCUSED_DENSITY_LIMITS_NUMERIC_ONLY")
        elif not has_any(f" {density} ", density_markers):
            errors.append("UI_FOCUSED_DENSITY_LIMITS_NON_CONCRETE_V3")

    depth = values.get("depth_style", "")
    depth_markers = (
        "elevation", "shadow", "flat", "depth", "layer", "raised", "inset",
        "border", "z-", "no added", "none", "elevación", "elevacion", "sombra",
        "plano", "profundidad", "capa", "elevado", "borde", "sin elevación",
        "sin elevacion", "sin sombra",
    )
    if depth and (
        not has_any(depth, depth_markers)
        or (len(tokens(depth)) < 2 and depth not in {"flat", "none", "plano"})
    ):
        errors.append("UI_FOCUSED_DEPTH_STYLE_NON_CONCRETE")

    weight = values.get("visual_weight", "")
    weight_markers = (
        "primary", "secondary", "tertiary", "hierarchy", "prominence", "opacity",
        "contrast", "relative", "subordinate", "dominant", "less than", "more than",
        "%", "primario", "secundario", "terciario", "jerarquía", "jerarquia",
        "prominencia", "opacidad", "contraste", "relativo", "subordinado",
        "dominante", "menos que", "más que", "mas que",
    )
    if weight and (not has_any(weight, weight_markers) or len(tokens(weight)) < 2):
        errors.append("UI_FOCUSED_VISUAL_WEIGHT_NON_CONCRETE")

    relationship = values.get("relationship_to_main_element", "")
    relation_markers = (
        "support", "without", "relative", "adjacent", "inside", "within", "before",
        "after", "below", "above", "next to", "around", "aligned", "anchored",
        "attached", "preserve", "competing", "replacing", "does not", "soporta",
        "apoya", "sin", "relativo", "adyacente", "dentro", "antes", "después",
        "despues", "debajo", "encima", "junto", "alrededor", "alineado",
        "anclado", "adjunto", "preserva", "compite", "reemplaza", "no ",
    )
    ui_targets = (
        "table", "content", "action", "cta", "control", "card", "component",
        "element", "navigation", "header", "row", "button", "field", "primary",
        "main", "selector", "tab", "panel", "tabla", "contenido", "acción",
        "accion", "tarjeta", "componente", "elemento", "navegación", "navegacion",
        "encabezado", "fila", "botón", "boton", "campo", "primario", "principal",
    )
    if relationship and not (has_any(relationship, relation_markers) and has_any(relationship, ui_targets)):
        errors.append("UI_FOCUSED_RELATIONSHIP_NON_CONCRETE")

    implementation = values.get("implementation_format", "")
    implementation_markers = (
        "css", "svg", "token", "component", "asset", "layout", "html",
        "javascript", "typescript", "tailwind", "class", "pseudo-element", "style",
        "gradient", "border", "shadow", "icon", "componente", "recurso", "clase",
        "pseudo-elemento", "estilo", "gradiente", "borde", "sombra", "icono", "ícono",
    )
    implementation_targets = (
        "card", "table", "component", "token", "icon", "viewport", "header",
        "row", "field", "button", "tab", "panel", "container", "selector", "cue",
        "edge", "rule", "tarjeta", "tabla", "componente", "icono", "ícono",
        "encabezado", "fila", "campo", "botón", "boton", "contenedor", "señal",
        "borde", "regla",
    )
    if implementation and not (
        has_any(implementation, implementation_markers)
        and has_any(implementation, implementation_targets)
        and len(tokens(implementation)) >= 3
    ):
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


class OutputGates:
    def __init__(self, repository: RepositoryBindings) -> None:
        self.repository = repository

    def contract(
        self, *, profile_slug: str, raw_output: Any, schema: SchemaBinding
    ) -> tuple[dict[str, Any], dict[str, Any] | None]:
        payload, parse_errors = strict_json_object(raw_output)
        errors: list[dict[str, Any]] = [
            {"code": code, "path": "$"} for code in parse_errors
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
                        }
                    )
            except SchemaError as exc:
                errors.append(
                    {
                        "code": "CANONICAL_JSON_SCHEMA_INVALID",
                        "path": "$schema",
                        "message": str(exc)[:500],
                    }
                )
            # The canonical UI Python validator is explicitly the Production UI Spec
            # validator. Focused Decision and Missing Input already have exact canonical
            # schemas and must not be falsely rejected by production-only fields.
            if not (
                profile_slug == "ui_architect" and schema.mode in UI_SCHEMA_ONLY_MODES
            ):
                errors.extend(self._canonical_errors(profile_slug, payload))
        blocking = sorted({str(item.get("code")) for item in errors})
        return (
            {
                "status": "PASS" if not errors else "FAIL",
                "validator_scope": "CANONICAL_SCHEMA_PLUS_APPLICABLE_PROFILE_VALIDATOR",
                "schema_sha256": schema.sha256,
                "schema_source_refs": list(schema.source_refs),
                "schema_mode": schema.mode,
                "blocking_codes": blocking,
                "errors": errors,
            },
            payload,
        )

    def semantic_utility(
        self,
        *,
        profile_slug: str,
        payload: dict[str, Any] | None,
        contract_gate: dict[str, Any],
    ) -> dict[str, Any]:
        if contract_gate.get("status") != "PASS" or payload is None:
            return {
                "status": "NOT_EVALUATED",
                "evaluation_scope": "DETERMINISTIC_UTILITY_FLOOR",
                "blocking_codes": ["PROFILE_CONTRACT_INVALID"],
                "independent_semantic_judge": "NOT_EXECUTED",
            }
        errors: list[str] = []
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
                    for exclusion in exclusions:
                        if not isinstance(exclusion, str):
                            continue
                        normalized = " ".join(exclusion.lower().strip().split())
                        if selected and normalized and (selected == normalized or selected in normalized):
                            errors.append("UI_FOCUSED_SELECTED_TREATMENT_EXCLUDED")
                            break

                generic_only = {
                    "small", "medium", "large", "thin", "thick", "light", "dark",
                    "above", "below", "left", "right", "center", "standard", "default",
                    "normal", "css", "svg", "component", "visual", "ui",
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
            }
        return {
            "status": "PASS" if not errors else "FAIL",
            "evaluation_scope": "DETERMINISTIC_UTILITY_FLOOR_NOT_FINAL_SEMANTIC_AUTHORITY",
            "blocking_codes": sorted(set(errors)),
            "independent_semantic_judge": "NOT_EXECUTED",
            "downstream_authorized": False,
        }

    def _canonical_errors(
        self, profile_slug: str, payload: dict[str, Any]
    ) -> list[dict[str, Any]]:
        module = self.repository.load_validator(profile_slug)
        if module is None:
            return []
        try:
            if profile_slug == "product_director_lf":
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

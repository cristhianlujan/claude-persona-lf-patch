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
                for key in (
                    "decision_subject",
                    "selected_visual_type",
                    "relationship_to_main_element",
                    "implementation_format",
                ):
                    value = payload.get(key)
                    if not isinstance(value, str) or len(value.strip()) < 3:
                        errors.append(f"UI_FOCUSED_{key.upper()}_WEAK")
                exclusions = payload.get("hard_exclusions")
                if not isinstance(exclusions, list) or not exclusions:
                    errors.append("UI_FOCUSED_HARD_EXCLUSIONS_EMPTY")
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

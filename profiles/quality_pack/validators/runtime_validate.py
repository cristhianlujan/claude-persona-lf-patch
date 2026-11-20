#!/usr/bin/env python3
"""Quality Pack's profile-local native Step50 gate.

A conservative RETURN is valid output, not a Quality PASS. Positive Quality
verdicts require resolver-backed 5-gate proof. This validator never promotes
rules, writes business state, or treats the producer's Step70 as independent.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

from jsonschema import Draft202012Validator

from validate_routing import validate_routing

BASE = Path(__file__).resolve().parents[1]
SCORE_FIELDS = (
    "contract_schema_compliance",
    "evidence_integrity",
    "lf_safety_governance",
    "handoff_readiness",
    "leakage_scope_control",
)
POSITIVE = {"PASS_TO_COMPOSER", "PASS_WITH_RESTRICTIONS"}
RETURNING = {"RETURN_TO_WORKER_FOR_SELF_REPAIR", "RETURN_TO_ORCHESTRATOR"}
GATES = ("structural", "provenance", "semantic", "artifact", "upstream")


def validate(payload):
    errors = []
    if not isinstance(payload, dict):
        return {"valid": False, "errors": ["QUALITY_OUTPUT_OBJECT_REQUIRED"]}

    schema_file = BASE / "schemas" / "quality_review.schema.json"
    try:
        schema = json.loads(schema_file.read_text(encoding="utf-8"))
        Draft202012Validator.check_schema(schema)
        for issue in Draft202012Validator(schema).iter_errors(payload):
            path = ".".join(map(str, issue.absolute_path)) or "$"
            errors.append("QUALITY_SCHEMA:" + path + ":" + str(issue.validator))
    except (OSError, ValueError, Exception) as exc:
        # Missing, malformed, or unusable schema never turns into a PASS.
        errors.append("QUALITY_CANONICAL_SCHEMA_UNAVAILABLE:" + type(exc).__name__)
        return {"valid": False, "errors": errors}

    verdict = payload.get("verdict")
    errors.extend("QUALITY_ROUTE:" + code for code in validate_routing(
        verdict, payload.get("routing")
    ))

    score = payload.get("score_breakdown")
    if not isinstance(score, dict):
        errors.append("QUALITY_SCORE_OBJECT_REQUIRED")
        score_total = None
    else:
        values = [score.get(field) for field in SCORE_FIELDS]
        if any(type(value) is not int or not 0 <= value <= 5 for value in values):
            errors.append("QUALITY_SCORE_CRITERION_INVALID")
            score_total = None
        else:
            score_total = sum(values)
            if type(score.get("total")) is not int or score["total"] != score_total:
                errors.append("QUALITY_SCORE_TOTAL_MISMATCH")
        if verdict == "PASS_TO_COMPOSER" and (score_total is None or score_total < 23):
            errors.append("QUALITY_PASS_SCORE_BELOW_23")
        if verdict == "PASS_WITH_RESTRICTIONS" and (score_total is None or score_total < 20):
            errors.append("QUALITY_RESTRICTED_PASS_SCORE_BELOW_20")

    evidence = payload.get("evidence_map")
    if not isinstance(evidence, list) or not evidence:
        errors.append("QUALITY_EVIDENCE_MAP_REQUIRED")
    else:
        for i, item in enumerate(evidence):
            if not isinstance(item, dict):
                errors.append(f"QUALITY_EVIDENCE_ENTRY_INVALID:{i}")
                continue
            if any(not isinstance(item.get(field), str) or not item[field].strip()
                   for field in ("area", "source_ref", "observed", "status")):
                errors.append(f"QUALITY_EVIDENCE_ENTRY_INCOMPLETE:{i}")

    codes = payload.get("blocking_codes")
    actions = payload.get("repair_actions")
    if verdict in RETURNING:
        if not isinstance(codes, list) or not codes or any(
            not isinstance(x, str) or not x.strip() for x in codes
        ):
            errors.append("QUALITY_RETURN_BLOCKING_CODES_REQUIRED")
        if not isinstance(actions, list) or not actions:
            errors.append("QUALITY_RETURN_REPAIR_ACTION_REQUIRED")
        else:
            for i, item in enumerate(actions):
                if not isinstance(item, dict) or any(
                    not isinstance(item.get(field), str) or not item[field].strip()
                    for field in (
                        "target_worker", "missing_or_failed_item", "why_it_fails",
                        "required_fix", "blocking_code",
                    )
                ):
                    errors.append(f"QUALITY_REPAIR_ACTION_INCOMPLETE:{i}")

    if verdict in POSITIVE:
        # A producer score, verified-looking flags or same-context Step70 does
        # not prove independence. Full independent resolver-backed evidence is
        # mandatory; the already existing GOV-037 bundle checker does the work.
        bundle = payload.get("quality_gate_bundle")
        if not isinstance(bundle, dict):
            errors.append("QUALITY_GOV037_FULL_GATE_BUNDLE_REQUIRED")
        elif bundle.get("final_verdict") != verdict:
            errors.append("QUALITY_GATE_VERDICT_MISMATCH")
        else:
            gates = bundle.get("gates")
            if not isinstance(gates, dict) or any(
                not isinstance(gates.get(gate), dict)
                or gates[gate].get("applicable") is not True
                or gates[gate].get("status") != "PASS"
                for gate in GATES
            ):
                errors.append("QUALITY_FIVE_GATES_NOT_INDEPENDENTLY_PASSED")
            else:
                try:
                    from validate_gate_bundle import validate_bundle
                    errors.extend(
                        "QUALITY_GOV037:" + x for x in validate_bundle(bundle)
                    )
                except Exception as exc:
                    errors.append("QUALITY_GOV037_RESOLVER_UNAVAILABLE:" + type(exc).__name__)
        if codes or actions:
            errors.append("QUALITY_PASS_WITH_BLOCKERS_FORBIDDEN")

    # Quality is not the owner and its output cannot authorize rule promotion.
    if payload.get("promotion_authorized") is True or payload.get("promotion_request_created") is True:
        errors.append("QUALITY_PROMOTION_AUTHORITY_FORBIDDEN")

    return {"valid": not errors, "errors": sorted(set(errors))}


def main():
    try:
        result = validate(json.load(sys.stdin))
    except (ValueError, UnicodeError) as exc:
        result = {"valid": False, "errors": ["QUALITY_INPUT_JSON_INVALID:" + type(exc).__name__]}
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    return 0 if result["valid"] else 1


if __name__ == "__main__":
    raise SystemExit(main())

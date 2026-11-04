"""A1 / Intake Normalize. Reusable pure skill: no Router, RUN, SQL, or profile dependency.

Canonical functional payload: REQUEST_CONTEXT_V1, schema kept only in its
source-of-truth path under sandbox/lf_contract_gate_test/... .
"""
from __future__ import annotations

import copy
from pathlib import Path
from typing import Any

from jsonschema import Draft202012Validator
import json

BASE = Path(__file__).resolve().parents[1]
ROOT = BASE.parents[1]
CANONICAL_SCHEMA = ROOT / "sandbox/lf_contract_gate_test/programming_agent_four_stage/wave1_boundary_contracts/analysis_request_context_v1.schema.json"


def _schema(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def _problems(value: Any, schema: dict) -> list[str]:
    return ["/".join(map(str, error.absolute_path)) or "ROOT"
            for error in sorted(Draft202012Validator(schema).iter_errors(value),
                                key=lambda error: (list(map(str, error.absolute_path)), error.message))]


def _unique(values: list[str]) -> list[str]:
    return list(dict.fromkeys(v.strip() for v in values))


def run(data: Any) -> dict:
    """Return candidate skill result; never claims external verification or effects."""
    base = {
        "schema_version": "A1_SKILL_CANDIDATE_RESULT_V1",
        "skill_code": "PROGRAMMING_ANALYSIS_A1",
        "business": data.get("business") if isinstance(data, dict) else None,
        "status": "BLOCKED",
        "payload": None,
        "declared_intent_kind": None,
        "blocking_codes": [],
        "next_capability": None,
        "external_authority_verified": False,
        "operationally_integrated": False,
        "effects_executed": False,
    }
    if not isinstance(data, dict):
        base["blocking_codes"] = ["INPUT_NOT_OBJECT"]
        return base
    errors = _problems(data, _schema(BASE / "schemas/input.schema.json"))
    if data.get("business") != "LF":
        errors.append("BUSINESS_BINDING_NOT_QUALIFIED")
    if errors:
        base["blocking_codes"] = sorted(set("INPUT_SCHEMA:" + x for x in errors))
        return base
    normalized = copy.deepcopy(data)
    for section in ("request_identity", "objective"):
        normalized[section] = {k: v.strip() if isinstance(v, str) else v
                               for k, v in normalized[section].items()}
    for k in ("target_hints", "source_refs", "constraints"):
        normalized[k] = _unique(normalized[k])
    facts = []
    for item in normalized["provided_facts"]:
        facts.append({**item,
                      "fact_code": item["fact_code"].strip(),
                      "source_ref": item["source_ref"].strip()})
    normalized["provided_facts"] = facts
    normalized["ambiguities"] = [
        {**item, "code": item["code"].strip(), "statement": item["statement"].strip()}
        for item in normalized["ambiguities"]
    ]
    if any(not normalized["objective"][k] for k in ("problem_statement", "desired_outcome")):
        base["blocking_codes"] = ["ESSENTIAL_OBJECTIVE_MISSING"]
        return base
    if any(not v for k in ("target_hints", "source_refs", "constraints") for v in normalized[k]):
        base["blocking_codes"] = ["BLANK_REFERENCE_OR_CONSTRAINT"]
        return base
    if any(x["source_ref"] not in normalized["source_refs"] for x in facts):
        base["blocking_codes"] = ["UNSUPPORTED_PROVIDED_FACT_REF"]
        return base
    payload = {k: normalized[k] for k in (
        "request_identity", "objective", "target_hints", "source_refs",
        "provided_facts", "constraints", "ambiguities"
    )}
    payload.update(schema_version="REQUEST_CONTEXT_V1", no_solution_inferred=True)
    defects = _problems(payload, _schema(CANONICAL_SCHEMA))
    if defects:
        base["blocking_codes"] = ["CANONICAL_OUTPUT_INVALID:" + x for x in defects]
        return base
    base["payload"] = payload
    base["declared_intent_kind"] = normalized["declared_intent_kind"]
    if any(a["resolution_state"] == "OPEN" and a["materiality"] in ("MATERIAL", "UNKNOWN")
           for a in payload["ambiguities"]):
        base["status"] = "REQUIRES_DECISION"
        base["blocking_codes"] = ["MATERIAL_INTENT_AMBIGUITY"]
    elif not payload["target_hints"]:
        base["status"] = "NEED_MORE_EVIDENCE"
        base["blocking_codes"] = ["TARGET_HINT_MISSING"]
    else:
        base["status"] = "VALID_OUTPUT"
        base["next_capability"] = "A2"
    if _problems(base, _schema(BASE / "schemas/output.schema.json")):
        raise ValueError("A1_INTERNAL_OUTPUT_SCHEMA_FAILURE")
    return base

"""A1 / Intake Normalize. Reusable pure skill: no Router, RUN, SQL, or profile dependency.

Canonical functional payload: REQUEST_CONTEXT_V1, schema kept only in its
source-of-truth path under sandbox/lf_contract_gate_test/... .
"""
from __future__ import annotations

import copy
import importlib.util
import json
import re
from hashlib import sha256
from pathlib import Path
from typing import Any

from jsonschema import Draft202012Validator

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


def _explicit_other_business_source(ref: str) -> bool:
    """Only deny explicit known cross-business namespaces, never guess authority."""
    return bool(re.match(r"(?i)^(?:saly(?=[:./]|$)|supabase://saly(?=[:./]|$))", ref))


def _normalized_prompt(payload: dict) -> str:
    objective = payload["objective"]
    lines = [
        "Solicitud: " + objective["problem_statement"],
        "Resultado esperado: " + objective["desired_outcome"],
    ]
    if payload["target_hints"]:
        lines.append("Identificadores o referencias recibidas (sin verificar): " + ", ".join(payload["target_hints"]))
    if payload["provided_facts"]:
        lines.append("Datos recibidos (declarados, no verificados): " + "; ".join(
            fact["fact_code"] + "=" + (
                fact["value"] if isinstance(fact["value"], str)
                else json.dumps(fact["value"], ensure_ascii=False, sort_keys=True)
            ) + " [fuente: " + fact["source_ref"] + "]"
            for fact in payload["provided_facts"]
        ))
    if payload["constraints"]:
        lines.append("Restricciones recibidas: " + "; ".join(payload["constraints"]))
    return "\n".join(lines)


def _guard_check(data: dict, result: dict) -> list[str]:
    spec = importlib.util.spec_from_file_location(
        "a1_deterministic_guard", BASE / "judges/semantic_guard.py"
    )
    if spec is None or spec.loader is None:
        return ["GUARD_UNAVAILABLE"]
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.check(data, result)


def run(data: Any) -> dict:
    """Return candidate skill result; never claims external verification or effects."""
    base = {
        "schema_version": "A1_SKILL_CANDIDATE_RESULT_V1",
        "skill_code": "PROGRAMMING_ANALYSIS_A1",
        "business": data.get("business") if isinstance(data, dict) else None,
        "status": "BLOCKED",
        "payload": None,
        "declared_intent_kind": None,
        "normalized_prompt": None,
        "original_request_sha256": None,
        "semantic_review_required": False,
        "interpretation_state": "NO_VALID_INTERPRETATION",
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
    original = data.get("original_request")
    mode = data.get("input_mode", "STRUCTURED")
    if isinstance(original, str) and original.strip():
        base["original_request_sha256"] = sha256(original.encode("utf-8")).hexdigest()
        base["semantic_review_required"] = True
    if mode == "SEMANTIC_CANDIDATE" and not isinstance(original, str):
        errors.append("ORIGINAL_LITERAL_REQUIRED_FOR_SEMANTIC_CANDIDATE")
    if isinstance(original, str) and not original.strip():
        errors.append("ORIGINAL_LITERAL_EMPTY")
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
    if any(_explicit_other_business_source(ref) for ref in normalized["source_refs"]):
        base["blocking_codes"] = ["CROSS_BUSINESS_SOURCE_REQUIRES_QUALIFIED_BINDING"]
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
    base["normalized_prompt"] = _normalized_prompt(payload)
    base["interpretation_state"] = (
        "SEMANTIC_CANDIDATE_UNATTESTED"
        if base["semantic_review_required"]
        else "PRESTRUCTURED_UNATTESTED"
    )
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
    faults = _guard_check(data, base)
    if faults:
        base["status"] = "BLOCKED"
        base["payload"] = None
        base["normalized_prompt"] = None
        base["next_capability"] = None
        base["interpretation_state"] = "NO_VALID_INTERPRETATION"
        base["blocking_codes"] = sorted(set(faults))
    return base

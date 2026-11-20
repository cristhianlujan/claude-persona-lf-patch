"""Product Director local deterministic utility; never a semantic judge."""
from __future__ import annotations

def evaluate(payload, contract_gate):
    if not isinstance(payload, dict) or not isinstance(contract_gate, dict) or contract_gate.get("status") != "PASS":
        return {"status": "FAIL", "blocking_codes": ["PRODUCT_CONTRACT_NOT_PASS"]}
    output_type = payload.get("output_type")
    if output_type == "PRODUCT_DIRECTION_SPEC":
        deliverable = payload.get("deliverable_created")
        missing = []
        if not isinstance(deliverable, dict):
            missing.append("PRODUCT_DELIVERABLE_MISSING")
        else:
            if not isinstance(deliverable.get("product_decision"), dict):
                missing.append("PRODUCT_DECISION_MISSING")
            if not deliverable.get("acceptance_criteria"):
                missing.append("PRODUCT_ACCEPTANCE_CRITERIA_EMPTY")
            if not isinstance(deliverable.get("decision_lineage"), dict):
                missing.append("PRODUCT_DECISION_LINEAGE_MISSING")
        return {"status": "FAIL" if missing else "PASS", "blocking_codes": missing}
    if output_type in {"PRODUCT_MISSING_INPUT_STATE", "BLOCKED_PRODUCT_RISK"}:
        # Exact canonical schema/validator already evaluated these states;
        # do not conflate their admissibility with promotion authorization.
        return {"status": "PASS", "blocking_codes": []}
    return {"status": "FAIL", "blocking_codes": ["PRODUCT_OUTPUT_TYPE_UNDECLARED"]}

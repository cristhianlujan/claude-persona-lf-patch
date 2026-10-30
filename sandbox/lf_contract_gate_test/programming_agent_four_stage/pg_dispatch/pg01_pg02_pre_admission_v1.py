"""PG-01 to PG-02 qualification bridge, no production dispatch or DB writes."""
PLAN = "PROGRAMMING_AGENT_PROGRAMMING_REMEDIATION_V1"
UNITS = {"PG-01": "PROG-REM-001", "PG-02": "PROG-REM-002"}


def qualify(snapshot):
    reasons = {"AUTHENTICATED_DISPATCH_HANDLER_REQUIRED"}
    if not isinstance(snapshot, dict):
        return {"verdict": "BLOCKED", "authority": "NONE",
                "reason_codes": sorted(reasons | {"INVALID_SNAPSHOT"})}
    if set(snapshot) != {"plan_code", "units", "dependencies", "pg01_receipt",
                         "bindings", "dispatcher"}:
        reasons.add("SNAPSHOT_FIELDS_MISMATCH")
    if snapshot.get("plan_code") != PLAN:
        reasons.add("PLAN_MISMATCH")
    units = snapshot.get("units")
    if not isinstance(units, dict) or set(units) != set(UNITS):
        reasons.add("INVALID_UNITS")
    else:
        for key, work_code in UNITS.items():
            row = units[key]
            if not isinstance(row, dict) or row.get("work_code") != work_code:
                reasons.add("UNIT_MAPPING_MISMATCH")
            elif row.get("status") != "DONE":
                reasons.add("UNIT_NOT_DONE_" + key.replace("-", "_"))
    deps = snapshot.get("dependencies")
    if not isinstance(deps, list) or len(deps) != 1 or not isinstance(deps[0], dict) or deps[0] != {
        "work_code": "PROG-REM-002",
        "requires_work": "PROG-REM-001",
        "relation_type": "REQUIRES",
    }:
        reasons.add("PG02_DEPENDENCY_NOT_VERIFIED")
    receipt = snapshot.get("pg01_receipt")
    # A caller's claim of PASS is never considered authenticated.
    if not isinstance(receipt, dict):
        reasons.add("PG01_RECEIPT_MISSING")
    else:
        reasons.add("PG01_RECEIPT_AUTHENTICITY_UNVERIFIED")
        if receipt.get("proposal_id") is None or not isinstance(receipt.get("proposal_id"), str):
            reasons.add("PG01_RECEIPT_ID_INVALID")
    bindings = snapshot.get("bindings")
    if not isinstance(bindings, list) or len(bindings) == 0:
        reasons.add("PG_VALIDATOR_BINDINGS_MISSING")
    else:
        reasons.add("PG_VALIDATOR_BINDINGS_UNATTESTED")
    dispatcher = snapshot.get("dispatcher")
    if not isinstance(dispatcher, dict) or dispatcher.get("handler") is None:
        reasons.add("DISPATCH_HANDLER_NOT_IDENTIFIED")
    else:
        reasons.add("DISPATCH_HANDLER_UNATTESTED")
    return {"verdict": "BLOCKED", "authority": "NONE",
            "dispatch_allowed": False, "reason_codes": sorted(reasons)}

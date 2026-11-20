"""Read-only evidence assessment for D8/I1; never authorizes an operation."""
OP = "DESARROLLO_CODIGO_AGENTE_LF"
CANDIDATE = {"asset_type": "REPOSITORY_ARTIFACT", "action_code": "CODE_DEVELOPMENT",
             "operation_code": OP, "operation_resolution": "STATIC",
             "status": "CANDIDATO_READ_ONLY", "write_allowed": False}
REQUIRED = ("operation_contract", "authorized_dispatcher", "pg01_receipt_provider",
            "checkpoint_admission", "router_binding", "reviewer_approval",
            "train_apply_route", "smoke_evidence")


def inspect(snapshot):
    reasons = {"I1_OWNER_ACTIVATION_DECISION_REQUIRED"}
    if not isinstance(snapshot, dict):
        reasons.add("INVALID_SNAPSHOT")
        return {"verdict": "BLOCKED", "authority": "NONE", "activate_allowed": False,
                "reason_codes": sorted(reasons)}
    if set(snapshot) != {"router_candidate", "operation_registered", "evidence"}:
        reasons.add("SNAPSHOT_FIELDS_MISMATCH")
    row = snapshot.get("router_candidate")
    if not isinstance(row, dict) or any(type(row.get(k)) is not type(v) or row.get(k) != v
                                        for k, v in CANDIDATE.items()):
        reasons.add("D8_CANDIDATE_MISMATCH")
    if snapshot.get("operation_registered") is not False:
        # This is not proof of registration; unexpected drift must be reviewed.
        reasons.add("OPERATION_REGISTRY_REVALIDATION_REQUIRED")
    evidence = snapshot.get("evidence")
    if not isinstance(evidence, dict):
        reasons.add("EVIDENCE_INVALID")
    else:
        for key in REQUIRED:
            # Do not accept caller-supplied PASS as authenticated proof.
            if not isinstance(evidence.get(key), str) or not evidence[key]:
                reasons.add("MISSING_" + key.upper())
        reasons.add("EVIDENCE_PROVENANCE_NOT_AUTHENTICATED")
        if set(evidence) != set(REQUIRED):
            reasons.add("EVIDENCE_FIELDS_MISMATCH")
    return {"verdict": "BLOCKED", "authority": "NONE",
            "activate_allowed": False, "reason_codes": sorted(reasons)}

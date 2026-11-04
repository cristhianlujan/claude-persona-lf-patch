"""Strict binding of a supplied RO ledger row to its readback context.

This verifies consistency, NOT source authentication. Only the trusted connector
may attest origin. No DB calls, operational authority, or PIP accreditation.
"""
import re
from collections.abc import Mapping
from pg_ledger_readback_advisory import project_checkpoint_row

SHA = re.compile(r"^[0-9a-f]{64}$")
PLAN = "PROGRAMMING_AGENT_PROGRAMMING_REMEDIATION_V1"

class BoundReadbackError(ValueError):
    pass

def bind_readback(row: Mapping, *, expected_plan: str, expected_unit: str,
                  expected_checkpoint: str, source_ref: str, run_id=None) -> dict:
    if not isinstance(row, Mapping):
        raise BoundReadbackError("ROW_NOT_OBJECT")
    if expected_plan != PLAN or row.get("plan_code") != expected_plan:
        raise BoundReadbackError("PLAN_IDENTITY_MISMATCH")
    if not isinstance(source_ref,str) or not SHA.fullmatch(source_ref):
        raise BoundReadbackError("SOURCE_REF_REQUIRED")
    if run_id is not None:
        raise BoundReadbackError("NO_PIP1_RUN_ASSOCIATION_IN_LEDGER")
    if row.get("assertion_receipt_sha256") is not None:
        if not isinstance(row["assertion_receipt_sha256"],str) or not SHA.fullmatch(row["assertion_receipt_sha256"]):
            raise BoundReadbackError("RECEIPT_HASH_INVALID")
    if not isinstance(row.get("updated_at"),str) or not row["updated_at"]:
        raise BoundReadbackError("UPDATED_AT_REQUIRED")
    projected = project_checkpoint_row(
        {**row, "has_receipt": row.get("assertion_receipt_sha256") is not None},
        expected_unit=expected_unit, expected_checkpoint=expected_checkpoint)
    projected.update({"plan_code":expected_plan,"source_ref":source_ref,
                      "observed_updated_at":row["updated_at"],
                      "source_authenticated":False,
                      "source_attestation_required":True,
                      "pip1_run_bound":False})
    return projected

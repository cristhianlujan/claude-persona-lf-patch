"""Read-only PG ledger row projection; deliberately NOT a PIP-1 authority bridge."""
from collections.abc import Mapping

class ReadbackBlocked(ValueError):
    pass

def project_checkpoint_row(row: Mapping, *, expected_unit: str, expected_checkpoint: str) -> dict:
    if not isinstance(row, Mapping):
        raise ReadbackBlocked("ROW_NOT_OBJECT")
    if row.get("unit_code") != expected_unit or row.get("checkpoint_code") != expected_checkpoint:
        raise ReadbackBlocked("ROW_IDENTITY_MISMATCH")
    status = row.get("status")
    if status not in {"PENDING","IN_PROGRESS","BLOCKED","FAILED","DONE","NOT_APPLICABLE"}:
        raise ReadbackBlocked("UNKNOWN_LEDGER_STATUS")
    if type(row.get("required")) is not bool or type(row.get("has_receipt")) is not bool:
        raise ReadbackBlocked("READBACK_SHAPE_INVALID")
    # The existence of a receipt is not proof of validity.
    return {
        "schema_version":"PG_LEDGER_READBACK_ADVISORY_V1",
        "unit_code":expected_unit,
        "checkpoint_code":expected_checkpoint,
        "ledger_status":status,
        "required":row["required"],
        "receipt_present_unverified":row["has_receipt"],
        "source":"SUPABASE_READ_ONLY_LEDGER",
        "pip1_outcome_accredited":False,
        "can_skip_checkpoint":False,
        "write_authorized":False,
        "transition_authorized":False,
        "worker_dispatch_authorized":False,
        "next_action":"EXTERNAL_AUTHORITY_AND_BINDING_VERIFICATION_REQUIRED"
    }

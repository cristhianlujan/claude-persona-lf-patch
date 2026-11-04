"""Read-only composition of an observed DB row with the existing chat advisory.

Source authentication belongs to the connected tool caller, not this module.
No PIP-1 transition, SQL, network I/O or dispatch.
"""
from pg_tool_readback import project_tool_row, PLAN
from pg_ledger_readback_advisory import project_checkpoint_row

def summarize_observation(row, *, unit, checkpoint):
    if not isinstance(row, dict) or row.get("plan_code") != PLAN:
        raise ValueError("PLAN_MISMATCH")
    tool_view = project_tool_row(row, unit=unit, checkpoint=checkpoint)
    ledger_view = project_checkpoint_row(
        {**row, "has_receipt": False}, expected_unit=unit, expected_checkpoint=checkpoint)
    if tool_view["ledger_status"] != ledger_view["ledger_status"]:
        raise ValueError("READBACK_DISAGREEMENT")
    return {
        "schema_version": "PG_CHAT_READBACK_FLOW_V1",
        "plan_code": PLAN,
        "unit_code": unit,
        "checkpoint_code": checkpoint,
        "observed_state": tool_view["ledger_status"],
        "readback_timestamp": tool_view["observed_updated_at"],
        "observation_only": True,
        "source_authenticated_by_module": False,
        "pip1_transition_evaluated": False,
        "worker_dispatch_authorized": False,
        "write_authorized": False,
        "next_action": "STOP_AWAIT_CHECKPOINT_BINDING_AND_EXTERNAL_AUTHORITY"
    }

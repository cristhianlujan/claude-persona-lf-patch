"""Static contract checks for the deployed IG CONTEXT_PACK ticket boundary.

Source parity reconciliation only. These checks do not certify a live end-to-end
execution, grant write permission, or exercise a production runtime.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]
EDGE = ROOT / "supabase" / "functions"

SOURCES = {
    kind: EDGE / f"input-governance-{kind}-v1" / "index.ts"
    for kind in ("agent", "curator", "validator")
}
CALLER = EDGE / "lf-profiles-governance-caller-v1" / "caller.ts"

def _read(path):
    return path.read_text(encoding="utf-8")

def _audit_ticket_contract(sources, caller):
    for kind, source in sources.items():
        assert "const TICKET_RE =" in source, f"{kind}: missing UUID ticket validator"
        assert 'const ticket = typeof body?.ticket === "string"' in source, f"{kind}: ticket not parsed"
        assert "if (!TICKET_RE.test(ticket))" in source, f"{kind}: missing negative ticket gate"
        assert "IG_PROFILE_TICKET_REQUIRED" in source, f"{kind}: missing fail-closed response"

    agent = sources["agent"]
    exec_calls = re.findall(r'rpc\("fn_input_governance_execute",\s*\{([^{}]*)\}', agent)
    fix_calls = re.findall(r'rpc\("fn_input_governance_safe_autofix_v1",\s*\{([^{}]*)\}', agent)
    assert len(exec_calls) == 3, f"agent: expected 3 dispatch calls, got {len(exec_calls)}"
    assert len(fix_calls) == 2, f"agent: expected 2 scoped autofix calls, got {len(fix_calls)}"
    assert all("p_ticket: ticket" in call for call in exec_calls + fix_calls), "agent: missing RPC ticket"
    for target in ("input-governance-curator-v1", "input-governance-validator-v1"):
        calls = re.findall(r'callRuntime\("' + re.escape(target) + r'",\s*\{([^{}]*)\}', agent)
        assert len(calls) == 1 and "ticket" in calls[0], f"agent: {target} ticket absent"

    curator = sources["curator"]
    curator_calls = re.findall(
        r'rpc\("fn_input_governance_(?:curator_materialize_v1|curator_handoff_receipt_v1)",\s*\{([^{}]*)\}',
        curator,
    )
    assert len(curator_calls) == 2, "curator: missing governed RPC"
    assert all("p_ticket: ticket" in call for call in curator_calls), "curator: RPC ticket missing"

    validator = sources["validator"]
    validator_calls = re.findall(
        r'rpc\((?:HANDOFF_ASSERT_ENTRYPOINT|VALIDATOR_ENTRYPOINT|"fn_input_governance_validator_resume_context_v1"),\s*\{([^{}]*)\}',
        validator,
    )
    assert len(validator_calls) == 3, "validator: missing handoff, resume or validation"
    assert all("p_ticket: ticket" in call for call in validator_calls), "validator: RPC ticket missing"

    assert "RUNTIME_TICKET_RPC" in caller, "caller: ticket consume RPC not found"
    assert "lf_profile_input_governance_runtime_ticket_consume_v1" in caller
    assert 'transport: "DIRECT_EDGE_INVOCATION"' in caller
    assert "queue_required: false" in caller
    assert "PROFILE_RUNTIME_TICKET_INVALID" in caller
    assert "ROUTER_PROFILE_DIRECT_OR_INTERMEDIATE_CALL_RETIRED" in caller

class TicketSourceParityTests(unittest.TestCase):
    def setUp(self):
        self.sources = {kind: _read(path) for kind, path in SOURCES.items()}
        self.caller = _read(CALLER)

    def test_expected_production_ticket_contract(self):
        _audit_ticket_contract(self.sources, self.caller)

    def test_negative_removed_agent_validation(self):
        altered = dict(self.sources)
        altered["agent"] = altered["agent"].replace(
            "if (!TICKET_RE.test(ticket))", "if (false)", 1
        )
        with self.assertRaises(AssertionError):
            _audit_ticket_contract(altered, self.caller)

    def test_negative_missing_autofix_ticket(self):
        altered = dict(self.sources)
        altered["agent"] = altered["agent"].replace(
            'rpc("fn_input_governance_safe_autofix_v1", { p_run_id: runId, p_ticket: ticket });',
            'rpc("fn_input_governance_safe_autofix_v1", { p_run_id: runId });',
            1,
        )
        self.assertNotEqual(altered["agent"], self.sources["agent"])
        with self.assertRaises(AssertionError):
            _audit_ticket_contract(altered, self.caller)

    def test_negative_missing_validator_ticket(self):
        altered = dict(self.sources)
        altered["validator"] = altered["validator"].replace(
            "p_ticket: ticket,", "", 1
        )
        with self.assertRaises(AssertionError):
            _audit_ticket_contract(altered, self.caller)

if __name__ == "__main__":
    unittest.main()

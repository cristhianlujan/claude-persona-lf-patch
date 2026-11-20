"""Portable replay of the new case discovered by a fresh native audit context.

No original LF run, external write or independent governance judge is asserted.
The raw source and original observed evidence are preserved in forward_test.json.
"""
import hashlib
import importlib.util
import json
import sys
import types
import unittest
from pathlib import Path

PACK = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PACK / "scripts"))
from inspect_sources import contract_candidates, call_candidates, enum_candidates


def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class BlindCaseReplay(unittest.TestCase):
    def test_raw_snapshot_matches_actual_blind_test_sources(self):
        evidence = json.loads((PACK / "reports/forward_test.json").read_text())
        for name, source in evidence["source_snapshot"].items():
            data = (PACK / "fixtures/holdout/baseline" / name).read_bytes()
            self.assertEqual(data.decode(), source["text"])
            self.assertEqual(hashlib.sha256(data).hexdigest(), source["sha256"])
        self.assertEqual(evidence["second_run_execution"]["reproduction_checks_passed"], 24)
        self.assertEqual(evidence["second_run_validation"]["exit_code"], 0)
        self.assertEqual(evidence["first_run_validation"]["exit_code"], 1)
        self.assertFalse(evidence["governance_independence_attested"])

    def test_renamed_contract_call_and_state_discovered_from_raw_sources(self):
        p = PACK / "fixtures/holdout/baseline"
        contract = json.loads((p / "contract.json").read_text())
        fields = contract_candidates(contract["payload"], p / "settlement.py", "settle", "payload")
        calls = call_candidates([p / "intake.py", p / "settlement.py"])
        states = enum_candidates(p / "intake.py", "act", "status", contract["states"])
        self.assertEqual([f["field"] for f in fields], ["currency"])
        self.assertEqual(calls[0]["missing"], ["revision"])
        self.assertEqual(states[0]["missing"], ["WAITING_FUNDS"])

    def test_first_failure_masks_second_and_coordinated_fix_resolves_both(self):
        bad = PACK / "fixtures/holdout/baseline"
        good = PACK / "fixtures/holdout/correct"
        prior = sys.modules.get("settlement")
        sys.modules["settlement"] = load(bad / "settlement.py", "blind_case_consumer")
        try:
            original = load(bad / "intake.py", "blind_case_original")
            corrected = load(good / "intake.py", "blind_case_corrected")
            with self.assertRaises(TypeError): original.dispatch()
            source = (bad / "intake.py").read_text().replace("return settle(payload)", "return settle(payload, revision)")
            partial = types.ModuleType("blind_case_partial")
            exec(compile(source, "<isolated partially corrected fixture>", "exec"), partial.__dict__)
            with self.assertRaises(KeyError): partial.dispatch()
            self.assertEqual(corrected.dispatch(), ("A17", 12, "PEN", "N19"))
            self.assertIsNone(original.act("WAITING_FUNDS"))
            self.assertEqual(corrected.act("WAITING_FUNDS"), "DEFER")
            for state in ("QUEUED", "CANCELLED"):
                self.assertEqual(original.act(state), corrected.act(state))
        finally:
            if prior is None:
                sys.modules.pop("settlement", None)
            else:
                sys.modules["settlement"] = prior


if __name__ == "__main__":
    unittest.main()

#!/usr/bin/env python3
"""Offline regression of source-bound GPT_NATIVE chat capture; no model execution."""
from __future__ import annotations
from copy import deepcopy
import hashlib
import json
import tempfile
from pathlib import Path
from gpt_native_in_chat_capture_v1 import _sha, _text_sha, _matches_exact_value, capture


def must_fail(code, packet, raw, root):
    try:
        capture(packet, raw, root=root, profile_slug="example")
    except ValueError as exc:
        assert str(exc) == code, f"expected {code}, got {exc}"
        print("EXPECTED_BLOCK", code)
        return
    raise AssertionError("FAIL_OPEN:" + code)


def main():
    with tempfile.TemporaryDirectory() as scratch:
        root = Path(scratch)
        profile = root / "profiles" / "example" / "SKILL.md"
        profile.parent.mkdir(parents=True)
        profile.write_text("# Example\nNo unsupported claims.\n", encoding="utf-8")
        literal = '{"case_id":"HCA-TEST","instruction":"Do not overclaim."}'
        sources = [{"ref": "profiles/example/SKILL.md",
                    "content_sha256": hashlib.sha256(profile.read_bytes()).hexdigest()}]
        contract = {"schema": "LF_PROFILE_EXECUTION_CONTRACT_V1",
                    "executor_mode": "GPT_NATIVE", "run_id": "HCA-TEST-RUN",
                    "profile_code": "PERFIL-TEST"}
        contract["contract_sha256"] = _sha(contract)
        manifest = {"execution_id": "HCA-TEST-RUN", "profile_code": "PERFIL-TEST",
                    "input_sha256": _text_sha(literal), "profile_source_sha256": _sha(sources),
                    "obligations": [
                        {"check_type": "EXACT_VALUE", "obligation_id": "INPUT_CASE_ID",
                         "evidence_pointer": "/case_id", "expected_value": "HCA-TEST"},
                        {"check_type": "EXACT_VALUE", "obligation_id": "PROFILE_NO_CAUSAL_OVERCLAIM",
                         "evidence_pointer": "/causality_proven", "expected_value": "false"},
                        {"check_type": "SEMANTIC_RELATION", "obligation_id": "GROUNDED_CLAIMS",
                         "evidence_pointer": "/reason"}]}
        packet = {
            "run_id": "HCA-TEST-RUN", "execution_contract": contract,
            "input_literal": literal, "input_sha256": _text_sha(literal),
            "profile_source_manifest": sources, "profile_source_sha256": _sha(sources),
            "scoped_semantic_obligation_manifest": manifest,
            "scoped_semantic_obligation_manifest_sha256": _sha(manifest)}
        raw = {"case_id": "HCA-TEST", "causality_proven": False,
               "reason": "Evidence is not sufficient to prove a cause."}
        ok = capture(packet, raw, root=root, profile_slug="example")
        assert ok["producer_mode"] == "GPT_NATIVE"
        assert ok["runtime_provider_attested"] is False
        assert ok["runtime_execution_receipt"] is None
        assert ok["downstream_authorized"] is False
        assert ok["cutover_eligible"] is False
        assert ok["capture_sha256"] == _sha({k: v for k, v in ok.items() if k != "capture_sha256"})
        print("PASS_GPT_NATIVE_INCHAT_UNATTESTED_CAPTURE")
        bad = deepcopy(packet); bad["input_literal"] += "tamper"
        must_fail("INPUT_SHA_MISMATCH", bad, raw, root)
        bad = deepcopy(packet); bad["execution_contract"]["executor_mode"] = "REMOTE_API"
        must_fail("NON_GPT_NATIVE_EXECUTOR_FORBIDDEN", bad, raw, root)
        bad = deepcopy(packet); bad["profile_source_manifest"][0]["content_sha256"] = "0" * 64
        must_fail("PROFILE_SOURCE_DRIFT", bad, raw, root)
        bad_raw = dict(raw, causality_proven=True)
        must_fail("DETERMINISTIC_OBLIGATION_FAILED:PROFILE_NO_CAUSAL_OVERCLAIM", packet, bad_raw, root)
        # A string that spells a boolean, or Python bool/int equality, cannot bypass typed control.
        must_fail("DETERMINISTIC_OBLIGATION_FAILED:PROFILE_NO_CAUSAL_OVERCLAIM",
                  packet, dict(raw, causality_proven="false"), root)
        must_fail("DETERMINISTIC_OBLIGATION_FAILED:PROFILE_NO_CAUSAL_OVERCLAIM",
                  packet, dict(raw, causality_proven=0), root)
        must_fail("DETERMINISTIC_OBLIGATION_FAILED:PROFILE_NO_CAUSAL_OVERCLAIM",
                  packet, dict(raw, causality_proven=None), root)
        assert _matches_exact_value(True, "true")
        assert not _matches_exact_value(1, "true")
        assert _matches_exact_value(None, "null")
        assert not _matches_exact_value("null", "null")
        assert _matches_exact_value({"a": 1}, '{"a":1}')
        assert not _matches_exact_value({"a": 2}, '{"a":1}')
        bad_raw = dict(raw, provider_signature="forged")
        must_fail("RAW_FORGED_ATTESTATION_FIELD", packet, bad_raw, root)
        print("PASS_POSITIVE_AND_8_NEGATIVE_TYPED_NO_MODEL_CALLS")


if __name__ == "__main__":
    main()

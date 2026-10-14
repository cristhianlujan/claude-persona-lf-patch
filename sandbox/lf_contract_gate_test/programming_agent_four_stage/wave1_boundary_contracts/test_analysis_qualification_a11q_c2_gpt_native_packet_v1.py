#!/usr/bin/env python3
"""Tests for the A11Q_C2 GPT Native packet. RAW below is a MECHANICS FIXTURE, never evidence."""
from __future__ import annotations

import copy
import hashlib
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import analysis_qualification_a11q_c2_gpt_native_packet_v1 as pk  # noqa: E402
import analysis_qualification_gpt_native_equivalent_v1 as eq  # noqa: E402

H = lambda c: c * 64  # noqa: E731
PACKET = pk.build_packet()
CTX = json.loads(PACKET["input"]["input_literal"])
IDS = sorted(pk.snapshot_ids(CTX))


def good_raw() -> dict:
    cs = []
    for i, c in enumerate(CTX["categories"]):
        cs.append({"category": c["category"], "mutation_description": "Se altera el elemento indicado del snapshot para intentar colar un estado favorable.",
                   "target_refs": [IDS[i % len(IDS)]], "expected_safe_behavior": "BLOCK", "false_ready_if_unblocked": True,
                   "executed": False, "observed_result": None})
    return {"schema_version": pk.OUT_SCHEMA, "request_ref": pk.REQUEST_REF, "cases": cs, "no_ready_claim": True,
            "adversarial_statement": "Casos producidos, no ejecutados; no hay medición contra un oráculo ni ruta gobernada."}


def run(raw, packet=PACKET, chat_ref="chat://fixture", chat_sha=H("b"), approval=H("a")):
    data = raw if isinstance(raw, bytes) else json.dumps(raw, ensure_ascii=False).encode("utf-8")
    return pk.intake(packet, data, chat_ref, chat_sha, approval)


def mutate(fn):
    raw = good_raw()
    fn(raw)
    return raw


def c0(r):
    return r["cases"][0]


def test_packet_deterministic_and_bound():
    assert pk.build_packet() == PACKET and PACKET["limits"]["provider_attested"] is False
    assert PACKET["input"]["input_sha256"] == hashlib.sha256(PACKET["input"]["input_literal"].encode()).hexdigest()
    assert len(CTX["categories"]) == 11 and len(IDS) == 16  # 11 scopes + 5 fronts


def test_positive():
    verdict, rec = run(good_raw())
    assert verdict == eq.PASS_C2 and rec["runtime_provider_attested"] is False


NEG = {
    "RAW_NOT_JSON": lambda: b"no es json",
    "RAW_NOT_OBJECT": lambda: b"[1]",
    "KEYS_OR_SCHEMA": lambda: mutate(lambda r: r.update(extra=1)),
    "REQUEST_REF_MISMATCH": lambda: mutate(lambda r: r.update(request_ref="REQ-X")),
    "READY_CLAIM": lambda: mutate(lambda r: r.update(no_ready_claim=False)),
    "CASES_SHAPE": lambda: mutate(lambda r: r.update(cases=[1])),
    "CATEGORY_SET_MISMATCH": lambda: mutate(lambda r: r["cases"].pop()),
    "CATEGORY_SET_MISMATCH ": lambda: mutate(lambda r: r["cases"].append(copy.deepcopy(r["cases"][0]))),
    "CATEGORY_SET_MISMATCH  ": lambda: mutate(lambda r: c0(r).update(category="INVENTED_CATEGORY")),
    "CASE_KEYS": lambda: mutate(lambda r: c0(r).update(extra=1)),
    "MUTATION_TEXT": lambda: mutate(lambda r: c0(r).update(mutation_description="corto")),
    "TARGET_REFS_INVALID": lambda: mutate(lambda r: c0(r).update(target_refs=["A99-REQ-999"])),
    "TARGET_REFS_INVALID ": lambda: mutate(lambda r: c0(r).update(target_refs=[])),
    "TARGET_REFS_INVALID  ": lambda: mutate(lambda r: c0(r).update(target_refs=[IDS[0], IDS[0]])),
    "SAFE_BEHAVIOR_INVALID": lambda: mutate(lambda r: c0(r).update(expected_safe_behavior="PASS")),
    "SAFE_BEHAVIOR_INVALID ": lambda: mutate(lambda r: c0(r).update(expected_safe_behavior="READY")),
    "FALSE_READY_FLAG": lambda: mutate(lambda r: c0(r).update(false_ready_if_unblocked=False)),
    "EXECUTION_CLAIMED": lambda: mutate(lambda r: c0(r).update(executed=True)),
    "EXECUTION_CLAIMED ": lambda: mutate(lambda r: c0(r).update(observed_result="BLOCKED")),
    "STATEMENT_MISSING": lambda: mutate(lambda r: r.update(adversarial_statement="corto")),
}


def test_raw_negatives():
    for code, build in NEG.items():
        verdict, rec = run(build())
        assert rec is None and verdict == "BLOCK:" + code.strip(), (code, verdict)


def test_shape_garbage_is_blocked_not_crash():
    for fn in (lambda r: r.update(cases=5), lambda r: c0(r).update(target_refs=5), lambda r: c0(r).update(target_refs=[[1]]),
               lambda r: c0(r).update(mutation_description=5)):
        verdict, rec = run(mutate(fn))
        assert rec is None and verdict.startswith("BLOCK:"), verdict


def test_packet_binding_negatives():
    bad = copy.deepcopy(PACKET)
    bad["input"]["input_literal"] += " "
    assert run(good_raw(), packet=bad)[0] == "BLOCK:PACKET_TAMPERED"
    assert run(good_raw(), packet={})[0] == "BLOCK:PACKET_SCHEMA_INVALID"
    assert run(good_raw(), chat_ref="")[0] == "BLOCK:CHAT_TRANSCRIPT_REF_MISSING"
    assert run(good_raw(), chat_sha="zz")[0] == "BLOCK:CHAT_TRANSCRIPT_DIGEST_FORMAT"
    assert run(good_raw(), approval="s")[0] == "BLOCK:OWNER_APPROVAL_DIGEST_FORMAT"


def main():
    for name, fn in sorted(globals().items()):
        if name.startswith("test_"):
            fn()
    print("PASS_A11Q_C2_GPT_NATIVE_PACKET positives=1 raw_negatives=%d shape_garbage=4 packet_binding_negatives=5 packet_sha256=%s "
          "api_calls=0 fixture_raw_is_not_evidence=true" % (len(NEG), PACKET["packet_sha256"][:16]))


if __name__ == "__main__":
    main()

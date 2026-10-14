#!/usr/bin/env python3
"""Tests for the A12Q_C2 GPT Native packet. RAW below is a MECHANICS FIXTURE, never evidence."""
from __future__ import annotations

import copy
import hashlib
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import analysis_qualification_a12q_c2_gpt_native_packet_v1 as pk  # noqa: E402
import analysis_qualification_gpt_native_equivalent_v1 as eq  # noqa: E402

H = lambda c: c * 64  # noqa: E731
PACKET = pk.build_packet()
CTX = json.loads(PACKET["input"]["input_literal"])
FIXED = CTX["baseline_fixed_domains"]


def good_raw() -> dict:
    base, cand = [], []
    for c in CTX["cases"]:
        base.append({"case_id": c["case_id"], "verdict": "NEED_MORE_EVIDENCE", "domains": [{"domain": d, "note": "Dominio aplicado sin evidencia del caso."} for d in FIXED],
                     "evidence_refs": [c["source_refs"][0]], "reinterpretation_required": True})
        cand.append({"case_id": c["case_id"], "verdict": "NEED_MORE_EVIDENCE",
                     "fronts": [{"front": "ALCANCE", "trigger_ref": c["source_refs"][0], "reason": "La referencia del caso exige definir el alcance."}],
                     "evidence_refs": [c["source_refs"][0]], "reinterpretation_required": True})
    return {"schema_version": pk.OUT_SCHEMA, "request_ref": pk.REQUEST_REF, "arms": {"baseline": base, "candidate": cand},
            "comparison": {"cases_compared": 7, "baseline_total_domains": 7 * len(FIXED), "candidate_total_fronts": 7, "baseline_fixed_domains_per_case": len(FIXED)},
            "no_ready_claim": True, "arms_statement": "Ambos brazos fueron producidos, no medidos; no es una comparación de rendimiento."}


def run(raw, packet=PACKET, chat_ref="chat://fixture", chat_sha=H("b"), approval=H("a")):
    data = raw if isinstance(raw, bytes) else json.dumps(raw, ensure_ascii=False).encode("utf-8")
    return pk.intake(packet, data, chat_ref, chat_sha, approval)


def mutate(fn):
    raw = good_raw()
    fn(raw)
    return raw


def b0(r):
    return r["arms"]["baseline"][0]


def c0(r):
    return r["arms"]["candidate"][0]


def test_packet_deterministic_and_bound():
    assert pk.build_packet() == PACKET and PACKET["limits"]["provider_attested"] is False
    assert PACKET["input"]["input_sha256"] == hashlib.sha256(PACKET["input"]["input_literal"].encode()).hexdigest()
    assert len(CTX["cases"]) == 7 and len(FIXED) == 6


def test_positive():
    verdict, rec = run(good_raw())
    assert verdict == eq.PASS_C2 and rec["runtime_provider_attested"] is False


NEG = {
    "RAW_NOT_JSON": lambda: b"no es json",
    "RAW_NOT_OBJECT": lambda: b"[1]",
    "KEYS_OR_SCHEMA": lambda: mutate(lambda r: r.update(extra=1)),
    "REQUEST_REF_MISMATCH": lambda: mutate(lambda r: r.update(request_ref="REQ-X")),
    "READY_CLAIM": lambda: mutate(lambda r: r.update(no_ready_claim=False)),
    "ARMS_SHAPE": lambda: mutate(lambda r: r["arms"].pop("candidate")),
    "ARMS_SHAPE ": lambda: mutate(lambda r: r.update(arms=[1])),
    "CASE_SET_MISMATCH": lambda: mutate(lambda r: r["arms"]["baseline"].pop()),
    "CASE_SET_MISMATCH ": lambda: mutate(lambda r: r["arms"]["candidate"].append(copy.deepcopy(c0(r)))),
    "BASELINE_KEYS": lambda: mutate(lambda r: b0(r).update(elapsed_ms=3)),
    "BASELINE_DOMAINS_SHAPE": lambda: mutate(lambda r: b0(r)["domains"][0].update(note="x")),
    "BASELINE_FIXED_DOMAINS_NOT_APPLIED": lambda: mutate(lambda r: b0(r)["domains"].pop()),
    "BASELINE_FIXED_DOMAINS_NOT_APPLIED ": lambda: mutate(lambda r: b0(r)["domains"][0].update(domain="OTRO")),
    "CANDIDATE_KEYS": lambda: mutate(lambda r: c0(r).update(input_tokens=5)),
    "CANDIDATE_FRONTS_SHAPE": lambda: mutate(lambda r: c0(r).update(fronts=[])),
    "TRIGGER_REF_OUTSIDE_CASE": lambda: mutate(lambda r: c0(r)["fronts"][0].update(trigger_ref="lf_eventos://99999")),
    "CANDIDATE_FRONTS_DUPLICATED": lambda: mutate(lambda r: (c0(r)["fronts"].append(copy.deepcopy(c0(r)["fronts"][0])), r["comparison"].update(candidate_total_fronts=8))),
    "VERDICT_READY_OR_INVALID": lambda: mutate(lambda r: b0(r).update(verdict="READY")),
    "VERDICT_READY_OR_INVALID ": lambda: mutate(lambda r: c0(r).update(verdict="PASS")),
    "EVIDENCE_REFS_INVALID": lambda: mutate(lambda r: b0(r).update(evidence_refs=["lf_eventos://99999"])),
    "EVIDENCE_REFS_INVALID ": lambda: mutate(lambda r: c0(r).update(evidence_refs=[])),
    "REINTERPRETATION_NOT_BOOL": lambda: mutate(lambda r: b0(r).update(reinterpretation_required="si")),
    "COMPARISON_SHAPE": lambda: mutate(lambda r: r["comparison"].pop("cases_compared")),
    "COMPARISON_SHAPE ": lambda: mutate(lambda r: r["comparison"].update(candidate_total_fronts="7")),
    "COMPARISON_COUNTS_MISMATCH": lambda: mutate(lambda r: r["comparison"].update(candidate_total_fronts=6)),
    "COMPARISON_COUNTS_MISMATCH ": lambda: mutate(lambda r: r["comparison"].update(baseline_total_domains=40)),
    "STATEMENT_MISSING": lambda: mutate(lambda r: r.update(arms_statement="corto")),
}


def test_raw_negatives():
    for code, build in NEG.items():
        verdict, rec = run(build())
        assert rec is None and verdict == "BLOCK:" + code.strip(), (code, verdict)


def test_shape_garbage_is_blocked_not_crash():
    for fn in (lambda r: r["arms"].update(baseline=5), lambda r: b0(r).update(domains=5), lambda r: c0(r).update(fronts=[5]),
               lambda r: r.update(comparison=5), lambda r: b0(r).update(evidence_refs=5)):
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
    print("PASS_A12Q_C2_GPT_NATIVE_PACKET positives=1 raw_negatives=%d shape_garbage=5 packet_binding_negatives=5 packet_sha256=%s "
          "api_calls=0 fixture_raw_is_not_evidence=true" % (len(NEG), PACKET["packet_sha256"][:16]))


if __name__ == "__main__":
    main()

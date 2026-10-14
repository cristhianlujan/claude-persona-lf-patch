#!/usr/bin/env python3
"""Tests for the A14Q_C2 GPT Native packet. The solver below applies ONLY the rules given in the packet (never the oracle); its agreement with the oracle proves the rules are sufficient.
RAW is a MECHANICS FIXTURE, never evidence."""
from __future__ import annotations

import copy
import hashlib
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import analysis_qualification_a14q_c2_gpt_native_packet_v1 as pk  # noqa: E402
import analysis_qualification_gpt_native_equivalent_v1 as eq  # noqa: E402

H = lambda c: c * 64  # noqa: E731
PACKET = pk.build_packet()
CTX = json.loads(PACKET["input"]["input_literal"])
ORACLE = pk.oracle_obj()


def depth(s: dict) -> str:
    if (s["materiality_level"] == "HIGH" or s["scope_bounded"] == "FALSE" or s["authority_state"] == "INSUFFICIENT" or s["currentness_decision"] == "STALE_AFFECTED"
            or s["material_contradiction"] is True or s["known_cross_scope_impact"] is True):
        return "L3"
    if (s["materiality_level"] in ("MEDIUM", "UNKNOWN") or s["scope_bounded"] == "UNKNOWN" or s["authority_state"] == "UNKNOWN" or s["reversibility_state"] in ("NOT_DEMONSTRATED", "UNKNOWN")
            or s["currentness_decision"] in ("CURRENT_REBOUND", "UNKNOWN_FAIL_CLOSED", "UNRESOLVED") or s["known_cross_scope_impact"] == "UNKNOWN"
            or s["unresolved_material_signal_count"] > 0 or s["required_specialist_count"] > 0):
        return "L2"
    return "L1"


def solve(c: dict) -> dict:
    ev, h = c["evidence"], c["handoff"]
    scopes = [s["scope_id"] for s in ev["scopes"]]
    crit = list(dict.fromkeys(i["impact_id"] for k in ("direct_impacts", "indirect_impacts", "second_order_impacts") for i in ev[k] if i.get("critical") is True))
    fronts = list(dict.fromkeys(f["front_id"] for f in ev["material_fronts"] if f.get("material") is True))
    hex64 = lambda v: isinstance(v, str) and re.fullmatch("[0-9a-f]{64}", v) is not None  # noqa: E731
    parity_ok = (all(hex64(h[k]) for k in ("producer_schema_digest_sha256", "receiver_schema_digest_sha256", "context_sha256", "receipt_context_sha256"))
                 and h["producer_schema_digest_sha256"] == h["receiver_schema_digest_sha256"] and h["context_sha256"] == h["receipt_context_sha256"] and h["lossy_projection"] is False)
    blocked, consistent, seen = set(), True, set()
    for f in ev["material_fronts"]:
        if f.get("material") is not True:
            continue
        aff = set(f.get("scope_ids", []))
        if not f.get("front_id") or f["front_id"] in seen or not aff or not aff <= set(scopes):
            consistent = False
        seen.add(f.get("front_id"))
        st, ef = f["status"], f["effect_on_scope"]
        if st in ("BLOCKED", "UNRESOLVED", "NEED_MORE_EVIDENCE", "REQUIRES_DECISION"):
            blocked |= aff
            consistent &= ef == "BLOCKS"
        elif st == "ACCOUNTED":
            consistent &= ef == "PRESERVE"
        else:
            consistent = False
    if ev["currentness"]["decision"] in ("STALE_AFFECTED", "UNKNOWN_FAIL_CLOSED"):
        blocked |= set(ev["currentness"]["affected_scope_ids"])
    refs = [r["matched_ref"] for r in c["specialist_requirements"] if r.get("matched_ref")]
    miss = [r["specialist_type"] for r in c["specialist_requirements"] if r.get("required") is True and not r.get("matched_ref")]
    for r in c["specialist_requirements"]:
        if r.get("required") is True and not r.get("matched_ref"):
            blocked |= set(r["affected_scope_ids"])
    if not parity_ok or not consistent:
        blocked |= set(scopes)
    ready = [s for s in scopes if s not in blocked]
    return {"case_id": c["case_id"], "depth_level": depth(c["signals"]), "critical_impacts": crit, "material_fronts": fronts, "blocked_scope_ids": sorted(blocked), "ready_scope_ids": ready,
            "handoff_parity": "PASS" if parity_ok else "BLOCK", "lossy_projection_detected": h["lossy_projection"] is True, "specialist_refs": refs, "missing_required_specialists": miss,
            "verdict": "READY" if not blocked else ("BLOCKED" if not ready else "PARTIAL_READY"), "rationale": "Reglas suministradas aplicadas a los datos del caso."}


def good_raw() -> dict:
    return {"schema_version": pk.OUT_SCHEMA, "request_ref": pk.REQUEST_REF, "answers": [solve(c) for c in CTX["cases"]],
            "answers_statement": "Respuestas producidas aplicando las reglas suministradas, sin ejecutar ni medir nada."}


def run(raw, packet=PACKET, chat_ref="chat://fixture", chat_sha=H("b"), approval=H("a")):
    data = raw if isinstance(raw, bytes) else json.dumps(raw, ensure_ascii=False).encode("utf-8")
    return pk.intake(packet, data, chat_ref, chat_sha, approval)


def mutate(fn):
    raw = good_raw()
    fn(raw)
    return raw


def idx(r, cid):
    return next(a for a in r["answers"] if a["case_id"] == cid)


def test_packet_deterministic_bound_and_oracle_hidden():
    assert pk.build_packet() == PACKET and PACKET["limits"]["provider_attested"] is False
    assert PACKET["input"]["input_sha256"] == hashlib.sha256(PACKET["input"]["input_literal"].encode()).hexdigest()
    assert len(CTX["cases"]) == 12 and len(ORACLE["oracle"]) == 12
    lit = PACKET["input"]["input_literal"] + PACKET["prompt_for_gpt"]
    for needle in ("depth_expected", "critical_impacts_expected", "blocked_scope_ids_expected", "oracle", "archetype"):
        assert needle not in lit.replace("blocked_scope_ids\"", ""), needle


def test_rules_alone_reproduce_the_oracle():
    verdict, rec = run(good_raw())
    assert verdict == eq.PASS_C2 and rec["runtime_provider_attested"] is False


NEG = {
    "RAW_NOT_JSON": lambda: b"no es json",
    "RAW_NOT_OBJECT": lambda: b"[1]",
    "KEYS_OR_SCHEMA": lambda: mutate(lambda r: r.update(extra=1)),
    "REQUEST_REF_MISMATCH": lambda: mutate(lambda r: r.update(request_ref="REQ-X")),
    "ANSWERS_SHAPE": lambda: mutate(lambda r: r.update(answers=[1])),
    "ANSWER_CASE_SET_MISMATCH": lambda: mutate(lambda r: r["answers"].pop()),
    "ANSWER_CASE_SET_MISMATCH ": lambda: mutate(lambda r: r["answers"].append(copy.deepcopy(r["answers"][0]))),
    "ANSWER_KEYS": lambda: mutate(lambda r: r["answers"][0].update(provider="x")),
    "ANSWER_KEYS ": lambda: mutate(lambda r: r["answers"][0].update(input_tokens=5)),
    "ANSWER_LISTS_INVALID": lambda: mutate(lambda r: r["answers"][0].update(critical_impacts="x")),
    "ANSWER_LISTS_INVALID ": lambda: mutate(lambda r: idx(r, "A14-FRESH-003").update(critical_impacts=["UPLOAD_TABLE_SEMANTICS", "UPLOAD_TABLE_SEMANTICS"])),
    "RATIONALE_MISSING": lambda: mutate(lambda r: r["answers"][0].update(rationale="corto")),
    "ANSWER_VALUE_INVALID": lambda: mutate(lambda r: r["answers"][0].update(depth_level="L4")),
    "ANSWER_VALUE_INVALID ": lambda: mutate(lambda r: r["answers"][0].update(lossy_projection_detected="no")),
    "ANSWER_VALUE_INVALID  ": lambda: mutate(lambda r: r["answers"][0].update(verdict="OK")),
    "DEPTH_WRONG": lambda: mutate(lambda r: idx(r, "A14-FRESH-001").update(depth_level="L2")),
    "DEPTH_WRONG ": lambda: mutate(lambda r: idx(r, "A14-FRESH-009").update(depth_level="L1")),
    "CRITICAL_IMPACTS_WRONG": lambda: mutate(lambda r: idx(r, "A14-FRESH-003").update(critical_impacts=["UPLOAD_TABLE_SEMANTICS"])),
    "CRITICAL_IMPACTS_WRONG ": lambda: mutate(lambda r: idx(r, "A14-FRESH-001").update(critical_impacts=["OFFER_PERCENT_RULE", "INVENTADO"])),
    "MATERIAL_FRONTS_WRONG": lambda: mutate(lambda r: idx(r, "A14-FRESH-001").update(material_fronts=[])),
    "BLOCKED_SCOPES_WRONG": lambda: mutate(lambda r: idx(r, "A14-FRESH-007").update(blocked_scope_ids=[])),
    "BLOCKED_SCOPES_WRONG ": lambda: mutate(lambda r: idx(r, "A14-FRESH-004").update(blocked_scope_ids=["S1", "S2"])),
    "READY_SCOPES_WRONG": lambda: mutate(lambda r: idx(r, "A14-FRESH-007").update(ready_scope_ids=["S1", "S2"])),
    "HANDOFF_WRONG": lambda: mutate(lambda r: idx(r, "A14-FRESH-010").update(handoff_parity="PASS")),
    "LOSSY_WRONG": lambda: mutate(lambda r: idx(r, "A14-FRESH-011").update(lossy_projection_detected=False)),
    "SPECIALIST_REFS_WRONG": lambda: mutate(lambda r: idx(r, "A14-FRESH-002").update(specialist_refs=[])),
    "MISSING_SPECIALIST_WRONG": lambda: mutate(lambda r: idx(r, "A14-FRESH-004").update(missing_required_specialists=[])),
    "VERDICT_INCONSISTENT": lambda: mutate(lambda r: idx(r, "A14-FRESH-004").update(verdict="READY")),
    "VERDICT_INCONSISTENT ": lambda: mutate(lambda r: idx(r, "A14-FRESH-001").update(verdict="BLOCKED")),
    "STATEMENT_MISSING": lambda: mutate(lambda r: r.update(answers_statement="corto")),
}


def test_raw_negatives():
    for code, build in NEG.items():
        verdict, rec = run(build())
        assert rec is None and verdict == "BLOCK:" + code.strip(), (code, verdict)


def test_shape_garbage_is_blocked_not_crash():
    for fn in (lambda r: r.update(answers=5), lambda r: r["answers"][0].update(blocked_scope_ids=5), lambda r: r["answers"][0].update(rationale=5),
               lambda r: r["answers"][0].update(case_id=5), lambda r: r.update(answers=None)):
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
    print("PASS_A14Q_C2_GPT_NATIVE_PACKET positives=1 raw_negatives=%d shape_garbage=5 packet_binding_negatives=5 packet_sha256=%s "
          "api_calls=0 fixture_raw_is_not_evidence=true" % (len(NEG), PACKET["packet_sha256"][:16]))


if __name__ == "__main__":
    main()

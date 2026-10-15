#!/usr/bin/env python3
"""Tests for the A8Q_C2 GPT Native packet. RAW below is a MECHANICS FIXTURE, never evidence."""
from __future__ import annotations

import copy
import hashlib
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import analysis_qualification_a8q_c2_gpt_native_packet_v1 as pk  # noqa: E402
import analysis_qualification_gpt_native_equivalent_v1 as eq  # noqa: E402

H = lambda c: c * 64  # noqa: E731
PACKET = pk.build_packet()
CTX = json.loads(PACKET["input"]["input_literal"])
FR = pk.fronts(CTX)
ALL = sorted(set().union(*FR.values()))


def good_raw() -> dict:
    return {"schema_version": pk.OUT_SCHEMA, "request_ref": pk.REQUEST_REF, "research_decision": "REQUIRES_DECISION",
            "stop_criteria": {"decision_stable": False, "front_accounting_complete": True, "decision_changing_questions_open": True},
            "front_trace": [{"front_id": f, "blockers": sorted(b), "effect_on_decision": "El frente sigue bloqueado y por eso la investigación no puede detenerse."}
                            for f, b in sorted(FR.items())],
            "owner_decisions_required": ALL, "evidence_refs": ["front:" + sorted(FR)[0], "decision:" + ALL[0] if ("decision:" + ALL[0]) in pk.allowed_refs(CTX) else "front:" + sorted(FR)[1]],
            "no_ready_claim": True,
            "decision_statement": "No se detiene la investigación: hay decisiones del propietario pendientes que pueden cambiar el resultado."}


def run(raw, packet=PACKET, chat_ref="chat://fixture", chat_sha=H("b"), approval=H("a")):
    data = raw if isinstance(raw, bytes) else json.dumps(raw, ensure_ascii=False).encode("utf-8")
    return pk.intake(packet, data, chat_ref, chat_sha, approval)


def mutate(fn):
    raw = good_raw()
    fn(raw)
    return raw


def test_packet_deterministic_and_bound():
    assert pk.build_packet() == PACKET and PACKET["limits"]["provider_attested"] is False
    assert PACKET["input"]["input_sha256"] == hashlib.sha256(PACKET["input"]["input_literal"].encode()).hexdigest()
    assert len(FR) == 5 and len(ALL) == 5


def test_positive_and_alternative_non_stop_decisions():
    verdict, rec = run(good_raw())
    assert verdict == eq.PASS_C2 and rec["runtime_provider_attested"] is False
    for d in ("CONTINUE", "BLOCKED"):
        assert run(mutate(lambda r: r.update(research_decision=d)))[0] == eq.PASS_C2


NEG = {
    "RAW_NOT_JSON": lambda: b"no es json",
    "RAW_NOT_OBJECT": lambda: b"[1]",
    "KEYS_OR_SCHEMA": lambda: mutate(lambda r: r.update(extra=1)),
    "REQUEST_REF_MISMATCH": lambda: mutate(lambda r: r.update(request_ref="REQ-X")),
    "READY_CLAIM": lambda: mutate(lambda r: r.update(no_ready_claim=False)),
    "DECISION_INVALID": lambda: mutate(lambda r: r.update(research_decision="READY")),
    "STOP_WITH_BLOCKED_FRONTS": lambda: mutate(lambda r: r.update(research_decision="STOP")),
    "STOP_CRITERIA_SHAPE": lambda: mutate(lambda r: r["stop_criteria"].pop("decision_stable")),
    "STOP_CRITERIA_SHAPE ": lambda: mutate(lambda r: r["stop_criteria"].update(decision_stable="no")),
    "STABILITY_OVERSTATED": lambda: mutate(lambda r: r["stop_criteria"].update(decision_stable=True)),
    "OPEN_QUESTIONS_UNDERSTATED": lambda: mutate(lambda r: r["stop_criteria"].update(decision_changing_questions_open=False)),
    "TRACE_SHAPE": lambda: mutate(lambda r: r["front_trace"][0].update(extra=1)),
    "TRACE_COVERAGE": lambda: mutate(lambda r: r.update(front_trace=r["front_trace"][:4])),
    "TRACE_BLOCKERS_MISMATCH": lambda: mutate(lambda r: r["front_trace"][0].update(blockers=["A5-DEC-005"] if r["front_trace"][0]["blockers"] != ["A5-DEC-005"] else ["A5-DEC-001"])),
    "TRACE_EFFECT": lambda: mutate(lambda r: r["front_trace"][0].update(effect_on_decision="x")),
    "OWNER_DECISIONS_INCOMPLETE": lambda: mutate(lambda r: r.update(owner_decisions_required=ALL[:-1])),
    "EVIDENCE_REFS_INVALID": lambda: mutate(lambda r: r.update(evidence_refs=["front:INVENTED"])),
    "STATEMENT_MISSING": lambda: mutate(lambda r: r.update(decision_statement="corto")),
    "SOLUTION_INFERRED": lambda: mutate(lambda r: r.update(decision_statement="Se debe esperar a definir una tabla en la base de datos antes de seguir investigando.")),
}


def test_raw_negatives():
    for code, build in NEG.items():
        verdict, rec = run(build())
        assert rec is None and verdict == "BLOCK:" + code.strip(), (code, verdict)


def test_shape_garbage_is_blocked_not_crash():
    for fn in (lambda r: r.update(front_trace=[1]), lambda r: r.update(stop_criteria=[]), lambda r: r.update(owner_decisions_required=5)):
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
    print("PASS_A8Q_C2_GPT_NATIVE_PACKET positives=3 raw_negatives=%d packet_binding_negatives=5 packet_sha256=%s "
          "api_calls=0 fixture_raw_is_not_evidence=true" % (len(NEG) + 1, PACKET["packet_sha256"][:16]))


if __name__ == "__main__":
    main()

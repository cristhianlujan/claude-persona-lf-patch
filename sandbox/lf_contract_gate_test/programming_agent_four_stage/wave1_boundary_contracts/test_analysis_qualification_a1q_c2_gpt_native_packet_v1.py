#!/usr/bin/env python3
"""Tests for the A1Q_C2 GPT Native packet. RAW below is a MECHANICS FIXTURE, never evidence."""
from __future__ import annotations

import copy
import hashlib
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import analysis_qualification_a1q_c2_gpt_native_packet_v1 as pk  # noqa: E402
import analysis_qualification_gpt_native_equivalent_v1 as eq  # noqa: E402

H = lambda c: c * 64  # noqa: E731
PACKET = pk.build_packet()


def good_raw() -> dict:
    return {"schema_version": "REQUEST_CONTEXT_V1",
            "request_identity": {"request_ref": pk.REQUEST_REF, "request_kind": "USER_REQUEST"},
            "objective": {"problem_statement": "Los clientes no entienden cuánto ahorran al negociar y abandonan.",
                          "desired_outcome": "Que el ahorro se vea claro y distinto del monto de la cuota."},
            "target_hints": ["marketplace"], "source_refs": [], "provided_facts": ["Hay abandono hoy"],
            "constraints": ["Urgente para el piloto"],
            "ambiguities": [
                {"code": "AMB-SCREEN", "statement": "No se indica en qué pantalla o momento se muestra.",
                 "materiality": "MATERIAL", "resolution_state": "OPEN"},
                {"code": "AMB-SAVING", "statement": "No se define qué significa ahorro ni contra qué base.",
                 "materiality": "MATERIAL", "resolution_state": "OPEN"},
                {"code": "AMB-URGENCY", "statement": "Urgente sin fecha ni criterio de aceptación.",
                 "materiality": "UNKNOWN", "resolution_state": "OPEN"}],
            "no_solution_inferred": True}


def run(raw, packet=PACKET, chat_ref="chat://fixture", chat_sha=H("b"), approval=H("a")):
    data = raw if isinstance(raw, bytes) else json.dumps(raw, ensure_ascii=False).encode("utf-8")
    return pk.intake(packet, data, chat_ref, chat_sha, approval)


def test_packet_deterministic_and_bound():
    again = pk.build_packet()
    assert again == PACKET and again["packet_sha256"] == PACKET["packet_sha256"]
    assert PACKET["input"]["input_sha256"] == hashlib.sha256(pk.INPUT_LITERAL.encode()).hexdigest()
    assert PACKET["limits"]["provider_attested"] is False and PACKET["producer_mode"] == "GPT_NATIVE"


def test_input_has_no_forbidden_solution_vocabulary():
    import re
    low = pk.INPUT_LITERAL.lower()
    assert not any(re.search(p, low) for p in pk.FORBIDDEN_SOLUTION)


def test_positive():
    verdict, rec = run(good_raw())
    assert verdict == eq.PASS_C2 and rec["runtime_provider_attested"] is False
    assert rec["raw_output_sha256"] == hashlib.sha256(json.dumps(good_raw(), ensure_ascii=False).encode()).hexdigest()


def mutate(fn):
    raw = good_raw()
    fn(raw)
    return raw


NEG = {
    "RAW_NOT_JSON": lambda: b"no es json",
    "RAW_NOT_OBJECT": lambda: b"[1,2]",
    "CONTRACT:REQUEST_CONTEXT_KEYS_MISMATCH": lambda: mutate(lambda r: r.update(extra=1)),
    "CONTRACT:REQUEST_CONTEXT_SOLUTION_INFERENCE": lambda: mutate(lambda r: r.update(no_solution_inferred=False)),
    "CONTRACT:AMBIGUITY_STATE": lambda: mutate(lambda r: r["ambiguities"][0].update(resolution_state="X")),
    "CONTRACT:OBJECTIVE_EMPTY": lambda: mutate(lambda r: r["objective"].update(desired_outcome=" ")),
    "REQUEST_REF_MISMATCH": lambda: mutate(lambda r: r["request_identity"].update(request_ref="REQ-OTHER-9")),
    "AMBIGUITY_NOT_RETAINED": lambda: mutate(lambda r: r.update(ambiguities=r["ambiguities"][:2])),
    "AMBIGUITY_NOT_RETAINED ": lambda: mutate(lambda r: [a.update(resolution_state="RESOLVED_FROM_SOURCE")
                                                         for a in r["ambiguities"]]),
    "SOLUTION_INFERRED": lambda: mutate(lambda r: r["constraints"].append("Usar una tabla en Postgres")),
    "SOLUTION_INFERRED ": lambda: mutate(lambda r: r["provided_facts"].append("exponer un API REST")),
}


def test_raw_negatives():
    for code, build in NEG.items():
        verdict, rec = run(build())
        assert rec is None and verdict == "BLOCK:" + code.strip(), (code, verdict)


def test_packet_negatives():
    bad = copy.deepcopy(PACKET)
    bad["input"]["input_literal"] += " usar redis"
    assert run(good_raw(), packet=bad)[0] == "BLOCK:PACKET_TAMPERED"
    assert run(good_raw(), packet={})[0] == "BLOCK:PACKET_SCHEMA_INVALID"


def test_binding_negatives():
    assert run(good_raw(), chat_ref="")[0] == "BLOCK:CHAT_TRANSCRIPT_REF_MISSING"
    assert run(good_raw(), chat_sha="zz")[0] == "BLOCK:CHAT_TRANSCRIPT_DIGEST_FORMAT"
    assert run(good_raw(), approval="short")[0] == "BLOCK:OWNER_APPROVAL_DIGEST_FORMAT"


def main():
    for name, fn in sorted(globals().items()):
        if name.startswith("test_"):
            fn()
    print("PASS_A1Q_C2_GPT_NATIVE_PACKET positives=1 raw_negatives=%d packet_negatives=2 binding_negatives=3 "
          "packet_sha256=%s api_calls=0 fixture_raw_is_not_evidence=true" % (len(NEG), PACKET["packet_sha256"][:16]))


if __name__ == "__main__":
    main()

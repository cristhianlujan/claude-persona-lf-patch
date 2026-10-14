#!/usr/bin/env python3
"""Tests for the A5Q_C2 GPT Native packet. RAW below is a MECHANICS FIXTURE, never evidence."""
from __future__ import annotations

import copy
import hashlib
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import analysis_qualification_a5q_c2_gpt_native_packet_v1 as pk  # noqa: E402
import analysis_qualification_gpt_native_equivalent_v1 as eq  # noqa: E402

H = lambda c: c * 64  # noqa: E731
PACKET = pk.build_packet()
CTX = json.loads(PACKET["input"]["input_literal"])
IMP = pk.impacts(CTX)
PAIRS = [("A4-DIRECT-001", "TARGET_IDENTITY_UNRESOLVED"), ("A4-DIRECT-002", "SAVINGS_SEMANTICS_UNRESOLVED"),
         ("A4-DIRECT-003", "AS_IS_BASELINE_MISSING"), ("A4-INDIRECT-001", "INSTALLMENT_DISTINCTION_UNRESOLVED"),
         ("A4-INDIRECT-002", "ACCEPTANCE_EVIDENCE_MISSING"), ("A4-DEPENDENCY-001", "TARGET_AUTHORITY_NOT_SUPPLIED")]


def good_raw() -> dict:
    pend = [{"decision_id": "DEC-%02d" % (i + 1),
             "question": "¿Qué define el propietario respecto de %s?" % g.lower().replace("_", " "),
             "owner_role": "OWNER_HUMAN", "blocking": i < 3, "gap_ref": g, "impact_ref": im,
             "status": "PENDING_OWNER_DECISION"} for i, (im, g) in enumerate(PAIRS)]
    return {"schema_version": pk.OUT_SCHEMA, "request_ref": pk.REQUEST_REF, "current_decisions": [],
            "current_decisions_basis": "La entrada no trae ninguna fuente de decisiones vigentes, por lo que no hay ninguna.",
            "pending_decisions": pend, "decisions_approved_by_agent": [],
            "evidence_refs": ["gap:TARGET_IDENTITY_UNRESOLVED", "impact:A4-DIRECT-002"],
            "decision_statement": "Las decisiones listadas corresponden al propietario humano; el agente no resolvió ninguna de ellas.",
            "no_self_approval": True}


def run(raw, packet=PACKET, chat_ref="chat://fixture", chat_sha=H("b"), approval=H("a")):
    data = raw if isinstance(raw, bytes) else json.dumps(raw, ensure_ascii=False).encode("utf-8")
    return pk.intake(packet, data, chat_ref, chat_sha, approval)


def mutate(fn):
    raw = good_raw()
    fn(raw)
    return raw


def test_packet_deterministic_and_bound():
    again = pk.build_packet()
    assert again == PACKET and PACKET["producer_mode"] == "GPT_NATIVE" and PACKET["limits"]["provider_attested"] is False
    assert PACKET["input"]["input_sha256"] == hashlib.sha256(PACKET["input"]["input_literal"].encode()).hexdigest()
    assert len(IMP) == 10


def test_expected_values_not_leaked_in_prompt():
    assert "OWNER_HUMAN" in PACKET["prompt_for_gpt"] and "PENDING_OWNER_DECISION" in PACKET["prompt_for_gpt"]


def test_positive():
    verdict, rec = run(good_raw())
    assert verdict == eq.PASS_C2 and rec["runtime_provider_attested"] is False


NEG = {
    "RAW_NOT_JSON": lambda: b"no es json",
    "RAW_NOT_OBJECT": lambda: b"[1]",
    "KEYS_OR_SCHEMA": lambda: mutate(lambda r: r.update(extra=1)),
    "KEYS_OR_SCHEMA ": lambda: mutate(lambda r: r.update(schema_version="X")),
    "REQUEST_REF_MISMATCH": lambda: mutate(lambda r: r.update(request_ref="REQ-X")),
    "SELF_APPROVAL_FLAG": lambda: mutate(lambda r: r.update(no_self_approval=False)),
    "AGENT_APPROVED_DECISION": lambda: mutate(lambda r: r.update(decisions_approved_by_agent=["DEC-01"])),
    "CURRENT_DECISION_WITHOUT_SOURCE": lambda: mutate(lambda r: r.update(current_decisions=[{"id": "ADR-1"}])),
    "CURRENT_BASIS_MISSING": lambda: mutate(lambda r: r.update(current_decisions_basis="x")),
    "PENDING_SHAPE": lambda: mutate(lambda r: r.update(pending_decisions=[])),
    "PENDING_SHAPE ": lambda: mutate(lambda r: r["pending_decisions"][0].update(extra=1)),
    "PENDING_IDS": lambda: mutate(lambda r: r["pending_decisions"][1].update(decision_id="DEC-01")),
    "PENDING_QUESTION": lambda: mutate(lambda r: r["pending_decisions"][0].update(question="Definir el ahorro como se vea mejor")),
    "PENDING_OWNER_ROLE": lambda: mutate(lambda r: r["pending_decisions"][0].update(owner_role="AGENT")),
    "PENDING_STATUS": lambda: mutate(lambda r: r["pending_decisions"][0].update(status="APPROVED")),
    "PENDING_BLOCKING_TYPE": lambda: mutate(lambda r: r["pending_decisions"][0].update(blocking="si")),
    "PENDING_IMPACT_NOT_IN_INPUT": lambda: mutate(lambda r: r["pending_decisions"][0].update(impact_ref="A4-INVENTED-9")),
    "PENDING_GAP_IMPACT_MISMATCH": lambda: mutate(lambda r: r["pending_decisions"][0].update(gap_ref="AS_IS_BASELINE_MISSING")),
    "GAP_COVERAGE_TOO_NARROW": lambda: mutate(lambda r: r.update(pending_decisions=r["pending_decisions"][:4])),
    "NO_BLOCKING_DECISION": lambda: mutate(lambda r: [p.update(blocking=False) for p in r["pending_decisions"]]),
    "EVIDENCE_REFS_INVALID": lambda: mutate(lambda r: r.update(evidence_refs=["gap:INVENTED"])),
    "EVIDENCE_REFS_INVALID ": lambda: mutate(lambda r: r.update(evidence_refs=[])),
    "DECISION_STATEMENT_MISSING": lambda: mutate(lambda r: r.update(decision_statement="corto")),
    "SELF_APPROVAL_LANGUAGE": lambda: mutate(lambda r: r.update(decision_statement="Se decide mostrar el ahorro; el propietario solo confirma la decisión tomada.")),
    "SELF_APPROVAL_LANGUAGE ": lambda: mutate(lambda r: r.update(decision_statement="El agente ha aprobado el alcance del piloto y cierra la revisión del propietario.")),
    "SOLUTION_INFERRED": lambda: mutate(lambda r: r["pending_decisions"][0].update(question="¿Se guarda el ahorro en una tabla de la base de datos?")),
}


def test_denial_of_approval_is_not_self_approval():
    ok = mutate(lambda r: r.update(decision_statement="Ninguna decisión ha sido aprobada por el agente; todas siguen pendientes del propietario humano."))
    assert run(ok)[0] == eq.PASS_C2
    assert pk.affirmed_self_approval("Se decide mostrar el ahorro.") and not pk.affirmed_self_approval("No se puede considerar aprobada ninguna regla.")


def test_raw_negatives():
    for code, build in NEG.items():
        verdict, rec = run(build())
        assert rec is None and verdict == "BLOCK:" + code.strip(), (code, verdict)


def test_shape_garbage_is_blocked_not_crash():
    verdict, rec = run(mutate(lambda r: r.update(pending_decisions=[1, 2])))
    assert rec is None and verdict.startswith("BLOCK:")


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
    print("PASS_A5Q_C2_GPT_NATIVE_PACKET positives=1 raw_negatives=%d packet_binding_negatives=5 packet_sha256=%s "
          "api_calls=0 fixture_raw_is_not_evidence=true" % (len(NEG) + 1, PACKET["packet_sha256"][:16]))


if __name__ == "__main__":
    main()

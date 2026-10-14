#!/usr/bin/env python3
"""Tests for the A6Q_C2 GPT Native packet. RAW below is a MECHANICS FIXTURE, never evidence."""
from __future__ import annotations

import copy
import hashlib
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import analysis_qualification_a6q_c2_gpt_native_packet_v1 as pk  # noqa: E402
import analysis_qualification_gpt_native_equivalent_v1 as eq  # noqa: E402

H = lambda c: c * 64  # noqa: E731
PACKET = pk.build_packet()
IDS = sorted(pk.decision_ids(json.loads(PACKET["input"]["input_literal"])))


def good_raw() -> dict:
    reqs = [{"requirement_id": "REQ-%02d" % (i + 1), "type": "FUNCTIONAL" if i < 3 else "DATA",
             "statement": "El cliente debe poder conocer el ahorro antes de aceptar la oferta (aspecto " + "abcde"[i] + ").",
             "status": pk.STATUS, "depends_on_decisions": [d], "source_ref": "decision:" + d} for i, d in enumerate(IDS)]
    dim = {k: {"status": pk.BLOCKED, "blocked_by": IDS[:2], "note": "No hay fuente en la entrada para especificar esta dimensión."}
           for k in pk.DIMENSIONS}
    dim["functional"] = {"status": pk.STATUS, "blocked_by": IDS, "note": "Provisional hasta que el propietario decida las cinco decisiones."}
    return {"schema_version": pk.OUT_SCHEMA, "request_ref": pk.REQUEST_REF, "requirements": reqs, "dimensions": dim,
            "evidence_refs": ["gap:TARGET_IDENTITY_UNRESOLVED", "decision:" + IDS[0]], "no_unlicensed_how": True,
            "requirements_statement": "Los requisitos son provisionales y dependen de decisiones pendientes; permisos, estados, errores y efectos siguen bloqueados."}


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
    assert len(IDS) == 5


def test_positive():
    verdict, rec = run(good_raw())
    assert verdict == eq.PASS_C2 and rec["runtime_provider_attested"] is False


NEG = {
    "RAW_NOT_JSON": lambda: b"no es json",
    "RAW_NOT_OBJECT": lambda: b"[1]",
    "KEYS_OR_SCHEMA": lambda: mutate(lambda r: r.update(extra=1)),
    "REQUEST_REF_MISMATCH": lambda: mutate(lambda r: r.update(request_ref="REQ-X")),
    "UNLICENSED_HOW_FLAG": lambda: mutate(lambda r: r.update(no_unlicensed_how=False)),
    "REQUIREMENTS_SHAPE": lambda: mutate(lambda r: r.update(requirements=[])),
    "REQUIREMENTS_SHAPE ": lambda: mutate(lambda r: r["requirements"][0].update(extra=1)),
    "REQUIREMENT_IDS": lambda: mutate(lambda r: r["requirements"][1].update(requirement_id="REQ-01")),
    "REQUIREMENT_TYPE_NOT_SOURCED": lambda: mutate(lambda r: r["requirements"][0].update(type="PERMISSION")),
    "REQUIREMENT_TYPE_NOT_SOURCED ": lambda: mutate(lambda r: r["requirements"][0].update(type="SIDE_EFFECT")),
    "REQUIREMENT_CONFIRMED_WITHOUT_DECISION": lambda: mutate(lambda r: r["requirements"][0].update(status="CONFIRMED")),
    "REQUIREMENT_DECISION_REFS": lambda: mutate(lambda r: r["requirements"][0].update(depends_on_decisions=[])),
    "REQUIREMENT_DECISION_REFS ": lambda: mutate(lambda r: r["requirements"][0].update(depends_on_decisions=["A5-DEC-099"])),
    "REQUIREMENT_SOURCE_REF": lambda: mutate(lambda r: r["requirements"][0].update(source_ref="decision:INVENTED")),
    "REQUIREMENT_STATEMENT": lambda: mutate(lambda r: r["requirements"][0].update(statement="corto")),
    "INVENTED_NUMBER": lambda: mutate(lambda r: r["requirements"][0].update(statement="El ahorro debe mostrarse en menos de 3 segundos antes de aceptar la oferta.")),
    "DECISION_COVERAGE_TOO_NARROW": lambda: mutate(lambda r: r.update(requirements=r["requirements"][:3])),
    "NO_FUNCTIONAL_REQUIREMENT": lambda: mutate(lambda r: [q.update(type="DATA") for q in r["requirements"]]),
    "DIMENSIONS_SHAPE": lambda: mutate(lambda r: r["dimensions"].pop("state")),
    "DIMENSION_SHAPE": lambda: mutate(lambda r: r["dimensions"]["data"].pop("note")),
    "DIMENSION_STATUS": lambda: mutate(lambda r: r["dimensions"]["data"].update(status="SPECIFIED")),
    "DIMENSION_NOTE": lambda: mutate(lambda r: r["dimensions"]["data"].update(note="x")),
    "UNSOURCED_DIMENSION_SPECIFIED": lambda: mutate(lambda r: r["dimensions"]["permissions"].update(status=pk.STATUS)),
    "DIMENSION_BLOCKERS": lambda: mutate(lambda r: r["dimensions"]["errors"].update(blocked_by=[])),
    "DIMENSION_BLOCKERS ": lambda: mutate(lambda r: r["dimensions"]["state"].update(blocked_by=["A5-DEC-099"])),
    "EVIDENCE_REFS_INVALID": lambda: mutate(lambda r: r.update(evidence_refs=["gap:INVENTED"])),
    "STATEMENT_MISSING": lambda: mutate(lambda r: r.update(requirements_statement="corto")),
    "SOLUTION_INFERRED": lambda: mutate(lambda r: r["requirements"][0].update(statement="El ahorro debe leerse desde una tabla de la base de datos antes de aceptar.")),
}


def test_raw_negatives():
    for code, build in NEG.items():
        verdict, rec = run(build())
        assert rec is None and verdict == "BLOCK:" + code.strip(), (code, verdict)


def test_shape_garbage_is_blocked_not_crash():
    for fn in (lambda r: r.update(requirements=[1, 2]), lambda r: r.update(dimensions=[]), lambda r: r["dimensions"].update(data=5)):
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
    print("PASS_A6Q_C2_GPT_NATIVE_PACKET positives=1 raw_negatives=%d packet_binding_negatives=5 packet_sha256=%s "
          "api_calls=0 fixture_raw_is_not_evidence=true" % (len(NEG) + 1, PACKET["packet_sha256"][:16]))


if __name__ == "__main__":
    main()

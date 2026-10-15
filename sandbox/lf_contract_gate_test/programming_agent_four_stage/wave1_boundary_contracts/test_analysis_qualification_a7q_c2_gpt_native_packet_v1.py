#!/usr/bin/env python3
"""Tests for the A7Q_C2 GPT Native packet. RAW below is a MECHANICS FIXTURE, never evidence."""
from __future__ import annotations

import copy
import hashlib
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import analysis_qualification_a7q_c2_gpt_native_packet_v1 as pk  # noqa: E402
import analysis_qualification_gpt_native_equivalent_v1 as eq  # noqa: E402

H = lambda c: c * 64  # noqa: E731
PACKET = pk.build_packet()
CTX = json.loads(PACKET["input"]["input_literal"])
SC = sorted(pk.scope_ids(CTX))
DEC = sorted(pk.decisions(CTX))
REQS = [s for s in SC if not s.startswith("dimension:")]
DIMS = [s for s in SC if s.startswith("dimension:")]


def front(i, scopes):
    return {"front_id": "FRONT-%02d" % i, "scope_ids": scopes, "obligation_mode": "REQUIRED", "closure": "BLOCKED",
            "blockers": DEC[:2], "evidence_refs": [scopes[0], "decision:" + DEC[0]],
            "reason": "El frente permanece bloqueado hasta que el propietario decida las cuestiones pendientes."}


def good_raw() -> dict:
    return {"schema_version": pk.OUT_SCHEMA, "request_ref": pk.REQUEST_REF,
            "material_fronts": [front(1, REQS[:3]), front(2, REQS[3:] + DIMS[:2]), front(3, DIMS[2:])],
            "evidence_refs": ["decision:" + DEC[0], REQS[0]],
            "fronts_statement": "Todos los frentes quedan bloqueados porque las decisiones pendientes del propietario no se han resuelto."}


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
    assert len(REQS) == 5 and len(DIMS) == 6


def test_positive():
    verdict, rec = run(good_raw())
    assert verdict == eq.PASS_C2 and rec["runtime_provider_attested"] is False


NEG = {
    "RAW_NOT_JSON": lambda: b"no es json",
    "RAW_NOT_OBJECT": lambda: b"[1]",
    "KEYS_OR_SCHEMA": lambda: mutate(lambda r: r.update(extra=1)),
    "REQUEST_REF_MISMATCH": lambda: mutate(lambda r: r.update(request_ref="REQ-X")),
    "FRONTS_SHAPE": lambda: mutate(lambda r: r.update(material_fronts=r["material_fronts"][:2])),
    "FRONTS_SHAPE ": lambda: mutate(lambda r: r["material_fronts"][0].update(extra=1)),
    "FRONT_IDS": lambda: mutate(lambda r: r["material_fronts"][1].update(front_id="FRONT-01")),
    "FRONT_SCOPE_IDS": lambda: mutate(lambda r: r["material_fronts"][0].update(scope_ids=["A6-REQ-099"])),
    "FRONT_SCOPE_IDS ": lambda: mutate(lambda r: r["material_fronts"][0].update(scope_ids=[])),
    "FRONT_MODE_INVALID": lambda: mutate(lambda r: r["material_fronts"][0].update(obligation_mode="OPTIONAL")),
    "FRONT_MODE_WITHOUT_AUTHORITY": lambda: mutate(lambda r: r["material_fronts"][0].update(obligation_mode="NOT_APPLICABLE")),
    "FRONT_MODE_WITHOUT_AUTHORITY ": lambda: mutate(lambda r: r["material_fronts"][0].update(obligation_mode="REUSE_AS_IS")),
    "FRONT_CLOSED_WITHOUT_EVIDENCE": lambda: mutate(lambda r: r["material_fronts"][0].update(closure="CLOSED")),
    "FRONT_BLOCKERS": lambda: mutate(lambda r: r["material_fronts"][0].update(blockers=[])),
    "FRONT_BLOCKERS ": lambda: mutate(lambda r: r["material_fronts"][0].update(blockers=["A5-DEC-099"])),
    "FRONT_EVIDENCE_REFS": lambda: mutate(lambda r: r["material_fronts"][0].update(evidence_refs=["gap:INVENTED"])),
    "FRONT_REASON": lambda: mutate(lambda r: r["material_fronts"][0].update(reason="x")),
    "SCOPE_COVERAGE_INCOMPLETE": lambda: mutate(lambda r: r["material_fronts"][2].update(scope_ids=DIMS[2:5])),
    "EVIDENCE_REFS_INVALID": lambda: mutate(lambda r: r.update(evidence_refs=[])),
    "STATEMENT_MISSING": lambda: mutate(lambda r: r.update(fronts_statement="corto")),
    "SOLUTION_INFERRED": lambda: mutate(lambda r: r["material_fronts"][0].update(reason="Se resuelve con una tabla en la base de datos del marketplace.")),
}


def test_raw_negatives():
    for code, build in NEG.items():
        verdict, rec = run(build())
        assert rec is None and verdict == "BLOCK:" + code.strip(), (code, verdict)


def test_shape_garbage_is_blocked_not_crash():
    for fn in (lambda r: r.update(material_fronts=[1, 2, 3]), lambda r: r["material_fronts"][0].update(scope_ids=5)):
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
    print("PASS_A7Q_C2_GPT_NATIVE_PACKET positives=1 raw_negatives=%d packet_binding_negatives=5 packet_sha256=%s "
          "api_calls=0 fixture_raw_is_not_evidence=true" % (len(NEG) + 1, PACKET["packet_sha256"][:16]))


if __name__ == "__main__":
    main()

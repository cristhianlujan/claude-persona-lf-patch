#!/usr/bin/env python3
"""Tests for the A9Q_C2 GPT Native packet. RAW below is a MECHANICS FIXTURE, never evidence."""
from __future__ import annotations

import copy
import hashlib
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import analysis_qualification_a9q_c2_gpt_native_packet_v1 as pk  # noqa: E402
import analysis_qualification_gpt_native_equivalent_v1 as eq  # noqa: E402

H = lambda c: c * 64  # noqa: E731
PACKET = pk.build_packet()
CTX = json.loads(PACKET["input"]["input_literal"])
FR = pk.a7_fronts(CTX)
OK = sorted(pk.allowed_refs(CTX))


def good_raw() -> dict:
    scopes = sorted(pk.a7_scopes(CTX))
    scope_rows = []
    for s in scopes:
        cont = sorted(i for i, a in FR.items() if s in a["scope_ids"])
        scope_rows.append({"scope_id": s, "status": "REQUIRES_DECISION", "material_front_refs": cont, "depends_on_scope_ids": [],
                           "blockers": sorted(set().union(*(set(FR[i]["blockers"]) for i in cont)))})
    fronts, matrix = [], []
    for i, a in sorted(FR.items()):
        fronts.append({"front_id": i, "front_kind": "ALCANCE", "status": a["obligation_mode"], "closure": a["closure"],
                       "source_signal_refs": [OK[0]], "scope_refs": sorted(a["scope_ids"]), "authority_refs": [],
                       "evidence_refs": [OK[0]], "currentness_refs": [], "blockers": sorted(a["blockers"]),
                       "reason": "El frente bloquea los scopes porque sus decisiones siguen pendientes."})
        for s in sorted(a["scope_ids"]):
            matrix.append({"scope_id": s, "front_id": i, "front_status": a["obligation_mode"], "front_closure": a["closure"], "effect_on_scope": "BLOCKS"})
    return {"schema_version": pk.OUT_SCHEMA, "request_ref": pk.REQUEST_REF, "candidate_only": True,
            "research_decision": CTX["a8_stage_output"]["research_decision"], "scope_readiness": scope_rows,
            "material_front_coverage": {"all_material_fronts_accounted": True, "material_fronts": fronts, "front_candidate_refs": sorted(FR),
                                         "unmapped_material_signals": [], "source_refs": [OK[0]], "currentness_refs": [],
                                         "coverage_fingerprint_sha256": pk.ZERO},
            "scope_front_matrix": matrix, "package_readiness": "REQUIRES_DECISION", "no_ready_claim": True,
            "snapshot_statement": "Ningún scope ni el paquete son READY porque todos los frentes están bloqueados por decisiones pendientes."}


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
    assert len(FR) == 5 and len(pk.a7_scopes(CTX)) == 11


def test_positive():
    verdict, rec = run(good_raw())
    assert verdict == eq.PASS_C2 and rec["runtime_provider_attested"] is False


def _first(r, k):
    return r["material_front_coverage"]["material_fronts"][0] if k == "front" else r["scope_readiness"][0]


NEG = {
    "RAW_NOT_JSON": lambda: b"no es json",
    "RAW_NOT_OBJECT": lambda: b"[1]",
    "KEYS_OR_SCHEMA": lambda: mutate(lambda r: r.update(extra=1)),
    "REQUEST_REF_MISMATCH": lambda: mutate(lambda r: r.update(request_ref="REQ-X")),
    "READY_OR_CANDIDATE_FLAG": lambda: mutate(lambda r: r.update(no_ready_claim=False)),
    "READY_OR_CANDIDATE_FLAG ": lambda: mutate(lambda r: r.update(candidate_only=False)),
    "RESEARCH_DECISION_MISMATCH": lambda: mutate(lambda r: r.update(research_decision="CONTINUE")),
    "PACKAGE_READINESS_INVALID": lambda: mutate(lambda r: r.update(package_readiness="READY")),
    "PACKAGE_READINESS_INVALID ": lambda: mutate(lambda r: r.update(package_readiness="PARTIAL_READY")),
    "SCOPE_SHAPE": lambda: mutate(lambda r: _first(r, "scope").update(extra=1)),
    "COVERAGE_SHAPE": lambda: mutate(lambda r: r["material_front_coverage"].pop("source_refs")),
    "MATRIX_SHAPE": lambda: mutate(lambda r: r["scope_front_matrix"][0].pop("effect_on_scope")),
    "FINGERPRINT_NOT_PLACEHOLDER": lambda: mutate(lambda r: r["material_front_coverage"].update(coverage_fingerprint_sha256="a" * 64)),
    "SCOPE_SET_MISMATCH": lambda: mutate(lambda r: _first(r, "scope").update(scope_id="A6-REQ-099")),
    "SCOPE_READY_OR_INVALID_STATUS": lambda: mutate(lambda r: _first(r, "scope").update(status="NOT_APPLICABLE")),
    "SCOPE_DEPENDENCY_INVENTED": lambda: mutate(lambda r: _first(r, "scope").update(depends_on_scope_ids=[r["scope_readiness"][1]["scope_id"]])),
    "SCOPE_BLOCKERS_MISMATCH": lambda: mutate(lambda r: _first(r, "scope").update(blockers=["A5-DEC-005"] if _first(r, "scope")["blockers"] != ["A5-DEC-005"] else ["A5-DEC-001"])),
    "FRONT_STATUS_MISMATCH": lambda: mutate(lambda r: _first(r, "front").update(status="REUSE_AS_IS")),
    "FRONT_BLOCKERS_MISMATCH": lambda: mutate(lambda r: _first(r, "front").update(blockers=["A5-DEC-005"])),
    "AUTHORITY_OR_CURRENTNESS_INVENTED": lambda: mutate(lambda r: _first(r, "front").update(authority_refs=[OK[0]])),
    "FRONT_REFS_INVALID": lambda: mutate(lambda r: _first(r, "front").update(source_signal_refs=["gap:INVENTED"])),
    "FRONT_TEXT": lambda: mutate(lambda r: _first(r, "front").update(reason="x")),
    "MATRIX_EFFECT_NOT_BLOCKS": lambda: mutate(lambda r: r["scope_front_matrix"][0].update(effect_on_scope="PRESERVE")),
    "COVERAGE_REFS_INVALID": lambda: mutate(lambda r: r["material_front_coverage"].update(source_refs=[])),
    "STATEMENT_MISSING": lambda: mutate(lambda r: r.update(snapshot_statement="corto")),
    "SOLUTION_INFERRED": lambda: mutate(lambda r: _first(r, "front").update(reason="El frente se resuelve guardando el ahorro en una tabla de la base de datos.")),
}


VALIDATOR_FIRST = {"SCOPE_SET_MISMATCH", "FRONT_STATUS_MISMATCH", "MATRIX_EFFECT_NOT_BLOCKS"}


def test_raw_negatives():
    for code, build in NEG.items():
        verdict, rec = run(build())
        want = "BLOCK:" + code.strip()
        if code in VALIDATOR_FIRST:  # the existing snapshot validator rejects an invented scope first (parity); own check is defense in depth
            assert rec is None and verdict.startswith("BLOCK:SNAPSHOT_VALIDATOR:"), verdict
            continue
        assert rec is None and verdict == want, (code, verdict)


def test_existing_snapshot_validator_rejections_are_blocked():
    # matrix row removed -> incomplete matrix (validator), scope marked READY -> status/validator
    v, rec = run(mutate(lambda r: r["scope_front_matrix"].pop()))
    assert rec is None and v.startswith("BLOCK:SNAPSHOT_VALIDATOR:")
    v, rec = run(mutate(lambda r: _first(r, "scope").update(status="READY")))
    assert rec is None and v.startswith("BLOCK:")


def test_shape_garbage_is_blocked_not_crash():
    for fn in (lambda r: r.update(scope_readiness=[1]), lambda r: r.update(material_front_coverage=[]), lambda r: r.update(scope_front_matrix=5)):
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
    print("PASS_A9Q_C2_GPT_NATIVE_PACKET positives=1 raw_negatives=%d packet_binding_negatives=5 packet_sha256=%s "
          "api_calls=0 fixture_raw_is_not_evidence=true" % (len(NEG) + 3, PACKET["packet_sha256"][:16]))


if __name__ == "__main__":
    main()

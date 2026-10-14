#!/usr/bin/env python3
"""Tests for the A10Q_C2 GPT Native packet. RAW below is a MECHANICS FIXTURE, never evidence."""
from __future__ import annotations

import copy
import hashlib
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import analysis_qualification_a10q_c2_gpt_native_packet_v1 as pk  # noqa: E402
import analysis_qualification_gpt_native_equivalent_v1 as eq  # noqa: E402

H = lambda c: c * 64  # noqa: E731
PACKET = pk.build_packet()
CTX = json.loads(PACKET["input"]["input_literal"])


def good_raw() -> dict:
    co = []
    for c in CTX["cases"]:
        co.append({"case_id": c["case_id"], "change_family": c["change_family"], "verdict": "NEED_MORE_EVIDENCE",
                   "critical_impacts_observed": [{"impact": "Posible efecto sobre consumidores del contrato afectado.", "basis": pk.BASIS}],
                   "material_fronts_observed": [{"front": "ALCANCE", "reason": "El alcance del cambio no está definido en la entrada."}],
                   "evidence_refs": [c["source_refs"][0]], "false_ready_count": 0, "reinterpretation_required": True,
                   "handoff_parity_verdict": pk.NOT_EVALUATED, "scope_front_consistency_verdict": pk.NOT_EVALUATED, "currentness_verdict": pk.NOT_EVALUATED,
                   "source_read_count": 0, "duplicate_read_count": 0, "retry_count": 0,
                   "evidence_note": "El análisis parte del asunto del caso y no del contenido de sus fuentes."})
    return {"schema_version": pk.OUT_SCHEMA, "request_ref": pk.REQUEST_REF, "cohort": co, "families_covered": sorted({c["change_family"] for c in CTX["cases"]}),
            "no_ready_claim": True,
            "cohort_statement": "Resultado candidato: ningún caso es READY y nada se midió contra un oráculo ni contra el contenido de las fuentes."}


def run(raw, packet=PACKET, chat_ref="chat://fixture", chat_sha=H("b"), approval=H("a")):
    data = raw if isinstance(raw, bytes) else json.dumps(raw, ensure_ascii=False).encode("utf-8")
    return pk.intake(packet, data, chat_ref, chat_sha, approval)


def mutate(fn):
    raw = good_raw()
    fn(raw)
    return raw


def c0(r):
    return r["cohort"][0]


def test_packet_deterministic_and_bound():
    assert pk.build_packet() == PACKET and PACKET["limits"]["provider_attested"] is False
    assert PACKET["input"]["input_sha256"] == hashlib.sha256(PACKET["input"]["input_literal"].encode()).hexdigest()
    assert len(CTX["cases"]) == 7 and {c["change_family"] for c in CTX["cases"]} == set(pk.FAMILIES)
    assert all(set(c) == {"case_id", "change_family", "historical_subject", "source_refs"} for c in CTX["cases"])  # no oracle fields leaked


def test_positive():
    verdict, rec = run(good_raw())
    assert verdict == eq.PASS_C2 and rec["runtime_provider_attested"] is False


NEG = {
    "RAW_NOT_JSON": lambda: b"no es json",
    "RAW_NOT_OBJECT": lambda: b"[1]",
    "KEYS_OR_SCHEMA": lambda: mutate(lambda r: r.update(extra=1)),
    "REQUEST_REF_MISMATCH": lambda: mutate(lambda r: r.update(request_ref="REQ-X")),
    "READY_CLAIM": lambda: mutate(lambda r: r.update(no_ready_claim=False)),
    "COHORT_SHAPE": lambda: mutate(lambda r: r.update(cohort=[1])),
    "CASE_SET_MISMATCH": lambda: mutate(lambda r: r["cohort"].pop()),
    "CASE_SET_MISMATCH ": lambda: mutate(lambda r: r["cohort"].append(copy.deepcopy(r["cohort"][0]))),
    "CASE_KEYS": lambda: mutate(lambda r: c0(r).update(elapsed_ms=5)),
    "FAMILY_MISMATCH": lambda: mutate(lambda r: c0(r).update(change_family="BUG" if c0(r)["change_family"] != "BUG" else "RUNTIME")),
    "VERDICT_READY_OR_INVALID": lambda: mutate(lambda r: c0(r).update(verdict="READY")),
    "IMPACTS_INVALID": lambda: mutate(lambda r: c0(r).update(critical_impacts_observed=[])),
    "IMPACTS_INVALID ": lambda: mutate(lambda r: c0(r)["critical_impacts_observed"][0].update(basis="VERIFIED_IN_SOURCE")),
    "FRONTS_INVALID": lambda: mutate(lambda r: c0(r).update(material_fronts_observed=[])),
    "EVIDENCE_REFS_INVALID": lambda: mutate(lambda r: c0(r).update(evidence_refs=["lf_eventos://99999"])),
    "EVIDENCE_REFS_INVALID ": lambda: mutate(lambda r: c0(r).update(evidence_refs=[])),
    "EVIDENCE_REFS_INVALID  ": lambda: mutate(lambda r: c0(r).update(evidence_refs=[r["cohort"][1]["evidence_refs"][0]])),
    "FALSE_READY_COUNT": lambda: mutate(lambda r: c0(r).update(false_ready_count=1)),
    "FALSE_READY_COUNT ": lambda: mutate(lambda r: c0(r).update(false_ready_count=False)),
    "REINTERPRETATION_NOT_BOOL": lambda: mutate(lambda r: c0(r).update(reinterpretation_required="si")),
    "UNMEASURED_VERDICT_CLAIMED": lambda: mutate(lambda r: c0(r).update(currentness_verdict="PASS")),
    "READ_COUNTS_NOT_ZERO": lambda: mutate(lambda r: c0(r).update(source_read_count=3)),
    "EVIDENCE_NOTE": lambda: mutate(lambda r: c0(r).update(evidence_note="corto")),
    "FAMILIES_COVERED": lambda: mutate(lambda r: r.update(families_covered=["BUG"])),
    "STATEMENT_MISSING": lambda: mutate(lambda r: r.update(cohort_statement="corto")),
    "SOLUTION_INFERRED": lambda: mutate(lambda r: c0(r)["material_fronts_observed"][0].update(reason="Se resuelve guardando el ahorro en una tabla de la base de datos.")),
}


def test_migration_word_allowed_only_in_migration_family_record():
    ok = mutate(lambda r: [x["critical_impacts_observed"][0].update(impact="Posible divergencia en una migración con consecuencias sobre datos afectados.")
                           for x in r["cohort"] if x["change_family"] == "MIGRATION"])
    assert run(ok)[0] == eq.PASS_C2
    bad = mutate(lambda r: [x["critical_impacts_observed"][0].update(impact="Posible divergencia en una migración con consecuencias sobre datos afectados.")
                            for x in r["cohort"] if x["change_family"] == "BUG"])
    assert run(bad)[0] == "BLOCK:SOLUTION_INFERRED"
    top = mutate(lambda r: r.update(cohort_statement="Resultado candidato: ningún caso es READY; se sugiere una migración para resolverlo todo, sin medir nada."))
    assert run(top)[0] == "BLOCK:SOLUTION_INFERRED"


def test_raw_negatives():
    for code, build in NEG.items():
        verdict, rec = run(build())
        assert rec is None and verdict == "BLOCK:" + code.strip(), (code, verdict)


def test_shape_garbage_is_blocked_not_crash():
    for fn in (lambda r: r.update(cohort=5), lambda r: r.update(families_covered=5), lambda r: c0(r).update(evidence_refs=5),
               lambda r: c0(r).update(critical_impacts_observed=[5]), lambda r: c0(r).update(material_fronts_observed=[5])):
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
    print("PASS_A10Q_C2_GPT_NATIVE_PACKET positives=1 raw_negatives=%d migration_exemption_scoped=1 shape_garbage=5 packet_binding_negatives=5 packet_sha256=%s "
          "api_calls=0 fixture_raw_is_not_evidence=true" % (len(NEG) + 0, PACKET["packet_sha256"][:16]))


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Tests for the A4Q_C2 GPT Native packet. RAW below is a MECHANICS FIXTURE, never evidence."""
from __future__ import annotations

import copy
import hashlib
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import analysis_qualification_a4q_c2_gpt_native_packet_v1 as pk  # noqa: E402
import analysis_qualification_gpt_native_equivalent_v1 as eq  # noqa: E402

H = lambda c: c * 64  # noqa: E731
PACKET = pk.build_packet()
CTX = json.loads(PACKET["input"]["input_literal"])
GAPS = sorted(pk.gap_codes(CTX))
SRC = CTX["a3_stage_output"]["source_refs"][0]


def good_raw() -> dict:
    un = [{"impact_id": "UI-%d" % i, "category": c, "gap_ref": GAPS[i],
           "statement": "No se puede determinar la incógnita de la categoría %s por la brecha indicada." % c}
          for i, c in enumerate(pk.CATEGORIES)]
    return {"schema_version": pk.OUT_SCHEMA, "request_ref": pk.REQUEST_REF, "direct_impacts": [], "indirect_impacts": [],
            "consumers": [], "dependency_paths": [], "evidence_refs": [SRC, "gap:" + GAPS[0]],
            "unresolved_material_impacts": un,
            "impact_statement": "La evidencia suministrada no identifica el objetivo, por lo que no se pueden afirmar efectos; solo se enumeran incógnitas.",
            "no_absence_claimed": True}


def run(raw, packet=PACKET, chat_ref="chat://fixture", chat_sha=H("b"), approval=H("a")):
    data = raw if isinstance(raw, bytes) else json.dumps(raw, ensure_ascii=False).encode("utf-8")
    return pk.intake(packet, data, chat_ref, chat_sha, approval)


def mut(fn):
    r = good_raw()
    fn(r)
    return r


def test_packet_deterministic_and_bound():
    assert pk.build_packet() == PACKET
    assert hashlib.sha256(PACKET["input"]["input_literal"].encode()).hexdigest() == PACKET["input"]["input_sha256"]
    assert PACKET["limits"]["provider_attested"] is False and PACKET["subject_ref"].endswith("A4Q/A4Q_C2")
    assert len(GAPS) >= 8


def test_positive():
    verdict, rec = run(good_raw())
    assert verdict == eq.PASS_C2 and rec["runtime_provider_attested"] is False


NEG = {
    "RAW_NOT_JSON": lambda: b"no es json",
    "RAW_NOT_OBJECT": lambda: b"[1]",
    "KEYS_OR_SCHEMA": lambda: mut(lambda r: r.update(extra=1)),
    "REQUEST_REF_MISMATCH": lambda: mut(lambda r: r.update(request_ref="REQ-X")),
    "ABSENCE_CLAIMED": lambda: mut(lambda r: r.update(no_absence_claimed=False)),
    "ABSENCE_CLAIMED ": lambda: mut(lambda r: r.update(impact_statement="Se concluye que no hay impacto indirecto alguno sobre otros módulos del sistema.")),
    "LIST_SHAPE_consumers": lambda: mut(lambda r: r.update(consumers="ninguno")),
    "IMPACT_ASSERTED_WITHOUT_EVIDENCE": lambda: mut(lambda r: r.update(direct_impacts=[{"statement": "x", "evidence_refs": [SRC]}])),
    "IMPACT_ASSERTED_WITHOUT_EVIDENCE ": lambda: mut(lambda r: r.update(consumers=[{"statement": "pantalla de ofertas", "evidence_refs": [SRC]}])),
    "EVIDENCE_REFS_INVALID": lambda: mut(lambda r: r.update(evidence_refs=["supabase://invented"])),
    "EVIDENCE_REFS_INVALID ": lambda: mut(lambda r: r.update(evidence_refs=[])),
    "UNRESOLVED_SHAPE": lambda: mut(lambda r: r["unresolved_material_impacts"][0].pop("gap_ref")),
    "UNRESOLVED_SHAPE ": lambda: mut(lambda r: r.update(unresolved_material_impacts=[])),
    "UNRESOLVED_IDS": lambda: mut(lambda r: r["unresolved_material_impacts"][1].update(impact_id="UI-0")),
    "UNRESOLVED_CATEGORY": lambda: mut(lambda r: r["unresolved_material_impacts"][0].update(category="OTHER")),
    "UNRESOLVED_STATEMENT": lambda: mut(lambda r: r["unresolved_material_impacts"][0].update(statement="corto")),
    "UNRESOLVED_GAP_REF_NOT_IN_INPUT": lambda: mut(lambda r: r["unresolved_material_impacts"][0].update(gap_ref="INVENTED_GAP")),
    "CATEGORY_NOT_COVERED": lambda: mut(lambda r: r["unresolved_material_impacts"][3].update(category="DIRECT")),
    "GAP_COVERAGE_TOO_NARROW": lambda: mut(lambda r: [u.update(gap_ref=GAPS[0]) for u in r["unresolved_material_impacts"]]),
    "IMPACT_STATEMENT_MISSING": lambda: mut(lambda r: r.update(impact_statement="corto")),
    "SOLUTION_INFERRED": lambda: mut(lambda r: r.update(impact_statement="Habría que crear una tabla en Postgres y exponer un endpoint para medirlo todo.")),
}


def test_raw_negatives():
    for code, build in NEG.items():
        verdict, rec = run(build())
        assert rec is None and verdict == "BLOCK:" + code.strip(), (code, verdict)


def test_packet_and_binding_negatives():
    bad = copy.deepcopy(PACKET)
    bad["input"]["input_literal"] += " "
    assert run(good_raw(), packet=bad)[0] == "BLOCK:PACKET_TAMPERED"
    assert run(good_raw(), packet={})[0] == "BLOCK:PACKET_SCHEMA_INVALID"
    assert run(good_raw(), chat_ref="")[0] == "BLOCK:CHAT_TRANSCRIPT_REF_MISSING"
    assert run(good_raw(), chat_sha="zz")[0] == "BLOCK:CHAT_TRANSCRIPT_DIGEST_FORMAT"
    assert run(good_raw(), approval="short")[0] == "BLOCK:OWNER_APPROVAL_DIGEST_FORMAT"


def main():
    for name, fn in sorted(globals().items()):
        if name.startswith("test_"):
            fn()
    print("PASS_A4Q_C2_GPT_NATIVE_PACKET positives=1 raw_negatives=%d packet_binding_negatives=5 "
          "packet_sha256=%s api_calls=0 fixture_raw_is_not_evidence=true" % (len(NEG), PACKET["packet_sha256"][:16]))


if __name__ == "__main__":
    main()

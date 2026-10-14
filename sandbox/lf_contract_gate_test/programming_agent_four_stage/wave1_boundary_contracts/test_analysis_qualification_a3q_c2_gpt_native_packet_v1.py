#!/usr/bin/env python3
"""Tests for the A3Q_C2 GPT Native packet. RAW below is a MECHANICS FIXTURE, never evidence."""
from __future__ import annotations

import copy
import hashlib
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import analysis_qualification_a3q_c2_gpt_native_packet_v1 as pk  # noqa: E402
import analysis_qualification_gpt_native_equivalent_v1 as eq  # noqa: E402

H = lambda c: c * 64  # noqa: E731
PACKET = pk.build_packet()
CTX = json.loads(PACKET["input"]["input_literal"])
TG = CTX["a2_stage_output"]["classification"]["target_granularity"]


def good_raw() -> dict:
    items = [{"source_ref": s, "read_status": "READ", "observed_fields": dict(pk.EXPECTED[s]),
              "currentness_basis": "READ_IN_THIS_RUN"} for s in pk.SUPPLIED]
    return {"schema_version": pk.OUT_SCHEMA, "request_ref": pk.REQUEST_REF, "evidence_items": items,
            "source_refs": list(pk.SUPPLIED), "currentness_refs": list(pk.SUPPLIED), "target_granularity": TG,
            "authority_state": "UNKNOWN", "implementation_state": "UNKNOWN",
            "target_resolution": {"authority_state": "UNKNOWN", "implementation_state": "UNKNOWN", "resolved": False,
                                  "reason": "Las fuentes leídas describen el pipeline, no el objetivo de la solicitud."},
            "authority_binding_refs": [],
            "as_is_baseline_or_new_implementation_evidence": {"kind": "NONE_SUPPLIED", "refs": []},
            "unresolved_material_gaps": [{"gap_code": "TARGET_SOURCE_MISSING",
                                          "statement": "No se suministró ninguna fuente que describa el objetivo."}],
            "sufficiency_verdict": "NEED_MORE_EVIDENCE",
            "stop_reason": "Se leyeron solo las fuentes suministradas; falta evidencia material del objetivo."}


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
    assert PACKET["limits"]["provider_attested"] is False and PACKET["subject_ref"].endswith("A3Q/A3Q_C2")


def test_expected_values_not_in_prompt():
    for vals in pk.EXPECTED.values():
        for v in vals.values():
            assert v not in PACKET["prompt_for_gpt"], v


def test_positive():
    verdict, rec = run(good_raw())
    assert verdict == eq.PASS_C2 and rec["runtime_provider_attested"] is False


def test_positive_blocked_verdict_variant():
    assert run(mut(lambda r: r.update(sufficiency_verdict="BLOCKED")))[0] == eq.PASS_C2


def set_field(src, key, val):
    def f(r):
        for x in r["evidence_items"]:
            if x["source_ref"] == src:
                x["observed_fields"][key] = val
    return mut(f)


NEG = {
    "RAW_NOT_JSON": lambda: b"no es json",
    "RAW_NOT_OBJECT": lambda: b"[1]",
    "KEYS_OR_SCHEMA": lambda: mut(lambda r: r.update(extra=1)),
    "REQUEST_REF_MISMATCH": lambda: mut(lambda r: r.update(request_ref="REQ-X")),
    "DUPLICATE_READ": lambda: mut(lambda r: r["evidence_items"].append(copy.deepcopy(r["evidence_items"][0]))),
    "OVER_SEARCH_UNSUPPLIED_SOURCE": lambda: mut(lambda r: r["evidence_items"].append(
        {"source_ref": "supabase://public.lf_eventos/1", "read_status": "READ", "observed_fields": {}, "currentness_basis": "READ_IN_THIS_RUN"})),
    "SUPPLIED_SOURCE_NOT_COVERED": lambda: mut(lambda r: r["evidence_items"].pop()),
    "EVIDENCE_ITEM_KEYS": lambda: mut(lambda r: r["evidence_items"][0].update(extra=1)),
    "EVIDENCE_ITEM_ENUM": lambda: mut(lambda r: r["evidence_items"][0].update(read_status="MAYBE")),
    "SOURCE_NOT_READ": lambda: mut(lambda r: r["evidence_items"][0].update(read_status="NOT_READ", observed_fields={})),
    "OBSERVED_FIELDS_SET": lambda: mut(lambda r: r["evidence_items"][0]["observed_fields"].pop("request_sha256")),
    "READ_VALUE_MISMATCH": lambda: set_field(pk.S1, "packet_sha256", H("0")),
    "READ_VALUE_MISMATCH ": lambda: set_field(pk.S2, "created_by_execution_id", "OTHER|A1Q_C2"),
    "CURRENTNESS_NOT_ESTABLISHED": lambda: mut(lambda r: r["evidence_items"][1].update(currentness_basis="UNVERIFIED")),
    "SOURCE_REFS_INCONSISTENT": lambda: mut(lambda r: r.update(source_refs=[pk.S1])),
    "CURRENTNESS_REFS_INCONSISTENT": lambda: mut(lambda r: r.update(currentness_refs=[])),
    "TARGET_GRANULARITY_NOT_FROM_A2": lambda: mut(lambda r: r.update(target_granularity="otro")),
    "STATE_ASSERTED_WITHOUT_EVIDENCE": lambda: mut(lambda r: r.update(authority_state="EXISTING")),
    "TARGET_RESOLUTION_SHAPE": lambda: mut(lambda r: r["target_resolution"].pop("reason")),
    "TARGET_RESOLVED_WITHOUT_EVIDENCE": lambda: mut(lambda r: r["target_resolution"].update(resolved=True)),
    "TARGET_RESOLUTION_REASON_MISSING": lambda: mut(lambda r: r["target_resolution"].update(reason=" ")),
    "AUTHORITY_BINDING_WITHOUT_EVIDENCE": lambda: mut(lambda r: r.update(authority_binding_refs=["adr://x"])),
    "AS_IS_INVENTED": lambda: mut(lambda r: r.update(as_is_baseline_or_new_implementation_evidence={"kind": "AS_IS_BASELINE", "refs": ["x"]})),
    "MATERIAL_GAPS_MISSING": lambda: mut(lambda r: r.update(unresolved_material_gaps=[])),
    "VERDICT_INVALID": lambda: mut(lambda r: r.update(sufficiency_verdict="DONE")),
    "SUFFICIENT_WITH_MATERIAL_GAPS": lambda: mut(lambda r: r.update(sufficiency_verdict="SUFFICIENT")),
    "STOP_REASON_MISSING": lambda: mut(lambda r: r.update(stop_reason="corto")),
    "SOLUTION_INFERRED": lambda: mut(lambda r: r.update(stop_reason="Falta evidencia; habría que crear una tabla en Postgres para guardarlo.")),
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
    print("PASS_A3Q_C2_GPT_NATIVE_PACKET positives=2 raw_negatives=%d packet_binding_negatives=5 "
          "packet_sha256=%s api_calls=0 fixture_raw_is_not_evidence=true" % (len(NEG), PACKET["packet_sha256"][:16]))


if __name__ == "__main__":
    main()

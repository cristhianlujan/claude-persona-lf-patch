#!/usr/bin/env python3
"""Tests for the A2Q_C2 GPT Native packet. RAW below is a MECHANICS FIXTURE, never evidence."""
from __future__ import annotations

import copy
import hashlib
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import analysis_qualification_a2q_c2_gpt_native_packet_v1 as pk  # noqa: E402
import analysis_qualification_gpt_native_equivalent_v1 as eq  # noqa: E402

H = lambda c: c * 64  # noqa: E731
PACKET = pk.build_packet()
CTX = json.loads(PACKET["input"]["input_literal"])
SRC = CTX["source_refs"][0]
AMB = "ambiguity:SAVINGS_MEANING_AND_BASIS"


def good_raw() -> dict:
    src = {"materiality_level": AMB, "scope_bounded": "ambiguity:CLIENT_CHANNEL_AND_SCOPE",
           "authority_state": pk.NO_SOURCE, "reversibility_state": pk.NO_SOURCE,
           "currentness_decision": pk.NO_SOURCE, "material_contradiction": SRC, "known_cross_scope_impact": pk.NO_SOURCE,
           "unresolved_material_signal_count": AMB, "required_specialist_count": pk.NO_SOURCE}
    return {"schema_version": pk.OUT_SCHEMA, "request_ref": pk.REQUEST_REF,
            "classification": {"target_granularity": "FLUJO de negociación de deuda", "change_type": "mejora de comprensión",
                               "depth": "L2", "authority_state": "UNKNOWN", "implementation_state": "UNKNOWN"},
            "signals": {"materiality_level": "MEDIUM", "scope_bounded": "FALSE", "authority_state": "UNKNOWN",
                        "reversibility_state": "UNKNOWN", "currentness_decision": "UNRESOLVED",
                        "material_contradiction": False, "known_cross_scope_impact": "UNKNOWN",
                        "unresolved_material_signal_count": 5, "required_specialist_count": 0},
            "signal_sources": [{"signal": k, "source_ref": v} for k, v in src.items()],
            "depth_reason": "Hay ambigüedades materiales abiertas y autoridad desconocida; no puede ser L1.",
            "evidence_refs": [SRC, AMB]}


def run(raw, packet=PACKET, chat_ref="chat://fixture", chat_sha=H("b"), approval=H("a")):
    data = raw if isinstance(raw, bytes) else json.dumps(raw, ensure_ascii=False).encode("utf-8")
    return pk.intake(packet, data, chat_ref, chat_sha, approval)


def mut(fn):
    r = good_raw()
    fn(r)
    return r


def set_sig(**kw):
    return mut(lambda r: r["signals"].update(kw))


def set_src(sig, ref):
    def f(r):
        for x in r["signal_sources"]:
            if x["signal"] == sig:
                x["source_ref"] = ref
    return mut(f)


def test_packet_deterministic_and_bound():
    again = pk.build_packet()
    assert again == PACKET
    assert hashlib.sha256(PACKET["input"]["input_literal"].encode()).hexdigest() == PACKET["input"]["input_sha256"] == pk.INPUT_SHA256
    assert PACKET["limits"]["provider_attested"] is False and PACKET["subject_ref"].endswith("A2Q/A2Q_C2")


def test_derive_depth_table():
    base = dict(materiality_level="LOW", scope_bounded="TRUE", authority_state="SUFFICIENT", reversibility_state="DEMONSTRATED",
                currentness_decision="CURRENT", material_contradiction=False, known_cross_scope_impact=False,
                unresolved_material_signal_count=0, required_specialist_count=0)
    assert pk.derive_depth(base) == "L1"
    for k, v, d in (("materiality_level", "HIGH", "L3"), ("material_contradiction", True, "L3"),
                    ("known_cross_scope_impact", True, "L3"), ("materiality_level", "UNKNOWN", "L2"),
                    ("scope_bounded", "UNKNOWN", "L2"), ("authority_state", "UNKNOWN", "L2"),
                    ("reversibility_state", "NOT_DEMONSTRATED", "L2"), ("currentness_decision", "UNRESOLVED", "L2"),
                    ("known_cross_scope_impact", "UNKNOWN", "L2"), ("unresolved_material_signal_count", 1, "L2")):
        assert pk.derive_depth({**base, k: v}) == d, (k, v)


def test_positive():
    verdict, rec = run(good_raw())
    assert verdict == eq.PASS_C2 and rec["runtime_provider_attested"] is False


def test_positive_l3_variant():
    raw = good_raw()
    raw["signals"]["materiality_level"] = "HIGH"
    raw["classification"]["depth"] = "L3"
    assert run(raw)[0] == eq.PASS_C2


NEG = {
    "RAW_NOT_JSON": lambda: b"no es json",
    "RAW_NOT_OBJECT": lambda: b"[1]",
    "KEYS_OR_SCHEMA": lambda: mut(lambda r: r.update(extra=1)),
    "KEYS_OR_SCHEMA ": lambda: mut(lambda r: r.update(schema_version="X")),
    "REQUEST_REF_MISMATCH": lambda: mut(lambda r: r.update(request_ref="REQ-OTHER")),
    "CLASSIFICATION_KEYS": lambda: mut(lambda r: r["classification"].pop("change_type")),
    "CLASSIFICATION_EMPTY_target_granularity": lambda: mut(lambda r: r["classification"].update(target_granularity=" ")),
    "DEPTH_INVALID": lambda: mut(lambda r: r["classification"].update(depth="L9")),
    "STATE_INVALID": lambda: mut(lambda r: r["classification"].update(authority_state="MAYBE")),
    "STATE_ASSERTED_WITHOUT_EVIDENCE": lambda: mut(lambda r: r["classification"].update(implementation_state="EXISTING")),
    "STATE_ASSERTED_WITHOUT_EVIDENCE ": lambda: mut(lambda r: r["classification"].update(authority_state="NEW")),
    "SIGNAL_KEYS": lambda: mut(lambda r: r["signals"].pop("required_specialist_count")),
    "SIGNAL_ENUM_materiality_level": lambda: set_sig(materiality_level="HUGE"),
    "SIGNAL_TYPE_material_contradiction": lambda: set_sig(material_contradiction="no"),
    "SIGNAL_TYPE_known_cross_scope_impact": lambda: set_sig(known_cross_scope_impact="maybe"),
    "SIGNAL_TYPE_unresolved_material_signal_count": lambda: set_sig(unresolved_material_signal_count=-1),
    "AUTHORITY_SIGNAL_WITHOUT_EVIDENCE": lambda: set_sig(authority_state="SUFFICIENT"),
    "UNRESOLVED_COUNT_HIDDEN": lambda: set_sig(unresolved_material_signal_count=0),
    "DEPTH_NOT_DERIVED_FROM_SIGNALS": lambda: mut(lambda r: r["classification"].update(depth="L3")),
    "DEPTH_NOT_DERIVED_FROM_SIGNALS ": lambda: mut(lambda r: r["classification"].update(depth="L1")),
    "SIGNAL_SOURCES_INCOMPLETE": lambda: mut(lambda r: r["signal_sources"].pop()),
    "SIGNAL_SOURCE_NOT_IN_CONTEXT": lambda: set_src("materiality_level", "supabase://invented/ref"),
    "SIGNAL_VALUE_WITHOUT_SOURCE": lambda: set_sig(reversibility_state="DEMONSTRATED"),
    "SIGNAL_VALUE_WITHOUT_SOURCE ": lambda: (lambda r: (r["signals"].update(currentness_decision="CURRENT"), r)[1])(good_raw()),
    "DEPTH_REASON_MISSING": lambda: mut(lambda r: r.update(depth_reason="corto")),
    "EVIDENCE_REFS_INVALID": lambda: mut(lambda r: r.update(evidence_refs=["supabase://invented"])),
    "EVIDENCE_REFS_INVALID ": lambda: mut(lambda r: r.update(evidence_refs=[])),
    "SOLUTION_INFERRED": lambda: mut(lambda r: r.update(depth_reason="Hay que crear una tabla en Postgres para guardarlo todo.")),
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
    print("PASS_A2Q_C2_GPT_NATIVE_PACKET positives=2 raw_negatives=%d packet_binding_negatives=5 "
          "packet_sha256=%s api_calls=0 fixture_raw_is_not_evidence=true" % (len(NEG), PACKET["packet_sha256"][:16]))


if __name__ == "__main__":
    main()

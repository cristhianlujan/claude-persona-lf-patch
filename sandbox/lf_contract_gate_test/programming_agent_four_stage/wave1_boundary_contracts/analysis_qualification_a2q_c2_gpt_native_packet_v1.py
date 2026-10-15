#!/usr/bin/env python3
"""A2Q_C2 frozen GPT Native packet: build, and check what GPT returns. Never calls a model.

Input is the A1 REQUEST_CONTEXT_V1 that GPT produced for A1Q_C2 (frozen file, sha pinned). The A2 output is a
classification with signals, a depth derived by monotonic precedence, and a source for every signal.
Tier: OWNER_APPROVED_GPT_NATIVE_IN_CHAT_EQUIVALENT (not provider-attested).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
sys.path.insert(0, str(HERE))
import analysis_qualification_gpt_native_equivalent_v1 as eq  # noqa: E402
import analysis_qualification_a1q_c2_gpt_native_packet_v1 as a1  # noqa: E402

SCHEMA = "ANALYSIS_GPT_NATIVE_PACKET_V1"
UNIT, CP = "A2", "C2"
OUT_SCHEMA = "A2_CLASSIFICATION_OUTPUT_V1"
INPUT_FILE = HERE / "a2q_c2_input_a1_context_v1.json"
INPUT_SHA256 = "02420a0ebbc3416193b788a95895966837db15cd2d934b7691924ade94303fce"
REQUEST_REF = "REQ-LF-A1Q-C2-PILOT-0001"
SKILL = a1.SKILL
NO_SOURCE = "NO_SOURCE_SUPPLIED"
KEYS = ["schema_version", "request_ref", "classification", "signals", "signal_sources", "depth_reason", "evidence_refs"]
CLS_KEYS = ["target_granularity", "change_type", "depth", "authority_state", "implementation_state"]
SIGNAL_ENUMS = {
    "materiality_level": {"LOW", "MEDIUM", "HIGH", "UNKNOWN"},
    "scope_bounded": {"TRUE", "FALSE", "UNKNOWN"},
    "authority_state": {"SUFFICIENT", "INSUFFICIENT", "UNKNOWN"},
    "reversibility_state": {"DEMONSTRATED", "NOT_DEMONSTRATED", "UNKNOWN"},
    "currentness_decision": {"CURRENT", "CURRENT_REBOUND", "STALE_AFFECTED", "UNKNOWN_FAIL_CLOSED", "UNRESOLVED"},
}
SIGNAL_NAMES = list(SIGNAL_ENUMS) + ["material_contradiction", "known_cross_scope_impact",
                                     "unresolved_material_signal_count", "required_specialist_count"]
UNSTATED = {"UNKNOWN", "UNRESOLVED", "UNKNOWN_FAIL_CLOSED"}


def jsha(value) -> str:
    return a1.jsha(value)


def input_literal() -> str:
    data = INPUT_FILE.read_bytes()
    if hashlib.sha256(data).hexdigest() != INPUT_SHA256:
        raise SystemExit("A2_INPUT_FILE_DRIFT")
    return data.decode("utf-8")


def allowed_refs(ctx: dict) -> set:
    refs = set(ctx["source_refs"])
    refs.update("ambiguity:" + a["code"] for a in ctx["ambiguities"])
    refs.update("fact:" + f["fact_code"] for f in ctx["provided_facts"])
    return refs


def derive_depth(s: dict) -> str:
    """Monotonic precedence, no weights: L3 explicit high risk > L2 medium or unproven > L1 fully bounded low risk."""
    if s["materiality_level"] == "HIGH" or s["material_contradiction"] is True or s["known_cross_scope_impact"] is True:
        return "L3"
    if (s["materiality_level"] == "LOW" and s["scope_bounded"] == "TRUE" and s["authority_state"] == "SUFFICIENT"
            and s["reversibility_state"] == "DEMONSTRATED" and s["currentness_decision"] in ("CURRENT", "CURRENT_REBOUND")
            and s["known_cross_scope_impact"] is False and s["unresolved_material_signal_count"] == 0):
        return "L1"
    return "L2"


def prompt_text(ctx_text: str) -> str:
    return (
        "Este mensaje es independiente: ignora cualquier otro paquete o salida anterior de este chat. "
        "Eres el productor de la etapa A2 (clasificación) del perfil de análisis. Recibes el contexto normalizado de la "
        "etapa A1 (abajo). Clasifica el cambio. No infieras solución técnica. No inventes fuentes: las únicas fuentes "
        "válidas son las del contexto (sus source_refs, 'ambiguity:<code>' y 'fact:<fact_code>'); si una señal no tiene "
        "fuente en el contexto, su fuente es '" + NO_SOURCE + "' y su valor debe ser UNKNOWN/UNRESOLVED. El estado de "
        "autoridad y de implementación no se pueden afirmar sin evidencia: usa UNKNOWN. Lo desconocido material nunca "
        "puede ser L1. Devuelve SOLO un objeto JSON, sin texto adicional, con exactamente estas claves: "
        + ", ".join(KEYS) + ". schema_version='" + OUT_SCHEMA + "'. request_ref='" + REQUEST_REF + "'. "
        "classification={target_granularity (texto), change_type (texto), depth (L1|L2|L3), authority_state "
        "(EXISTING|NEW|UNKNOWN), implementation_state (EXISTING|NEW|UNKNOWN)}. "
        "signals={materiality_level (LOW|MEDIUM|HIGH|UNKNOWN), scope_bounded (TRUE|FALSE|UNKNOWN), authority_state "
        "(SUFFICIENT|INSUFFICIENT|UNKNOWN), reversibility_state (DEMONSTRATED|NOT_DEMONSTRATED|UNKNOWN), "
        "currentness_decision (CURRENT|CURRENT_REBOUND|STALE_AFFECTED|UNKNOWN_FAIL_CLOSED|UNRESOLVED), "
        "material_contradiction (true|false), known_cross_scope_impact (true|false|\"UNKNOWN\"), "
        "unresolved_material_signal_count (entero >=0), required_specialist_count (entero >=0)}. "
        "signal_sources=lista con UN elemento por cada una de las 9 señales: {signal, source_ref}. "
        "Regla de profundidad (precedencia monótona): L3 si materiality_level=HIGH o material_contradiction=true o "
        "known_cross_scope_impact=true; L1 solo si materiality LOW, scope_bounded TRUE, authority_state SUFFICIENT, "
        "reversibility DEMONSTRATED, currentness CURRENT o CURRENT_REBOUND, known_cross_scope_impact=false y "
        "unresolved_material_signal_count=0; en otro caso L2. depth_reason: texto no vacío que justifica la "
        "profundidad. evidence_refs: lista no vacía de fuentes válidas del contexto.\n\nCONTEXTO A1 (JSON):\n" + ctx_text)


def build_packet(root: Path = REPO) -> dict:
    ctx_text = input_literal()
    skill_bytes = (root / SKILL).read_bytes()
    packet = {
        "schema": SCHEMA, "subject_ref": eq.subject(UNIT, CP), "unit": UNIT, "checkpoint": CP,
        "stage_output_selector": UNIT, "producer_mode": "GPT_NATIVE", "evidence_tier": eq.TIER,
        "run_id": "A2Q_C2-GPTN-PILOT-0001",
        "input": {"request_ref": REQUEST_REF, "input_literal": ctx_text,
                  "input_sha256": hashlib.sha256(ctx_text.encode("utf-8")).hexdigest(),
                  "input_origin": "A1Q_C2 GPT Native RAW (raw_output_sha256 " + INPUT_SHA256 + ")"},
        "profile_source": {"ref": SKILL, "sha256": hashlib.sha256(skill_bytes).hexdigest()},
        "output_contract": {"schema": OUT_SCHEMA, "required_keys": KEYS,
                            "validator": "analysis_qualification_a2q_c2_gpt_native_packet_v1.py::semantic_checks"},
        "deterministic_checks": {"request_ref_equals": REQUEST_REF, "classification_keys": CLS_KEYS,
                                 "signal_names": SIGNAL_NAMES, "no_source_marker": NO_SOURCE,
                                 "depth_rule": "derive_depth monotonic precedence",
                                 "authority_and_implementation_state_must_be": "UNKNOWN",
                                 "forbidden_solution_patterns": a1.FORBIDDEN_SOLUTION},
        "prompt_for_gpt": prompt_text(ctx_text),
        "owner_approval_doc": eq.APPROVAL_DOC, "limits": eq.limits(),
    }
    packet["request_sha256"] = jsha({k: packet[k] for k in ("subject_ref", "input", "profile_source",
                                                           "output_contract", "prompt_for_gpt")})
    packet["packet_sha256"] = jsha({k: v for k, v in packet.items() if k != "packet_sha256"})
    return packet


def _check_packet(packet) -> str | None:
    if not isinstance(packet, dict) or packet.get("schema") != SCHEMA:
        return "PACKET_SCHEMA_INVALID"
    if jsha({k: v for k, v in packet.items() if k != "packet_sha256"}) != packet.get("packet_sha256"):
        return "PACKET_TAMPERED"
    return None


def semantic_checks(packet: dict, out: dict) -> str | None:
    ctx = json.loads(packet["input"]["input_literal"])
    if set(out) != set(KEYS) or out.get("schema_version") != OUT_SCHEMA:
        return "KEYS_OR_SCHEMA"
    if out["request_ref"] != packet["deterministic_checks"]["request_ref_equals"]:
        return "REQUEST_REF_MISMATCH"
    c, s = out["classification"], out["signals"]
    if not isinstance(c, dict) or set(c) != set(CLS_KEYS):
        return "CLASSIFICATION_KEYS"
    for k in ("target_granularity", "change_type"):
        if not isinstance(c[k], str) or not c[k].strip():
            return "CLASSIFICATION_EMPTY_" + k
    if c["depth"] not in ("L1", "L2", "L3"):
        return "DEPTH_INVALID"
    if c["authority_state"] not in ("EXISTING", "NEW", "UNKNOWN") or c["implementation_state"] not in ("EXISTING", "NEW", "UNKNOWN"):
        return "STATE_INVALID"
    if c["authority_state"] != "UNKNOWN" or c["implementation_state"] != "UNKNOWN":
        return "STATE_ASSERTED_WITHOUT_EVIDENCE"
    if not isinstance(s, dict) or set(s) != set(SIGNAL_NAMES):
        return "SIGNAL_KEYS"
    for k, vals in SIGNAL_ENUMS.items():
        if s[k] not in vals:
            return "SIGNAL_ENUM_" + k
    if not isinstance(s["material_contradiction"], bool):
        return "SIGNAL_TYPE_material_contradiction"
    if s["known_cross_scope_impact"] not in (True, False, "UNKNOWN"):
        return "SIGNAL_TYPE_known_cross_scope_impact"
    for k in ("unresolved_material_signal_count", "required_specialist_count"):
        if type(s[k]) is not int or s[k] < 0:
            return "SIGNAL_TYPE_" + k
    if s["authority_state"] != "UNKNOWN":
        return "AUTHORITY_SIGNAL_WITHOUT_EVIDENCE"
    open_material = sum(1 for a in ctx["ambiguities"] if a["resolution_state"] == "OPEN" and a["materiality"] == "MATERIAL")
    if open_material and s["unresolved_material_signal_count"] < 1:
        return "UNRESOLVED_COUNT_HIDDEN"
    if c["depth"] != derive_depth(s):
        return "DEPTH_NOT_DERIVED_FROM_SIGNALS"
    if c["depth"] == "L1":
        return "UNKNOWN_BECAME_L1"
    ok = allowed_refs(ctx) | {NO_SOURCE}
    srcs = out["signal_sources"]
    if not isinstance(srcs, list) or sorted(x.get("signal") if isinstance(x, dict) else None for x in srcs) != sorted(SIGNAL_NAMES):
        return "SIGNAL_SOURCES_INCOMPLETE"
    for x in srcs:
        if set(x) != {"signal", "source_ref"} or x["source_ref"] not in ok:
            return "SIGNAL_SOURCE_NOT_IN_CONTEXT"
        v = s[x["signal"]]
        # An enum signal with no supplied source cannot carry a stated value; authority and currentness
        # need evidence this pilot input does not contain, so a source cannot make them known either.
        if x["signal"] in SIGNAL_ENUMS and v not in UNSTATED and (
                x["source_ref"] == NO_SOURCE or x["signal"] in ("authority_state", "currentness_decision")):
            return "SIGNAL_VALUE_WITHOUT_SOURCE"
    if not isinstance(out["depth_reason"], str) or len(out["depth_reason"].strip()) < 20:
        return "DEPTH_REASON_MISSING"
    ev = out["evidence_refs"]
    if not (isinstance(ev, list) and ev and all(isinstance(r, str) and r in ok - {NO_SOURCE} for r in ev)):
        return "EVIDENCE_REFS_INVALID"
    text = json.dumps(out, ensure_ascii=False).lower()
    ctx_text = packet["input"]["input_literal"].lower()
    for pat in packet["deterministic_checks"]["forbidden_solution_patterns"]:
        if re.search(pat, text) and not re.search(pat, ctx_text):
            return "SOLUTION_INFERRED"
    return None


def intake(packet: dict, raw_bytes: bytes, chat_ref: str, chat_sha256: str, approval_doc_sha256: str):
    bad = _check_packet(packet)
    if bad:
        return "BLOCK:" + bad, None
    try:
        out = json.loads(raw_bytes.decode("utf-8"))
    except (ValueError, UnicodeDecodeError):
        return "BLOCK:RAW_NOT_JSON", None
    if not isinstance(out, dict):
        return "BLOCK:RAW_NOT_OBJECT", None
    try:
        err = semantic_checks(packet, out)
    except (KeyError, TypeError, AttributeError):
        err = "SHAPE_INVALID"
    if err:
        return "BLOCK:" + err, None
    record = {
        "schema": eq.CAPTURE_SCHEMA, "subject_ref": packet["subject_ref"], "stage_output_selector": UNIT,
        "evidence_tier": eq.TIER, "producer_mode": "GPT_NATIVE", "runtime_provider_attested": False,
        "transcript_is_provider_evidence": False, "run_id": packet["run_id"],
        "owner_approval_ref": eq.APPROVAL_DOC + "@" + approval_doc_sha256,
        "owner_approval_doc_sha256": approval_doc_sha256,
        "chat_transcript_ref": chat_ref, "chat_transcript_sha256": chat_sha256,
        "input_sha256": packet["input"]["input_sha256"], "request_sha256": packet["request_sha256"],
        "raw_output_sha256": hashlib.sha256(raw_bytes).hexdigest(),
    }
    verdict = eq.attest_c2(record, UNIT, packet["input"]["input_literal"].encode("utf-8"), raw_bytes)
    return verdict, (record if verdict == eq.PASS_C2 else None)


def main() -> None:
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="mode", required=True)
    b = sub.add_parser("build")
    b.add_argument("--output", type=Path, required=True)
    i = sub.add_parser("intake")
    i.add_argument("--packet", type=Path, required=True)
    i.add_argument("--raw", type=Path, required=True)
    i.add_argument("--chat-ref", required=True)
    i.add_argument("--chat-sha256", required=True)
    i.add_argument("--output", type=Path, required=True)
    a = ap.parse_args()
    if a.mode == "build":
        p = build_packet()
        a.output.write_text(json.dumps(p, ensure_ascii=False, sort_keys=True, indent=2) + "\n", encoding="utf-8")
        print(json.dumps({"packet_sha256": p["packet_sha256"], "request_sha256": p["request_sha256"]}))
        return
    approval = hashlib.sha256((REPO / eq.APPROVAL_DOC).read_bytes()).hexdigest()
    verdict, rec = intake(json.loads(a.packet.read_text(encoding="utf-8")), a.raw.read_bytes(), a.chat_ref, a.chat_sha256, approval)
    if rec:
        a.output.write_text(json.dumps(rec, ensure_ascii=False, sort_keys=True, indent=2) + "\n", encoding="utf-8")
    print(verdict)
    sys.exit(0 if rec else 1)


if __name__ == "__main__":
    main()

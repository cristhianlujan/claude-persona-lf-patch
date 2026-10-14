#!/usr/bin/env python3
"""A3Q_C2 frozen GPT Native packet: build, and check what GPT returns. Never calls a model.

Input: the A2 classification GPT produced (frozen file, sha pinned) plus two EXACT supplied sources. GPT must read
them with its own read-only Supabase connector and report exact field values. The verifier knows the true values
(they are not in the prompt), so a guessed or invented read fails. Targeted research only: reading anything beyond
the supplied sources is rejected. The supplied sources do not describe the request target, so authority and
implementation state must stay UNKNOWN, no AS-IS baseline may be invented, and the verdict cannot be SUFFICIENT.
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
UNIT, CP = "A3", "C2"
OUT_SCHEMA = "A3_TARGETED_EVIDENCE_OUTPUT_V1"
INPUT_FILE = HERE / "a3q_c2_input_a2_output_v1.json"
INPUT_FILE_SHA256 = "381a76bccf5e26696460897a68a87b1960ad6882c065b0c171953334d54ebcde"
REQUEST_REF = "REQ-LF-A1Q-C2-PILOT-0001"
SKILL = a1.SKILL
S1 = "supabase://programacion.engineering_plan_units/A1Q#unit_metadata.gpt_native_packets_v1.A1Q_C2"
S2 = "supabase://public.lf_eventos/20843"
SUPPLIED = [S1, S2]
FIELDS = {S1: ["packet_sha256", "request_sha256", "input_sha256"],
          S2: ["evento_tipo", "created_by_execution_id", "payload_packet_sha256"]}
# Known true values. They live in deterministic_checks (verifier side), never in the prompt.
EXPECTED = {
    S1: {"packet_sha256": "1cbe8daa96f35a3a37b194659c690fcbd9437407c465d32987c956a5eef10b4a",
         "request_sha256": "a136daa7486437dc62b8757993b5213b3b6b2575bb32cb08e2a5217c84df3071",
         "input_sha256": "a1974eae630ef1eea450e6bd95248a73da785257de73b06e13fb727190e76987"},
    S2: {"evento_tipo": "HANDOFF_DEEP_CONTEXT", "created_by_execution_id": "ANALYSIS_QUAL_C2_GPT_HANDOFF_V1|A1Q_C2",
         "payload_packet_sha256": "1cbe8daa96f35a3a37b194659c690fcbd9437407c465d32987c956a5eef10b4a"},
}
KEYS = ["schema_version", "request_ref", "evidence_items", "source_refs", "currentness_refs", "target_granularity",
        "authority_state", "implementation_state", "target_resolution", "authority_binding_refs",
        "as_is_baseline_or_new_implementation_evidence", "unresolved_material_gaps", "sufficiency_verdict", "stop_reason"]
VERDICTS = {"SUFFICIENT", "NEED_MORE_EVIDENCE", "REQUIRES_DECISION", "BLOCKED"}


def jsha(value) -> str:
    return a1.jsha(value)


def input_literal() -> str:
    data = INPUT_FILE.read_bytes()
    if hashlib.sha256(data.rstrip(b"\n")).hexdigest() != INPUT_FILE_SHA256:
        raise SystemExit("A3_INPUT_FILE_DRIFT")
    obj = {"a2_stage_output": json.loads(data.decode("utf-8")), "supplied_sources": [
        {"source_ref": s, "fields_to_report": FIELDS[s]} for s in SUPPLIED]}
    return json.dumps(obj, ensure_ascii=False, sort_keys=True, indent=2)


def prompt_text(ctx_text: str) -> str:
    return (
        "Este mensaje es independiente: ignora cualquier otro paquete o salida anterior de este chat. "
        "Eres el productor de la etapa A3 (evidencia dirigida) del perfil de análisis. Recibes la salida de la etapa A2 y "
        "DOS fuentes exactas (abajo). Debes LEER cada fuente con tu conector de Supabase de solo lectura y reportar el valor "
        "EXACTO de cada campo pedido. Regla de investigación mínima: no leas nada más que esas dos fuentes. Si no puedes "
        "leer una fuente, marca read_status='NOT_READ', deja observed_fields vacío y NO inventes valores. Estas fuentes "
        "describen el pipeline de análisis, no el objetivo de la solicitud: no declares estado de autoridad o de "
        "implementación del objetivo sin evidencia (usa UNKNOWN), no inventes línea base AS-IS ni delta, y el veredicto no "
        "puede ser SUFFICIENT mientras falte evidencia material del objetivo. No infieras solución técnica. Devuelve SOLO un "
        "objeto JSON, sin texto adicional, con exactamente estas claves: " + ", ".join(KEYS) + ". "
        "schema_version='" + OUT_SCHEMA + "'. request_ref='" + REQUEST_REF + "'. "
        "evidence_items=lista con UN elemento por fuente suministrada: {source_ref, read_status (READ|NOT_READ), "
        "observed_fields (objeto con exactamente los campos pedidos para esa fuente), currentness_basis "
        "(READ_IN_THIS_RUN|UNVERIFIED)}. source_refs=lista de las fuentes leídas. currentness_refs=lista de fuentes con "
        "currentness_basis=READ_IN_THIS_RUN. target_granularity=el target_granularity de la clasificación A2 (texto). "
        "authority_state e implementation_state (EXISTING|NEW|UNKNOWN). "
        "target_resolution={authority_state, implementation_state, resolved (booleano), reason (texto)}. "
        "authority_binding_refs=lista de referencias de autoridad del objetivo (vacía si no hay). "
        "as_is_baseline_or_new_implementation_evidence={kind (NONE_SUPPLIED|AS_IS_BASELINE|NEW_IMPLEMENTATION_EVIDENCE), refs (lista)}. "
        "unresolved_material_gaps=lista de {gap_code, statement} (al menos una si falta evidencia del objetivo). "
        "sufficiency_verdict (SUFFICIENT|NEED_MORE_EVIDENCE|REQUIRES_DECISION|BLOCKED). stop_reason=texto no vacío.\n\n"
        "ENTRADA (JSON):\n" + ctx_text)


def build_packet(root: Path = REPO) -> dict:
    ctx_text = input_literal()
    skill_bytes = (root / SKILL).read_bytes()
    packet = {
        "schema": SCHEMA, "subject_ref": eq.subject(UNIT, CP), "unit": UNIT, "checkpoint": CP,
        "stage_output_selector": UNIT, "producer_mode": "GPT_NATIVE", "evidence_tier": eq.TIER,
        "run_id": "A3Q_C2-GPTN-PILOT-0001",
        "input": {"request_ref": REQUEST_REF, "input_literal": ctx_text,
                  "input_sha256": hashlib.sha256(ctx_text.encode("utf-8")).hexdigest(),
                  "input_origin": "A2Q_C2 GPT Native RAW (raw_output_sha256 " + INPUT_FILE_SHA256 + ") + two supplied sources"},
        "profile_source": {"ref": SKILL, "sha256": hashlib.sha256(skill_bytes).hexdigest()},
        "output_contract": {"schema": OUT_SCHEMA, "required_keys": KEYS,
                            "validator": "analysis_qualification_a3q_c2_gpt_native_packet_v1.py::semantic_checks"},
        "deterministic_checks": {"request_ref_equals": REQUEST_REF, "supplied_sources": SUPPLIED, "fields": FIELDS,
                                 "expected_values": EXPECTED, "verdicts": sorted(VERDICTS),
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
    chk = packet["deterministic_checks"]
    ctx = json.loads(packet["input"]["input_literal"])
    a2 = ctx["a2_stage_output"]
    if set(out) != set(KEYS) or out.get("schema_version") != OUT_SCHEMA:
        return "KEYS_OR_SCHEMA"
    if out["request_ref"] != chk["request_ref_equals"]:
        return "REQUEST_REF_MISMATCH"
    items = out["evidence_items"]
    if not isinstance(items, list) or not all(isinstance(x, dict) for x in items):
        return "EVIDENCE_ITEMS_SHAPE"
    refs = [x.get("source_ref") for x in items]
    if len(refs) != len(set(refs)):
        return "DUPLICATE_READ"
    if set(refs) - set(chk["supplied_sources"]):
        return "OVER_SEARCH_UNSUPPLIED_SOURCE"
    if set(refs) != set(chk["supplied_sources"]):
        return "SUPPLIED_SOURCE_NOT_COVERED"
    for x in items:
        if set(x) != {"source_ref", "read_status", "observed_fields", "currentness_basis"}:
            return "EVIDENCE_ITEM_KEYS"
        if x["read_status"] not in ("READ", "NOT_READ") or x["currentness_basis"] not in ("READ_IN_THIS_RUN", "UNVERIFIED"):
            return "EVIDENCE_ITEM_ENUM"
        if x["read_status"] == "NOT_READ":
            return "SOURCE_NOT_READ"
        want = chk["expected_values"][x["source_ref"]]
        got = x["observed_fields"]
        if not isinstance(got, dict) or set(got) != set(chk["fields"][x["source_ref"]]):
            return "OBSERVED_FIELDS_SET"
        if any(got[k] != v for k, v in want.items()):
            return "READ_VALUE_MISMATCH"
        if x["currentness_basis"] != "READ_IN_THIS_RUN":
            return "CURRENTNESS_NOT_ESTABLISHED"
    if sorted(out["source_refs"]) != sorted(chk["supplied_sources"]) if isinstance(out["source_refs"], list) else True:
        return "SOURCE_REFS_INCONSISTENT"
    if not isinstance(out["currentness_refs"], list) or sorted(out["currentness_refs"]) != sorted(chk["supplied_sources"]):
        return "CURRENTNESS_REFS_INCONSISTENT"
    if out["target_granularity"] != a2["classification"]["target_granularity"]:
        return "TARGET_GRANULARITY_NOT_FROM_A2"
    if out["authority_state"] != "UNKNOWN" or out["implementation_state"] != "UNKNOWN":
        return "STATE_ASSERTED_WITHOUT_EVIDENCE"
    tr = out["target_resolution"]
    if not isinstance(tr, dict) or set(tr) != {"authority_state", "implementation_state", "resolved", "reason"}:
        return "TARGET_RESOLUTION_SHAPE"
    if tr["authority_state"] != "UNKNOWN" or tr["implementation_state"] != "UNKNOWN" or tr["resolved"] is not False:
        return "TARGET_RESOLVED_WITHOUT_EVIDENCE"
    if not isinstance(tr["reason"], str) or not tr["reason"].strip():
        return "TARGET_RESOLUTION_REASON_MISSING"
    if out["authority_binding_refs"] != []:
        return "AUTHORITY_BINDING_WITHOUT_EVIDENCE"
    asis = out["as_is_baseline_or_new_implementation_evidence"]
    if not isinstance(asis, dict) or set(asis) != {"kind", "refs"} or asis["kind"] != "NONE_SUPPLIED" or asis["refs"] != []:
        return "AS_IS_INVENTED"
    gaps = out["unresolved_material_gaps"]
    if not (isinstance(gaps, list) and gaps and all(isinstance(g, dict) and set(g) == {"gap_code", "statement"}
                                                    and str(g["gap_code"]).strip() and str(g["statement"]).strip() for g in gaps)):
        return "MATERIAL_GAPS_MISSING"
    if out["sufficiency_verdict"] not in VERDICTS:
        return "VERDICT_INVALID"
    if out["sufficiency_verdict"] == "SUFFICIENT":
        return "SUFFICIENT_WITH_MATERIAL_GAPS"
    if not isinstance(out["stop_reason"], str) or len(out["stop_reason"].strip()) < 20:
        return "STOP_REASON_MISSING"
    text = json.dumps(out, ensure_ascii=False).lower()
    ctx_text = packet["input"]["input_literal"].lower()
    for pat in chk["forbidden_solution_patterns"]:
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

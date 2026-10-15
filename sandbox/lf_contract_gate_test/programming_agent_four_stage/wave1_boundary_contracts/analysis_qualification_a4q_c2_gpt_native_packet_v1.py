#!/usr/bin/env python3
"""A4Q_C2 frozen GPT Native packet: build, and check what GPT returns. Never calls a model.

Input: the A3 targeted-evidence output GPT produced (frozen file, sha pinned). A3 left the target unresolved, so no
impact, consumer or dependency is supported by any supplied evidence. The A4 output must therefore enumerate the
uncertainty per category (direct, indirect, consumer, dependency) tied to the A3 gaps, assert no impact it cannot
source, and never claim that impacts are absent. Every ref must resolve inside the input.
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
UNIT, CP = "A4", "C2"
OUT_SCHEMA = "A4_IMPACT_MAP_OUTPUT_V1"
INPUT_FILE = HERE / "a4q_c2_input_a3_output_v1.json"
INPUT_FILE_SHA256 = "30150806da0208b9e9e3caad77878e7faa930fc6b7293ef7ee0e82782ea29e0a"
REQUEST_REF = "REQ-LF-A1Q-C2-PILOT-0001"
SKILL = a1.SKILL
CATEGORIES = ["DIRECT", "INDIRECT", "CONSUMER", "DEPENDENCY"]
LISTS = ["direct_impacts", "indirect_impacts", "consumers", "dependency_paths"]
KEYS = ["schema_version", "request_ref"] + LISTS + ["evidence_refs", "unresolved_material_impacts",
                                                     "impact_statement", "no_absence_claimed"]
MIN_DISTINCT_GAPS = 3
ABSENCE = re.compile(r"\bno (hay|existe|existen|tiene|tendr\w*|produce|afecta)\s+(ning[úu]n[oa]?s?\s+)?(\w+\s+)?(impactos?|consumidor\w*|dependencia\w*)", re.I)


def jsha(value) -> str:
    return a1.jsha(value)


def input_literal() -> str:
    data = INPUT_FILE.read_bytes()
    if hashlib.sha256(data.rstrip(b"\n")).hexdigest() != INPUT_FILE_SHA256:
        raise SystemExit("A4_INPUT_FILE_DRIFT")
    return json.dumps({"a3_stage_output": json.loads(data.decode("utf-8"))}, ensure_ascii=False, sort_keys=True, indent=2)


def allowed_refs(ctx: dict) -> set:
    a3 = ctx["a3_stage_output"]
    refs = set(a3["source_refs"])
    refs.update("gap:" + g["gap_code"] for g in a3["unresolved_material_gaps"])
    return refs


def gap_codes(ctx: dict) -> set:
    return {g["gap_code"] for g in ctx["a3_stage_output"]["unresolved_material_gaps"]}


def prompt_text(ctx_text: str) -> str:
    return (
        "Este mensaje es independiente: ignora cualquier otro paquete o salida anterior de este chat. "
        "Eres el productor de la etapa A4 (mapa de impacto) del perfil de análisis. Recibes la salida de la etapa A3 "
        "(abajo). Enumera los efectos directos e indirectos, consumidores y dependencias del cambio SOLO si la evidencia "
        "suministrada los respalda. Si no se conocen, enumera las incógnitas por categoría; NUNCA afirmes que no hay "
        "impactos, consumidores o dependencias. No inventes consumidores, rutas de dependencia ni fuentes. Las únicas "
        "referencias válidas son las source_refs de la entrada y 'gap:<gap_code>' para cada brecha de la entrada. No "
        "infieras solución técnica. Devuelve SOLO un objeto JSON, sin texto adicional, con exactamente estas claves: "
        + ", ".join(KEYS) + ". schema_version='" + OUT_SCHEMA + "'. request_ref='" + REQUEST_REF + "'. "
        "direct_impacts, indirect_impacts, consumers, dependency_paths: listas (cada elemento, si lo hay, debe ser "
        "{statement, evidence_refs} con referencias válidas; déjalas vacías si ninguna evidencia suministrada respalda "
        "un elemento). evidence_refs: lista no vacía de referencias válidas. unresolved_material_impacts: lista de "
        "{impact_id (único), category (DIRECT|INDIRECT|CONSUMER|DEPENDENCY), statement (texto), gap_ref (un gap_code de la "
        "entrada)}; debe haber al menos una por cada una de las cuatro categorías y deben cubrir al menos "
        + str(MIN_DISTINCT_GAPS) + " brechas distintas. impact_statement: texto que explica qué no se puede afirmar y por "
        "qué. no_absence_claimed=true.\n\nENTRADA (JSON):\n" + ctx_text)


def build_packet(root: Path = REPO) -> dict:
    ctx_text = input_literal()
    skill_bytes = (root / SKILL).read_bytes()
    packet = {
        "schema": SCHEMA, "subject_ref": eq.subject(UNIT, CP), "unit": UNIT, "checkpoint": CP,
        "stage_output_selector": UNIT, "producer_mode": "GPT_NATIVE", "evidence_tier": eq.TIER,
        "run_id": "A4Q_C2-GPTN-PILOT-0001",
        "input": {"request_ref": REQUEST_REF, "input_literal": ctx_text,
                  "input_sha256": hashlib.sha256(ctx_text.encode("utf-8")).hexdigest(),
                  "input_origin": "A3Q_C2 GPT Native RAW (raw_output_sha256 " + INPUT_FILE_SHA256 + ")"},
        "profile_source": {"ref": SKILL, "sha256": hashlib.sha256(skill_bytes).hexdigest()},
        "output_contract": {"schema": OUT_SCHEMA, "required_keys": KEYS,
                            "validator": "analysis_qualification_a4q_c2_gpt_native_packet_v1.py::semantic_checks"},
        "deterministic_checks": {"request_ref_equals": REQUEST_REF, "categories": CATEGORIES, "lists": LISTS,
                                 "min_distinct_gaps": MIN_DISTINCT_GAPS,
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
    ok, gaps = allowed_refs(ctx), gap_codes(ctx)
    if set(out) != set(KEYS) or out.get("schema_version") != OUT_SCHEMA:
        return "KEYS_OR_SCHEMA"
    if out["request_ref"] != chk["request_ref_equals"]:
        return "REQUEST_REF_MISMATCH"
    if out["no_absence_claimed"] is not True:
        return "ABSENCE_CLAIMED"
    for name in chk["lists"]:
        items = out[name]
        if not isinstance(items, list):
            return "LIST_SHAPE_" + name
        if items:
            # The supplied evidence supports no concrete impact, consumer or dependency: any asserted item is invented.
            return "IMPACT_ASSERTED_WITHOUT_EVIDENCE"
    ev = out["evidence_refs"]
    if not (isinstance(ev, list) and ev and all(isinstance(r, str) and r in ok for r in ev)):
        return "EVIDENCE_REFS_INVALID"
    un = out["unresolved_material_impacts"]
    if not (isinstance(un, list) and un and all(isinstance(u, dict) and set(u) == {"impact_id", "category", "statement", "gap_ref"} for u in un)):
        return "UNRESOLVED_SHAPE"
    ids = [u["impact_id"] for u in un]
    if len(ids) != len(set(ids)) or not all(isinstance(i, str) and i.strip() for i in ids):
        return "UNRESOLVED_IDS"
    for u in un:
        if u["category"] not in chk["categories"]:
            return "UNRESOLVED_CATEGORY"
        if not isinstance(u["statement"], str) or len(u["statement"].strip()) < 20:
            return "UNRESOLVED_STATEMENT"
        if u["gap_ref"] not in gaps:
            return "UNRESOLVED_GAP_REF_NOT_IN_INPUT"
    if {u["category"] for u in un} != set(chk["categories"]):
        return "CATEGORY_NOT_COVERED"
    if len({u["gap_ref"] for u in un}) < chk["min_distinct_gaps"]:
        return "GAP_COVERAGE_TOO_NARROW"
    st = out["impact_statement"]
    if not isinstance(st, str) or len(st.strip()) < 40:
        return "IMPACT_STATEMENT_MISSING"
    text = json.dumps(out, ensure_ascii=False)
    if ABSENCE.search(text):
        return "ABSENCE_CLAIMED"
    low, ctx_text = text.lower(), packet["input"]["input_literal"].lower()
    for pat in chk["forbidden_solution_patterns"]:
        if re.search(pat, low) and not re.search(pat, ctx_text):
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

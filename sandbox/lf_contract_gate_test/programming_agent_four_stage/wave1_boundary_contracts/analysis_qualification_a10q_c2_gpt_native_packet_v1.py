#!/usr/bin/env python3
"""A10Q_C2 frozen GPT Native packet (criterion amended: docs/programming-agent/ANALYSIS_C2_CRITERIA_AMENDMENT_A9_A14_V1.md).

Input: 7 historical heterogeneous cases (one per required change family), reduced to case_id, change_family, historical_subject and source_refs.
The expected-signal oracle fields of the case registry are NOT given to GPT. No source content is supplied, so GPT can only produce hypotheses from the
subject name: every verdict must stay non-READY, every impact is tagged as a hypothesis, evidence refs must come from the case's own source_refs, and the
telemetry that GPT cannot measure (handoff parity, scope-front consistency, currentness, latency, tokens, provider) is declared NOT_EVALUATED or omitted.
Tier: OWNER_APPROVED_GPT_NATIVE_IN_CHAT_EQUIVALENT (not provider-attested). No governed execution, no scoring against an oracle.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import analysis_qualification_gpt_native_packet_common_v1 as common  # noqa: E402
import analysis_qualification_a1q_c2_gpt_native_packet_v1 as a1  # noqa: E402

UNIT = "A10"
OUT_SCHEMA = "A10_COHORT_OUTPUT_V1"
INPUT_FILE = HERE / "a10q_c2_input_cohort_v1.json"
INPUT_FILE_SHA256 = "2f61c8a1e4bf2253108230f1d5ab5775f1ad67fbbacb9f2066d6747735360e6a"
REQUEST_REF = "REQ-LF-A1Q-C2-PILOT-0001"
FAMILIES = ["BUG", "CONCURRENCY_IDEMPOTENCY", "FEATURE", "GOVERNANCE", "MIGRATION", "MODEL_OR_INTELLIGENCE", "RUNTIME"]
KEYS = ["schema_version", "request_ref", "cohort", "families_covered", "no_ready_claim", "cohort_statement"]
CASE_KEYS = {"case_id", "change_family", "verdict", "critical_impacts_observed", "material_fronts_observed", "evidence_refs", "false_ready_count",
             "reinterpretation_required", "handoff_parity_verdict", "scope_front_consistency_verdict", "currentness_verdict",
             "source_read_count", "duplicate_read_count", "retry_count", "evidence_note"}
VERDICTS = ["BLOCKED", "REQUIRES_DECISION", "NEED_MORE_EVIDENCE"]
NOT_EVALUATED = "NOT_EVALUATED"
BASIS = "HYPOTHESIS_FROM_SUBJECT"


def input_obj() -> dict:
    return common.load_frozen(INPUT_FILE, INPUT_FILE_SHA256, "A10")


def prompt_for(ctx_text: str) -> str:
    return (
        "Este mensaje es independiente: ignora cualquier otro paquete o salida anterior de este chat. "
        "Eres el productor de la etapa A10 (cohorte heterogénea de casos) del perfil de análisis. Recibes 7 casos históricos (abajo): de cada uno solo tienes case_id, "
        "change_family, historical_subject y source_refs; NO se te suministra el contenido de las fuentes. Analiza cada caso de forma candidata a partir del asunto: "
        "qué impactos críticos podrían existir y qué frentes materiales habría que resolver. Todo es hipótesis: no declares READY, no inventes contenido de las fuentes, "
        "no propongas soluciones técnicas ni leas fuentes. Devuelve SOLO un objeto JSON, sin texto adicional, con exactamente estas claves: " + ", ".join(KEYS) +
        ". schema_version='" + OUT_SCHEMA + "'. request_ref='" + REQUEST_REF + "'. cohort: lista con un registro por cada caso de la entrada, cada registro con exactamente las claves "
        + ", ".join(sorted(CASE_KEYS)) + ": case_id y change_family copiados de la entrada; verdict: " + "|".join(VERDICTS) + "; "
        "critical_impacts_observed: lista no vacía de {impact (texto de al menos 10 caracteres), basis='" + BASIS + "'}; "
        "material_fronts_observed: lista no vacía de {front (texto corto), reason (texto de al menos 10 caracteres)}; "
        "evidence_refs: lista no vacía, sin repetidos, con source_refs del propio caso (solo las de ese caso); false_ready_count=0; reinterpretation_required: booleano; "
        "handoff_parity_verdict, scope_front_consistency_verdict y currentness_verdict='" + NOT_EVALUATED + "' (no se evalúan aquí); "
        "source_read_count=0, duplicate_read_count=0, retry_count=0; evidence_note: texto de al menos 20 caracteres que diga que el análisis parte del asunto y no del contenido de las fuentes. "
        "No incluyas latencia, tokens, proveedor ni identificadores de ejecución. families_covered: lista ordenada de las familias distintas presentes. no_ready_claim=true. "
        "cohort_statement: texto de al menos 40 caracteres que explique que el resultado es candidato, no READY y no medido contra un oráculo.\n\nENTRADA (JSON):\n" + ctx_text)


def build_packet(root: Path = common.REPO) -> dict:
    checks = {"request_ref_equals": REQUEST_REF, "verdicts": VERDICTS, "families": FAMILIES, "case_keys": sorted(CASE_KEYS), "not_evaluated": NOT_EVALUATED,
              "basis": BASIS, "forbidden_solution_patterns": a1.FORBIDDEN_SOLUTION}
    return common.build(UNIT, OUT_SCHEMA, KEYS, input_obj(), "A10 cohort fixture (" + INPUT_FILE_SHA256 + ")", REQUEST_REF, prompt_for, checks,
                        "analysis_qualification_a10q_c2_gpt_native_packet_v1.py::semantic_checks", root)


def _txt(v, n) -> bool:
    return isinstance(v, str) and len(v.strip()) >= n


def semantic_checks(packet: dict, out: dict) -> str | None:
    chk = packet["deterministic_checks"]
    ctx = json.loads(packet["input"]["input_literal"])
    cases = {c["case_id"]: c for c in ctx["cases"]}
    if set(out) != set(KEYS) or out.get("schema_version") != OUT_SCHEMA:
        return "KEYS_OR_SCHEMA"
    if out["request_ref"] != chk["request_ref_equals"]:
        return "REQUEST_REF_MISMATCH"
    if out["no_ready_claim"] is not True:
        return "READY_CLAIM"
    co = out["cohort"]
    if not (isinstance(co, list) and all(isinstance(r, dict) for r in co)):
        return "COHORT_SHAPE"
    ids = [r.get("case_id") for r in co]
    if len(ids) != len(set(ids)) or set(ids) != set(cases):
        return "CASE_SET_MISMATCH"
    for r in co:
        if set(r) != set(chk["case_keys"]):
            return "CASE_KEYS"
        c = cases[r["case_id"]]
        if r["change_family"] != c["change_family"]:
            return "FAMILY_MISMATCH"
        if r["verdict"] not in chk["verdicts"]:
            return "VERDICT_READY_OR_INVALID"
        imp, fr = r["critical_impacts_observed"], r["material_fronts_observed"]
        if not (isinstance(imp, list) and imp and all(isinstance(i, dict) and set(i) == {"impact", "basis"} and _txt(i["impact"], 10) and i["basis"] == chk["basis"] for i in imp)):
            return "IMPACTS_INVALID"
        if not (isinstance(fr, list) and fr and all(isinstance(f, dict) and set(f) == {"front", "reason"} and _txt(f["front"], 3) and _txt(f["reason"], 10) for f in fr)):
            return "FRONTS_INVALID"
        ev = r["evidence_refs"]
        if not (isinstance(ev, list) and ev and len(ev) == len(set(ev)) and all(isinstance(x, str) for x in ev) and set(ev) <= set(c["source_refs"])):
            return "EVIDENCE_REFS_INVALID"
        if r["false_ready_count"] != 0 or isinstance(r["false_ready_count"], bool):
            return "FALSE_READY_COUNT"
        if not isinstance(r["reinterpretation_required"], bool):
            return "REINTERPRETATION_NOT_BOOL"
        if any(r[k] != chk["not_evaluated"] for k in ("handoff_parity_verdict", "scope_front_consistency_verdict", "currentness_verdict")):
            return "UNMEASURED_VERDICT_CLAIMED"
        if any(isinstance(r[k], bool) or r[k] != 0 for k in ("source_read_count", "duplicate_read_count", "retry_count")):
            return "READ_COUNTS_NOT_ZERO"
        if not _txt(r["evidence_note"], 20):
            return "EVIDENCE_NOTE"
    fam = out["families_covered"]
    if not (isinstance(fam, list) and fam == sorted({c["change_family"] for c in cases.values()}) and fam == chk["families"]):
        return "FAMILIES_COVERED"
    if not _txt(out["cohort_statement"], 40):
        return "STATEMENT_MISSING"
    low, ctx_text = json.dumps(out, ensure_ascii=False).lower(), packet["input"]["input_literal"].lower()
    for pat in chk["forbidden_solution_patterns"]:
        if re.search(pat, low) and not re.search(pat, ctx_text):
            return "SOLUTION_INFERRED"
    return None


def intake(packet, raw_bytes, chat_ref, chat_sha256, approval_doc_sha256):
    return common.intake(UNIT, semantic_checks, packet, raw_bytes, chat_ref, chat_sha256, approval_doc_sha256)


if __name__ == "__main__":
    common.cli(UNIT, build_packet, intake)

#!/usr/bin/env python3
"""A8Q_C2 frozen GPT Native packet. Input: the A7 fronts output GPT produced (frozen, sha pinned).

A8 decides whether research may STOP. STOP is admissible only with a stable decision, complete front accounting and no unresolved question that could
change the result. In the input every front is BLOCKED by pending owner decisions, so STOP is forbidden; the output must trace every front to its
blockers and keep the decision unstable. Tier: OWNER_APPROVED_GPT_NATIVE_IN_CHAT_EQUIVALENT (not provider-attested).
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

UNIT = "A8"
OUT_SCHEMA = "A8_RESEARCH_DECISION_OUTPUT_V1"
INPUT_FILE = HERE / "a8q_c2_input_a7_output_v1.json"
INPUT_FILE_SHA256 = "6bbeadcc8ac1c69d239aec02af75d6a0e153a745c1954703e6c4811c001173fa"
REQUEST_REF = "REQ-LF-A1Q-C2-PILOT-0001"
KEYS = ["schema_version", "request_ref", "research_decision", "stop_criteria", "front_trace", "owner_decisions_required",
        "evidence_refs", "no_ready_claim", "decision_statement"]
DECISIONS = ["STOP", "CONTINUE", "REQUIRES_DECISION", "BLOCKED"]
CRITERIA = ["decision_stable", "front_accounting_complete", "decision_changing_questions_open"]
TRACE_KEYS = {"front_id", "blockers", "effect_on_decision"}


def input_obj() -> dict:
    return {"a7_stage_output": common.load_frozen(INPUT_FILE, INPUT_FILE_SHA256, "A8")}


def fronts(ctx: dict) -> dict:
    return {f["front_id"]: set(f["blockers"]) for f in ctx["a7_stage_output"]["material_fronts"]}


def allowed_refs(ctx: dict) -> set:
    a7 = ctx["a7_stage_output"]
    return set(a7["evidence_refs"]) | {"front:" + i for i in fronts(ctx)}


def prompt_for(ctx_text: str) -> str:
    return (
        "Este mensaje es independiente: ignora cualquier otro paquete o salida anterior de este chat. "
        "Eres el productor de la etapa A8 (decisión de investigación) del perfil de análisis. Recibes la salida de la etapa A7 (abajo). "
        "Decide si la investigación puede detenerse. STOP solo es admisible con decisión estable, contabilidad de frentes completa y ninguna pregunta sin resolver "
        "que pueda cambiar el resultado; si no se cumple, elige CONTINUE, REQUIRES_DECISION o BLOCKED según corresponda. No declares READY ni resuelvas decisiones del propietario. "
        "Referencias válidas: las evidence_refs de la entrada y 'front:<front_id>' para cada frente. Devuelve SOLO un objeto JSON, sin texto adicional, con exactamente estas claves: " +
        ", ".join(KEYS) + ". schema_version='" + OUT_SCHEMA + "'. request_ref='" + REQUEST_REF + "'. research_decision: " + "|".join(DECISIONS) +
        ". stop_criteria: objeto con exactamente las claves booleanas " + ", ".join(CRITERIA) + ". front_trace: lista con un elemento por cada frente de la entrada, "
        "{front_id, blockers (lista de decision_id del frente), effect_on_decision (texto)}. owner_decisions_required: lista de decision_id de la entrada que el propietario debe resolver "
        "(todas las que bloquean algún frente). evidence_refs: lista no vacía de referencias válidas. no_ready_claim=true. decision_statement: texto que explica la decisión y por qué no es STOP si corresponde."
        "\n\nENTRADA (JSON):\n" + ctx_text)


def build_packet(root: Path = common.REPO) -> dict:
    checks = {"request_ref_equals": REQUEST_REF, "decisions": DECISIONS, "criteria": CRITERIA, "trace_keys": sorted(TRACE_KEYS),
              "stop_forbidden_while_fronts_blocked": True, "forbidden_solution_patterns": a1.FORBIDDEN_SOLUTION}
    return common.build(UNIT, OUT_SCHEMA, KEYS, input_obj(), "A7Q_C2 GPT Native RAW (raw_output_sha256 " + INPUT_FILE_SHA256 + ")",
                        REQUEST_REF, prompt_for, checks, "analysis_qualification_a8q_c2_gpt_native_packet_v1.py::semantic_checks", root)


def semantic_checks(packet: dict, out: dict) -> str | None:
    chk = packet["deterministic_checks"]
    ctx = json.loads(packet["input"]["input_literal"])
    fr, ok = fronts(ctx), allowed_refs(ctx)
    all_dec = set().union(*fr.values())
    if set(out) != set(KEYS) or out.get("schema_version") != OUT_SCHEMA:
        return "KEYS_OR_SCHEMA"
    if out["request_ref"] != chk["request_ref_equals"]:
        return "REQUEST_REF_MISMATCH"
    if out["no_ready_claim"] is not True:
        return "READY_CLAIM"
    if out["research_decision"] not in chk["decisions"]:
        return "DECISION_INVALID"
    if out["research_decision"] == "STOP":
        return "STOP_WITH_BLOCKED_FRONTS"
    sc = out["stop_criteria"]
    if not (isinstance(sc, dict) and set(sc) == set(chk["criteria"]) and all(isinstance(v, bool) for v in sc.values())):
        return "STOP_CRITERIA_SHAPE"
    if sc["decision_stable"] is not False:
        return "STABILITY_OVERSTATED"
    if sc["decision_changing_questions_open"] is not True:
        return "OPEN_QUESTIONS_UNDERSTATED"
    tr = out["front_trace"]
    if not (isinstance(tr, list) and all(isinstance(t, dict) and set(t) == set(chk["trace_keys"]) for t in tr)):
        return "TRACE_SHAPE"
    ids = [t["front_id"] for t in tr]
    if len(ids) != len(set(ids)) or set(ids) != set(fr):
        return "TRACE_COVERAGE"
    for t in tr:
        b = t["blockers"]
        if not (isinstance(b, list) and len(b) == len(set(b)) and set(b) == fr[t["front_id"]]):
            return "TRACE_BLOCKERS_MISMATCH"
        if not isinstance(t["effect_on_decision"], str) or len(t["effect_on_decision"].strip()) < 20:
            return "TRACE_EFFECT"
    od = out["owner_decisions_required"]
    if not (isinstance(od, list) and len(od) == len(set(od)) and set(od) == all_dec):
        return "OWNER_DECISIONS_INCOMPLETE"
    ev = out["evidence_refs"]
    if not (isinstance(ev, list) and ev and all(isinstance(x, str) and x in ok for x in ev)):
        return "EVIDENCE_REFS_INVALID"
    st = out["decision_statement"]
    if not isinstance(st, str) or len(st.strip()) < 40:
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

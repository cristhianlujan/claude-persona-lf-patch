#!/usr/bin/env python3
"""A5Q_C2 frozen GPT Native packet. Input: the A4 impact map GPT produced (frozen, sha pinned).

A5 preserves the material decisions that an owner must take. With no current-decision source supplied, no decision
may be presented as in force; every pending decision is traced to an A4 impact and its A3 gap, stays PENDING with a
human owner, and nothing is approved, chosen or decided by the agent.
Tier: OWNER_APPROVED_GPT_NATIVE_IN_CHAT_EQUIVALENT (not provider-attested).
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

UNIT = "A5"
OUT_SCHEMA = "A5_DECISIONS_OUTPUT_V1"
INPUT_FILE = HERE / "a5q_c2_input_a4_output_v1.json"
INPUT_FILE_SHA256 = "58396efc6d1a31c443e151b54d1267a6ea64b6c5c34029d200048647435b40b5"
REQUEST_REF = "REQ-LF-A1Q-C2-PILOT-0001"
KEYS = ["schema_version", "request_ref", "current_decisions", "current_decisions_basis", "pending_decisions",
        "decisions_approved_by_agent", "evidence_refs", "decision_statement", "no_self_approval"]
PENDING_KEYS = {"decision_id", "question", "owner_role", "blocking", "gap_ref", "impact_ref", "status"}
MIN_DISTINCT_GAPS = 5
SELF_APPROVAL = re.compile(r"\b(aprob(é|ado|ada|amos|ó)|decid(í|ido|ida|imos)|se decide|queda decidid[oa]|elegid[oa]|se elige|se adopta)\b", re.I)


def input_obj() -> dict:
    return {"a4_stage_output": common.load_frozen(INPUT_FILE, INPUT_FILE_SHA256, "A5")}


def impacts(ctx: dict) -> dict:
    return {u["impact_id"]: u["gap_ref"] for u in ctx["a4_stage_output"]["unresolved_material_impacts"]}


def allowed_refs(ctx: dict) -> set:
    a4 = ctx["a4_stage_output"]
    return set(a4["evidence_refs"]) | {"impact:" + i for i in impacts(ctx)}


def prompt_for(ctx_text: str) -> str:
    return (
        "Este mensaje es independiente: ignora cualquier otro paquete o salida anterior de este chat. "
        "Eres el productor de la etapa A5 (decisiones) del perfil de análisis. Recibes la salida de la etapa A4 (abajo). "
        "Conserva las decisiones materiales que debe tomar el propietario humano. NO apruebes, elijas ni decidas nada: "
        "no resuelvas ADRs ni decisiones de producto. Distingue decisiones vigentes (solo si la entrada trae una fuente "
        "que las respalde; si no, la lista va vacía) de decisiones nuevas pendientes. Las únicas referencias válidas son "
        "las evidence_refs de la entrada y 'impact:<impact_id>' para cada impacto no resuelto. No infieras solución "
        "técnica. Devuelve SOLO un objeto JSON, sin texto adicional, con exactamente estas claves: " + ", ".join(KEYS) +
        ". schema_version='" + OUT_SCHEMA + "'. request_ref='" + REQUEST_REF + "'. current_decisions: lista (vacía si "
        "no hay fuente vigente). current_decisions_basis: texto que explica por qué está vacía o de dónde salen. "
        "pending_decisions: lista de {decision_id (único), question (una pregunta, texto que termina en '?'), "
        "owner_role='OWNER_HUMAN', blocking (booleano), gap_ref (un gap_code de la entrada), impact_ref (un impact_id de "
        "la entrada cuyo gap_ref coincida con el gap_ref), status='PENDING_OWNER_DECISION'}; deben cubrir al menos "
        + str(MIN_DISTINCT_GAPS) + " brechas distintas y al menos una debe ser blocking. decisions_approved_by_agent: "
        "lista vacía. evidence_refs: lista no vacía de referencias válidas. decision_statement: texto que explica qué "
        "decide el propietario y qué no decidió el agente. no_self_approval=true.\n\nENTRADA (JSON):\n" + ctx_text)


def build_packet(root: Path = common.REPO) -> dict:
    checks = {"request_ref_equals": REQUEST_REF, "pending_keys": sorted(PENDING_KEYS), "min_distinct_gaps": MIN_DISTINCT_GAPS,
              "forbidden_solution_patterns": a1.FORBIDDEN_SOLUTION}
    return common.build(UNIT, OUT_SCHEMA, KEYS, input_obj(), "A4Q_C2 GPT Native RAW (raw_output_sha256 " + INPUT_FILE_SHA256 + ")",
                        REQUEST_REF, prompt_for, checks, "analysis_qualification_a5q_c2_gpt_native_packet_v1.py::semantic_checks", root)


def semantic_checks(packet: dict, out: dict) -> str | None:
    chk = packet["deterministic_checks"]
    ctx = json.loads(packet["input"]["input_literal"])
    imp, ok = impacts(ctx), allowed_refs(ctx)
    if set(out) != set(KEYS) or out.get("schema_version") != OUT_SCHEMA:
        return "KEYS_OR_SCHEMA"
    if out["request_ref"] != chk["request_ref_equals"]:
        return "REQUEST_REF_MISMATCH"
    if out["no_self_approval"] is not True:
        return "SELF_APPROVAL_FLAG"
    if out["decisions_approved_by_agent"] != []:
        return "AGENT_APPROVED_DECISION"
    if out["current_decisions"] != []:
        return "CURRENT_DECISION_WITHOUT_SOURCE"
    if not isinstance(out["current_decisions_basis"], str) or len(out["current_decisions_basis"].strip()) < 20:
        return "CURRENT_BASIS_MISSING"
    pend = out["pending_decisions"]
    if not (isinstance(pend, list) and pend and all(isinstance(p, dict) and set(p) == set(chk["pending_keys"]) for p in pend)):
        return "PENDING_SHAPE"
    ids = [p["decision_id"] for p in pend]
    if len(ids) != len(set(ids)) or not all(isinstance(i, str) and i.strip() for i in ids):
        return "PENDING_IDS"
    for p in pend:
        q = p["question"]
        if not isinstance(q, str) or len(q.strip()) < 20 or not q.strip().endswith("?"):
            return "PENDING_QUESTION"
        if p["owner_role"] != "OWNER_HUMAN":
            return "PENDING_OWNER_ROLE"
        if p["status"] != "PENDING_OWNER_DECISION":
            return "PENDING_STATUS"
        if not isinstance(p["blocking"], bool):
            return "PENDING_BLOCKING_TYPE"
        if p["impact_ref"] not in imp:
            return "PENDING_IMPACT_NOT_IN_INPUT"
        if imp[p["impact_ref"]] != p["gap_ref"]:
            return "PENDING_GAP_IMPACT_MISMATCH"
    if len({p["gap_ref"] for p in pend}) < chk["min_distinct_gaps"]:
        return "GAP_COVERAGE_TOO_NARROW"
    if not any(p["blocking"] for p in pend):
        return "NO_BLOCKING_DECISION"
    ev = out["evidence_refs"]
    if not (isinstance(ev, list) and ev and all(isinstance(r, str) and r in ok for r in ev)):
        return "EVIDENCE_REFS_INVALID"
    st = out["decision_statement"]
    if not isinstance(st, str) or len(st.strip()) < 40:
        return "DECISION_STATEMENT_MISSING"
    text = json.dumps(out, ensure_ascii=False)
    if SELF_APPROVAL.search(text):
        return "SELF_APPROVAL_LANGUAGE"
    low, ctx_text = text.lower(), packet["input"]["input_literal"].lower()
    for pat in chk["forbidden_solution_patterns"]:
        if re.search(pat, low) and not re.search(pat, ctx_text):
            return "SOLUTION_INFERRED"
    return None


def intake(packet, raw_bytes, chat_ref, chat_sha256, approval_doc_sha256):
    return common.intake(UNIT, semantic_checks, packet, raw_bytes, chat_ref, chat_sha256, approval_doc_sha256)


if __name__ == "__main__":
    common.cli(UNIT, build_packet, intake)

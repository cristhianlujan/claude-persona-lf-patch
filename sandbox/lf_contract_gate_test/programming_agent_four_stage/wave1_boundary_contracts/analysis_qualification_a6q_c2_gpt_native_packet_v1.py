#!/usr/bin/env python3
"""A6Q_C2 frozen GPT Native packet. Input: the A5 decisions output GPT produced (frozen, sha pinned).

A6 turns what is known into typed WHAT requirements. Every A5 decision is still pending, so nothing may be CONFIRMED: requirements
stay PROVISIONAL and tied to pending decisions, and the permissions/state/error/side-effect dimensions must be reported as BLOCKED
(no source) instead of being invented. No HOW (technology/implementation) is licensed.
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

UNIT = "A6"
OUT_SCHEMA = "A6_REQUIREMENTS_OUTPUT_V1"
INPUT_FILE = HERE / "a6q_c2_input_a5_output_v1.json"
INPUT_FILE_SHA256 = "8db2b41750ab425b85a5d1c6bbe336ee4ff75052c40e46c5101b9564936a09f1"
REQUEST_REF = "REQ-LF-A1Q-C2-PILOT-0001"
KEYS = ["schema_version", "request_ref", "requirements", "dimensions", "evidence_refs", "no_unlicensed_how", "requirements_statement"]
REQ_KEYS = {"requirement_id", "type", "statement", "status", "depends_on_decisions", "source_ref"}
REQ_TYPES = ["FUNCTIONAL", "DATA", "NON_FUNCTIONAL"]
DIMENSIONS = ["functional", "data", "permissions", "state", "errors", "side_effects"]
MUST_BE_BLOCKED = ["permissions", "state", "errors", "side_effects"]
STATUS = "PROVISIONAL_PENDING_DECISION"
BLOCKED = "BLOCKED_UNDETERMINED"
MIN_DECISIONS_COVERED = 4


def input_obj() -> dict:
    return {"a5_stage_output": common.load_frozen(INPUT_FILE, INPUT_FILE_SHA256, "A6")}


def decision_ids(ctx: dict) -> set:
    return {p["decision_id"] for p in ctx["a5_stage_output"]["pending_decisions"]}


def allowed_refs(ctx: dict) -> set:
    return set(ctx["a5_stage_output"]["evidence_refs"]) | {"decision:" + d for d in decision_ids(ctx)}


def prompt_for(ctx_text: str) -> str:
    return (
        "Este mensaje es independiente: ignora cualquier otro paquete o salida anterior de este chat. "
        "Eres el productor de la etapa A6 (requisitos tipados) del perfil de análisis. Recibes la salida de la etapa A5 (abajo). "
        "Expresa QUÉ debe cumplir el cambio, sin indicar CÓMO implementarlo (nada de tecnología, almacenamiento, interfaces técnicas ni diseño). "
        "Toda decisión de A5 sigue pendiente, así que ningún requisito puede darse por confirmado: cada requisito es provisional y depende de decisiones "
        "pendientes. No inventes permisos, estados, errores, efectos colaterales ni cifras: si la entrada no los respalda, declara esa dimensión como bloqueada. "
        "Referencias válidas: las evidence_refs de la entrada y 'decision:<decision_id>' para cada decisión pendiente. "
        "Devuelve SOLO un objeto JSON, sin texto adicional, con exactamente estas claves: " + ", ".join(KEYS) + ". schema_version='" + OUT_SCHEMA +
        "'. request_ref='" + REQUEST_REF + "'. requirements: lista de {requirement_id (único), type (" + "|".join(REQ_TYPES) + "), statement (qué se exige, "
        "texto, sin cifras que no estén en la entrada), status='" + STATUS + "', depends_on_decisions (lista no vacía de decision_id de la entrada), "
        "source_ref (una referencia válida)}; deben depender en conjunto de al menos " + str(MIN_DECISIONS_COVERED) + " decisiones distintas y al menos uno debe ser FUNCTIONAL. "
        "dimensions: objeto con exactamente las claves " + ", ".join(DIMENSIONS) + "; cada una es {status ('" + STATUS + "' o '" + BLOCKED + "'), "
        "blocked_by (lista de decision_id de la entrada), note (texto)}. permissions, state, errors y side_effects deben ser '" + BLOCKED + "' con blocked_by no vacío. "
        "evidence_refs: lista no vacía de referencias válidas. no_unlicensed_how=true. requirements_statement: texto que explica qué quedó especificado y qué sigue "
        "bloqueado.\n\nENTRADA (JSON):\n" + ctx_text)


def build_packet(root: Path = common.REPO) -> dict:
    checks = {"request_ref_equals": REQUEST_REF, "req_keys": sorted(REQ_KEYS), "req_types": REQ_TYPES, "dimensions": DIMENSIONS,
              "must_be_blocked": MUST_BE_BLOCKED, "min_decisions_covered": MIN_DECISIONS_COVERED,
              "forbidden_solution_patterns": a1.FORBIDDEN_SOLUTION}
    return common.build(UNIT, OUT_SCHEMA, KEYS, input_obj(), "A5Q_C2 GPT Native RAW (raw_output_sha256 " + INPUT_FILE_SHA256 + ")",
                        REQUEST_REF, prompt_for, checks, "analysis_qualification_a6q_c2_gpt_native_packet_v1.py::semantic_checks", root)


def _valid_ids(v, ids) -> bool:
    return isinstance(v, list) and v and all(isinstance(x, str) and x in ids for x in v)


def semantic_checks(packet: dict, out: dict) -> str | None:
    chk = packet["deterministic_checks"]
    ctx = json.loads(packet["input"]["input_literal"])
    ids, ok = decision_ids(ctx), allowed_refs(ctx)
    if set(out) != set(KEYS) or out.get("schema_version") != OUT_SCHEMA:
        return "KEYS_OR_SCHEMA"
    if out["request_ref"] != chk["request_ref_equals"]:
        return "REQUEST_REF_MISMATCH"
    if out["no_unlicensed_how"] is not True:
        return "UNLICENSED_HOW_FLAG"
    reqs = out["requirements"]
    if not (isinstance(reqs, list) and reqs and all(isinstance(r, dict) and set(r) == set(chk["req_keys"]) for r in reqs)):
        return "REQUIREMENTS_SHAPE"
    rid = [r["requirement_id"] for r in reqs]
    if len(rid) != len(set(rid)) or not all(isinstance(i, str) and i.strip() for i in rid):
        return "REQUIREMENT_IDS"
    digits_ok = set(re.findall(r"\d+", packet["input"]["input_literal"]))
    covered = set()
    for r in reqs:
        if r["type"] not in chk["req_types"]:
            return "REQUIREMENT_TYPE_NOT_SOURCED"
        if r["status"] != STATUS:
            return "REQUIREMENT_CONFIRMED_WITHOUT_DECISION"
        if not _valid_ids(r["depends_on_decisions"], ids):
            return "REQUIREMENT_DECISION_REFS"
        covered |= set(r["depends_on_decisions"])
        if r["source_ref"] not in ok:
            return "REQUIREMENT_SOURCE_REF"
        if not isinstance(r["statement"], str) or len(r["statement"].strip()) < 20:
            return "REQUIREMENT_STATEMENT"
        if not set(re.findall(r"\d+", r["statement"])) <= digits_ok:
            return "INVENTED_NUMBER"
    if len(covered) < chk["min_decisions_covered"]:
        return "DECISION_COVERAGE_TOO_NARROW"
    if not any(r["type"] == "FUNCTIONAL" for r in reqs):
        return "NO_FUNCTIONAL_REQUIREMENT"
    dim = out["dimensions"]
    if not (isinstance(dim, dict) and set(dim) == set(chk["dimensions"])):
        return "DIMENSIONS_SHAPE"
    for k, d in dim.items():
        if not (isinstance(d, dict) and set(d) == {"status", "blocked_by", "note"}):
            return "DIMENSION_SHAPE"
        if d["status"] not in (STATUS, BLOCKED):
            return "DIMENSION_STATUS"
        if not isinstance(d["note"], str) or len(d["note"].strip()) < 20:
            return "DIMENSION_NOTE"
        if k in chk["must_be_blocked"] and d["status"] != BLOCKED:
            return "UNSOURCED_DIMENSION_SPECIFIED"
        if d["status"] == BLOCKED or k in chk["must_be_blocked"]:
            if not _valid_ids(d["blocked_by"], ids):
                return "DIMENSION_BLOCKERS"
        elif not (isinstance(d["blocked_by"], list) and all(isinstance(x, str) and x in ids for x in d["blocked_by"])):
            return "DIMENSION_BLOCKERS"
    ev = out["evidence_refs"]
    if not (isinstance(ev, list) and ev and all(isinstance(x, str) and x in ok for x in ev)):
        return "EVIDENCE_REFS_INVALID"
    st = out["requirements_statement"]
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

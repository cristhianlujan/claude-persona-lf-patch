#!/usr/bin/env python3
"""A7Q_C2 frozen GPT Native packet. Input: the A6 requirements output GPT produced (frozen, sha pinned).

A7 accounts for the material fronts derived from the A6 requirements and dimensions. The input carries no positive authority and no
currentness evidence, so NOT_APPLICABLE and REUSE_AS_IS are forbidden, every front must be BLOCKED with real A5 decision blockers, and every
requirement and every dimension must be linked to at least one front. Tier: OWNER_APPROVED_GPT_NATIVE_IN_CHAT_EQUIVALENT (not provider-attested).
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

UNIT = "A7"
OUT_SCHEMA = "A7_FRONTS_OUTPUT_V1"
INPUT_FILE = HERE / "a7q_c2_input_a6_output_v1.json"
INPUT_FILE_SHA256 = "e6ceef2605a44a7f63837784089cf3c8f40f7a3500d20f2a07adfc63c5cfac29"
REQUEST_REF = "REQ-LF-A1Q-C2-PILOT-0001"
KEYS = ["schema_version", "request_ref", "material_fronts", "evidence_refs", "fronts_statement"]
FRONT_KEYS = {"front_id", "scope_ids", "obligation_mode", "closure", "blockers", "evidence_refs", "reason"}
MODES = ["REQUIRED", "REUSE_AS_IS", "NOT_APPLICABLE"]
MIN_FRONTS = 3


def input_obj() -> dict:
    return {"a6_stage_output": common.load_frozen(INPUT_FILE, INPUT_FILE_SHA256, "A7")}


def scope_ids(ctx: dict) -> set:
    a6 = ctx["a6_stage_output"]
    return {r["requirement_id"] for r in a6["requirements"]} | {"dimension:" + k for k in a6["dimensions"]}


def decisions(ctx: dict) -> set:
    a6 = ctx["a6_stage_output"]
    out = {d for r in a6["requirements"] for d in r["depends_on_decisions"]}
    for d in a6["dimensions"].values():
        out |= set(d["blocked_by"])
    return out


def allowed_refs(ctx: dict) -> set:
    a6 = ctx["a6_stage_output"]
    return set(a6["evidence_refs"]) | scope_ids(ctx) | {"decision:" + d for d in decisions(ctx)}


def prompt_for(ctx_text: str) -> str:
    return (
        "Este mensaje es independiente: ignora cualquier otro paquete o salida anterior de este chat. "
        "Eres el productor de la etapa A7 (cobertura de frentes) del perfil de análisis. Recibes la salida de la etapa A6 (abajo). "
        "Agrupa en frentes materiales todo lo que la entrada obliga a considerar, sin inventar frentes que la entrada no sustente. "
        "Cada requisito (requirement_id) y cada dimensión (como 'dimension:<nombre>') de la entrada debe quedar vinculado a al menos un frente. "
        "La entrada no trae autoridad positiva ni evidencia de vigencia: por eso NO_APPLICABLE y REUSE_AS_IS están prohibidos, y todo frente queda "
        "BLOCKED con bloqueadores que sean decision_id de la entrada. No propongas soluciones técnicas. Referencias válidas: las evidence_refs de la entrada, "
        "los requirement_id, 'dimension:<nombre>' y 'decision:<decision_id>'. Devuelve SOLO un objeto JSON, sin texto adicional, con exactamente estas claves: " +
        ", ".join(KEYS) + ". schema_version='" + OUT_SCHEMA + "'. request_ref='" + REQUEST_REF + "'. material_fronts: lista de {front_id (único), "
        "scope_ids (lista no vacía de requirement_id o 'dimension:<nombre>' de la entrada), obligation_mode (" + "|".join(MODES) + "), closure (CLOSED|BLOCKED), "
        "blockers (lista de decision_id de la entrada), evidence_refs (lista no vacía de referencias válidas), reason (texto)}; al menos " + str(MIN_FRONTS) +
        " frentes. evidence_refs: lista no vacía de referencias válidas. fronts_statement: texto que explica qué frentes quedan bloqueados y por qué.\n\nENTRADA (JSON):\n" + ctx_text)


def build_packet(root: Path = common.REPO) -> dict:
    checks = {"request_ref_equals": REQUEST_REF, "front_keys": sorted(FRONT_KEYS), "modes": MODES, "min_fronts": MIN_FRONTS,
              "forbidden_modes": ["REUSE_AS_IS", "NOT_APPLICABLE"], "forbidden_solution_patterns": a1.FORBIDDEN_SOLUTION}
    return common.build(UNIT, OUT_SCHEMA, KEYS, input_obj(), "A6Q_C2 GPT Native RAW (raw_output_sha256 " + INPUT_FILE_SHA256 + ")",
                        REQUEST_REF, prompt_for, checks, "analysis_qualification_a7q_c2_gpt_native_packet_v1.py::semantic_checks", root)


def _ids(v, allowed, non_empty=True) -> bool:
    return isinstance(v, list) and (v or not non_empty) and all(isinstance(x, str) and x in allowed for x in v) and len(v) == len(set(v))


def semantic_checks(packet: dict, out: dict) -> str | None:
    chk = packet["deterministic_checks"]
    ctx = json.loads(packet["input"]["input_literal"])
    sc, dec, ok = scope_ids(ctx), decisions(ctx), allowed_refs(ctx)
    if set(out) != set(KEYS) or out.get("schema_version") != OUT_SCHEMA:
        return "KEYS_OR_SCHEMA"
    if out["request_ref"] != chk["request_ref_equals"]:
        return "REQUEST_REF_MISMATCH"
    fr = out["material_fronts"]
    if not (isinstance(fr, list) and len(fr) >= chk["min_fronts"] and all(isinstance(f, dict) and set(f) == set(chk["front_keys"]) for f in fr)):
        return "FRONTS_SHAPE"
    fid = [f["front_id"] for f in fr]
    if len(fid) != len(set(fid)) or not all(isinstance(i, str) and i.strip() for i in fid):
        return "FRONT_IDS"
    covered = set()
    for f in fr:
        if not _ids(f["scope_ids"], sc):
            return "FRONT_SCOPE_IDS"
        covered |= set(f["scope_ids"])
        if f["obligation_mode"] not in chk["modes"]:
            return "FRONT_MODE_INVALID"
        if f["obligation_mode"] in chk["forbidden_modes"]:
            return "FRONT_MODE_WITHOUT_AUTHORITY"
        if f["closure"] != "BLOCKED":
            return "FRONT_CLOSED_WITHOUT_EVIDENCE"
        if not _ids(f["blockers"], dec):
            return "FRONT_BLOCKERS"
        if not _ids(f["evidence_refs"], ok):
            return "FRONT_EVIDENCE_REFS"
        if not isinstance(f["reason"], str) or len(f["reason"].strip()) < 20:
            return "FRONT_REASON"
    if covered != sc:
        return "SCOPE_COVERAGE_INCOMPLETE"
    if not _ids(out["evidence_refs"], ok):
        return "EVIDENCE_REFS_INVALID"
    st = out["fronts_statement"]
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

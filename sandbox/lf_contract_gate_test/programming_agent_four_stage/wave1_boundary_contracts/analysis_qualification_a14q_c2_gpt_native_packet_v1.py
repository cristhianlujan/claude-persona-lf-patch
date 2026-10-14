#!/usr/bin/env python3
"""A14Q_C2 frozen GPT Native packet (criterion amended: docs/programming-agent/ANALYSIS_C2_CRITERIA_AMENDMENT_A9_A14_V1.md).

Input: the 12 fresh holdout cases (signals, evidence, specialist requirements, handoff; archetype labels removed) and the rules to apply (derived from the frozen
change-classification and handoff-parity contracts and the candidate replay logic). GPT answers every case; the answers are scored against the frozen blind oracle
(analysis_a14_fresh_oracle_v1.json, pinned by sha256 and NOT included in the packet). Pass requires every gate of the original A14 score to hold (no relaxation):
depth, critical impacts, material fronts, blocked and ready scopes, handoff parity, lossy projection, specialists. Provider identity, tokens and cost are out of the criterion
and must not appear. Nothing is executed or measured. Tier: OWNER_APPROVED_GPT_NATIVE_IN_CHAT_EQUIVALENT (not provider-attested).
"""
from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import analysis_qualification_gpt_native_packet_common_v1 as common  # noqa: E402

UNIT = "A14"
OUT_SCHEMA = "A14_HOLDOUT_ANSWERS_OUTPUT_V1"
INPUT_FILE = HERE / "a14q_c2_input_holdout_v1.json"
INPUT_FILE_SHA256 = "bf435cdf0e3635c4116fa300ac2fd51fe0e359875da2e3241410e410a96686b2"
ORACLE_FILE = HERE / "analysis_a14_fresh_oracle_v1.json"
ORACLE_FILE_SHA256 = "7db7ae22ed5ecd65fd9233c1a1ef8d9b66fc24979166554eb6131f7f538a29e1"
REQUEST_REF = "REQ-LF-A1Q-C2-PILOT-0001"
KEYS = ["schema_version", "request_ref", "answers", "answers_statement"]
ANS_KEYS = {"case_id", "depth_level", "critical_impacts", "material_fronts", "blocked_scope_ids", "ready_scope_ids", "handoff_parity", "lossy_projection_detected",
            "specialist_refs", "missing_required_specialists", "verdict", "rationale"}
DEPTHS = ["L1", "L2", "L3"]
VERDICTS = ["READY", "PARTIAL_READY", "BLOCKED"]
PARITY = ["PASS", "BLOCK"]


def input_obj() -> dict:
    return common.load_frozen(INPUT_FILE, INPUT_FILE_SHA256, "A14")


def oracle_obj() -> dict:
    return common.load_frozen(ORACLE_FILE, ORACLE_FILE_SHA256, "A14_ORACLE")


def prompt_for(ctx_text: str) -> str:
    return (
        "Este mensaje es independiente: ignora cualquier otro paquete o salida anterior de este chat. "
        "Eres el productor de la etapa A14 (validación con casos holdout nuevos). Recibes 12 casos (cases) y las reglas que debes aplicar (rules) (abajo). "
        "Responde CADA caso aplicando únicamente esas reglas a los datos del caso; no ejecutes nada, no midas nada y no inventes datos. "
        "Devuelve SOLO un objeto JSON, sin texto adicional, con exactamente estas claves: " + ", ".join(KEYS) + ". schema_version='" + OUT_SCHEMA + "'. request_ref='" + REQUEST_REF + "'. "
        "answers: lista con un registro por caso (12), con exactamente las claves " + ", ".join(sorted(ANS_KEYS)) + ": case_id; depth_level: " + "|".join(DEPTHS) +
        "; critical_impacts, material_fronts, blocked_scope_ids, ready_scope_ids, specialist_refs, missing_required_specialists: listas de textos sin repetidos (pueden ser vacías) según las reglas; "
        "handoff_parity: " + "|".join(PARITY) + "; lossy_projection_detected: booleano; verdict: " + "|".join(VERDICTS) + "; rationale: texto de al menos 20 caracteres con la razón principal. "
        "answers_statement: texto de al menos 40 caracteres que diga que las respuestas se produjeron aplicando las reglas suministradas, sin ejecutar ni medir nada. "
        "No incluyas proveedor, tokens, costos, latencia ni identificadores de ejecución.\n\nENTRADA (JSON):\n" + ctx_text)


def build_packet(root: Path = common.REPO) -> dict:
    checks = {"request_ref_equals": REQUEST_REF, "ans_keys": sorted(ANS_KEYS), "depths": DEPTHS, "verdicts": VERDICTS, "parity": PARITY,
              "oracle_file_sha256": ORACLE_FILE_SHA256, "oracle_in_packet": False}
    return common.build(UNIT, OUT_SCHEMA, KEYS, input_obj(), "A14 holdout fixture (" + INPUT_FILE_SHA256 + ")", REQUEST_REF, prompt_for, checks,
                        "analysis_qualification_a14q_c2_gpt_native_packet_v1.py::semantic_checks", root)


def _txt(v, n) -> bool:
    return isinstance(v, str) and len(v.strip()) >= n


def _set_list(v) -> bool:
    return isinstance(v, list) and all(isinstance(x, str) for x in v) and len(v) == len(set(v))


def semantic_checks(packet: dict, out: dict) -> str | None:
    chk = packet["deterministic_checks"]
    ctx = json.loads(packet["input"]["input_literal"])
    cases = {c["case_id"]: c for c in ctx["cases"]}
    oracle = {o["case_id"]: o for o in oracle_obj()["oracle"]}
    if set(out) != set(KEYS) or out.get("schema_version") != OUT_SCHEMA:
        return "KEYS_OR_SCHEMA"
    if out["request_ref"] != chk["request_ref_equals"]:
        return "REQUEST_REF_MISMATCH"
    ans = out["answers"]
    if not (isinstance(ans, list) and all(isinstance(a, dict) for a in ans)):
        return "ANSWERS_SHAPE"
    ids = [a.get("case_id") for a in ans]
    if len(ids) != len(set(ids)) or set(ids) != set(cases) or set(oracle) != set(cases):
        return "ANSWER_CASE_SET_MISMATCH"
    for a in ans:
        if set(a) != set(chk["ans_keys"]):
            return "ANSWER_KEYS"
        if not all(_set_list(a[k]) for k in ("critical_impacts", "material_fronts", "blocked_scope_ids", "ready_scope_ids", "specialist_refs", "missing_required_specialists")):
            return "ANSWER_LISTS_INVALID"
        if not _txt(a["rationale"], 20):
            return "RATIONALE_MISSING"
        if a["depth_level"] not in chk["depths"] or a["handoff_parity"] not in chk["parity"] or a["verdict"] not in chk["verdicts"] or not isinstance(a["lossy_projection_detected"], bool):
            return "ANSWER_VALUE_INVALID"
        c, o = cases[a["case_id"]], oracle[a["case_id"]]
        if a["depth_level"] != o["depth_expected"]:
            return "DEPTH_WRONG"
        if set(a["critical_impacts"]) != set(o["critical_impacts_expected"]):
            return "CRITICAL_IMPACTS_WRONG"
        if set(a["material_fronts"]) != set(o["material_fronts_expected"]):
            return "MATERIAL_FRONTS_WRONG"
        scopes = [s["scope_id"] for s in c["evidence"]["scopes"]]
        blocked = set(o["blocked_scope_ids_expected"])
        if set(a["blocked_scope_ids"]) != blocked:
            return "BLOCKED_SCOPES_WRONG"
        if set(a["ready_scope_ids"]) != set(scopes) - blocked:
            return "READY_SCOPES_WRONG"
        if a["handoff_parity"] != o["handoff_parity_expected"]:
            return "HANDOFF_WRONG"
        if a["lossy_projection_detected"] != o["lossy_projection_expected_block"]:
            return "LOSSY_WRONG"
        if set(a["specialist_refs"]) != set(o["specialist_refs_expected"]):
            return "SPECIALIST_REFS_WRONG"
        miss = {r["specialist_type"] for r in c["specialist_requirements"] if r.get("required") is True and not r.get("matched_ref")}
        if set(a["missing_required_specialists"]) != miss or bool(miss) != o["required_specialist_missing_expected"]:
            return "MISSING_SPECIALIST_WRONG"
        exp_verdict = "READY" if not blocked else ("BLOCKED" if blocked == set(scopes) else "PARTIAL_READY")
        if a["verdict"] != exp_verdict:
            return "VERDICT_INCONSISTENT"
    if not _txt(out["answers_statement"], 40):
        return "STATEMENT_MISSING"
    return None


def intake(packet, raw_bytes, chat_ref, chat_sha256, approval_doc_sha256):
    return common.intake(UNIT, semantic_checks, packet, raw_bytes, chat_ref, chat_sha256, approval_doc_sha256)


if __name__ == "__main__":
    common.cli(UNIT, build_packet, intake)

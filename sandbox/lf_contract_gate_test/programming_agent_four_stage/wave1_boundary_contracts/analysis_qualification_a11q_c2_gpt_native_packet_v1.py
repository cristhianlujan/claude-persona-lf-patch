#!/usr/bin/env python3
"""A11Q_C2 frozen GPT Native packet (criterion amended: docs/programming-agent/ANALYSIS_C2_CRITERIA_AMENDMENT_A9_A14_V1.md).

Input: the A9 snapshot GPT produced (frozen RAW) plus the 11 adversarial categories of the campaign contract. GPT must PRODUCE one adversarial case per category:
a concrete mutation of real elements of the snapshot and the safe behavior expected from the pipeline (never PASS/READY). Nothing is executed: every case declares
executed=false and observed_result=null. No governed route, no oracle, no measurement. Tier: OWNER_APPROVED_GPT_NATIVE_IN_CHAT_EQUIVALENT (not provider-attested).
The A1-pilot solution-inference word list is NOT applied here: adversarial vocabulary (schema, API, table) is legitimate in this stage.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import analysis_qualification_gpt_native_packet_common_v1 as common  # noqa: E402

UNIT = "A11"
OUT_SCHEMA = "A11_ADVERSARIAL_OUTPUT_V1"
INPUT_FILE = HERE / "a11q_c2_input_a9_snapshot_categories_v1.json"
INPUT_FILE_SHA256 = "bb991adf3fde3cd5c05238cf2a26b12c70d8afa99466313252b56a781d1bb4ac"
REQUEST_REF = "REQ-LF-A1Q-C2-PILOT-0001"
KEYS = ["schema_version", "request_ref", "cases", "no_ready_claim", "adversarial_statement"]
CASE_KEYS = {"category", "mutation_description", "target_refs", "expected_safe_behavior", "false_ready_if_unblocked", "executed", "observed_result"}
SAFE = ["BLOCK", "REQUIRES_DECISION", "NEED_MORE_EVIDENCE"]


def input_obj() -> dict:
    return common.load_frozen(INPUT_FILE, INPUT_FILE_SHA256, "A11")


def snapshot_ids(ctx: dict) -> set:
    s = ctx["a9_snapshot"]
    return {x["scope_id"] for x in s["scope_readiness"]} | {f["front_id"] for f in s["material_front_coverage"]["material_fronts"]}


def prompt_for(ctx_text: str) -> str:
    return (
        "Este mensaje es independiente: ignora cualquier otro paquete o salida anterior de este chat. "
        "Eres el productor de la etapa A11 (casos adversariales) del perfil de análisis. Recibes el snapshot A9 (a9_snapshot) y las 11 categorías adversariales (categories) (abajo). "
        "Produce UN caso adversarial por categoría: una mutación concreta de elementos reales del snapshot (scope_id o front_id que existan en él) que intente colar un falso READY o un falso PASS, "
        "y el comportamiento seguro esperado del pipeline. NO ejecutes nada ni inventes resultados: cada caso declara executed=false y observed_result=null. No declares READY. "
        "Devuelve SOLO un objeto JSON, sin texto adicional, con exactamente estas claves: " + ", ".join(KEYS) + ". schema_version='" + OUT_SCHEMA + "'. request_ref='" + REQUEST_REF + "'. "
        "cases: lista con exactamente un registro por categoría de la entrada (11), cada uno con exactamente las claves " + ", ".join(sorted(CASE_KEYS)) + ": category copiada de la entrada; "
        "mutation_description: texto de al menos 30 caracteres que describa la mutación concreta; target_refs: lista no vacía, sin repetidos, de scope_id o front_id presentes en a9_snapshot; "
        "expected_safe_behavior: " + "|".join(SAFE) + "; false_ready_if_unblocked=true; executed=false; observed_result=null. no_ready_claim=true. "
        "adversarial_statement: texto de al menos 40 caracteres que diga que los casos son producidos, no ejecutados, y que no hay medición contra un oráculo.\n\nENTRADA (JSON):\n" + ctx_text)


def build_packet(root: Path = common.REPO) -> dict:
    checks = {"request_ref_equals": REQUEST_REF, "safe_behaviors": SAFE, "case_keys": sorted(CASE_KEYS), "critical_false_ready_tolerance": 0}
    return common.build(UNIT, OUT_SCHEMA, KEYS, input_obj(), "A9 snapshot RAW + adversarial categories (" + INPUT_FILE_SHA256 + ")", REQUEST_REF, prompt_for, checks,
                        "analysis_qualification_a11q_c2_gpt_native_packet_v1.py::semantic_checks", root)


def _txt(v, n) -> bool:
    return isinstance(v, str) and len(v.strip()) >= n


def semantic_checks(packet: dict, out: dict) -> str | None:
    chk = packet["deterministic_checks"]
    ctx = json.loads(packet["input"]["input_literal"])
    cats = [c["category"] for c in ctx["categories"]]
    ids = snapshot_ids(ctx)
    if set(out) != set(KEYS) or out.get("schema_version") != OUT_SCHEMA:
        return "KEYS_OR_SCHEMA"
    if out["request_ref"] != chk["request_ref_equals"]:
        return "REQUEST_REF_MISMATCH"
    if out["no_ready_claim"] is not True:
        return "READY_CLAIM"
    cs = out["cases"]
    if not (isinstance(cs, list) and all(isinstance(c, dict) for c in cs)):
        return "CASES_SHAPE"
    got = [c.get("category") for c in cs]
    if len(got) != len(set(got)) or set(got) != set(cats):
        return "CATEGORY_SET_MISMATCH"
    for c in cs:
        if set(c) != set(chk["case_keys"]):
            return "CASE_KEYS"
        if not _txt(c["mutation_description"], 30):
            return "MUTATION_TEXT"
        t = c["target_refs"]
        if not (isinstance(t, list) and t and len(t) == len(set(t)) and all(isinstance(x, str) for x in t) and set(t) <= ids):
            return "TARGET_REFS_INVALID"
        if c["expected_safe_behavior"] not in chk["safe_behaviors"]:
            return "SAFE_BEHAVIOR_INVALID"
        if c["false_ready_if_unblocked"] is not True:
            return "FALSE_READY_FLAG"
        if c["executed"] is not False or c["observed_result"] is not None:
            return "EXECUTION_CLAIMED"
    if not _txt(out["adversarial_statement"], 40):
        return "STATEMENT_MISSING"
    return None


def intake(packet, raw_bytes, chat_ref, chat_sha256, approval_doc_sha256):
    return common.intake(UNIT, semantic_checks, packet, raw_bytes, chat_ref, chat_sha256, approval_doc_sha256)


if __name__ == "__main__":
    common.cli(UNIT, build_packet, intake)

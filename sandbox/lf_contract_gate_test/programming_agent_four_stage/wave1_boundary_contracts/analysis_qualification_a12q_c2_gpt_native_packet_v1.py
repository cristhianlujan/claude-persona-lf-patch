#!/usr/bin/env python3
"""A12Q_C2 frozen GPT Native packet (criterion amended: docs/programming-agent/ANALYSIS_C2_CRITERIA_AMENDMENT_A9_A14_V1.md).

Input: the 7 A10 cohort cases (same case set for both arms), the six fixed baseline domains and a one-line description of each arm. GPT must PRODUCE both arms:
the baseline arm applies the full fixed-domain list to every case; the candidate arm records only evidence-triggered fronts, each tied to a source_ref of its own case.
A comparison block must carry counts that the verifier recomputes. Latency, tokens and provider identity are out of the criterion: they must not appear.
Nothing is executed or measured; this is not a performance comparison. Tier: OWNER_APPROVED_GPT_NATIVE_IN_CHAT_EQUIVALENT (not provider-attested).
The A1-pilot solution-inference word list is not applied (see A11).
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import analysis_qualification_gpt_native_packet_common_v1 as common  # noqa: E402

UNIT = "A12"
OUT_SCHEMA = "A12_ARMS_OUTPUT_V1"
INPUT_FILE = HERE / "a12q_c2_input_arms_v1.json"
INPUT_FILE_SHA256 = "9dbc2185a3ba5f9f2b84e6380bdf86d610d0ce88701dbb9394ff98e8bb06fa4b"
REQUEST_REF = "REQ-LF-A1Q-C2-PILOT-0001"
KEYS = ["schema_version", "request_ref", "arms", "comparison", "no_ready_claim", "arms_statement"]
VERDICTS = ["BLOCKED", "REQUIRES_DECISION", "NEED_MORE_EVIDENCE"]
BASE_KEYS = {"case_id", "verdict", "domains", "evidence_refs", "reinterpretation_required"}
CAND_KEYS = {"case_id", "verdict", "fronts", "evidence_refs", "reinterpretation_required"}
CMP_KEYS = {"cases_compared", "baseline_total_domains", "candidate_total_fronts", "baseline_fixed_domains_per_case"}


def input_obj() -> dict:
    return common.load_frozen(INPUT_FILE, INPUT_FILE_SHA256, "A12")


def prompt_for(ctx_text: str) -> str:
    return (
        "Este mensaje es independiente: ignora cualquier otro paquete o salida anterior de este chat. "
        "Eres el productor de la etapa A12 (comparación de dos brazos sobre los mismos casos) del perfil de análisis. Recibes 7 casos (cases), la lista de dominios fijos del brazo baseline "
        "(baseline_fixed_domains) y la descripción de cada brazo (arms) (abajo). NO se suministra el contenido de las fuentes: todo es hipótesis a partir del asunto. "
        "Produce AMBOS brazos para los MISMOS 7 casos. Baseline: por cada caso, TODOS los dominios fijos, sin importar la evidencia. Candidate: por cada caso, solo los frentes que una "
        "referencia del propio caso permita justificar. No declares READY, no ejecutes nada, no mides nada. Devuelve SOLO un objeto JSON, sin texto adicional, con exactamente estas claves: " + ", ".join(KEYS) +
        ". schema_version='" + OUT_SCHEMA + "'. request_ref='" + REQUEST_REF + "'. arms: objeto con exactamente las claves baseline y candidate, cada una una lista con un registro por caso (7). "
        "Registro baseline, con exactamente las claves " + ", ".join(sorted(BASE_KEYS)) + ": case_id; verdict: " + "|".join(VERDICTS) + "; domains: lista con un elemento {domain, note} por CADA dominio fijo "
        "(note: texto de al menos 10 caracteres); evidence_refs: lista no vacía, sin repetidos, con source_refs del propio caso; reinterpretation_required: booleano. "
        "Registro candidate, con exactamente las claves " + ", ".join(sorted(CAND_KEYS)) + ": case_id; verdict igual que arriba; fronts: lista no vacía de {front (texto corto), trigger_ref (una source_ref del propio caso), "
        "reason (texto de al menos 10 caracteres)}; evidence_refs y reinterpretation_required como arriba. "
        "comparison: objeto con exactamente las claves " + ", ".join(sorted(CMP_KEYS)) + " (enteros): casos comparados, total de dominios del baseline sumando todos los casos, total de frentes del candidate sumando todos los casos, "
        "y número de dominios fijos por caso. No incluyas latencia, tokens, proveedor ni identificadores de ejecución. no_ready_claim=true. "
        "arms_statement: texto de al menos 40 caracteres que diga que ambos brazos fueron producidos, no medidos, y que no es una comparación de rendimiento.\n\nENTRADA (JSON):\n" + ctx_text)


def build_packet(root: Path = common.REPO) -> dict:
    checks = {"request_ref_equals": REQUEST_REF, "verdicts": VERDICTS, "base_keys": sorted(BASE_KEYS), "cand_keys": sorted(CAND_KEYS), "cmp_keys": sorted(CMP_KEYS)}
    return common.build(UNIT, OUT_SCHEMA, KEYS, input_obj(), "A12 arms fixture (" + INPUT_FILE_SHA256 + ")", REQUEST_REF, prompt_for, checks,
                        "analysis_qualification_a12q_c2_gpt_native_packet_v1.py::semantic_checks", root)


def _txt(v, n) -> bool:
    return isinstance(v, str) and len(v.strip()) >= n


def _int(v) -> bool:
    return isinstance(v, int) and not isinstance(v, bool)


def _common(r: dict, cases: dict, chk: dict) -> str | None:
    c = cases[r["case_id"]]
    if r["verdict"] not in chk["verdicts"]:
        return "VERDICT_READY_OR_INVALID"
    ev = r["evidence_refs"]
    if not (isinstance(ev, list) and ev and len(ev) == len(set(ev)) and all(isinstance(x, str) for x in ev) and set(ev) <= set(c["source_refs"])):
        return "EVIDENCE_REFS_INVALID"
    if not isinstance(r["reinterpretation_required"], bool):
        return "REINTERPRETATION_NOT_BOOL"
    return None


def semantic_checks(packet: dict, out: dict) -> str | None:
    chk = packet["deterministic_checks"]
    ctx = json.loads(packet["input"]["input_literal"])
    cases = {c["case_id"]: c for c in ctx["cases"]}
    fixed = ctx["baseline_fixed_domains"]
    if set(out) != set(KEYS) or out.get("schema_version") != OUT_SCHEMA:
        return "KEYS_OR_SCHEMA"
    if out["request_ref"] != chk["request_ref_equals"]:
        return "REQUEST_REF_MISMATCH"
    if out["no_ready_claim"] is not True:
        return "READY_CLAIM"
    arms = out["arms"]
    if not (isinstance(arms, dict) and set(arms) == {"baseline", "candidate"} and isinstance(arms["baseline"], list) and isinstance(arms["candidate"], list)
            and all(isinstance(r, dict) for r in arms["baseline"] + arms["candidate"])):
        return "ARMS_SHAPE"
    for arm in ("baseline", "candidate"):
        ids = [r.get("case_id") for r in arms[arm]]
        if len(ids) != len(set(ids)) or set(ids) != set(cases):
            return "CASE_SET_MISMATCH"
    nb = nc = 0
    for r in arms["baseline"]:
        if set(r) != set(chk["base_keys"]):
            return "BASELINE_KEYS"
        bad = _common(r, cases, chk)
        if bad:
            return bad
        d = r["domains"]
        if not (isinstance(d, list) and all(isinstance(x, dict) and set(x) == {"domain", "note"} and _txt(x["note"], 10) for x in d)):
            return "BASELINE_DOMAINS_SHAPE"
        names = [x["domain"] for x in d]
        if len(names) != len(set(names)) or sorted(names) != sorted(fixed):
            return "BASELINE_FIXED_DOMAINS_NOT_APPLIED"
        nb += len(d)
    for r in arms["candidate"]:
        if set(r) != set(chk["cand_keys"]):
            return "CANDIDATE_KEYS"
        bad = _common(r, cases, chk)
        if bad:
            return bad
        f = r["fronts"]
        if not (isinstance(f, list) and f and all(isinstance(x, dict) and set(x) == {"front", "trigger_ref", "reason"} and _txt(x["front"], 3) and _txt(x["reason"], 10) for x in f)):
            return "CANDIDATE_FRONTS_SHAPE"
        if any(x["trigger_ref"] not in cases[r["case_id"]]["source_refs"] for x in f):
            return "TRIGGER_REF_OUTSIDE_CASE"
        if len({x["front"] for x in f}) != len(f):
            return "CANDIDATE_FRONTS_DUPLICATED"
        nc += len(f)
    cmp_ = out["comparison"]
    if not (isinstance(cmp_, dict) and set(cmp_) == set(chk["cmp_keys"]) and all(_int(v) for v in cmp_.values())):
        return "COMPARISON_SHAPE"
    if cmp_["cases_compared"] != len(cases) or cmp_["baseline_total_domains"] != nb or cmp_["candidate_total_fronts"] != nc or cmp_["baseline_fixed_domains_per_case"] != len(fixed):
        return "COMPARISON_COUNTS_MISMATCH"
    if not _txt(out["arms_statement"], 40):
        return "STATEMENT_MISSING"
    return None


def intake(packet, raw_bytes, chat_ref, chat_sha256, approval_doc_sha256):
    return common.intake(UNIT, semantic_checks, packet, raw_bytes, chat_ref, chat_sha256, approval_doc_sha256)


if __name__ == "__main__":
    common.cli(UNIT, build_packet, intake)

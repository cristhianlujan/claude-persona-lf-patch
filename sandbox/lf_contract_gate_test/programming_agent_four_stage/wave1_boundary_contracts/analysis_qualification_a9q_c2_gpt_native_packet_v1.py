#!/usr/bin/env python3
"""A9Q_C2 frozen GPT Native packet (criterion amended: docs/programming-agent/ANALYSIS_C2_CRITERIA_AMENDMENT_A9_A14_V1.md).

Inputs: the frozen A7 fronts output and the A8 research-decision output GPT produced. GPT must assemble a PROGRAMMING_CONTEXT_SNAPSHOT_V1-shaped
candidate that passes the existing validate_programming_snapshot_payload_v1 and is consistent with A7/A8: every A7 scope is a snapshot scope, every A7
front is a snapshot front with the same blockers, no scope is READY (all fronts block), and the package is never READY. The coverage fingerprint is a
harness placeholder (64 zeros), NOT a computed fingerprint; nothing here is persisted, published or attested.
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
import validate_wave1_boundary_contracts_v1 as wave1  # noqa: E402

UNIT = "A9"
OUT_SCHEMA = "PROGRAMMING_CONTEXT_SNAPSHOT_V1"
A7_FILE, A7_SHA = HERE / "a9q_c2_input_a7_output_v1.json", "6bbeadcc8ac1c69d239aec02af75d6a0e153a745c1954703e6c4811c001173fa"
A8_FILE, A8_SHA = HERE / "a9q_c2_input_a8_output_v1.json", "2fee538e7c6228fbd19d7ce5a01b88decd3afec213bb63170d52715fc7b09d30"
REQUEST_REF = "REQ-LF-A1Q-C2-PILOT-0001"
ZERO = "0" * 64
KEYS = ["schema_version", "request_ref", "candidate_only", "research_decision", "scope_readiness", "material_front_coverage",
        "scope_front_matrix", "package_readiness", "no_ready_claim", "snapshot_statement"]
SCOPE_KEYS = {"scope_id", "status", "material_front_refs", "depends_on_scope_ids", "blockers"}
FRONT_KEYS = {"front_id", "front_kind", "status", "closure", "source_signal_refs", "scope_refs", "authority_refs", "evidence_refs",
              "currentness_refs", "blockers", "reason"}
COVERAGE_KEYS = {"all_material_fronts_accounted", "material_fronts", "front_candidate_refs", "unmapped_material_signals", "source_refs",
                 "currentness_refs", "coverage_fingerprint_sha256"}
MATRIX_KEYS = {"scope_id", "front_id", "front_status", "front_closure", "effect_on_scope"}
PACKAGE = ["BLOCKED", "REQUIRES_DECISION", "NEED_MORE_EVIDENCE"]
SCOPE_STATUS = ["BLOCKED", "REQUIRES_DECISION", "NEED_MORE_EVIDENCE"]


def input_obj() -> dict:
    return {"a7_stage_output": common.load_frozen(A7_FILE, A7_SHA, "A9_A7"), "a8_stage_output": common.load_frozen(A8_FILE, A8_SHA, "A9_A8")}


def a7_fronts(ctx: dict) -> dict:
    return {f["front_id"]: f for f in ctx["a7_stage_output"]["material_fronts"]}


def a7_scopes(ctx: dict) -> set:
    return {s for f in ctx["a7_stage_output"]["material_fronts"] for s in f["scope_ids"]}


def allowed_refs(ctx: dict) -> set:
    return set(ctx["a7_stage_output"]["evidence_refs"]) | set(ctx["a8_stage_output"]["evidence_refs"]) | {"front:" + i for i in a7_fronts(ctx)}


def prompt_for(ctx_text: str) -> str:
    return (
        "Este mensaje es independiente: ignora cualquier otro paquete o salida anterior de este chat. "
        "Eres el productor de la etapa A9 (snapshot de contexto de programación) del perfil de análisis. Recibes las salidas de A7 (frentes) y A8 (decisión de investigación) (abajo). "
        "Arma un candidato PROGRAMMING_CONTEXT_SNAPSHOT_V1 coherente con ambas entradas. Todo es candidato: no declares READY, no persistas ni atestigues nada, no inventes autoridad ni vigencia. "
        "Cada scope_id de A7 (requisitos y 'dimension:<nombre>') es un scope del snapshot; cada front de A7 es un frente del snapshot con los mismos bloqueadores; "
        "ningún scope puede ser READY porque todos los frentes bloquean. Devuelve SOLO un objeto JSON, sin texto adicional, con exactamente estas claves: " + ", ".join(KEYS) +
        ". schema_version='" + OUT_SCHEMA + "'. request_ref='" + REQUEST_REF + "'. candidate_only=true. research_decision: igual a la decisión de la entrada A8. "
        "scope_readiness: lista de {scope_id, status (" + "|".join(SCOPE_STATUS) + "), material_front_refs (front_id de los frentes de A7 que contienen ese scope), "
        "depends_on_scope_ids (lista vacía), blockers (decision_id de los frentes que lo contienen)}. "
        "material_front_coverage: {all_material_fronts_accounted=true, material_fronts: lista de {front_id, front_kind (texto corto), status (el obligation_mode de A7), closure (el de A7), "
        "source_signal_refs (referencias válidas), scope_refs (los scope_ids del frente en A7), authority_refs ([]), evidence_refs (lista no vacía de referencias válidas), currentness_refs ([]), "
        "blockers (los de A7), reason (texto)}, front_candidate_refs (todos los front_id), unmapped_material_signals (lista de referencias válidas de la entrada que no quedaron ligadas a un frente, puede ser vacía), "
        "source_refs (lista no vacía de referencias válidas), currentness_refs ([]), coverage_fingerprint_sha256 (usa exactamente 64 ceros: es un marcador del arnés, NO una huella calculada)}. "
        "scope_front_matrix: una fila {scope_id, front_id, front_status, front_closure, effect_on_scope} por cada par scope-frente, con effect_on_scope='BLOCKS'. "
        "package_readiness: " + "|".join(PACKAGE) + ". no_ready_claim=true. snapshot_statement: texto que explica por qué ningún scope ni el paquete son READY. "
        "Referencias válidas: las evidence_refs de A7 y A8 y 'front:<front_id>'.\n\nENTRADAS (JSON):\n" + ctx_text)


def build_packet(root: Path = common.REPO) -> dict:
    checks = {"request_ref_equals": REQUEST_REF, "zero_fingerprint": ZERO, "package": PACKAGE, "scope_status": SCOPE_STATUS,
              "scope_keys": sorted(SCOPE_KEYS), "front_keys": sorted(FRONT_KEYS), "coverage_keys": sorted(COVERAGE_KEYS), "matrix_keys": sorted(MATRIX_KEYS),
              "existing_validator": "validate_wave1_boundary_contracts_v1.py::validate_programming_snapshot_payload_v1",
              "forbidden_solution_patterns": a1.FORBIDDEN_SOLUTION}
    return common.build(UNIT, OUT_SCHEMA, KEYS, input_obj(), "A7Q_C2 RAW (" + A7_SHA + ") and A8Q_C2 RAW (" + A8_SHA + ")",
                        REQUEST_REF, prompt_for, checks, "analysis_qualification_a9q_c2_gpt_native_packet_v1.py::semantic_checks", root)


def _set(v, allowed=None) -> bool:
    return isinstance(v, list) and len(v) == len(set(v)) and all(isinstance(x, str) and x for x in v) and (allowed is None or set(v) <= allowed)


def semantic_checks(packet: dict, out: dict) -> str | None:
    chk = packet["deterministic_checks"]
    ctx = json.loads(packet["input"]["input_literal"])
    fr7, sc7, ok = a7_fronts(ctx), a7_scopes(ctx), allowed_refs(ctx)
    if set(out) != set(KEYS) or out.get("schema_version") != OUT_SCHEMA:
        return "KEYS_OR_SCHEMA"
    if out["request_ref"] != chk["request_ref_equals"]:
        return "REQUEST_REF_MISMATCH"
    if out["candidate_only"] is not True or out["no_ready_claim"] is not True:
        return "READY_OR_CANDIDATE_FLAG"
    if out["research_decision"] != ctx["a8_stage_output"]["research_decision"]:
        return "RESEARCH_DECISION_MISMATCH"
    if out["package_readiness"] not in chk["package"]:
        return "PACKAGE_READINESS_INVALID"
    scopes, cov, mat = out["scope_readiness"], out["material_front_coverage"], out["scope_front_matrix"]
    if not (isinstance(scopes, list) and all(isinstance(s, dict) and set(s) == set(chk["scope_keys"]) for s in scopes)):
        return "SCOPE_SHAPE"
    if not (isinstance(cov, dict) and set(cov) == set(chk["coverage_keys"]) and isinstance(cov["material_fronts"], list)
            and all(isinstance(f, dict) and set(f) == set(chk["front_keys"]) for f in cov["material_fronts"])):
        return "COVERAGE_SHAPE"
    if not (isinstance(mat, list) and all(isinstance(m, dict) and set(m) == set(chk["matrix_keys"]) for m in mat)):
        return "MATRIX_SHAPE"
    if cov["coverage_fingerprint_sha256"] != chk["zero_fingerprint"]:
        return "FINGERPRINT_NOT_PLACEHOLDER"
    try:
        wave1.validate_programming_snapshot_payload_v1({"schema_version": out["schema_version"], "scope_readiness": scopes,
                                                       "material_front_coverage": cov, "scope_front_matrix": mat,
                                                       "package_readiness": out["package_readiness"]})
    except (wave1.ContractError, KeyError, TypeError, AttributeError) as exc:
        return "SNAPSHOT_VALIDATOR:" + str(exc)
    if {s["scope_id"] for s in scopes} != sc7:
        return "SCOPE_SET_MISMATCH"
    if {f["front_id"] for f in cov["material_fronts"]} != set(fr7) or set(cov["front_candidate_refs"]) != set(fr7):
        return "FRONT_SET_MISMATCH"
    for f in cov["material_fronts"]:
        a = fr7[f["front_id"]]
        if f["status"] != a["obligation_mode"] or f["closure"] != a["closure"]:
            return "FRONT_STATUS_MISMATCH"
        if set(f["blockers"]) != set(a["blockers"]) or len(f["blockers"]) != len(set(f["blockers"])):
            return "FRONT_BLOCKERS_MISMATCH"
        if set(f["scope_refs"]) != set(a["scope_ids"]):
            return "FRONT_SCOPE_REFS_MISMATCH"
        if f["authority_refs"] != [] or f["currentness_refs"] != []:
            return "AUTHORITY_OR_CURRENTNESS_INVENTED"
        if not (_set(f["source_signal_refs"], ok) and _set(f["evidence_refs"], ok) and f["evidence_refs"]):
            return "FRONT_REFS_INVALID"
        if not isinstance(f["reason"], str) or len(f["reason"].strip()) < 20 or not isinstance(f["front_kind"], str) or not f["front_kind"].strip():
            return "FRONT_TEXT"
    for s in scopes:
        if s["status"] not in chk["scope_status"]:
            return "SCOPE_READY_OR_INVALID_STATUS"
        if s["depends_on_scope_ids"] != []:
            return "SCOPE_DEPENDENCY_INVENTED"
        containing = {i for i, a in fr7.items() if s["scope_id"] in a["scope_ids"]}
        if set(s["material_front_refs"]) != containing:
            return "SCOPE_FRONT_REFS_MISMATCH"
        if set(s["blockers"]) != set().union(*(fr7[i]["blockers"] for i in containing)) or len(s["blockers"]) != len(set(s["blockers"])):
            return "SCOPE_BLOCKERS_MISMATCH"
    if any(m["effect_on_scope"] != "BLOCKS" for m in mat):
        return "MATRIX_EFFECT_NOT_BLOCKS"
    if not (_set(cov["unmapped_material_signals"], ok) and _set(cov["source_refs"], ok) and cov["source_refs"] and cov["currentness_refs"] == []):
        return "COVERAGE_REFS_INVALID"
    st = out["snapshot_statement"]
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

#!/usr/bin/env python3
"""A1Q_C2 frozen GPT Native packet: build, and check what GPT returns. Never calls a model.

build_packet() is deterministic (no clock, no randomness). intake() validates a RAW REQUEST_CONTEXT_V1
returned by a GPT Native chat with the existing validate_request_context plus deterministic checks for
"no solution inferred" and "ambiguity retained", then delegates binding checks to the equivalent-tier
verifier. A passing result is tier OWNER_APPROVED_GPT_NATIVE_IN_CHAT_EQUIVALENT: not provider-attested.
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
import validate_wave1_boundary_contracts_v1 as wave1  # noqa: E402

SCHEMA = "ANALYSIS_GPT_NATIVE_PACKET_V1"
UNIT, CP = "A1", "C2"
REQUEST_REF = "REQ-LF-A1Q-C2-PILOT-0001"
INPUT_LITERAL = (
    "Los clientes del marketplace deberían poder ver cuánto les ahorra negociar su deuda antes de "
    "aceptar una oferta. Hoy no lo entienden y abandonan. Que quede claro y que no se confunda con "
    "el monto de la cuota. Es urgente para el piloto."
)
SKILL = "profiles/programming_analysis_lf/SKILL.md"
MIN_OPEN_AMBIGUITIES = 3
# Solution vocabulary absent from the input; its presence in the output means a solution was inferred.
FORBIDDEN_SOLUTION = [r"\bredis\b", r"\bkafka\b", r"\bpostgres\w*", r"\breact\b", r"\bsql\b", r"\bapi\b",
                      r"\bendpoint\b", r"\btrigger\b", r"\bmigraci\w+", r"\bmicroservic\w+", r"\brpc\b",
                      r"\bedge function\b", r"\btabla\b", r"\bbase de datos\b", r"\bcomponente\b"]
KEYS = ["schema_version", "request_identity", "objective", "target_hints", "source_refs",
        "provided_facts", "constraints", "ambiguities", "no_solution_inferred"]


def jsha(value) -> str:
    data = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(data).hexdigest()


def prompt_text() -> str:
    return (
        "Eres el productor de la etapa A1 (normalización) del perfil de análisis. Normaliza la solicitud "
        "literal de abajo. No infieras ninguna solución técnica ni identidad de historia. Conserva como "
        "ambigüedad todo lo que la solicitud no define. Devuelve SOLO un objeto JSON, sin texto adicional, "
        "con exactamente estas claves: " + ", ".join(KEYS) + ". schema_version='REQUEST_CONTEXT_V1'. "
        "request_identity={request_ref (usa '" + REQUEST_REF + "'), request_kind (USER_REQUEST|SYSTEM_REQUEST|"
        "ISSUE|HANDOFF|FILE|EVENT|OTHER)}. objective={problem_statement, desired_outcome} (textos no vacíos). "
        "ambigüedades: lista de {code, statement, materiality (MATERIAL|NON_MATERIAL|UNKNOWN), "
        "resolution_state (OPEN|RESOLVED_FROM_SOURCE)}. no_solution_inferred=true.\n\nSOLICITUD LITERAL:\n"
        + INPUT_LITERAL)


def build_packet(root: Path = REPO) -> dict:
    skill_bytes = (root / SKILL).read_bytes()
    packet = {
        "schema": SCHEMA, "subject_ref": eq.subject(UNIT, CP), "unit": UNIT, "checkpoint": CP,
        "stage_output_selector": UNIT, "producer_mode": "GPT_NATIVE", "evidence_tier": eq.TIER,
        "run_id": "A1Q_C2-GPTN-PILOT-0001",
        "input": {"request_ref": REQUEST_REF, "input_literal": INPUT_LITERAL,
                  "input_sha256": hashlib.sha256(INPUT_LITERAL.encode("utf-8")).hexdigest()},
        "profile_source": {"ref": SKILL, "sha256": hashlib.sha256(skill_bytes).hexdigest()},
        "output_contract": {"schema": "REQUEST_CONTEXT_V1", "required_keys": KEYS,
                            "validator": "validate_wave1_boundary_contracts_v1.py::validate_request_context"},
        "deterministic_checks": {"request_ref_equals": REQUEST_REF, "no_solution_inferred_true": True,
                                 "min_open_ambiguities": MIN_OPEN_AMBIGUITIES,
                                 "forbidden_solution_patterns": FORBIDDEN_SOLUTION},
        "prompt_for_gpt": prompt_text(),
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
    """Deterministic A1 checks. Returns an error code or None."""
    checks = packet["deterministic_checks"]
    try:
        wave1.validate_request_context(out)
    except (wave1.ContractError, KeyError, TypeError, AttributeError) as exc:
        return "CONTRACT:" + str(exc)
    if out["request_identity"]["request_ref"] != checks["request_ref_equals"]:
        return "REQUEST_REF_MISMATCH"
    open_amb = [a for a in out["ambiguities"] if a["resolution_state"] == "OPEN"]
    if len(open_amb) < checks["min_open_ambiguities"]:
        return "AMBIGUITY_NOT_RETAINED"
    text = json.dumps(out, ensure_ascii=False).lower()
    for pat in checks["forbidden_solution_patterns"]:
        if re.search(pat, text) and not re.search(pat, packet["input"]["input_literal"].lower()):
            return "SOLUTION_INFERRED"
    return None


def intake(packet: dict, raw_bytes: bytes, chat_ref: str, chat_sha256: str, approval_doc_sha256: str):
    """Return (verdict, record). verdict is eq.PASS_C2 or BLOCK:<code>."""
    bad = _check_packet(packet)
    if bad:
        return "BLOCK:" + bad, None
    try:
        out = json.loads(raw_bytes.decode("utf-8"))
    except (ValueError, UnicodeDecodeError):
        return "BLOCK:RAW_NOT_JSON", None
    if not isinstance(out, dict):
        return "BLOCK:RAW_NOT_OBJECT", None
    err = semantic_checks(packet, out)
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
    verdict, rec = intake(json.loads(a.packet.read_text(encoding="utf-8")), a.raw.read_bytes(),
                          a.chat_ref, a.chat_sha256, approval)
    if rec:
        a.output.write_text(json.dumps(rec, ensure_ascii=False, sort_keys=True, indent=2) + "\n", encoding="utf-8")
    print(verdict)
    sys.exit(0 if rec else 1)


if __name__ == "__main__":
    main()

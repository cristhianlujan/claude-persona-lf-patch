#!/usr/bin/env python3
"""Shared mechanics for the per-unit GPT Native C2 packets (A5 onward). Never calls a model.

A unit module supplies: UNIT, OUT_SCHEMA, KEYS, the frozen input (file + sha), the prompt text, the
deterministic_checks dict and a semantic_checks(packet, out) function returning an error code or None.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

import analysis_qualification_gpt_native_equivalent_v1 as eq
import analysis_qualification_a1q_c2_gpt_native_packet_v1 as a1

SCHEMA = "ANALYSIS_GPT_NATIVE_PACKET_V1"
REPO = Path(__file__).resolve().parent.parents[3]
SKILL = a1.SKILL
jsha = a1.jsha


def load_frozen(path: Path, sha256: str, label: str) -> dict:
    data = path.read_bytes()
    if hashlib.sha256(data.rstrip(b"\n")).hexdigest() != sha256:
        raise SystemExit(label + "_INPUT_FILE_DRIFT")
    return json.loads(data.decode("utf-8"))


def build(unit: str, out_schema: str, keys: list, input_obj: dict, input_origin: str, request_ref: str,
          prompt_for, checks: dict, validator_ref: str, root: Path = REPO) -> dict:
    ctx_text = json.dumps(input_obj, ensure_ascii=False, sort_keys=True, indent=2)
    skill_bytes = (root / SKILL).read_bytes()
    packet = {
        "schema": SCHEMA, "subject_ref": eq.subject(unit, "C2"), "unit": unit, "checkpoint": "C2",
        "stage_output_selector": unit, "producer_mode": "GPT_NATIVE", "evidence_tier": eq.TIER,
        "run_id": unit + "Q_C2-GPTN-PILOT-0001",
        "input": {"request_ref": request_ref, "input_literal": ctx_text,
                  "input_sha256": hashlib.sha256(ctx_text.encode("utf-8")).hexdigest(), "input_origin": input_origin},
        "profile_source": {"ref": SKILL, "sha256": hashlib.sha256(skill_bytes).hexdigest()},
        "output_contract": {"schema": out_schema, "required_keys": keys, "validator": validator_ref},
        "deterministic_checks": checks,
        "prompt_for_gpt": prompt_for(ctx_text),
        "owner_approval_doc": eq.APPROVAL_DOC, "limits": eq.limits(),
    }
    packet["request_sha256"] = jsha({k: packet[k] for k in ("subject_ref", "input", "profile_source",
                                                           "output_contract", "prompt_for_gpt")})
    packet["packet_sha256"] = jsha({k: v for k, v in packet.items() if k != "packet_sha256"})
    return packet


def check_packet(packet) -> str | None:
    if not isinstance(packet, dict) or packet.get("schema") != SCHEMA:
        return "PACKET_SCHEMA_INVALID"
    if jsha({k: v for k, v in packet.items() if k != "packet_sha256"}) != packet.get("packet_sha256"):
        return "PACKET_TAMPERED"
    return None


def intake(unit: str, semantic_checks, packet: dict, raw_bytes: bytes, chat_ref: str, chat_sha256: str,
           approval_doc_sha256: str):
    bad = check_packet(packet)
    if bad:
        return "BLOCK:" + bad, None
    try:
        out = json.loads(raw_bytes.decode("utf-8"))
    except (ValueError, UnicodeDecodeError):
        return "BLOCK:RAW_NOT_JSON", None
    if not isinstance(out, dict):
        return "BLOCK:RAW_NOT_OBJECT", None
    try:
        err = semantic_checks(packet, out)
    except (KeyError, TypeError, AttributeError):
        err = "SHAPE_INVALID"
    if err:
        return "BLOCK:" + err, None
    record = {
        "schema": eq.CAPTURE_SCHEMA, "subject_ref": packet["subject_ref"], "stage_output_selector": unit,
        "evidence_tier": eq.TIER, "producer_mode": "GPT_NATIVE", "runtime_provider_attested": False,
        "transcript_is_provider_evidence": False, "run_id": packet["run_id"],
        "owner_approval_ref": eq.APPROVAL_DOC + "@" + approval_doc_sha256,
        "owner_approval_doc_sha256": approval_doc_sha256,
        "chat_transcript_ref": chat_ref, "chat_transcript_sha256": chat_sha256,
        "input_sha256": packet["input"]["input_sha256"], "request_sha256": packet["request_sha256"],
        "raw_output_sha256": hashlib.sha256(raw_bytes).hexdigest(),
    }
    verdict = eq.attest_c2(record, unit, packet["input"]["input_literal"].encode("utf-8"), raw_bytes)
    return verdict, (record if verdict == eq.PASS_C2 else None)


def cli(unit: str, build_packet, intake_fn) -> None:
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
    verdict, rec = intake_fn(json.loads(a.packet.read_text(encoding="utf-8")), a.raw.read_bytes(), a.chat_ref, a.chat_sha256, approval)
    if rec:
        a.output.write_text(json.dumps(rec, ensure_ascii=False, sort_keys=True, indent=2) + "\n", encoding="utf-8")
    print(verdict)
    sys.exit(0 if rec else 1)

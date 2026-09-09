#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
from pathlib import Path


def load(path: str):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def fail(code: str):
    print(code)
    raise SystemExit(1)


if len(sys.argv) != 7:
    fail("REAL_REPLAY_ARGC_INVALID")

artifact = load(sys.argv[1])
input_text = Path(sys.argv[2]).read_text(encoding="utf-8")
execution_receipt = load(sys.argv[3])
input_governance = load(sys.argv[4])
card_text = Path(sys.argv[5]).read_text(encoding="utf-8")
authority_text = Path(sys.argv[6]).read_text(encoding="utf-8")

deliverable = artifact.get("deliverable_created")
if not isinstance(deliverable, dict):
    fail("REAL_ARTIFACT_DELIVERABLE_MISSING")
governance = deliverable.get("governance_context")
if not isinstance(governance, dict):
    fail("REAL_ARTIFACT_GOVERNANCE_MISSING")
screen = deliverable.get("screen_definition")
if not isinstance(screen, dict) or screen.get("screen_code") != "B2B-CARGA-001":
    fail("REAL_ARTIFACT_SCREEN_MISMATCH")

execution_id = execution_receipt.get("execution_id")
if not isinstance(execution_id, str) or governance.get("execution_id") != execution_id:
    fail("REAL_EXECUTION_LINEAGE_MISMATCH")
if execution_receipt.get("raw_output_captured") is not True:
    fail("REAL_RECEIPT_RAW_OUTPUT_NOT_CAPTURED")
if execution_receipt.get("profile_code") != "PERFIL-UI-ARCHITECT":
    fail("REAL_RECEIPT_PROFILE_MISMATCH")
if artifact.get("worker") != "ui_architect":
    fail("REAL_ARTIFACT_WORKER_MISMATCH")

if len(input_text.strip()) < 100:
    fail("REAL_INPUT_TOO_SMALL")
if not isinstance(input_governance, dict) or not input_governance:
    fail("REAL_INPUT_GOVERNANCE_MISSING")
if "CARD_MARKETPLACE_LF_DECISIONES_PRODUCTO_EXPERIENCIA" not in card_text:
    fail("REAL_CARD_AUTHORITY_MISMATCH")
if "UI Architect" not in authority_text and "ui_architect" not in authority_text.lower():
    fail("REAL_PROFILE_AUTHORITY_MISMATCH")

print(json.dumps({
    "status": "PASS",
    "execution_id": execution_id,
    "screen_code": screen["screen_code"],
    "worker": artifact.get("worker"),
    "source": "FROZEN_BUNDLE_ONLY"
}, sort_keys=True))

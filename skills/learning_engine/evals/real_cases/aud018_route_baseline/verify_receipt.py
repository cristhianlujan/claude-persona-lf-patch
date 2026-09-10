from __future__ import annotations

import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent

FILES = {
    "source_sha256": "case_input.json",
    "router_invocation_sha256": "router_invocation.json",
    "configuration_sha256": "configuration.json",
    "evidence_sha256": "router_actual_output.json",
}

receipt = json.loads((ROOT / "execution_receipt.json").read_text(encoding="utf-8"))

errors = []
for field, filename in FILES.items():
    observed = hashlib.sha256((ROOT / filename).read_bytes()).hexdigest()
    expected = receipt.get(field)
    if observed != expected:
        errors.append(f"{field}: expected={expected} observed={observed}")

actual = json.loads((ROOT / "router_actual_output.json").read_text(encoding="utf-8"))
if receipt.get("executed") is not True:
    errors.append("executed must be true")
if receipt.get("exit_code") != 0:
    errors.append("exit_code must be 0")
if receipt.get("result") != actual.get("status"):
    errors.append("receipt result must equal actual router status")
if receipt.get("blocking_code") != actual.get("blocking_code"):
    errors.append("receipt blocking_code must equal actual output")
if receipt.get("claim_ceiling") != "ROUTER_BASELINE_ONLY_LEARNING_ENGINE_NOT_EXECUTED":
    errors.append("claim ceiling changed")
if receipt.get("no_write_performed_on_supabase") is not True:
    errors.append("Supabase no-write claim missing")
if receipt.get("no_s30_mutation") is not True or receipt.get("no_s26_mutation") is not True:
    errors.append("cross-project mutation boundary missing")

if errors:
    print("MOTOR_AUD018_BASELINE_RECEIPT_FAIL")
    for error in errors:
        print(error)
    raise SystemExit(1)

print("MOTOR_AUD018_BASELINE_RECEIPT_PASS")

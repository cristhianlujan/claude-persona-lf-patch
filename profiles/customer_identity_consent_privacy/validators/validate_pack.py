#!/usr/bin/env python3
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REQUIRED = [
    "README.md", "SKILL.md", "contracts/main_contract.md", "contracts/input_governance_binding.json",
    "schemas/output.schema.json", "judges/score_rubric.md", "judges/mini_judge.md",
    "examples/good_output.json", "examples/bad_output.json", "evals/eval_matrix.json",
    "handoffs/to_quality_pack.handoff.json", "manifest.json"
]
TRIGGERS = {"input_not_governed_by_adapter","cross_adapter_conflict","profile_specific_constraint","authority_or_policy_uncertainty","critical_input_validation"}

def fail(code):
    raise SystemExit(f"CUSTOMER_IDENTITY_CONSENT_PRIVACY_FAIL:{code}")

for rel in REQUIRED:
    if not (ROOT / rel).is_file():
        fail(f"MISSING:{rel}")

schema = json.loads((ROOT / "schemas/output.schema.json").read_text())
expected_modes = {"CUSTOMER_IDENTITY_CONSENT_PRIVACY_SPEC","MISSING_IDENTITY_OR_CONSENT_AUTHORITY","BLOCKED_OVER_COLLECTION_OR_UNAUTHORIZED_USE","BLOCKED_INVALID_CONSENT_PATTERN"}
if set(schema["properties"]["output_type"]["enum"]) != expected_modes:
    fail("OUTPUT_ENUM_MISMATCH")

binding = json.loads((ROOT / "contracts/input_governance_binding.json").read_text())
if binding.get("mode") != "selective" or binding.get("entrypoint") != "router_only":
    fail("INPUT_GOVERNANCE_NOT_SELECTIVE_ROUTER_ONLY")
if set(binding.get("allowed_triggers", [])) != TRIGGERS:
    fail("INPUT_GOVERNANCE_TRIGGER_SET_MISMATCH")
if not binding.get("adapter_receipt_precedence") or not binding.get("duplicate_checks_forbidden"):
    fail("ADAPTER_RECEIPT_PRECEDENCE_MISSING")
if binding.get("outcomes", {}).get("BLOCK") != "fail_closed" or not binding.get("receipt_required"):
    fail("INPUT_GOVERNANCE_FAIL_CLOSED_MISSING")

manifest = json.loads((ROOT / "manifest.json").read_text())
if manifest.get("profile_code") != "CUSTOMER_IDENTITY_CONSENT_PRIVACY":
    fail("PROFILE_IDENTITY_MISMATCH")
if manifest.get("runtime_enabled") is not False or manifest.get("automatic_promotion") is not False:
    fail("RUNTIME_OR_AUTOPROMOTION_NOT_BLOCKED")
if not set(REQUIRED).issubset(set(manifest.get("required_files", []))):
    fail("MANIFEST_REQUIRED_FILES_INCOMPLETE")

evals = json.loads((ROOT / "evals/eval_matrix.json").read_text())
case_types = {c.get("type") for c in evals.get("cases", [])}
for needed in {"positive","negative","adversarial","equivalence","handoff"}:
    if needed not in case_types:
        fail(f"EVAL_COVERAGE_MISSING:{needed}")

bad = json.loads((ROOT / "examples/bad_output.json").read_text())
if bad["consent_items"][0]["affirmative_action"] != "prechecked checkbox":
    fail("NEGATIVE_FIXTURE_CONSENT_DEFECT_REMOVED")
if bad["identity_assurance"].get("authority_refs") != []:
    fail("NEGATIVE_FIXTURE_AUTHORITY_DEFECT_REMOVED")

skill = (ROOT / "SKILL.md").read_text().lower()
for token in ["data minimization", "never infer consent", "optional consent", "ui architect", "gamification system architect"]:
    if token not in skill:
        fail(f"SKILL_GUARD_MISSING:{token}")

print("CUSTOMER_IDENTITY_CONSENT_PRIVACY_PACK_PASS")

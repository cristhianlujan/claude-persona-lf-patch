#!/usr/bin/env python3
"""Generic pre-research baseline -> incremental-value proof regressions."""

import copy
import json
import runpy
import sys
from pathlib import Path

from jsonschema import Draft7Validator

ROOT = Path(__file__).resolve().parents[1]
VALIDATORS = ROOT / "validators"
sys.path.insert(0, str(VALIDATORS))

import incremental_value
import runtime_validate
import runtime_semantic_utility

fixture = runpy.run_path(str(ROOT / "evals" / "v03_deterministic_floor_cases.py"))
valid_pair = fixture["valid_pair"]
rebind = fixture["rebind"]
RUNTIME_SCHEMA = json.loads((ROOT / "schemas" / "runtime_output.schema.json").read_text())
runtime_schema_validator = Draft7Validator(RUNTIME_SCHEMA)


def assert_code(result, code, label):
    assert result["status"] == "FAIL", (label, result)
    assert code in result["blocking_codes"], (label, code, result["blocking_codes"])


def drop_incremental(candidate):
    x = copy.deepcopy(candidate)
    for key in (
        "baseline_solution_snapshot",
        "baseline_digest",
        "discovery_deltas",
        "incremental_value_outcome",
        "incremental_value_rationale",
    ):
        x["research_assurance"].pop(key, None)
    return x


# 1. Canonical DEEP fixture carries a digest-coherent proof and remains valid.
deep, manifest = valid_pair()
gate = runtime_validate.validate(deep, manifest)
assert gate["status"] == "PASS", gate
summary = gate["incremental_value_summary"]
assert summary["applies"] is True
assert summary["outcome"] == "MATERIAL_UPLIFT"
assert summary["adopted_delta_ids"] == ["DELTA-JIT-CONTEXT", "DELTA-INDEPENDENT-EVAL"]
assert summary["packet_estimated_tokens"] <= summary["soft_limit_tokens"]
assert runtime_semantic_utility.evaluate(deep, gate, manifest)["status"] == "PASS"

# 2. LIGHTWEIGHT is exempt; no proof is forced onto simple defects.
light, light_manifest = valid_pair()
light = drop_incremental(light)
light["solution_depth"]["mode"] = "LIGHTWEIGHT"
light["research_assurance"]["current_practice_research_required"] = False
light, light_manifest = rebind(light, light_manifest)
light_gate = runtime_validate.validate(light, light_manifest)
assert light_gate["status"] == "PASS", light_gate
assert light_gate["incremental_value_summary"]["applies"] is False

# 3. DEEP ready spec without baseline/delta proof fails closed.
missing, missing_manifest = valid_pair()
missing = drop_incremental(missing)
missing, missing_manifest = rebind(missing, missing_manifest)
assert_code(runtime_validate.validate(missing, missing_manifest), "SRCR_INCREMENTAL_VALUE_PROOF_REQUIRED", "deep_proof_required")

# 4. Baseline digest cannot be rewritten after the fact.
tampered, tampered_manifest = valid_pair()
tampered["research_assurance"]["baseline_solution_snapshot"]["leading_solution_summary"] += " silently changed"
tampered, tampered_manifest = rebind(tampered, tampered_manifest)
assert_code(runtime_validate.validate(tampered, tampered_manifest), "SRCR_INCREMENTAL_VALUE_BASELINE_DIGEST_MISMATCH", "baseline_digest")

# 5. Later external-research refs cannot be backfilled into the pre-research baseline.
leak, leak_manifest = valid_pair()
leak_baseline = leak["research_assurance"]["baseline_solution_snapshot"]
leak_baseline["evidence_refs"].append("external://current-practice/jit-context")
leak["research_assurance"]["baseline_digest"] = incremental_value.canonical_baseline_digest(leak_baseline)
leak, leak_manifest = rebind(leak, leak_manifest)
assert_code(runtime_validate.validate(leak, leak_manifest), "SRCR_INCREMENTAL_VALUE_BASELINE_EXTERNAL_RESEARCH_LEAK", "baseline_contamination")

# 6. MATERIAL_UPLIFT requires at least one adopted evidence-triggered delta.
no_adopt, no_adopt_manifest = valid_pair()
for row in no_adopt["research_assurance"]["discovery_deltas"]:
    row["disposition"] = "REJECTED"
no_adopt, no_adopt_manifest = rebind(no_adopt, no_adopt_manifest)
assert_code(runtime_validate.validate(no_adopt, no_adopt_manifest), "SRCR_INCREMENTAL_VALUE_UPLIFT_WITHOUT_ADOPTED_DELTA", "uplift_without_delta")

# 7. NO_MATERIAL_UPLIFT is a valid result when research finds no adopted material delta.
no_uplift, no_uplift_manifest = valid_pair()
for row in no_uplift["research_assurance"]["discovery_deltas"]:
    row["disposition"] = "REJECTED"
no_uplift["research_assurance"]["incremental_value_outcome"] = "NO_MATERIAL_UPLIFT"
no_uplift["research_assurance"]["incremental_value_rationale"] = "Research completed and no evidence-supported material improvement over the frozen baseline remained after challenge."
no_uplift, no_uplift_manifest = rebind(no_uplift, no_uplift_manifest)
no_uplift_gate = runtime_validate.validate(no_uplift, no_uplift_manifest)
assert no_uplift_gate["status"] == "PASS", no_uplift_gate
assert no_uplift_gate["incremental_value_summary"]["adopted_delta_ids"] == []

# 8. NO_MATERIAL_UPLIFT cannot hide an adopted delta.
false_none, false_none_manifest = valid_pair()
false_none["research_assurance"]["incremental_value_outcome"] = "NO_MATERIAL_UPLIFT"
false_none, false_none_manifest = rebind(false_none, false_none_manifest)
assert_code(runtime_validate.validate(false_none, false_none_manifest), "SRCR_INCREMENTAL_VALUE_NO_UPLIFT_WITH_ADOPTED_DELTA", "false_no_uplift")

# 9. UNPROVEN cannot close a ready material-research specification.
unproven, unproven_manifest = valid_pair()
unproven["research_assurance"]["incremental_value_outcome"] = "UNPROVEN"
unproven, unproven_manifest = rebind(unproven, unproven_manifest)
assert_code(runtime_validate.validate(unproven, unproven_manifest), "SRCR_INCREMENTAL_VALUE_UNPROVEN", "unproven_ready")

# 10. BOUNDED + current-practice research requires the same proof.
bounded, bounded_manifest = valid_pair()
bounded = drop_incremental(bounded)
bounded["solution_depth"]["mode"] = "BOUNDED"
bounded["research_assurance"]["current_practice_research_required"] = True
bounded, bounded_manifest = rebind(bounded, bounded_manifest)
assert_code(runtime_validate.validate(bounded, bounded_manifest), "SRCR_INCREMENTAL_VALUE_PROOF_REQUIRED", "bounded_research_proof")

# 11. BOUNDED without current-practice research does not pay the proof/context cost.
bounded_local, bounded_local_manifest = valid_pair()
bounded_local = drop_incremental(bounded_local)
bounded_local["solution_depth"]["mode"] = "BOUNDED"
bounded_local["research_assurance"]["current_practice_research_required"] = False
bounded_local, bounded_local_manifest = rebind(bounded_local, bounded_local_manifest)
bounded_local_gate = runtime_validate.validate(bounded_local, bounded_local_manifest)
assert bounded_local_gate["status"] == "PASS", bounded_local_gate
assert bounded_local_gate["incremental_value_summary"]["applies"] is False

# 12. Adopted delta must contain post-baseline evidence, not only baseline refs.
stale_delta, stale_manifest = valid_pair()
stale_delta["research_assurance"]["discovery_deltas"][0]["trigger_evidence_refs"] = ["gate://A2R_PARITY"]
stale_delta, stale_manifest = rebind(stale_delta, stale_manifest)
assert_code(runtime_validate.validate(stale_delta, stale_manifest), "SRCR_INCREMENTAL_VALUE_DELTA_NOT_POST_BASELINE", "post_baseline_trigger")

# 13. Compact proof packet has a hard context budget.
large, large_manifest = valid_pair()
large["research_assurance"]["discovery_deltas"][0]["material_effect"] = "x" * 12000
large, large_manifest = rebind(large, large_manifest)
assert_code(runtime_validate.validate(large, large_manifest), "SRCR_INCREMENTAL_VALUE_CONTEXT_BUDGET_EXCEEDED", "context_budget")

# 14. Provider constraint rejects an invalid outcome before canonical validation.
provider_bad = copy.deepcopy(deep)
provider_bad["research_assurance"]["incremental_value_outcome"] = "WOW"
assert list(runtime_schema_validator.iter_errors(provider_bad))

# 15. Provider constraint rejects a noncanonical baseline capture stage.
provider_stage = copy.deepcopy(deep)
provider_stage["research_assurance"]["baseline_solution_snapshot"]["capture_stage"] = "POST_RESEARCH"
assert list(runtime_schema_validator.iter_errors(provider_stage))

print("PASS_SRCR_V03_INCREMENTAL_VALUE=15/15")

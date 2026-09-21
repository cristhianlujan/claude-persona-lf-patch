#!/usr/bin/env python3
import json
import subprocess
import sys
from pathlib import Path

REQUIRED = [
    "README.md","SKILL.md","contracts/main_contract.md","schemas/output.schema.json",
    "judges/mini_judge.md","evals/eval_matrix.json","manifest.json",
    "judges/score_rubric.md","examples/good_output.json","examples/bad_output.json",
    "validators/validate_pack.py","handoffs/to_quality_pack.handoff.json",
    "contracts/evidence_manifest.schema.json","contracts/closure_vocabulary.v2.json",
    "schemas/quality_receipt.schema.json","schemas/runtime_output.schema.json",
    "validators/closure_proof.py","validators/runtime_validate.py",
    "validators/runtime_semantic_utility.py","validators/validate_quality_receipt.py",
    "evals/v03_contract_schema_cases.py","evals/v03_deterministic_floor_cases.py",
    "evals/v03_quality_receipt_cases.py","evals/v03_generalization_property_cases.py",
    "evals/v03_original_escape_replay.py","evals/v03_transversal_contract_cases.py"
]

def fail(code):
    print(code)
    raise SystemExit(1)

root = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
for rel in REQUIRED:
    p = root / rel
    if not p.is_file() or not p.read_text(encoding="utf-8").strip():
        fail("MISSING_OR_EMPTY:" + rel)

schema = json.loads((root/"schemas/output.schema.json").read_text())
if schema.get("additionalProperties") is not False:
    fail("SCHEMA_NOT_STRICT")
required = set(schema.get("required", []))
for key in ["systemic_root_cause","first_bad_control","alternatives","falsification_results","hard_guard","historical_regressions","evidence_map"]:
    if key not in required:
        fail("SCHEMA_REQUIRED_KEY_MISSING:" + key)

evals = json.loads((root/"evals/eval_matrix.json").read_text())
cases = evals.get("cases", [])
if len(cases) < 10:
    fail("EVAL_DEPTH_INSUFFICIENT")
expected = {c.get("expected") for c in cases}
for status in ["SYSTEMIC_REPAIR_SPEC","NEEDS_MORE_EVIDENCE","RETURN_TO_WORKER_FOR_SELF_REPAIR","BLOCK_PIPELINE"]:
    if status not in expected:
        fail("EVAL_STATUS_MISSING:" + status)

good = json.loads((root/"examples/good_output.json").read_text())
if len(good.get("alternatives", [])) < 3:
    fail("GOOD_EXAMPLE_ALTERNATIVES_INSUFFICIENT")
if len(good.get("falsification_results", [])) < 7:
    fail("GOOD_EXAMPLE_FALSIFICATION_INSUFFICIENT")
if good.get("symptom") == good.get("systemic_root_cause"):
    fail("GOOD_EXAMPLE_CAUSAL_COLLAPSE")

bad = json.loads((root/"examples/bad_output.json").read_text())
if "systemic_root_cause" in bad and "alternatives" in bad:
    fail("BAD_EXAMPLE_NOT_BAD_ENOUGH")

skill = (root/"SKILL.md").read_text()
for token in ["FIRST BAD CONTROL","FALSIFICATION","minimum sufficient","fail closed","residual"]:
    if token.lower() not in skill.lower():
        fail("SKILL_RULE_MISSING:" + token)

def run_assurance(rel):
    script = root / rel
    proc = subprocess.run(
        [sys.executable, str(script)],
        cwd=str(root.parent.parent),
        text=True,
        capture_output=True,
        check=False,
    )
    if proc.returncode != 0:
        if proc.stdout:
            print(proc.stdout.rstrip())
        if proc.stderr:
            print(proc.stderr.rstrip())
        fail("V03_ASSURANCE_FAILED:" + rel)
    lines = [line for line in proc.stdout.splitlines() if line.strip()]
    if lines:
        print(lines[-1])

for rel in [
    "evals/v03_contract_schema_cases.py",
    "evals/v03_deterministic_floor_cases.py",
    "evals/v03_quality_receipt_cases.py",
    "evals/v03_generalization_property_cases.py",
    "evals/v03_transversal_contract_cases.py",
    "evals/sandbox_b/run_cases.py",
]:
    run_assurance(rel)

print("PASS_SYSTEMIC_ROOT_CAUSE_REPAIR_PACK")

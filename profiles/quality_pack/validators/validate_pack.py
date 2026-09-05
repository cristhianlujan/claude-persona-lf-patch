#!/usr/bin/env python3
import json
import subprocess
import sys
from pathlib import Path

REQUIRED = [
    "SKILL.md",
    "contracts/quality_gate_contract.md",
    "evals/quality_gate_adversarial.py",
    "evals/existing_artifact_remediation_adversarial.py",
    "judges/quality_pack_mini_judge.md",
    "schemas/quality_review.schema.json",
    "schemas/runtime_output.schema.json",
    "validators/trusted_ref_resolver.py",
    "validators/validate_gate_bundle.py",
    "validators/validate_routing.py",
    "validators/validate_pack.py",
]


def run_json_eval(root, rel, failure_code, min_cases):
    run = subprocess.run(
        [sys.executable, str(root / rel)],
        cwd=root,
        text=True,
        capture_output=True,
    )
    if run.stdout:
        print(run.stdout, end="" if run.stdout.endswith("\n") else "\n")
    if run.stderr:
        print(run.stderr, end="" if run.stderr.endswith("\n") else "\n", file=sys.stderr)
    blocking = []
    if run.returncode != 0:
        blocking.append(failure_code)
        return blocking
    try:
        summary = json.loads(run.stdout)
        if summary.get("passed") is not True:
            blocking.append(failure_code.replace("_FAILED", "_NOT_PASS"))
        if int(summary.get("case_count", 0)) < min_cases:
            blocking.append(failure_code.replace("_FAILED", "_CASE_COUNT_TOO_LOW"))
        digest = summary.get("results_sha256")
        if not isinstance(digest, str) or len(digest) != 64:
            blocking.append(failure_code.replace("_FAILED", "_DIGEST_MISSING"))
    except Exception as exc:
        blocking.append(failure_code.replace("_FAILED", "_OUTPUT_INVALID:") + type(exc).__name__)
    return blocking


def main():
    root = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path.cwd().resolve()
    blocking = []

    for rel in REQUIRED:
        if not (root / rel).exists():
            blocking.append("MISSING_REQUIRED_FILE:" + rel)

    if not blocking:
        canonical_schema = root / "schemas/quality_review.schema.json"
        runtime_schema = root / "schemas/runtime_output.schema.json"
        if runtime_schema.read_bytes() != canonical_schema.read_bytes():
            blocking.append("RUNTIME_OUTPUT_SCHEMA_DRIFT")

    if not blocking:
        blocking.extend(run_json_eval(root, "evals/quality_gate_adversarial.py", "QUALITY_GATE_ADVERSARIAL_EVAL_FAILED", 21))
        blocking.extend(run_json_eval(root, "evals/existing_artifact_remediation_adversarial.py", "EXISTING_ARTIFACT_REMEDIATION_EVAL_FAILED", 11))

    result = {
        "status": "PASS" if not blocking else "FAIL",
        "profile_pack_id": "QUALITY_PACK_GATE_001",
        "blocking_codes": blocking,
        "runtime_authorized": False,
        "automatic_impact_authorized": False,
        "recommended_action": "READY_FOR_GOVERNED_QUALITY_USE" if not blocking else "RETURN_TO_WORKER_FOR_SELF_REPAIR",
    }
    print(json.dumps(result, indent=2))
    return 0 if not blocking else 1


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
import hashlib
import json


def evaluate(case):
    mode = case.get("mode")
    source_ref = case.get("source_artifact_ref")
    source_sha = case.get("source_image_sha256")
    dimensions = case.get("source_dimensions")
    visual_evidence = case.get("visual_evidence")
    authorized_delta = case.get("authorized_delta")
    shell_applies = case.get("shell_applies") is True
    shell_receipt = case.get("shell_adapter_receipt")
    downstream_authorized = case.get("downstream_authorized")
    outside_delta = case.get("outside_delta_changes", 0)
    shell_locked_mutations = case.get("shell_locked_mutations", 0)

    if mode == "CREATE_NEW":
        return "ALLOW_POLICY_NOT_APPLICABLE"
    if mode not in {"EVALUATE_EXISTING", "REMEDIATE_EXISTING"}:
        return "FAIL_CLOSED"
    if not source_ref or not source_sha or not dimensions or not visual_evidence:
        return "FAIL_CLOSED"
    if mode == "REMEDIATE_EXISTING" and not authorized_delta:
        return "FAIL_CLOSED"
    if shell_applies:
        if not isinstance(shell_receipt, dict):
            return "FAIL_CLOSED"
        if shell_receipt.get("source_image_sha256") != source_sha:
            return "FAIL_CLOSED"
    if downstream_authorized is True:
        return "FAIL_CLOSED"
    if outside_delta != 0 or shell_locked_mutations != 0:
        return "FAIL_CLOSED"
    return "ALLOW_PROFILE_REVIEW"


SHA = "a" * 64
BASE = {
    "source_artifact_ref": "artifact://screen/123",
    "source_image_sha256": SHA,
    "source_dimensions": {"width": 1440, "height": 900},
    "visual_evidence": [{"ref": "artifact://screen/123#region-main"}],
    "authorized_delta": [{"target_component_id": "cta-primary", "operation": "RESTYLE"}],
    "shell_applies": False,
    "downstream_authorized": False,
    "outside_delta_changes": 0,
    "shell_locked_mutations": 0,
}

cases = [
    ("C1_CREATE_NEW_NO_SOURCE", {"mode": "CREATE_NEW"}, "ALLOW_POLICY_NOT_APPLICABLE"),
    ("C2_EVAL_MISSING_SHA", {**BASE, "mode": "EVALUATE_EXISTING", "source_image_sha256": None}, "FAIL_CLOSED"),
    ("C3_EVAL_COMPLETE", {**BASE, "mode": "EVALUATE_EXISTING"}, "ALLOW_PROFILE_REVIEW"),
    ("C4_REMEDIATE_MISSING_DELTA", {**BASE, "mode": "REMEDIATE_EXISTING", "authorized_delta": []}, "FAIL_CLOSED"),
    ("C5_REMEDIATE_COMPLETE_NO_SHELL", {**BASE, "mode": "REMEDIATE_EXISTING"}, "ALLOW_PROFILE_REVIEW"),
    ("C6_SHELL_MISSING_RECEIPT", {**BASE, "mode": "REMEDIATE_EXISTING", "shell_applies": True, "shell_adapter_receipt": None}, "FAIL_CLOSED"),
    ("C7_SHELL_SHA_MISMATCH", {**BASE, "mode": "REMEDIATE_EXISTING", "shell_applies": True, "shell_adapter_receipt": {"source_image_sha256": "b" * 64}}, "FAIL_CLOSED"),
    ("C8_SHELL_SAME_SHA", {**BASE, "mode": "REMEDIATE_EXISTING", "shell_applies": True, "shell_adapter_receipt": {"source_image_sha256": SHA}}, "ALLOW_PROFILE_REVIEW"),
    ("C9_DOWNSTREAM_SELF_AUTH_FORBIDDEN", {**BASE, "mode": "REMEDIATE_EXISTING", "downstream_authorized": True}, "FAIL_CLOSED"),
    ("C10_OUTSIDE_DELTA_FORBIDDEN", {**BASE, "mode": "REMEDIATE_EXISTING", "outside_delta_changes": 1}, "FAIL_CLOSED"),
    ("C11_SHELL_LOCKED_MUTATION_FORBIDDEN", {**BASE, "mode": "REMEDIATE_EXISTING", "shell_locked_mutations": 1}, "FAIL_CLOSED"),
]

results = []
failed = False
for case_id, payload, expected in cases:
    observed = evaluate(payload)
    passed = observed == expected
    failed |= not passed
    results.append({"id": case_id, "expected": expected, "observed": observed, "passed": passed})

digest = hashlib.sha256(json.dumps(results, sort_keys=True).encode()).hexdigest()
print(json.dumps({"passed": not failed, "case_count": len(results), "results_sha256": digest, "results": results}, indent=2))
raise SystemExit(1 if failed else 0)

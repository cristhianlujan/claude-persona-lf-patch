#!/usr/bin/env python3
"""Produce GitHub-readback-bound positive/negative *fixture* validation evidence.

This executes the deployed generic output runner and canonical SRCR contracts.
It does NOT issue a Ledger receipt, authorize production, execute a model,
or treat historical examples as an evolved profile output.
"""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "skills/profile_creator/validators"))
from run_bound_profile_output_validator_v1 import validate_bound_output

SLUG = "systemic_root_cause_repair_lf"
BASE = Path("profiles") / SLUG
REFS = {
    "schema": BASE / "schemas/output.schema.json",
    "validator": BASE / "validators/runtime_validate.py",
    "runtime_binding": BASE / "contracts/runtime_binding.json",
    "positive_raw_output": BASE / "examples/good_output.json",
    "negative_raw_output": BASE / "examples/bad_output.json",
    "producer": Path("skills/profile_creator/evals/produce_pe10_c6_source_bound_output_evidence_v1.py"),
    "runner": Path("skills/profile_creator/validators/run_bound_profile_output_validator_v1.py"),
}
HEX40 = re.compile(r"^[a-f0-9]{40}$")


def canonical(value: object) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def digest(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def git(*args: str) -> bytes:
    return subprocess.check_output(
        ["git", "-C", str(ROOT), *args], stderr=subprocess.PIPE,
        timeout=30,
    ).strip()


def resolve_github_head() -> str:
    if os.environ.get("GITHUB_ACTIONS") != "true":
        raise ValueError("GITHUB_PROVIDER_RUN_REQUIRED")
    if os.environ.get("GITHUB_REPOSITORY") != "cristhianlujan/claude-persona-lf-patch":
        raise ValueError("GITHUB_PROVIDER_REPOSITORY_MISMATCH")
    if os.environ.get("GITHUB_EVENT_NAME") != "pull_request":
        raise ValueError("GITHUB_PR_PROVIDER_EVENT_REQUIRED")
    event_path = os.environ.get("GITHUB_EVENT_PATH")
    if not event_path:
        raise ValueError("GITHUB_PROVIDER_EVENT_PATH_MISSING")
    event = json.loads(Path(event_path).read_text(encoding="utf-8"))
    head = event.get("pull_request", {}).get("head", {}).get("sha")
    if not isinstance(head, str) or HEX40.fullmatch(head) is None:
        raise ValueError("GITHUB_PROVIDER_HEAD_INVALID")
    if event.get("pull_request", {}).get("head", {}).get("repo", {}).get("full_name") != os.environ["GITHUB_REPOSITORY"]:
        raise ValueError("GITHUB_FORK_UNTRUSTED_PRODUCER")
    # GitHub pull_request checkout is often a synthetic merge SHA, not head.
    # Fetch the exact provider-advertised HEAD and compare every consumed byte.
    subprocess.run(
        ["git", "-C", str(ROOT), "fetch", "--no-tags", "--depth=1", "origin", head],
        check=True, timeout=45, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    for rel in REFS.values():
        actual = (ROOT / rel).read_bytes()
        committed = subprocess.check_output(
            ["git", "-C", str(ROOT), "show", f"{head}:{rel.as_posix()}"],
            stderr=subprocess.PIPE, timeout=30,
        )
        if actual != committed:
            raise ValueError("PROFILE_OUTPUT_SOURCE_NOT_EXACT_PR_HEAD:" + rel.as_posix())
    return head


def packet(raw: Path, expected_valid: bool) -> dict:
    p = {
        "schema": "PROFILE_OUTPUT_VALIDATION_BINDING_V1",
        "operation_code": "ACTUALIZACION_PERFIL_LF",
        "profile_slug": SLUG,
        "validator_transport": "STDIN_JSON",
        "expected_valid": expected_valid,
        "runtime_binding_sha256": digest((ROOT / REFS["runtime_binding"]).read_bytes()),
    }
    for name, source in (
        ("schema", REFS["schema"]),
        ("validator", REFS["validator"]),
        ("raw_output", raw),
    ):
        p[f"{name}_ref"] = source.as_posix()
        p[f"{name}_sha256"] = digest((ROOT / source).read_bytes())
    return p


def main() -> dict:
    head = resolve_github_head()
    positive = validate_bound_output(ROOT, packet(REFS["positive_raw_output"], True))
    negative = validate_bound_output(ROOT, packet(REFS["negative_raw_output"], False))
    if (positive["status"] != "CANDIDATE_OUTPUT_PARITY_OBSERVED"
        or positive.get("profile_validator_executed") is not True
        or positive.get("canonical_json_schema_executed") is not True
        or positive.get("validator_exit_code") != 0
        or positive.get("validator_errors") != []):
        raise ValueError("REAL_POSITIVE_VALIDATION_NOT_PROVEN:" + str(positive))
    if (negative["status"] not in (
            "EXPECTED_NEGATIVE_REJECTED_BY_SHAPE",
            "EXPECTED_NEGATIVE_REJECTED_BY_VALIDATOR")
        or negative.get("canonical_json_schema_executed") is not True
        or (
            negative["status"] == "EXPECTED_NEGATIVE_REJECTED_BY_SHAPE"
            and not negative.get("shape_errors")
        )
        or (
            negative["status"] == "EXPECTED_NEGATIVE_REJECTED_BY_VALIDATOR"
            and (negative.get("profile_validator_executed") is not True
                 or not negative.get("validator_errors"))
        )):
        raise ValueError("REAL_NEGATIVE_VALIDATION_NOT_PROVEN:" + str(negative))
    if any(x.get("admission_authorized") is not False
           or x.get("runtime_activation_authorized") is not False
           or x.get("provider_attested") is not False
           for x in (positive, negative)):
        raise ValueError("PROFILE_OUTPUT_PRODUCER_AUTHORITY_ESCALATION")
    evidence = {
        "schema": "PE10_C6_GITHUB_PROVIDER_OUTPUT_SOURCE_READBACK_V1",
        "evidence_scope": "PROFILE_CANONICAL_EXAMPLES_NOT_EVOLVED_CANDIDATE",
        "profile_slug": SLUG,
        "source_head_sha": head,
        "provider": "GITHUB",
        "github_actions_run_id": os.environ["GITHUB_RUN_ID"],
        "capability_code": "PACK_VALIDATION_HARNESS",
        "gate_code": "PROFILE_OUTPUT_CONTRACT_VALIDATION",
        "receipt_issued": False,
        "cutover_authorized": False,
        "production_activation": False,
        "github_readback_source_sha256": {
            name: digest((ROOT / rel).read_bytes()) for name, rel in REFS.items()
        },
        "positive_result": positive,
        "negative_result": negative,
    }
    evidence["evidence_sha256"] = digest(canonical(evidence))
    print("PE10_C6_PROVIDER_OUTPUT_EVIDENCE_V1=" +
          canonical(evidence).decode("utf-8"), flush=True)
    return evidence


if __name__ == "__main__":
    main()

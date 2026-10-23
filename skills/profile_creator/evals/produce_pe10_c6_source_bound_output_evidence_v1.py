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
CURRENT_REFS = {
    "schema": REFS["schema"],
    "validator": REFS["validator"],
    "runtime_binding": REFS["runtime_binding"],
    "positive_raw_output": Path(
        "skills/profile_creator/evals/results/profile_output_v06_current_candidate_20261023.json"
    ),
    "negative_raw_output": Path(
        "skills/profile_creator/evals/results/profile_output_v06_current_candidate_negative_20261023.json"
    ),
    "evidence_manifest": Path(
        "skills/profile_creator/evals/results/profile_output_v06_current_evidence_manifest_20261023.json"
    ),
    "builder": Path(
        "skills/profile_creator/evals/build_profile_output_v06_provider_candidate_v1.py"
    ),
    "producer": REFS["producer"],
    "runner": REFS["runner"],
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


def resolve_github_head(refs: dict[str, Path] = REFS) -> str:
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
    for rel in refs.values():
        actual = (ROOT / rel).read_bytes()
        committed = subprocess.check_output(
            ["git", "-C", str(ROOT), "show", f"{head}:{rel.as_posix()}"],
            stderr=subprocess.PIPE, timeout=30,
        )
        if actual != committed:
            raise ValueError("PROFILE_OUTPUT_SOURCE_NOT_EXACT_PR_HEAD:" + rel.as_posix())
    return head


def packet(
    raw: Path,
    expected_valid: bool,
    evidence_manifest: Path | None = None,
) -> dict:
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
    if evidence_manifest is not None:
        p["evidence_manifest_ref"] = evidence_manifest.as_posix()
        p["evidence_manifest_sha256"] = digest((ROOT / evidence_manifest).read_bytes())
    return p


def ensure_declared_schema_engine() -> None:
    """Provision only the already-pinned runtime dependency in ephemeral CI."""
    from importlib.metadata import PackageNotFoundError, version
    requirements = (ROOT / "services/profile_runtime_api/requirements.in").read_text(encoding="utf-8")
    if "jsonschema==4.26.0" not in requirements.splitlines():
        raise ValueError("CANONICAL_SCHEMA_ENGINE_RUNTIME_PIN_CHANGED")
    try:
        installed = version("jsonschema")
    except PackageNotFoundError:
        installed = None
    if installed != "4.26.0":
        subprocess.run(
            [sys.executable, "-m", "pip", "install",
             "--disable-pip-version-check", "jsonschema==4.26.0"],
            check=True, timeout=90,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )
    if version("jsonschema") != "4.26.0":
        raise ValueError("CANONICAL_SCHEMA_ENGINE_RUNTIME_VERSION_MISMATCH")


def main() -> dict:
    head = resolve_github_head()
    ensure_declared_schema_engine()
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


def main_current_v06() -> dict:
    """Validate the committed current V0.6 candidate from the exact PR HEAD."""
    head = resolve_github_head(CURRENT_REFS)
    ensure_declared_schema_engine()

    candidate = json.loads((ROOT / CURRENT_REFS["positive_raw_output"]).read_text(encoding="utf-8"))
    negative_candidate = json.loads(
        (ROOT / CURRENT_REFS["negative_raw_output"]).read_text(encoding="utf-8")
    )
    evidence_manifest = json.loads(
        (ROOT / CURRENT_REFS["evidence_manifest"]).read_text(encoding="utf-8")
    )

    if candidate.get("profile_pack_id") != "SYSTEMIC_ROOT_CAUSE_REPAIR_LF_V0_6":
        raise ValueError("CURRENT_V06_PROFILE_PACK_MISMATCH")
    if candidate.get("status") != "NEEDS_MORE_EVIDENCE":
        raise ValueError("CURRENT_V06_STATUS_NOT_FAIL_CLOSED")
    if candidate.get("blocking_codes") != [
        "PROFILE_OUTPUT_PROVIDER_VERIFIED_RECEIPTS_MISSING"
    ]:
        raise ValueError("CURRENT_V06_BLOCKING_CODE_DRIFT")
    uncertainties = candidate.get("current_uncertainties")
    if (not isinstance(uncertainties, list) or not uncertainties
            or uncertainties[0].get("uncertainty_id") != "U-PROVIDER-E2E"):
        raise ValueError("CURRENT_V06_PROVIDER_UNCERTAINTY_MISSING")
    producer = evidence_manifest.get("producer")
    if (not isinstance(producer, dict)
            or producer.get("kind") != "GPT_NATIVE_CURRENT_CHAT_SOURCE_AUTHORED"):
        raise ValueError("CURRENT_V06_AUTHORING_MODE_DRIFT")

    expected_negative = dict(candidate)
    expected_negative.pop("status", None)
    if negative_candidate != expected_negative:
        raise ValueError("CURRENT_V06_NEGATIVE_NOT_DERIVED_FROM_POSITIVE")

    manifest_ref = CURRENT_REFS["evidence_manifest"]
    positive = validate_bound_output(
        ROOT, packet(CURRENT_REFS["positive_raw_output"], True, manifest_ref)
    )
    negative = validate_bound_output(
        ROOT, packet(CURRENT_REFS["negative_raw_output"], False, manifest_ref)
    )

    if (positive["status"] != "CANDIDATE_OUTPUT_PARITY_OBSERVED"
        or positive.get("profile_validator_executed") is not True
        or positive.get("canonical_json_schema_executed") is not True
        or positive.get("source_readback_matched") is not True
        or positive.get("validator_exit_code") != 0
        or positive.get("validator_errors") != []):
        raise ValueError("CURRENT_V06_POSITIVE_VALIDATION_NOT_PROVEN:" + str(positive))
    if (negative["status"] != "EXPECTED_NEGATIVE_REJECTED_BY_SHAPE"
        or negative.get("canonical_json_schema_executed") is not True
        or negative.get("source_readback_matched") is not True
        or not negative.get("shape_errors")
        or negative.get("profile_validator_executed") is not False):
        raise ValueError("CURRENT_V06_NEGATIVE_VALIDATION_NOT_PROVEN:" + str(negative))
    if any(
        result.get("admission_authorized") is not False
        or result.get("runtime_activation_authorized") is not False
        or result.get("provider_attested") is not False
        for result in (positive, negative)
    ):
        raise ValueError("CURRENT_V06_PROVIDER_AUTHORITY_ESCALATION")

    evidence = {
        "schema": "PROFILE_OUTPUT_V06_GITHUB_PROVIDER_E2E_V1",
        "evidence_scope": "CURRENT_V06_EVOLVED_CANDIDATE",
        "profile_slug": SLUG,
        "profile_pack_id": candidate["profile_pack_id"],
        "candidate_status": candidate["status"],
        "source_head_sha": head,
        "provider": "GITHUB",
        "github_actions_run_id": os.environ["GITHUB_RUN_ID"],
        "capability_code": "PACK_VALIDATION_HARNESS",
        "gate_code": "PROFILE_OUTPUT_CONTRACT_VALIDATION",
        "authoring_mode": "GPT_NATIVE_CURRENT_CHAT_SOURCE_AUTHORED",
        "candidate_output_provider_e2e_verified": True,
        "runtime_provider_attested": False,
        "receipt_issued": False,
        "ledger_verified": False,
        "cutover_authorized": False,
        "checkpoint_closed": False,
        "production_activation": False,
        "github_readback_source_sha256": {
            name: digest((ROOT / rel).read_bytes())
            for name, rel in CURRENT_REFS.items()
        },
        "positive_result": positive,
        "negative_result": negative,
    }
    evidence["evidence_sha256"] = digest(canonical(evidence))
    print(
        "PROFILE_OUTPUT_V06_GITHUB_PROVIDER_E2E_V1="
        + canonical(evidence).decode("utf-8"),
        flush=True,
    )
    return evidence


if __name__ == "__main__":
    if len(sys.argv) == 1:
        main()
    elif len(sys.argv) == 2 and sys.argv[1] == "--current-v06":
        main_current_v06()
    else:
        raise SystemExit(
            "usage: produce_pe10_c6_source_bound_output_evidence_v1.py [--current-v06]"
        )

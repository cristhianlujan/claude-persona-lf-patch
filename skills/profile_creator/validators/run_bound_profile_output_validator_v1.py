#!/usr/bin/env python3
"""Generic post-generation output gate (not S26 assessment or admission authority).

Executes ONLY an explicitly source-sha-bound, profile-local deterministic
validator through its declared stdin/file interface. It never imports the
target profile in the read-only assessment and never attests model provenance.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path
from profile_output_shape_preflight_v1 import validate_shape

SCHEMA = "PROFILE_OUTPUT_VALIDATION_BINDING_V1"
SLUG = re.compile(r"^[a-z][a-z0-9_]*$")
SHA = re.compile(r"^[0-9a-f]{64}$")
INTERFACES = {"STDIN_JSON", "JSON_FILE_ARGUMENT"}


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def validate_bound_output(root: Path, packet: dict) -> dict:
    result = {
        "schema": "PROFILE_OUTPUT_VALIDATION_RESULT_V1",
        "status": "FAIL", "blocking_codes": [],
        "structural_check_executed": False, "profile_validator_executed": False,
        "source_readback_matched": False, "independent_review_executed": False,
        "provider_attested": False, "admission_authorized": False,
        "profile_write_authorized": False, "runtime_activation_authorized": False,
    }

    def block(code: str) -> dict:
        result["blocking_codes"].append(code)
        # One governed producer repair may correct a proven candidate/fixture
        # defect. This reader never edits a profile or declares admission.
        output_fault = code in {"OUTPUT_SHAPE_INVALID", "OUTPUT_JSON_INVALID",
                                "CANONICAL_VALIDATOR_RESULT_UNEXPECTED"}
        source_bound = result["source_readback_matched"] is True
        negative = packet.get("expected_valid") is False if isinstance(packet, dict) else False
        allowed = output_fault and source_bound
        result["remediation"] = {
            "schema": "PROFILE_UPDATE_BOUND_REMEDIATION_DIRECTIVE_V1",
            "classification": (
                "CANDIDATE_OUTPUT_DEFECT" if output_fault and not negative
                else "NEGATIVE_COUNTEREXAMPLE_DEFECT" if output_fault
                else "SOURCE_OR_VALIDATOR_AUTHORITY_BLOCKER"
            ),
            "action": (
                "RETURN_TO_GOVERNED_PRODUCER_ONCE" if allowed
                else "RETURN_TO_EVIDENCE_OR_AUTHORITY"
            ),
            "target": (
                "NEGATIVE_FIXTURE_ONLY" if allowed and negative
                else "CANDIDATE_OUTPUT_ONLY" if allowed
                else "NONE"
            ),
            "max_repair_cycles": 1 if allowed else 0,
            "attempts_executed": 0,
            "input_raw_sha256": (
                result.get("raw_output_sha256") if source_bound else None
            ),
            "defect_code": code,
            "shape_errors": result.get("shape_errors", []),
            "validator_errors": result.get("validator_errors", []),
            "must_rerun_same_bound_canonical_schema_and_validator": allowed,
            "must_preserve_original_failure_and_new_head_evidence": allowed,
            "may_change_canonical_schema_or_validator": False,
            "semantic_judge_required": True,
            "producer_repair_executed": False,
            "admission_authorized": False,
            "runtime_activation_authorized": False,
        }
        return result

    if not isinstance(packet, dict) or packet.get("schema") != SCHEMA:
        return block("BINDING_SCHEMA_INVALID")
    op = packet.get("operation_code")
    if op not in ("ACTUALIZACION_PERFIL_LF", "CREACION_PERFIL_LF"):
        return block("OPERATION_SCOPE_INVALID")
    slug = packet.get("profile_slug")
    if not isinstance(slug, str) or not SLUG.fullmatch(slug):
        return block("PROFILE_SLUG_INVALID")
    transport = packet.get("validator_transport")
    if transport not in INTERFACES:
        return block("VALIDATOR_TRANSPORT_UNRESOLVED")
    if type(packet.get("expected_valid")) is not bool:
        return block("EXPECTED_VALIDITY_NOT_TYPED")
    root = root.resolve()
    contents = {}
    for key in ("schema", "validator", "raw_output"):
        ref = packet.get(key + "_ref")
        digest = packet.get(key + "_sha256")
        if not isinstance(ref, str) or not isinstance(digest, str) or not SHA.fullmatch(digest):
            return block("SOURCE_BINDING_MISSING:" + key)
        if Path(ref).is_absolute() or ".." in Path(ref).parts:
            return block("SOURCE_PATH_UNSAFE:" + key)
        path = (root / ref).resolve()
        if not path.is_relative_to(root) or not path.is_file():
            return block("SOURCE_PATH_UNRESOLVED:" + key)
        rel = path.relative_to(root).as_posix()
        if key == "schema" and not rel.startswith(f"profiles/{slug}/schemas/"):
            return block("SCHEMA_PROFILE_SCOPE_MISMATCH")
        if key == "validator" and (
            not rel.startswith(f"profiles/{slug}/validators/") or
            not path.name.startswith("validate_") or not path.name.endswith(".py")
        ):
            return block("VALIDATOR_PROFILE_SCOPE_MISMATCH")
        try:
            data = path.read_bytes()
        except OSError:
            return block("SOURCE_READ_FAILED:" + key)
        if sha(data) != digest:
            return block("SOURCE_SHA_MISMATCH:" + key)
        contents[key] = (path, data)
    result["source_readback_matched"] = True
    result["source_refs"] = {
        k: packet[k + "_ref"] for k in contents
    }
    result["raw_output_sha256"] = packet["raw_output_sha256"]
    try:
        shape = validate_shape(
            json.loads(contents["schema"][1]),
            json.loads(contents["raw_output"][1]),
        )
    except (ValueError, UnicodeError):
        return block("OUTPUT_JSON_INVALID")
    result["structural_check_executed"] = True
    result["shape_errors"] = shape["blocking_codes"]
    if shape["status"] != "PASS":
        if packet["expected_valid"] is False:
            result["status"] = "EXPECTED_NEGATIVE_REJECTED_BY_SHAPE"
            return result
        return block("OUTPUT_SHAPE_INVALID")
    cmd = [sys.executable, str(contents["validator"][0])]
    if transport == "JSON_FILE_ARGUMENT":
        cmd.append(str(contents["raw_output"][0]))
    try:
        proc = subprocess.run(
            cmd, input=(contents["raw_output"][1] if transport == "STDIN_JSON" else None),
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15, cwd=root,
            check=False,
        )
        validator = json.loads(proc.stdout)
    except (subprocess.TimeoutExpired, ValueError, OSError):
        return block("CANONICAL_VALIDATOR_EXECUTION_FAILED")
    result["profile_validator_executed"] = True
    result["validator_exit_code"] = proc.returncode
    result["validator_stdout_sha256"] = sha(proc.stdout)
    if (not isinstance(validator, dict) or type(validator.get("valid")) is not bool
            or not isinstance(validator.get("errors"), list)):
        return block("CANONICAL_VALIDATOR_OUTPUT_INVALID")
    result["validator_errors"] = validator["errors"]
    validator_pass = validator["valid"] is True and proc.returncode == 0 and not validator["errors"]
    if packet["expected_valid"] is True and validator_pass:
        result["status"] = "CANDIDATE_OUTPUT_PARITY_OBSERVED"
        return result
    if packet["expected_valid"] is False and not validator_pass:
        result["status"] = "EXPECTED_NEGATIVE_REJECTED_BY_VALIDATOR"
        return result
    return block("CANONICAL_VALIDATOR_RESULT_UNEXPECTED")



def validate_with_bounded_producer_repair(root: Path, packet: dict, producer_repair) -> dict:
    """One local candidate repair, never an independent or provider attestation.

    The callback is owned by an authorized operation consumer. This function
    neither resolves governance credentials nor imposes a process timeout on
    that callback; the real producer must separately prove budget and dispatch.
    No historical RAW may be overwritten during the attempt.
    """
    before = validate_bound_output(root, packet)
    remediation = before.get("remediation") or {}
    receipt = {
        "schema": "PROFILE_UPDATE_BOUNDED_REVALIDATION_V1",
        "status": "NOT_EXECUTED",
        "before": before,
        "after": None,
        "producer_attempts": 0,
        "producer_adapter_invoked": False,
        "producer_repair_executed": False,
        "original_failure_sha256": before.get("raw_output_sha256"),
        "original_raw_snapshot_sha256": None,
        "original_raw_preserved_local": False,
        "original_raw_durable_receipt": None,
        "repaired_output_sha256": None,
        "repaired_output_ref": None,
        "source_authority_unchanged": None,
        "local_deterministic_revalidation": False,
        "producer_budget_enforced": False,
        "requires_governed_producer_and_durable_raw_receipt": True,
        "independent_review_executed": False,
        "provider_attested": False,
        "admission_authorized": False,
        "runtime_activation_authorized": False,
    }
    if remediation.get("action") != "RETURN_TO_GOVERNED_PRODUCER_ONCE":
        receipt["status"] = "NO_CORRECTABLE_OUTPUT_DEFECT"
        return receipt
    if not callable(producer_repair):
        receipt["status"] = "BLOCKED_PRODUCER_ADAPTER_MISSING"
        return receipt
    if not isinstance(packet, dict) or packet.get("operation_code") != "ACTUALIZACION_PERFIL_LF":
        receipt["status"] = "BLOCKED_OPERATION_SCOPE"
        return receipt
    if not before.get("source_readback_matched"):
        receipt["status"] = "BLOCKED_UNBOUND_FAILURE"
        return receipt
    original_ref = packet.get("raw_output_ref")
    original_sha = packet.get("raw_output_sha256")
    if not isinstance(original_ref, str) or not isinstance(original_sha, str):
        receipt["status"] = "BLOCKED_UNBOUND_FAILURE"
        return receipt
    root = root.resolve()
    try:
        original_path = (root / original_ref).resolve(strict=True)
        if not original_path.is_relative_to(root) or not original_path.is_file():
            raise OSError("UNSAFE_ORIGINAL")
        original_bytes = original_path.read_bytes()
    except OSError:
        receipt["status"] = "BLOCKED_ORIGINAL_RAW_UNAVAILABLE"
        return receipt
    if sha(original_bytes) != original_sha:
        receipt["status"] = "BLOCKED_ORIGINAL_RAW_MISMATCH"
        return receipt
    receipt["original_raw_snapshot_sha256"] = original_sha

    def original_intact() -> bool:
        try:
            return sha(original_path.read_bytes()) == original_sha
        except OSError:
            return False

    # A profile-local validator is executable code. Its initial subprocess
    # could already have mutated authority before a correction is attempted.
    def source_still_bound(bound_packet: dict) -> bool:
        for name in ("schema", "validator", "raw_output"):
            ref = bound_packet.get(name + "_ref")
            digest = bound_packet.get(name + "_sha256")
            if not isinstance(ref, str) or not isinstance(digest, str) or not SHA.fullmatch(digest):
                return False
            try:
                bound_path = (root / ref).resolve(strict=True)
                if not bound_path.is_relative_to(root) or sha(bound_path.read_bytes()) != digest:
                    return False
            except (OSError, RuntimeError):
                return False
        return True

    if not source_still_bound(packet):
        receipt["status"] = "BLOCKED_SOURCE_MUTATED_DURING_INITIAL_VALIDATION"
        return receipt

    # Existing producer adapter gets exactly one attempt. The original remains
    # immutable; it must produce a DIFFERENT source-bound candidate artifact.
    receipt["producer_attempts"] = 1
    receipt["producer_adapter_invoked"] = True
    try:
        proposed = producer_repair(root, dict(packet), dict(remediation))
    except Exception:
        receipt["original_raw_preserved_local"] = original_intact()
        receipt["status"] = ("STOP_PRODUCER_REPAIR_FAILED" if receipt["original_raw_preserved_local"]
                             else "STOP_ORIGINAL_RAW_MUTATED")
        return receipt
    receipt["original_raw_preserved_local"] = original_intact()
    if not receipt["original_raw_preserved_local"]:
        receipt["status"] = "STOP_ORIGINAL_RAW_MUTATED"
        return receipt
    if not isinstance(proposed, dict) or set(proposed) != set(packet):
        receipt["status"] = "STOP_REPAIR_REBOUND_UNTRUSTED"
        return receipt
    allowed_delta = {"raw_output_ref", "raw_output_sha256"}
    if any(proposed[key] != packet[key] for key in packet if key not in allowed_delta):
        receipt["status"] = "STOP_REPAIR_AUTHORITY_CHANGED"
        return receipt
    revised_ref = proposed.get("raw_output_ref")
    revised_sha = proposed.get("raw_output_sha256")
    if not isinstance(revised_ref, str) or not isinstance(revised_sha, str) or not SHA.fullmatch(revised_sha):
        receipt["status"] = "STOP_REPAIR_SHA_INVALID"
        return receipt
    if revised_ref == original_ref and revised_sha == original_sha:
        receipt["status"] = "STOP_REPAIR_NO_OUTPUT_DELTA"
        return receipt
    if revised_ref == original_ref:
        receipt["status"] = "STOP_REPAIR_SAME_RAW_PATH"
        return receipt
    if revised_sha == original_sha:
        receipt["status"] = "STOP_REPAIR_NO_OUTPUT_DELTA"
        return receipt
    receipt["repaired_output_sha256"] = revised_sha
    receipt["repaired_output_ref"] = revised_ref
    after = validate_bound_output(root, proposed)
    receipt["after"] = after
    receipt["original_raw_preserved_local"] = original_intact()
    if not receipt["original_raw_preserved_local"]:
        receipt["status"] = "STOP_ORIGINAL_RAW_MUTATED"
        return receipt
    receipt["source_authority_unchanged"] = bool(after.get("source_readback_matched")) and source_still_bound(proposed)
    if not receipt["source_authority_unchanged"]:
        receipt["status"] = "STOP_POST_VALIDATION_SOURCE_MUTATED"
        return receipt
    eligible = (
        (proposed["expected_valid"] is True
         and after["status"] == "CANDIDATE_OUTPUT_PARITY_OBSERVED")
        or
        (proposed["expected_valid"] is False and after["status"] in {
            "EXPECTED_NEGATIVE_REJECTED_BY_SHAPE",
            "EXPECTED_NEGATIVE_REJECTED_BY_VALIDATOR",
        })
    )
    if not eligible:
        receipt["status"] = "STOP_REPAIR_NOT_VALIDATED"
        return receipt
    receipt["local_deterministic_revalidation"] = True
    receipt["producer_repair_executed"] = True
    receipt["status"] = "LOCAL_REPAIRED_REVALIDATED_AWAITING_GOVERNED_EVIDENCE"
    return receipt


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--binding", type=Path, required=True)
    args = parser.parse_args()
    try:
        packet = json.loads(args.binding.read_text(encoding="utf-8"))
        result = validate_bound_output(args.root, packet)
    except (ValueError, OSError):
        result = {"schema":"PROFILE_OUTPUT_VALIDATION_RESULT_V1","status":"FAIL",
                  "blocking_codes":["BINDING_UNREADABLE"],"admission_authorized":False}
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    return 0 if result["status"].startswith("CANDIDATE_OUTPUT_PARITY_") or result["status"].startswith("EXPECTED_NEGATIVE_") else 1


if __name__ == "__main__":
    raise SystemExit(main())

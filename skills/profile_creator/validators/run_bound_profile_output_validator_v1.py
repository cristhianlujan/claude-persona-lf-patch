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

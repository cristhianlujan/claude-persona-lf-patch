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
    # A profile declares its actual canonical schema/validator, rather than
    # forcing all profiles to rename their validator to validate_*.py.
    binding_path = root / f"profiles/{slug}/contracts/runtime_binding.json"
    declared_binding = None
    if binding_path.is_file():
        try:
            declared_binding = json.loads(binding_path.read_text(encoding="utf-8"))
        except (ValueError, OSError):
            return block("RUNTIME_BINDING_UNREADABLE")
        if not isinstance(declared_binding, dict) or declared_binding.get("profile_slug") != slug:
            return block("RUNTIME_BINDING_IDENTITY_INVALID")
        schema_rel = declared_binding.get("runtime_schema", {}).get("default")
        validator_decl = declared_binding.get("canonical_validator")
        if (not isinstance(schema_rel, str) or not isinstance(validator_decl, dict)
                or not isinstance(validator_decl.get("path"), str)
                or validator_decl.get("callable") != "validate"):
            return block("RUNTIME_BINDING_CANONICAL_TARGET_INVALID")
        if (packet.get("schema_ref") != f"profiles/{slug}/{schema_rel}"
                or packet.get("validator_ref") != f"profiles/{slug}/{validator_decl['path']}"):
            return block("RUNTIME_BINDING_SOURCE_NOT_CANONICAL")
        if packet.get("runtime_binding_sha256") != sha(binding_path.read_bytes()):
            return block("RUNTIME_BINDING_DIGEST_MISMATCH")
        result["runtime_binding_sha256"] = packet["runtime_binding_sha256"]
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
            not path.name.endswith(".py") or
            (declared_binding is None and not path.name.startswith("validate_"))
        ):
            return block("VALIDATOR_PROFILE_SCOPE_MISMATCH")
        try:
            data = path.read_bytes()
        except OSError:
            return block("SOURCE_READ_FAILED:" + key)
        if sha(data) != digest:
            return block("SOURCE_SHA_MISMATCH:" + key)
        contents[key] = (path, data)

    # V0.3+ profiles may require an external evidence manifest. Keep it
    # source-bound in the same packet and feed it only to the declared
    # canonical validator; the canonical output schema still validates the
    # candidate itself, never a wrapper invented by this runner.
    manifest_json = None
    manifest_ref = packet.get("evidence_manifest_ref")
    manifest_digest = packet.get("evidence_manifest_sha256")
    if manifest_ref is not None or manifest_digest is not None:
        if transport != "STDIN_JSON":
            return block("EVIDENCE_MANIFEST_TRANSPORT_UNSUPPORTED")
        if (not isinstance(manifest_ref, str) or not isinstance(manifest_digest, str)
                or not SHA.fullmatch(manifest_digest)):
            return block("SOURCE_BINDING_MISSING:evidence_manifest")
        if Path(manifest_ref).is_absolute() or ".." in Path(manifest_ref).parts:
            return block("SOURCE_PATH_UNSAFE:evidence_manifest")
        manifest_path = (root / manifest_ref).resolve()
        if not manifest_path.is_relative_to(root) or not manifest_path.is_file():
            return block("SOURCE_PATH_UNRESOLVED:evidence_manifest")
        try:
            manifest_data = manifest_path.read_bytes()
        except OSError:
            return block("SOURCE_READ_FAILED:evidence_manifest")
        if sha(manifest_data) != manifest_digest:
            return block("SOURCE_SHA_MISMATCH:evidence_manifest")
        try:
            manifest_json = json.loads(manifest_data)
        except (ValueError, UnicodeError):
            return block("EVIDENCE_MANIFEST_JSON_INVALID")
        contents["evidence_manifest"] = (manifest_path, manifest_data)

    result["source_readback_matched"] = True
    result["source_refs"] = {
        k: packet[k + "_ref"] for k in contents
    }
    result["raw_output_sha256"] = packet["raw_output_sha256"]
    # The light shape preflight cannot handle $ref/oneOf/allOf/if/then/else.
    # The entire canonical JSON Schema MUST be evaluated, never skipped.
    try:
        from jsonschema import Draft202012Validator
        from jsonschema.exceptions import SchemaError
    except ImportError:
        return block("CANONICAL_JSON_SCHEMA_ENGINE_UNAVAILABLE")
    try:
        canonical_schema = json.loads(contents["schema"][1])
        candidate = json.loads(contents["raw_output"][1])
        Draft202012Validator.check_schema(canonical_schema)
        errors = sorted(
            Draft202012Validator(canonical_schema).iter_errors(candidate),
            key=lambda err: (tuple(str(x) for x in err.absolute_path), err.validator or ""),
        )
    except (ValueError, UnicodeError):
        return block("OUTPUT_JSON_INVALID")
    except SchemaError:
        return block("CANONICAL_JSON_SCHEMA_INVALID")
    result["structural_check_executed"] = True
    result["canonical_json_schema_executed"] = True
    result["shape_errors"] = [
        {"code": "CANONICAL_JSON_SCHEMA_REJECTED:" + str(e.validator),
         "path": "$" + "".join(f"[{x!r}]" for x in e.absolute_path)}
        for e in errors[:30]
    ]
    if errors:
        if packet["expected_valid"] is False:
            result["status"] = "EXPECTED_NEGATIVE_REJECTED_BY_SHAPE"
            return result
        return block("OUTPUT_SHAPE_INVALID")
    validator_input = contents["raw_output"][1]
    if manifest_json is not None:
        validator_input = json.dumps(
            {"candidate": candidate, "evidence_manifest": manifest_json},
            sort_keys=True, separators=(",", ":"), ensure_ascii=False,
        ).encode("utf-8")
    cmd = [sys.executable, str(contents["validator"][0])]
    if transport == "JSON_FILE_ARGUMENT":
        cmd.append(str(contents["raw_output"][0]))
    try:
        proc = subprocess.run(
            cmd, input=(validator_input if transport == "STDIN_JSON" else None),
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

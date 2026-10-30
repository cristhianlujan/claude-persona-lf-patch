"""M10.5 R17: isolated, reversible *file-bundle* rehearsal for one Edge target.

Never calls the Supabase deploy endpoint or writes to the LF database.
A rehearsal of a local file bundle DOES NOT certify provider-level rollback or
provider-level idempotency. The live runtime is accessed with GET only.
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

from edge_management_credential_canary_v1 import (
    CanaryBlocked, TARGET_SLUG, read_existing_function,
)

OPERATION = "DEPLOY_SUPABASE_EDGE_FUNCTION_LF"
ROLLBACK_REF = "cbaecd8d154b593f7d16126e9f3097797f31a7aa"
TARGET_DIR = "supabase/functions/" + TARGET_SLUG
RUNTIME_FILES = ("index.ts", "caller.ts", "cp2_edge_bridge.ts")
ROLLBACK_FILES = ("index.ts", "caller.ts")
ARTIFACT = Path("m105_edge_bundle_rollback_rehearsal.json")
# Exact, reviewed 2026-10-28 deploy-compatibility change: remove a type-only
# Deno import and replace it with a comment. No other entrypoint drift is accepted.
LEGACY_DENO_TYPES_IMPORT = b'import "jsr:@supabase/functions-js/edge-runtime.d.ts";\\n'
CURRENT_DENO_TYPES_COMMENT = (
    b"// Deno.serve and Deno.env are native runtime globals; "
    b"no remote JSR types fetch required.\\n"
)
SHA40 = re.compile(r"^[0-9a-f]{40}$")


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def git_bytes(ref: str, file: str) -> bytes:
    if not SHA40.fullmatch(ref) and ref != "HEAD":
        raise CanaryBlocked("R17_GIT_REF_INVALID")
    if file not in RUNTIME_FILES:
        raise CanaryBlocked("R17_UNDECLARED_FILE")
    try:
        result = subprocess.run(
            ["git", "show", f"{ref}:{TARGET_DIR}/{file}"],
            check=True, capture_output=True, timeout=15,
        )
    except (subprocess.CalledProcessError, TimeoutError, OSError):
        raise CanaryBlocked("R17_GIT_BLOB_UNAVAILABLE") from None
    if not result.stdout:
        raise CanaryBlocked("R17_GIT_EMPTY_FILE")
    return result.stdout


def exact_head() -> str:
    try:
        sha = subprocess.run(
            ["git", "rev-parse", "HEAD"], capture_output=True,
            check=True, text=True, timeout=10,
        ).stdout.strip()
    except (subprocess.CalledProcessError, TimeoutError, OSError):
        raise CanaryBlocked("R17_GIT_HEAD_UNAVAILABLE") from None
    if not SHA40.fullmatch(sha):
        raise CanaryBlocked("R17_GIT_HEAD_INVALID")
    ci_sha = os.getenv("GITHUB_SHA")
    if ci_sha and ci_sha != sha:
        raise CanaryBlocked("R17_NOT_EXACT_GITHUB_SHA")
    return sha


def validate_manifests(current: dict[str, bytes],
                       rollback: dict[str, bytes]) -> None:
    if set(current) != set(RUNTIME_FILES) or set(rollback) != set(ROLLBACK_FILES):
        raise CanaryBlocked("R17_BUNDLE_SCOPE_OR_ROLLBACK_MISMATCH")
    if any(not isinstance(data, bytes) or not data for data in
           [*current.values(), *rollback.values()]):
        raise CanaryBlocked("R17_BUNDLE_INVALID_BYTES")
    if current["caller.ts"] == rollback["caller.ts"]:
        raise CanaryBlocked("R17_NO_NEW_CALLER_DELTA")
    if b'"./cp2_edge_bridge.ts"' not in current["caller.ts"]:
        raise CanaryBlocked("R17_BRIDGE_IMPORT_MISSING")
    if b'"./caller.ts"' not in current["index.ts"]:
        raise CanaryBlocked("R17_CALLER_IMPORT_MISSING")
    if current["index.ts"] != rollback["index.ts"]:
        # Only the exact, reviewed type-declaration-only prefix transition is
        # permitted. The executable entrypoint bytes following it stay equal.
        legacy = rollback["index.ts"]
        updated = current["index.ts"]
        known_safe_transition = (
            legacy.startswith(LEGACY_DENO_TYPES_IMPORT)
            and updated.startswith(CURRENT_DENO_TYPES_COMMENT)
            and legacy[len(LEGACY_DENO_TYPES_IMPORT):]
                == updated[len(CURRENT_DENO_TYPES_COMMENT):]
        )
        if not known_safe_transition:
            raise CanaryBlocked("R17_INDEX_ENTRYPOINT_DRIFT")


def state(directory: Path) -> dict[str, str]:
    names = [p.name for p in directory.iterdir()]
    if any(n not in RUNTIME_FILES for n in names):
        raise CanaryBlocked("R17_UNDECLARED_TEMP_FILE")
    if any(p.is_symlink() or not p.is_file() for p in directory.iterdir()):
        raise CanaryBlocked("R17_TEMP_NONREGULAR_FILE")
    return {name: sha256((directory / name).read_bytes()) for name in sorted(names)}


def apply_bundle(directory: Path, bundle: dict[str, bytes]) -> int:
    """Idempotent local target reconciliation. Return count of actual file changes."""
    if not set(bundle).issubset(RUNTIME_FILES):
        raise CanaryBlocked("R17_BUNDLE_TARGET_ESCAPE")
    changes = 0
    for name in RUNTIME_FILES:
        path = directory / name
        if path.is_symlink() or (path.exists() and not path.is_file()):
            raise CanaryBlocked("R17_UNSAFE_TEMP_PATH")
        if name not in bundle:
            if path.exists():
                path.unlink()
                changes += 1
        elif not path.exists() or path.read_bytes() != bundle[name]:
            path.write_bytes(bundle[name])
            changes += 1
    return changes


def rehearse(current: dict[str, bytes], rollback: dict[str, bytes]) -> dict:
    validate_manifests(current, rollback)
    with tempfile.TemporaryDirectory(prefix="lf-m105-r17-offline-") as tmp:
        directory = Path(tmp)
        baseline_first = apply_bundle(directory, rollback)
        initial = state(directory)
        expected_rollback = {n: sha256(data) for n, data in sorted(rollback.items())}
        expected_current = {n: sha256(data) for n, data in sorted(current.items())}
        if initial != expected_rollback:
            raise CanaryBlocked("R17_ROLLBACK_PREIMAGE_MISMATCH")

        first_forward = apply_bundle(directory, current)
        if state(directory) != expected_current:
            raise CanaryBlocked("R17_LOCAL_FORWARD_PARITY_FAIL")
        second_forward = apply_bundle(directory, current)
        if second_forward != 0 or state(directory) != expected_current:
            raise CanaryBlocked("R17_LOCAL_FORWARD_REPLAY_NOT_IDEMPOTENT")

        first_restore = apply_bundle(directory, rollback)
        if state(directory) != initial:
            raise CanaryBlocked("R17_LOCAL_ROLLBACK_PARITY_FAIL")
        second_restore = apply_bundle(directory, rollback)
        if second_restore != 0 or state(directory) != initial:
            raise CanaryBlocked("R17_LOCAL_ROLLBACK_REPLAY_NOT_IDEMPOTENT")
        if (directory / "cp2_edge_bridge.ts").exists():
            raise CanaryBlocked("R17_BRIDGE_RESIDUE")
    return {
        "local_bundle_first_stage_changes": baseline_first,
        "local_forward_changes": first_forward,
        "local_forward_repeat_changes": second_forward,
        "local_rollback_changes": first_restore,
        "local_rollback_repeat_changes": second_restore,
        "source_file_sha256": expected_current,
        "rollback_file_sha256": expected_rollback,
        "local_file_rehearsal": "VERIFIED",
        "local_file_idempotency": "VERIFIED",
        "local_temporary_artifacts_retained": False,
    }


def run(read=read_existing_function, source_reader=git_bytes,
        git_head=exact_head) -> dict:
    head = git_head()
    if head == ROLLBACK_REF:
        raise CanaryBlocked("R17_HEAD_EQUALS_ROLLBACK")
    token = os.getenv("SUPABASE_ACCESS_TOKEN", "")
    before = read(token)
    if before.get("result") != "EDGE_MANAGEMENT_READ_PASS":
        raise CanaryBlocked("R17_LIVE_BEFORE_NOT_VERIFIED")
    current = {n: source_reader(head, n) for n in RUNTIME_FILES}
    rollback = {n: source_reader(ROLLBACK_REF, n) for n in ROLLBACK_FILES}
    result = rehearse(current, rollback)
    after = read(token)
    if (after.get("result") != "EDGE_MANAGEMENT_READ_PASS"
        or after.get("version") != before.get("version")
        or after.get("target") != before.get("target")):
        raise CanaryBlocked("R17_LIVE_VERSION_CHANGED_DURING_REHEARSAL")

    return {
        "schema": "LF_M105_R17_EDGE_BUNDLE_REHEARSAL_V1",
        "observed_at": datetime.now(timezone.utc).isoformat(),
        "operation_code": OPERATION,
        "target": TARGET_SLUG,
        "exact_main_sha": head,
        "rollback_git_sha": ROLLBACK_REF,
        "github_run_id": os.getenv("GITHUB_RUN_ID", "LOCAL_TEST"),
        "live_edge_version_before": before["version"],
        "live_edge_version_after": after["version"],
        "live_verify_jwt_preserved": True,
        "source_retrieval": "GIT_EXACT_COMMITS",
        "rollback_baseline_provenance": "PRIOR_LIVE_BYTE_PARITY_READBACK",
        "runtime_bundle": list(RUNTIME_FILES),
        "rollback_bundle": list(ROLLBACK_FILES),
        "method": "LOCAL_EPHEMERAL_FILE_ONLY",
        "http_management_method": "GET",
        "provider_deployment_executed": False,
        "provider_rollback_executed": False,
        "provider_idempotency_executed": False,
        "operation_effect_guard_reserved": False,
        "r17_verdict": "PARTIAL_NOT_AUTHORIZED",
        "cp2_runs_started": 0,
        **result,
    }


def main() -> int:
    try:
        receipt = run()
        code = 0
    except CanaryBlocked as exc:
        receipt = {
            "schema": "LF_M105_R17_EDGE_BUNDLE_REHEARSAL_V1",
            "result": "BLOCKED",
            "reason": str(exc),
            "provider_deployment_executed": False,
            "r17_verdict": "PARTIAL_NOT_AUTHORIZED",
            "cp2_runs_started": 0,
        }
        code = 2
    ARTIFACT.write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(receipt, sort_keys=True))
    return code


if __name__ == "__main__":
    sys.exit(main())

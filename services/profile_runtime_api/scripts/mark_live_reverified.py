#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import re
import tempfile
import sys
from datetime import datetime, timezone
from pathlib import Path

import psycopg
from psycopg.rows import dict_row

PACKAGE_ROOT = Path(__file__).resolve().parents[1]
if str(PACKAGE_ROOT) not in sys.path:
    sys.path.insert(0, str(PACKAGE_ROOT))

from profile_runtime_api.deployment import MARKER_SCHEMA, marker_digest

SHA40 = re.compile(r"^[0-9a-f]{40}$")


def _env(name: str, default: str = "") -> str:
    return os.getenv(name, default).strip()


def _connect() -> psycopg.Connection:
    password = _env("LF_SUPABASE_DB_PASSWORD")
    project = _env("SUPABASE_PROJECT_ID", "mhwmirqcgxxukpctffuv")
    host = _env("SUPABASE_POOLER_HOST", "aws-1-us-east-1.pooler.supabase.com")
    if not password:
        raise RuntimeError("LF_SUPABASE_DB_PASSWORD_REQUIRED")
    return psycopg.connect(host=host, port=6543, dbname="postgres", user=f"postgres.{project}", password=password, sslmode="require", row_factory=dict_row)


def _nested(mapping: object, *keys: str) -> object:
    current = mapping
    for key in keys:
        if not isinstance(current, dict):
            return None
        current = current.get(key)
    return current


def verify_record(row: dict, source_sha: str) -> dict:
    if row.get("status") != "SUCCEEDED" or row.get("error_code") is not None or row.get("error_detail") is not None:
        raise RuntimeError("LIVE_REVERIFY_QUEUE_NOT_SUCCEEDED")
    if row.get("runtime_target") != "HETZNER" or row.get("runtime_provider") != "hetzner_profile_runtime_api":
        raise RuntimeError("LIVE_REVERIFY_RUNTIME_TARGET_INVALID")
    attestation = row.get("runtime_attestation")
    if not isinstance(attestation, dict) or attestation.get("source_sha") != source_sha:
        raise RuntimeError("LIVE_REVERIFY_SOURCE_SHA_MISMATCH")
    package = row.get("result_package")
    engine_result = _nested(package, "result", "result")
    if not isinstance(engine_result, dict):
        raise RuntimeError("LIVE_REVERIFY_RESULT_PACKAGE_INVALID")
    if _nested(engine_result, "runtime_completion", "status") != "PASS":
        raise RuntimeError("LIVE_REVERIFY_RUNTIME_COMPLETION_NOT_PASS")
    if _nested(engine_result, "profile_contract_valid", "status") != "PASS":
        raise RuntimeError("LIVE_REVERIFY_CONTRACT_NOT_PASS")
    if _nested(engine_result, "semantic_utility", "status") != "PASS":
        raise RuntimeError("LIVE_REVERIFY_SEMANTIC_UTILITY_NOT_PASS")
    if engine_result.get("downstream_authorized") is not False:
        raise RuntimeError("LIVE_REVERIFY_DOWNSTREAM_AUTHORIZATION_INVALID")
    envelope = row.get("runtime_request_envelope")
    gov = _nested(envelope, "input_governance")
    if not isinstance(gov, dict) or gov.get("status") != "ADVISORY_READ_ONLY" or gov.get("subject_mode") != "NON_CANONICAL_ARTIFACT":
        raise RuntimeError("LIVE_REVERIFY_GOVERNANCE_INVALID")
    constraints = gov.get("constraints")
    if not isinstance(constraints, dict):
        raise RuntimeError("LIVE_REVERIFY_CONSTRAINTS_MISSING")
    expected = {
        "read_only": True,
        "no_write": True,
        "no_promotion": True,
        "canonical_registration_required": False,
    }
    for key, value in expected.items():
        if constraints.get(key) is not value:
            raise RuntimeError(f"LIVE_REVERIFY_CONSTRAINT_INVALID:{key}")
    return {
        "runtime_completion": "PASS",
        "profile_contract_valid": "PASS",
        "semantic_utility": "PASS",
        "downstream_authorized": False,
        "canonical_registration_required": False,
        "read_only": True,
        "no_write": True,
        "no_promotion": True,
        "attested_at": attestation.get("attested_at"),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--request-id", required=True)
    parser.add_argument("--source-sha", default=_env("PROFILE_RUNTIME_SOURCE_SHA"))
    parser.add_argument("--state-dir", default=_env("PROFILE_RUNTIME_STATE_DIR", "/var/lib/lf-profile-runtime-api"))
    args = parser.parse_args()
    if not SHA40.fullmatch(args.source_sha):
        raise RuntimeError("PROFILE_RUNTIME_SOURCE_SHA_INVALID")
    with _connect() as conn, conn.cursor() as cur:
        cur.execute("""
            select request_id::text as request_id, status, error_code, error_detail,
                   runtime_target, runtime_provider, runtime_attestation,
                   result_package, runtime_request_envelope
              from private.lf_profile_runtime_queue_v1
             where request_id = %s::uuid
        """, (args.request_id,))
        row = cur.fetchone()
    if not row:
        raise RuntimeError("LIVE_REVERIFY_REQUEST_NOT_FOUND")
    evidence = verify_record(row, args.source_sha)
    payload = {
        "schema": MARKER_SCHEMA,
        "source_sha": args.source_sha,
        "request_id": row["request_id"],
        "queue_status": "SUCCEEDED",
        "verified_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        **evidence,
    }
    payload["evidence_sha256"] = marker_digest(payload)
    state_dir = Path(args.state_dir)
    state_dir.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=".live_reverify.", dir=state_dir)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump(payload, fh, sort_keys=True, separators=(",", ":"))
            fh.write("\n")
            fh.flush(); os.fsync(fh.fileno())
        os.chmod(tmp, 0o644)
        os.replace(tmp, state_dir / "live_reverify.json")
    finally:
        if os.path.exists(tmp): os.unlink(tmp)
    print(json.dumps(payload, sort_keys=True))
    return 0

if __name__ == "__main__":
    raise SystemExit(main())

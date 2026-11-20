#!/usr/bin/env python3
"""LF L37: isolated PostgreSQL 17.6 and 18.7 migration apply + ROLLBACK tests.
Never connects to Supabase. Requires local Docker; no live DB credentials used.
Run: python3 docs/rule-quality-lote37/apply_preparation/test_policy19_pg17_pg18_rollback.py
"""
import shutil
import subprocess
import time
import uuid
from pathlib import Path

HERE = Path(__file__).resolve().parent
FIXTURE = HERE / "policy19_pg_isolated_fixture.sql"
CANDIDATE = HERE / "policy19_description_only_candidate.sql"
SOURCE_SHA = "f82cf4ed0887d8240e1a20d193a7a3a82f92271334de6eb543e4489ecac21b07"
DESCRIPTION_SHA = "0beb7404a61197b3d2528de19a210350a02ae83a5d7fbc58d57726645173975b"
POLICY = "SEC-B2B-MFA-FACTOR-ELIGIBILITY"

def pg17_18(image: str, expected_version: str) -> None:
    assert shutil.which("docker"), "NOT_TESTED_NO_DOCKER"
    assert FIXTURE.is_file() and CANDIDATE.is_file(), "NOT_TESTED_SOURCE_FILE_MISSING"
    container = "lf-policy19-l37-" + uuid.uuid4().hex[:10]
    launched = subprocess.run(
        ["docker", "run", "-d", "--rm", "--name", container,
         "-e", "POSTGRES_PASSWORD=postgres", "-e", "POSTGRES_DB=postgres", image],
        capture_output=True, text=True, timeout=240
    )
    if launched.returncode:
        raise RuntimeError("NOT_TESTED_DOCKER_IMAGE_START_FAILED: " + launched.stderr[-2000:])
    def psql(sql: str, expect_error: str | None = None) -> str:
        p = subprocess.run(
            ["docker", "exec", "-i", container, "psql", "-X", "-v", "ON_ERROR_STOP=1",
             "-U", "postgres", "-d", "postgres", "-A", "-t", "-q"],
            input=sql, capture_output=True, text=True, timeout=120
        )
        if expect_error:
            assert p.returncode != 0 and expect_error in p.stderr,                 "NEGATIVE_TEST_FAILED: " + p.stdout + p.stderr
        else:
            assert p.returncode == 0, "SQL_FAILED:" + p.stderr[-3000:]
        return p.stdout.strip()

    try:
        for _ in range(70):
            ready = subprocess.run(["docker", "exec", container, "pg_isready", "-U", "postgres"],
                                   capture_output=True, timeout=10)
            if ready.returncode == 0:
                break
            time.sleep(1)
        else:
            raise AssertionError("NOT_TESTED_PG_READY_TIMEOUT")
        version = psql("SHOW server_version_num;").splitlines()[-1]
        assert version == expected_version, f"WRONG_PG_VERSION:{version}"
        psql(FIXTURE.read_text(encoding="utf-8"))
        query_sha = ("SELECT encode(pg_catalog.sha256(convert_to(to_jsonb(p)::text,'UTF8')),'hex') "
                     "FROM lf_ops.politicas_seguridad p WHERE security_policy_id=19;")
        assert psql(query_sha).splitlines()[-1] == SOURCE_SHA
        expected_desc = ("SELECT encode(pg_catalog.sha256(convert_to(description,'UTF8')),'hex') "
                         "FROM lf_ops.politicas_seguridad WHERE security_policy_id=19;")
        unchanged = ("SELECT (policy_config->>'admin_minimum_strength'='PHISHING_RESISTANT')::text "
                     "FROM lf_ops.politicas_seguridad WHERE security_policy_id=19;")
        positive = ("BEGIN;\n" + CANDIDATE.read_text(encoding="utf-8")
                    + "\n" + expected_desc + "\n" + unchanged
                    + "\nSELECT status FROM lf_ops.politicas_seguridad WHERE security_policy_id=19;"
                    + "\nROLLBACK;\n" + query_sha)
        lines = psql(positive).splitlines()
        assert DESCRIPTION_SHA in lines, "POSITIVE_DESCRIPTION_SHA_MISMATCH"
        assert "t" in lines, "POLICY_CONFIG_CHANGED"
        assert "CANDIDATO" in lines, "UNAUTHORIZED_PROMOTION"
        assert lines[-1] == SOURCE_SHA, "ROLLBACK_FULLROW_SHA_NOT_RESTORED"
        psql("UPDATE lf_ops.politicas_seguridad SET description='DRIFT_INJECTED' WHERE security_policy_id=19;")
        psql(CANDIDATE.read_text(encoding="utf-8"), expect_error="LF_POLICY19_SOURCE_PREIMAGE_DRIFT")
        assert psql("SELECT description FROM lf_ops.politicas_seguridad WHERE security_policy_id=19;") == "DRIFT_INJECTED"
        print(f"PASS_POLICY19_DESCRIPTION_ONLY_APPLY_ROLLBACK_NEGATIVE_{image}_version={version}", flush=True)
    finally:
        subprocess.run(["docker", "rm", "-f", container], capture_output=True, text=True, timeout=90)

if __name__ == "__main__":
    pg17_18("postgres:17.6", "170006")
    pg17_18("postgres:18.7", "180007")
    print("PASS_POLICY19_PG17_6_PG18_7_ROLLBACK_BOTH", flush=True)

#!/usr/bin/env python3
"""LF IG G3: fail-closed isolated PostgreSQL verification.

Only a deliberately created local and disposable instance may be used.
Requires exact existing N-4 function definitions, a SANITIZED baseline
with the 14 active selectors and 58 screens, and validated source drift.
This script NEVER connects to Supabase or performs any production migration.
"""
from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
from pathlib import Path


def reject(message: str) -> None:
    raise SystemExit(message)


def isolated_environment() -> tuple[str, str, str]:
    db = os.environ.get("PGDATABASE", "")
    host = os.environ.get("PGHOST", "")
    data_dir = os.environ.get("LF_IG_EXPECTED_DATA_DIRECTORY", "")
    if os.environ.get("LF_IG_ISOLATED_PG_CONFIRMED") != "YES":
        reject("BLOCK: explicit local isolated DB confirmation required")
    if not re.fullmatch(r"lf_ig_n4_isolated_[a-zA-Z0-9_]+", db):
        reject("BLOCK: disposable PGDATABASE name required")
    if not host.startswith("/tmp/lf_ig_n4_socket_") or not Path(host).is_dir():
        reject("BLOCK: isolated private Unix socket directory required")
    if not data_dir.startswith("/tmp/lf_ig_n4_data_") or not Path(data_dir).is_dir():
        reject("BLOCK: isolated private PostgreSQL data directory required")
    if any(os.environ.get(x) for x in (
        "PGSERVICE", "PGSERVICEFILE", "DATABASE_URL", "PGHOSTADDR", "PGOPTIONS"
    )):
        reject("BLOCK: indirect PostgreSQL connection settings forbidden")
    if not shutil.which("psql"):
        reject("NO_VERIFICADO: psql is not installed locally")
    return db, host, data_dir


def run_psql(sql: str, timeout: int) -> str:
    p = subprocess.run(
        ["psql", "-X", "-w", "-A", "-t", "-F", "|",
         "-v", "ON_ERROR_STOP=1"],
        input=sql, text=True, capture_output=True,
        timeout=timeout, check=False,
    )
    if p.returncode:
        reject("FAIL: PostgreSQL verification error: " + p.stderr[-1600:])
    return p.stdout


def main() -> int:
    db, _host, data_dir = isolated_environment()
    root = Path(__file__).resolve().parent
    candidate = (root / "ig_n4_clause_matcher_hardened_candidate_20261028.sql").read_text()
    vectors = (root / "ig_n4_preclass_synthetic_matcher_v2_20261028.sql").read_text()
    fixture = (root / "ig_n4_pg17_6_sanitized_fixture_20261028.sql").read_text()

    if len(re.findall(r"^BEGIN;$", candidate, flags=re.MULTILINE)) != 1:
        reject("BLOCK: candidate does not declare a single outer BEGIN")
    if not candidate.rstrip().endswith("ROLLBACK;"):
        reject("BLOCK: candidate must end with ROLLBACK")
    if candidate.count("CREATE OR REPLACE FUNCTION") != 3:
        reject("BLOCK: expected exactly three N-4 functions in candidate")
    if not re.search(r"\\bCREATE OR REPLACE FUNCTION\\b", candidate):
        reject("BLOCK: function definitions not present")
    if not re.search(r"SELECT case_id,description,expected,actual,CASE", vectors):
        reject("BLOCK: vector reporting contract changed")

    check = run_psql(
        "SELECT current_database(), "
        "coalesce(inet_server_addr()::text,'LOCAL_SOCKET'), "
        "current_setting('data_directory'), "
        "pg_is_in_recovery(), current_setting('server_version_num')",
        timeout=15,
    ).strip().split("|")
    if len(check) != 5 or check[0] != db or check[1] != "LOCAL_SOCKET":
        reject("BLOCK: not using the isolated database/socket")
    if Path(check[2]).resolve() != Path(data_dir).resolve() or check[3] != "f":
        reject("BLOCK: cluster data directory/recovery state mismatch")
    if check[4] != "170006":
        reject("BLOCK: isolated PostgreSQL 17.6 required to preserve source MD5")
    # The baseline is sanitized: only screen id/module code/app shell code and
    # existing declarative selector JSON. No live Supabase data is queried here.
    run_psql(fixture, timeout=50)

    start = candidate.index("\nBEGIN;") + len("\nBEGIN;")
    end = candidate.rfind("ROLLBACK;")
    patch = candidate[start:end]
    before = """
CREATE TEMP TABLE ig_n4_preimage ON COMMIT DROP AS
SELECT r.rule_id,p.screen_id,
 programacion.fn_input_rule_selector_matches_v1(
   r.selector,p.context
 ) AS old_match
FROM public.ig_n4_rule_fixtures r
CROSS JOIN public.ig_n4_screen_fixtures p;
"""
    after = """
SELECT 'PARITY',
 count(*),
 count(*) FILTER (WHERE old_match),
 count(*) FILTER (WHERE new_match),
 count(*) FILTER (WHERE old_match IS DISTINCT FROM new_match),
 count(DISTINCT rule_id),
 count(DISTINCT screen_id)
FROM (
 SELECT a.*,programacion.fn_input_rule_selector_matches_v1(
   r.selector,p.context
 ) AS new_match
 FROM ig_n4_preimage a
 JOIN public.ig_n4_rule_fixtures r ON r.rule_id=a.rule_id
 JOIN public.ig_n4_screen_fixtures p ON p.screen_id=a.screen_id
) results;
"""
    sql = "BEGIN;\n" + before + patch + "\n" + vectors + "\n" + after + "\nROLLBACK;\n"
    stdout = run_psql(sql, timeout=90)
    rows = stdout.splitlines()
    fixture_rows = [x for x in rows if re.fullmatch(r"T[0-9]{2}\\|.*", x)]
    if len(fixture_rows) != 27 or any(not x.endswith("|PASS") for x in fixture_rows):
        reject("FAIL: not all 27 synthetic tests passed in isolated PostgreSQL")
    matches = [x for x in rows if x.startswith("PARITY|")]
    if len(matches) != 1:
        reject("FAIL: isolated N-4 parity result missing")
    cols = matches[0].split("|")
    if len(cols) != 7 or cols[1:] != ["812", "52", "52", "0", "14", "58"]:
        reject("FAIL: isolated baseline/selector parity mismatch: " + matches[0])

    # One final independent connection checks the rollback did not persist any
    # new helper and confirms unchanged source hashes.
    after_rollback = run_psql("""
SELECT md5(pg_get_functiondef(
 'programacion.fn_input_rule_selector_matches_v1(jsonb,jsonb)'::regprocedure)),
 md5(pg_get_functiondef(
 'programacion.fn_input_rule_selector_clause_matches_v1(jsonb,jsonb)'::regprocedure)),
 to_regprocedure('programacion.fn_input_rule_selector_clause_schema_valid_v1(jsonb)') IS NULL;
""", timeout=15).strip().split("|")
    if after_rollback != [
        "3b912c7872aceff83de24e9e8d1ad934",
        "1123257c0c6c7eb1e2aa26783f3ccc0a",
        "t",
    ]:
        reject("FAIL: post-ROLLBACK source parity not restored")

    print("PASS_G3_ISOLATED_PG_27_VECTORS_812_PARITY_ROLLBACK")
    print(matches[0])
    return 0


if __name__ == "__main__":
    sys.exit(main())

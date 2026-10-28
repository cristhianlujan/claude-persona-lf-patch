#!/usr/bin/env python3
"""G3 LF IG: isolated PostgreSQL transaction-only verification.

Must run only against a dedicated LOCAL isolated DB populated with a vetted,
sanitized snapshot of IG schemas/functions/rule-screen relationships.
Never use this against Supabase, prod, shared staging, Docker tunnels to prod,
or any linked project. No Router. No migration. All candidate DDL rolls back.
A missing postgres/psql is a BLOCK, never a simulated PASS.
"""
from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
from pathlib import Path


def main() -> int:
    db = os.environ.get("PGDATABASE", "")
    host = os.environ.get("PGHOST", "")
    if os.environ.get("LF_IG_ISOLATED_PG_CONFIRMED") != "YES":
        raise SystemExit("BLOCK: explicit local isolated DB confirmation required")
    if not db.startswith("lf_ig_n4_isolated_"):
        raise SystemExit("BLOCK: PGDATABASE must be a disposable lf_ig_n4_isolated_* DB")
    if host not in ("", "/var/run/postgresql", "/tmp", "127.0.0.1", "localhost", "::1"):
        raise SystemExit("BLOCK: remote PostgreSQL host refused")
    if os.environ.get("PGSERVICE") or os.environ.get("DATABASE_URL") or os.environ.get("PGSERVICEFILE"):
        raise SystemExit("BLOCK: connection URI/service indirection refused")
    if not shutil.which("psql"):
        raise SystemExit("NO_VERIFICADO: local psql binary unavailable")

    dirpath = Path(__file__).resolve().parent
    candidate = (dirpath / "ig_n4_clause_matcher_hardened_candidate_20261028.sql").read_text()
    vectors = (dirpath / "ig_n4_preclass_synthetic_matcher_v2_20261028.sql").read_text()
    if candidate.count("BEGIN;") != 1 or not candidate.rstrip().endswith("ROLLBACK;"):
        raise SystemExit("BLOCK: candidate transaction contract changed")
    if not re.search(r"\\bCREATE OR REPLACE FUNCTION\\b", candidate):
        raise SystemExit("BLOCK: candidate contains no functions")
    if not re.search(r"SELECT case_id,description,expected,actual,CASE", vectors):
        raise SystemExit("BLOCK: vector reporting contract changed")

    check = subprocess.run(
        ["psql", "-X", "-w", "-A", "-t", "-v", "ON_ERROR_STOP=1", "-c",
         "SELECT current_database(), coalesce(inet_server_addr()::text,'LOCAL_SOCKET')"],
        capture_output=True, text=True, timeout=12, check=False,
    )
    if check.returncode:
        raise SystemExit("BLOCK: cannot verify isolated DB identity: " + check.stderr[:500])
    observed = check.stdout.strip().split("|")
    if len(observed) != 2 or observed[0] != db or observed[1] not in (
        "LOCAL_SOCKET", "127.0.0.1", "::1"
    ):
        raise SystemExit("BLOCK: database identity/network guard failed: " + repr(observed))

    # Trim BEGIN and ROLLBACK so the snapshot is taken BEFORE the candidate's
    # changes and test queries execute BEFORE the one final mandatory ROLLBACK.
    start = candidate.index("BEGIN;") + len("BEGIN;")
    end = candidate.rfind("ROLLBACK;")
    payload = candidate[start:end]
    before = """
CREATE TEMP TABLE ig_n4_old_match ON COMMIT DROP AS
SELECT r.id rule_id,p.id screen_id,
  programacion.fn_input_rule_selector_matches_v1(
      r.valor_config->'applicability_v1',
      programacion.fn_input_rule_target_context_v1(p.id,'INPUT_GOVERNANCE')
  ) AS old_match
FROM lf_ops.reglas r CROSS JOIN lf_ops.pantallas p
WHERE r.estado='VIGENTE'
  AND r.valor_config->'applicability_v1'->>'status'='ACTIVE';
"""
    after = """
SELECT 'PARITY' AS test_name,
  count(*) AS pairs,
  count(*) FILTER (WHERE old_match) AS old_matches,
  count(*) FILTER (
   WHERE programacion.fn_input_rule_selector_matches_v1(
    r.valor_config->'applicability_v1',
    programacion.fn_input_rule_target_context_v1(p.id,'INPUT_GOVERNANCE')
   )
  ) AS candidate_matches,
  count(*) FILTER (
   WHERE old_match IS DISTINCT FROM
   programacion.fn_input_rule_selector_matches_v1(
    r.valor_config->'applicability_v1',
    programacion.fn_input_rule_target_context_v1(p.id,'INPUT_GOVERNANCE')
   )
  ) AS differences
FROM ig_n4_old_match m
JOIN lf_ops.reglas r ON r.id=m.rule_id
JOIN lf_ops.pantallas p ON p.id=m.screen_id;
"""
    program = "BEGIN;\n" + before + "\n" + payload + "\n" + vectors + "\n" + after + "\nROLLBACK;\n"
    # Retain no DB dumps; all SQL is constructed from versioned repository files.
    result = subprocess.run(
        ["psql", "-X", "-w", "-A", "-t", "-F", "|", "-v", "ON_ERROR_STOP=1"],
        input=program, text=True, capture_output=True, timeout=75, check=False,
    )
    # A failed psql transaction never counts as PASS, even if ROLLBACK ran.
    if result.returncode:
        raise SystemExit("FAIL: candidate PG execution failed: " + result.stderr[-1500:])
    lines = result.stdout.splitlines()
    test_rows = [line for line in lines if re.match(r"^T[0-9]{2}\\|", line)]
    if len(test_rows) != 27 or any(not line.endswith("|PASS") for line in test_rows):
        raise SystemExit("FAIL: 27 selector fixture results missing or negative")
    parity = [line for line in lines if line.startswith("PARITY|")]
    if len(parity) != 1:
        raise SystemExit("FAIL: exact parity line missing")
    fields = parity[0].split("|")
    if len(fields) != 5 or int(fields[1]) <= 0 or fields[2] != fields[3] or fields[4] != "0":
        raise SystemExit("FAIL: non-zero selector parity drift " + repr(parity[0]))
    print("PASS_ISOLATED_POSTGRESQL_CANDIDATE_27_VECTORS_AND_ACTIVE_PARITY_ROLLBACK")
    print(parity[0])
    return 0


if __name__ == "__main__":
    sys.exit(main())

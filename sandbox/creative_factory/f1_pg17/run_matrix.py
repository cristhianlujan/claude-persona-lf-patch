#!/usr/bin/env python3
"""Fail-closed PG17 runner; not a replacement for the actual F1 fixtures/tests."""
import hashlib
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parent
CASES = {
    "T01": "LF L2A/L2C/L3B canonical success",
    "T02": "mandatory logo absent blocked",
    "T03": "cross-project asset blocked",
    "T04": "tampered snapshot blocked",
    "T05": "claim/admit/advance/wire/reserve without dispatch",
    "T06": "reservation idempotency and conflict",
    "T07": "SALY base/candidate parity",
    "T08": "historical records unchanged",
    "T09": "release DONE without verified delivery blocked",
    "T10": "missing semantic QA blocked",
    "T11": "pending semantic QA blocked",
    "T12": "LF order other than 23 admitted",
    "T13": "frozen policy/lease/RUN coherent",
    "T14": "historical SALY order 22 exception preserved",
    "T15": "two independent sessions, both lock orders",
}

def main():
    if len(sys.argv) != 2:
        raise SystemExit("usage: run_matrix.py MIGRATION")
    if os.environ.get("PGHOST") != "127.0.0.1" or os.environ.get("PGDATABASE") != "lf_creative_f1_ci" or os.environ.get("PGUSER") != "postgres":
        raise SystemExit("F1_MATRIX_UNSAFE_TARGET")
    if any(os.environ.get(k) for k in ("PGSERVICE", "PGSERVICEFILE", "PGHOSTADDR", "PGOPTIONS", "PGPORT")):
        raise SystemExit("F1_MATRIX_UNEXPECTED_CONNECTION_OVERRIDE")
    version = subprocess.check_output(["psql", "-XAt", "-v", "ON_ERROR_STOP=1", "-c", "SHOW server_version_num"], text=True).strip()
    if not version.startswith("17"):
        raise SystemExit("F1_MATRIX_PG17_REQUIRED")
    candidate = Path(sys.argv[1]).resolve(strict=True)
    setup = ROOT / "setup.sh"
    cases = [(case, ROOT / (case + ".sh")) for case in CASES]
    missing = [p.name for p in [setup] + [p for _, p in cases] if not p.is_file()]
    if missing:
        raise SystemExit("F1_MATRIX_BLOCKED_MISSING_REAL_CASES: " + ",".join(missing))
    env = dict(os.environ, F1_CANDIDATE=str(candidate), F1_CANDIDATE_SHA256=hashlib.sha256(candidate.read_bytes()).hexdigest())
    subprocess.run(["bash", str(setup)], check=True, env=env)
    for case, path in cases:
        result = subprocess.run(["bash", str(path)], env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        print(result.stdout, end="")
        if result.returncode or result.stdout.splitlines().count(case + "|PASS") != 1:
            raise SystemExit("F1_MATRIX_CASE_FAILED:" + case)
    print("F1_MATRIX_15_15_PASS")

if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Input Governance IG-006/IG-007 adapter for LF_GOVERNED_CANARY_RUNNER_V1.

This file contains the domain-specific exact-version logic. The generic runner
remains domain-agnostic. No production or merge authority is granted here.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import shutil
import subprocess
import sys
from urllib.parse import quote

RUNNER_VERSION = "LF_GOVERNED_CANARY_RUNNER_V1"
PROJECT = "mhwmirqcgxxukpctffuv"
POOLER_HOST = "aws-1-us-east-1.pooler.supabase.com"
IG_SOURCE_SHA = "36793f6a2292dabc56fa2f6f609136bb921ae4e3"
BASE_TEST_SHA = "5b9ff7f7c870e21b1daf53e21e62bdbb31266cbe"
FORWARD_VERSION = "20260907023000"
ROLLBACK_VERSION = "20260907023100"
FORWARD_NAME = "lf_input_governance_ig006_ig007_exact_canary_forward_v1"
ROLLBACK_NAME = "lf_input_governance_ig006_ig007_exact_canary_rollback_v1"
FORWARD_PATH = f"supabase/migrations/{FORWARD_VERSION}_{FORWARD_NAME}.sql"
ROLLBACK_PATH = f"supabase/migrations/{ROLLBACK_VERSION}_{ROLLBACK_NAME}.sql"
BASE_TEST_PATH = "sandbox/s28-input-governance-ig006-ig007-exact-canary-20260907.sql"
CONFIG_PATH = "supabase/config.toml"
BASELINE_SHA = {
    "rebind": "1bbf57bb5f51fff22e540664a3fe4e07a547a5e62b855c69abb2f981e5d92c79",
    "assertions": "d02e3d07523debdb2acf38f46a7ebfd4c0b7d8d5238ed4b5d13de3581e9d4822",
    "rebind_assertion": "b3ab572553e592fa8e8c64b9031ec741936995be67c2c469c2a0834ce11d6f9e",
    "guard": "d000493dce8f7d25139c20c75025a0a0c6dd5041547f6469aecf6d373acad574",
}
CANDIDATE_FUNCTIONS = (
    "fn_guard_input_family_assessment_insert_baseline_ig007_v1",
    "fn_input_rebind_assertion_cached_v1",
    "fn_input_v58_build_assertions_cached_v1",
    "fn_input_governance_curator_rebind_candidate_v1",
)
CURRENT_SCREENS = ((43, "B2B-CARGA-001"), (5, "HOME_002"), (57, "ONB_004"), (3, "ONB_003"), (2, "ONB_002"))
STALE_RUNS = (218, 210, 186, 191)


class AdapterError(RuntimeError):
    pass


def run(args: list[str], *, cwd: Path | None = None, env: dict[str, str] | None = None, timeout: int = 120) -> subprocess.CompletedProcess[str]:
    proc = subprocess.run(args, cwd=cwd, env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout, check=False)
    if proc.returncode != 0:
        raise AdapterError(f"COMMAND_FAILED:{Path(args[0]).name}:exit={proc.returncode}:stdout_sha256={sha(proc.stdout.encode())}:stderr_sha256={sha(proc.stderr.encode())}")
    return proc


def sha(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def require_secret() -> str:
    value = os.environ.get("LF_SUPABASE_DB_PASSWORD", "")
    if not value:
        raise AdapterError("LF_SUPABASE_DB_PASSWORD_MISSING")
    return value


def db_url() -> str:
    return f"postgresql://postgres.{PROJECT}:{quote(require_secret(), safe='')}@{POOLER_HOST}:5432/postgres?sslmode=require"


def pg_env() -> dict[str, str]:
    env = os.environ.copy()
    env.update({
        "PGHOST": POOLER_HOST,
        "PGPORT": "5432",
        "PGUSER": f"postgres.{PROJECT}",
        "PGPASSWORD": require_secret(),
        "PGDATABASE": "postgres",
        "PGSSLMODE": "require",
    })
    return env


def docker_psql(sql: str, *, timeout: int = 120) -> str:
    env = pg_env()
    args = ["docker", "run", "--rm"]
    for name in ("PGHOST", "PGPORT", "PGUSER", "PGPASSWORD", "PGDATABASE", "PGSSLMODE"):
        args += ["-e", name]
    args += ["postgres:17.6", "psql", "-X", "-A", "-t", "-v", "ON_ERROR_STOP=1", "-c", sql]
    return run(args, env=env, timeout=timeout).stdout.strip()


def docker_psql_file(path: Path, *, timeout: int = 500) -> tuple[str, str]:
    env = pg_env()
    args = ["docker", "run", "--rm"]
    for name in ("PGHOST", "PGPORT", "PGUSER", "PGPASSWORD", "PGDATABASE", "PGSSLMODE"):
        args += ["-e", name]
    args += ["-v", f"{path}:/runner.sql:ro", "postgres:17.6", "psql", "-X", "-A", "-t", "-v", "ON_ERROR_STOP=1", "-f", "/runner.sql"]
    proc = run(args, env=env, timeout=timeout)
    return proc.stdout, proc.stderr


def repo_root() -> Path:
    proc = run(["git", "rev-parse", "--show-toplevel"], timeout=20)
    return Path(proc.stdout.strip())


def git_show(commit: str, path: str, target: Path) -> None:
    root = repo_root()
    run(["git", "fetch", "origin", commit], cwd=root, timeout=60)
    proc = run(["git", "show", f"{commit}:{path}"], cwd=root, timeout=30)
    target.write_text(proc.stdout, encoding="utf-8")


def ensure_sources(work: Path) -> None:
    work.mkdir(parents=True, exist_ok=True)
    expected = {
        "forward.sql": (IG_SOURCE_SHA, FORWARD_PATH),
        "rollback.sql": (IG_SOURCE_SHA, ROLLBACK_PATH),
        "base_test.sql": (BASE_TEST_SHA, BASE_TEST_PATH),
        "config.toml": (IG_SOURCE_SHA, CONFIG_PATH),
    }
    for name, (commit, path) in expected.items():
        target = work / name
        if not target.exists():
            git_show(commit, path, target)


def require_cli() -> str:
    path = shutil.which("supabase")
    if not path:
        raise AdapterError("SUPABASE_CLI_MISSING")
    version = run([path, "--version"], timeout=20).stdout.strip()
    if version != "2.116.0":
        raise AdapterError(f"SUPABASE_CLI_VERSION_MISMATCH:{version}")
    return path


def cli(args: list[str], *, timeout: int = 180) -> str:
    return run([require_cli(), *args], timeout=timeout).stdout


def candidate_count_sql() -> str:
    names = ",".join("'" + x + "'" for x in CANDIDATE_FUNCTIONS)
    return f"(select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='programacion' and p.proname in ({names}))"


def ledger_state() -> dict[str, int]:
    sql = f"select json_build_object('f',(select count(*) from supabase_migrations.schema_migrations where version='{FORWARD_VERSION}'),'r',(select count(*) from supabase_migrations.schema_migrations where version='{ROLLBACK_VERSION}'),'objects',{candidate_count_sql()})::text;"
    return json.loads(docker_psql(sql))


def phase_preflight(work: Path) -> None:
    ensure_sources(work)
    require_cli()
    state = ledger_state()
    if state != {"f": 0, "r": 0, "objects": 0}:
        raise AdapterError(f"PREFLIGHT_STATE_INVALID:{state}")
    sql = "select position('fn_input_governance_curator_rebind_candidate_v1' in pg_get_functiondef('programacion.fn_input_governance_execute(integer,text)'::regprocedure))::int;"
    if int(docker_psql(sql) or "0") != 0:
        raise AdapterError("PREFLIGHT_LIVE_ENTRYPOINT_CONTAMINATED")
    print("PREFLIGHT_EXACT_PASS")


def build_mirror(work: Path) -> Path:
    ensure_sources(work)
    mirror = work / "mirror"
    if mirror.exists():
        shutil.rmtree(mirror)
    (mirror / "supabase").mkdir(parents=True)
    shutil.copy2(work / "config.toml", mirror / "supabase/config.toml")
    cli(["--workdir", str(mirror), "--yes", "migration", "fetch", "--db-url", db_url()], timeout=180)
    migrations = list((mirror / "supabase/migrations").glob("20????????????_*.sql"))
    if len(migrations) < 100:
        raise AdapterError(f"REMOTE_MIRROR_TOO_SMALL:{len(migrations)}")
    for version in ("20260906185000", "20260906185100"):
        if not list((mirror / "supabase/migrations").glob(version + "_*.sql")):
            raise AdapterError(f"REMOTE_REQUIRED_VERSION_MISSING:{version}")
    if list((mirror / "supabase/migrations").glob(FORWARD_VERSION + "_*.sql")) or list((mirror / "supabase/migrations").glob(ROLLBACK_VERSION + "_*.sql")):
        raise AdapterError("REMOTE_TARGET_VERSION_ALREADY_IN_MIRROR")
    return mirror


def phase_forward(work: Path) -> None:
    mirror = build_mirror(work)
    destination = mirror / "supabase/migrations" / f"{FORWARD_VERSION}_{FORWARD_NAME}.sql"
    shutil.copy2(work / "forward.sql", destination)
    dry = cli(["--workdir", str(mirror), "db", "push", "--db-url", db_url(), "--dry-run"], timeout=180)
    if FORWARD_VERSION not in dry or ROLLBACK_VERSION in dry:
        raise AdapterError("FORWARD_DRY_RUN_SCOPE_FAIL")
    cli(["--workdir", str(mirror), "--yes", "db", "push", "--db-url", db_url()], timeout=180)
    state = ledger_state()
    if state != {"f": 1, "r": 0, "objects": 4}:
        raise AdapterError(f"FORWARD_READBACK_FAIL:{state}")
    print("FORWARD_EXACT_PASS")


def augment_test_sql(source: str) -> str:
    anchor = "-- Durable readback: all test identities must have rolled back.\n"
    if anchor not in source:
        raise AdapterError("TEST_ANCHOR_MISSING")
    extra = """-- IG-A additional current controls.\nbegin;\nset local statement_timeout='120s';\nselect pg_temp.s28_ig_exact_case(57,'ONB_004') as s28_ig_exact_result;\nrollback;\nbegin;\nset local statement_timeout='120s';\nselect pg_temp.s28_ig_exact_case(3,'ONB_003') as s28_ig_exact_result;\nrollback;\nbegin;\nset local statement_timeout='120s';\nselect pg_temp.s28_ig_exact_case(2,'ONB_002') as s28_ig_exact_result;\nrollback;\ndo $stale$\ndeclare x bigint; v boolean;\nbegin\n  foreach x in array array[218::bigint,210::bigint,186::bigint,191::bigint] loop\n    v:=programacion.fn_input_readiness_run_is_current_cached_v2(x);\n    if v is distinct from false then raise exception 'S28_IGA_STALE_FALSE_CLOSE:run=% current=%',x,v; end if;\n  end loop;\n  raise notice 'S28_IGA_STALE_CONTROLS_PASS runs=218,210,186,191 false_close=0';\nend;\n$stale$;\n\n"""
    return source.replace(anchor, extra + anchor, 1)


def percentile(values: list[float], p: float) -> float:
    xs = sorted(values)
    k = (len(xs) - 1) * p
    lo, hi = math.floor(k), math.ceil(k)
    return xs[lo] if lo == hi else xs[lo] + (xs[hi] - xs[lo]) * (k - lo)


def phase_tests(work: Path) -> None:
    ensure_sources(work)
    test_path = work / "augmented_test.sql"
    test_path.write_text(augment_test_sql((work / "base_test.sql").read_text(encoding="utf-8")), encoding="utf-8")
    stdout, stderr = docker_psql_file(test_path, timeout=500)
    combined = stdout + "\n" + stderr
    for marker in ("S28_IGA_STALE_CONTROLS_PASS", "S28_IG_EXACT_CANARY_PASS"):
        if marker not in combined:
            raise AdapterError(f"TEST_MARKER_MISSING:{marker}")
    rows: list[dict] = []
    for line in stdout.splitlines():
        line = line.strip()
        if line.startswith("{") and "screen_code" in line:
            rows.append(json.loads(line))
    if len(rows) != 5:
        raise AdapterError(f"TEST_RESULT_CARDINALITY:{len(rows)}")
    expected_screens = {name for _, name in CURRENT_SCREENS}
    if {row.get("screen_code") for row in rows} != expected_screens:
        raise AdapterError("TEST_SCREEN_SET_MISMATCH")
    for row in rows:
        if row.get("result") != "PASS" or row.get("validator_pass_count") != 47 or row.get("semantic_diff_count") != 0 or row.get("missing_classifier_fingerprint_count") != 0:
            raise AdapterError(f"TEST_RESULT_NONPASS:{row.get('screen_code')}")
    curator = [float(row["curator_ms"]) for row in rows]
    validator = [float(row["validator_total_ms"]) for row in rows]
    metrics = {
        "current_screens_passed": 5,
        "stale_controls_passed": 4,
        "false_close": 0,
        "curator_p50_ms": round(percentile(curator, 0.50), 3),
        "curator_p95_ms": round(percentile(curator, 0.95), 3),
        "validator_total_p50_ms": round(percentile(validator, 0.50), 3),
        "validator_total_p95_ms": round(percentile(validator, 0.95), 3),
        "cases": sorted(rows, key=lambda row: row["screen_code"]),
    }
    (work / "metrics.json").write_text(json.dumps(metrics, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("IG_A_CONSUMER_PASS")


def phase_rollback(work: Path) -> None:
    ensure_sources(work)
    state = ledger_state()
    if state == {"f": 0, "r": 0, "objects": 0}:
        print("ROLLBACK_EXACT_PASS")
        return
    if state == {"f": 1, "r": 1, "objects": 0}:
        print("ROLLBACK_EXACT_PASS")
        return
    if state != {"f": 1, "r": 0, "objects": 4}:
        raise AdapterError(f"ROLLBACK_PRESTATE_INVALID:{state}")
    mirror = work / "mirror"
    if not mirror.exists():
        raise AdapterError("ROLLBACK_MIRROR_MISSING")
    destination = mirror / "supabase/migrations" / f"{ROLLBACK_VERSION}_{ROLLBACK_NAME}.sql"
    shutil.copy2(work / "rollback.sql", destination)
    dry = cli(["--workdir", str(mirror), "db", "push", "--db-url", db_url(), "--dry-run"], timeout=180)
    if ROLLBACK_VERSION not in dry:
        raise AdapterError("ROLLBACK_DRY_RUN_SCOPE_FAIL")
    cli(["--workdir", str(mirror), "--yes", "db", "push", "--db-url", db_url()], timeout=180)
    print("ROLLBACK_EXACT_PASS")


def phase_post_readback(work: Path) -> None:
    state = ledger_state()
    if state["objects"] != 0:
        raise AdapterError(f"POST_CANDIDATE_RESIDUE:{state}")
    if (state["f"], state["r"]) not in {(0, 0), (1, 1)}:
        raise AdapterError(f"POST_LEDGER_STATE_INVALID:{state}")
    sql = """
    select json_build_object(
      'rebind',encode(extensions.digest(convert_to(pg_get_functiondef('programacion.fn_input_governance_curator_rebind_v1(integer,text,text,boolean)'::regprocedure),'UTF8'),'sha256'),'hex'),
      'assertions',encode(extensions.digest(convert_to(pg_get_functiondef('programacion.fn_input_v58_build_assertions(bigint,bigint,text)'::regprocedure),'UTF8'),'sha256'),'hex'),
      'rebind_assertion',encode(extensions.digest(convert_to(pg_get_functiondef('programacion.fn_input_rebind_assertion(bigint,text,jsonb)'::regprocedure),'UTF8'),'sha256'),'hex'),
      'guard',encode(extensions.digest(convert_to(pg_get_functiondef('programacion.fn_guard_input_family_assessment_insert()'::regprocedure),'UTF8'),'sha256'),'hex'),
      'test_runs',(select count(*) from programacion.input_readiness_runs where curator_identity like 'INPUT_CURATOR:EDGE:input-governance-curator-v1:S28IGEXACT_%' or validator_identity like 'INPUT_VALIDATOR:EDGE:input-governance-validator-v1:S28IGEXACT_%'),
      'live_switched',position('fn_input_governance_curator_rebind_candidate_v1' in pg_get_functiondef('programacion.fn_input_governance_execute(integer,text)'::regprocedure))>0
    )::text;
    """
    details = json.loads(docker_psql(sql))
    for key, expected in BASELINE_SHA.items():
        if details.get(key) != expected:
            raise AdapterError(f"POST_BASELINE_SHA_MISMATCH:{key}")
    if details.get("test_runs") != 0 or details.get("live_switched") is not False:
        raise AdapterError(f"POST_RUNTIME_RESIDUE:{details}")
    (work / "post_readback.json").write_text(json.dumps({"ledger": state, "details": details}, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("ZERO_RESIDUE_PASS")


def build_manifest(work: Path) -> Path:
    runner = Path(__file__).with_name("lf_governed_canary_runner.py")
    adapter = Path(__file__).resolve()
    manifest = {
        "contract_version": RUNNER_VERSION,
        "canary_id": "S28:IG006-IG007-GENERIC-RUNNER-001",
        "change_mode": "MIGRATION_EXACT_VERSION",
        "exact_versions": {"forward": FORWARD_VERSION, "rollback": ROLLBACK_VERSION},
        "target": {"environment": "sandbox", "production": False, "merge_authorized": False, "automatic_promotion": False},
        "steps": {
            "preflight": [{"id": "IG_PREFLIGHT", "argv": [sys.executable, str(adapter), "--phase", "preflight", "--workdir", str(work)], "timeout_seconds": 90, "env_names": ["LF_SUPABASE_DB_PASSWORD"], "expect": {"exit_codes": [0], "stdout_contains": ["PREFLIGHT_EXACT_PASS"]}}],
            "forward": [{"id": "IG_FORWARD", "argv": [sys.executable, str(adapter), "--phase", "forward", "--workdir", str(work)], "timeout_seconds": 240, "env_names": ["LF_SUPABASE_DB_PASSWORD"], "expect": {"exit_codes": [0], "stdout_contains": ["FORWARD_EXACT_PASS"]}}],
            "tests": [{"id": "IG_TESTS", "argv": [sys.executable, str(adapter), "--phase", "tests", "--workdir", str(work)], "timeout_seconds": 600, "env_names": ["LF_SUPABASE_DB_PASSWORD"], "expect": {"exit_codes": [0], "stdout_contains": ["IG_A_CONSUMER_PASS"]}}],
            "rollback": [{"id": "IG_ROLLBACK", "argv": [sys.executable, str(adapter), "--phase", "rollback", "--workdir", str(work)], "timeout_seconds": 240, "env_names": ["LF_SUPABASE_DB_PASSWORD"], "expect": {"exit_codes": [0], "stdout_contains": ["ROLLBACK_EXACT_PASS"]}}],
            "post_readback": [{"id": "IG_POST_READBACK", "argv": [sys.executable, str(adapter), "--phase", "post_readback", "--workdir", str(work)], "timeout_seconds": 90, "env_names": ["LF_SUPABASE_DB_PASSWORD"], "expect": {"exit_codes": [0], "stdout_contains": ["ZERO_RESIDUE_PASS"]}}],
        },
        "evidence": {"output_path": str(work / "runner_evidence.json"), "include_raw_output": False, "require_post_readback": True, "require_zero_residue": True, "zero_residue_token": "ZERO_RESIDUE_PASS"},
    }
    path = work / "manifest.json"
    path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return path


def phase_run(work: Path) -> None:
    ensure_sources(work)
    manifest = build_manifest(work)
    runner = Path(__file__).with_name("lf_governed_canary_runner.py")
    proc = subprocess.run([sys.executable, str(runner), "--manifest", str(manifest)], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False, timeout=900)
    if proc.stdout:
        print(proc.stdout.strip())
    if proc.returncode != 0:
        raise AdapterError(f"GENERIC_RUNNER_FAILED:exit={proc.returncode}:stderr_sha256={sha(proc.stderr.encode())}")
    print("GENERIC_RUNNER_INPUT_GOVERNANCE_PASS")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--phase", choices=("preflight", "forward", "tests", "rollback", "post_readback", "run"), default="run")
    parser.add_argument("--workdir", type=Path, required=True)
    args = parser.parse_args()
    try:
        {
            "preflight": phase_preflight,
            "forward": phase_forward,
            "tests": phase_tests,
            "rollback": phase_rollback,
            "post_readback": phase_post_readback,
            "run": phase_run,
        }[args.phase](args.workdir)
        return 0
    except (AdapterError, subprocess.TimeoutExpired, json.JSONDecodeError, OSError) as exc:
        print(f"FAIL_ADAPTER:{type(exc).__name__}:{exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

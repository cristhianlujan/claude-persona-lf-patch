#!/usr/bin/env python3
"""Fresh exact-version IG006/IG007 adapter for LF_GOVERNED_CANARY_RUNNER_V1.

Candidate transport only. No production, merge, runtime switch, or automatic promotion.
The executable SQL is read from the exact checked-out PR head and guarded by
Git blob identity in the CI admission workflow.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys

import input_governance_ig006_ig007_adapter as base

FORWARD_VERSION = "20260907210811"
ROLLBACK_VERSION = "20260907210812"
FORWARD_NAME = "lf_input_governance_ig006_ig007_generic_runner_forward_v2"
ROLLBACK_NAME = "lf_input_governance_ig006_ig007_generic_runner_rollback_v2"
FORWARD_PATH = f"supabase/migrations/{FORWARD_VERSION}_{FORWARD_NAME}.sql"
ROLLBACK_PATH = f"supabase/migrations/{ROLLBACK_VERSION}_{ROLLBACK_NAME}.sql"
EXECUTE_SHA = "3290e752c27a46a089ed93d9a15769b7b9ca416f00d389c681431fde977da588"
BASE_TEST_FORWARD_VERSION = "20260907023000"
BASE_TEST_ROLLBACK_VERSION = "20260907023100"
BASE_TEST_FORWARD_NAME = "lf_input_governance_ig006_ig007_exact_canary_forward_v1"

# Pin the existing domain adapter to the fresh exact-version pair.
base.FORWARD_VERSION = FORWARD_VERSION
base.ROLLBACK_VERSION = ROLLBACK_VERSION
base.FORWARD_NAME = FORWARD_NAME
base.ROLLBACK_NAME = ROLLBACK_NAME
base.FORWARD_PATH = FORWARD_PATH
base.ROLLBACK_PATH = ROLLBACK_PATH

_original_tests = base.phase_tests
_original_post = base.phase_post_readback
_original_ensure_sources = base.ensure_sources


def ensure_sources(work: Path) -> None:
    """Bind SQL to the exact checked-out head; keep historical test source pinned."""
    work.mkdir(parents=True, exist_ok=True)
    root = base.repo_root()
    for source_path, target_name in (
        (FORWARD_PATH, "forward.sql"),
        (ROLLBACK_PATH, "rollback.sql"),
        (base.CONFIG_PATH, "config.toml"),
    ):
        source = root / source_path
        if not source.is_file():
            raise base.AdapterError(f"EXACT_HEAD_SOURCE_MISSING:{source_path}")
        shutil.copy2(source, work / target_name)
    base_test = work / "base_test.sql"
    if not base_test.exists():
        base.git_show(base.BASE_TEST_SHA, base.BASE_TEST_PATH, base_test)


base.ensure_sources = ensure_sources


def cli(args: list[str], *, timeout: int = 180) -> str:
    patched = list(args)
    if "db" in patched and "push" in patched and "--include-all" not in patched:
        patched.append("--include-all")
    proc = base.run([base.require_cli(), *patched], timeout=timeout)
    # Supabase CLI emits dry-run planning text across stdout/stderr. Inspect the
    # combined in-memory stream, matching the previously proven exact-version
    # workflow. The generic runner still persists only hashes, never raw output.
    return (proc.stdout + "\n" + proc.stderr).strip()


base.cli = cli


def _docker_args() -> tuple[list[str], dict[str, str]]:
    env = base.pg_env()
    args = ["docker", "run", "--rm"]
    for name in ("PGHOST", "PGPORT", "PGUSER", "PGPASSWORD", "PGDATABASE", "PGSSLMODE"):
        args += ["-e", name]
    return args, env


def docker_psql(sql: str, *, timeout: int = 120) -> str:
    args, env = _docker_args()
    args += ["postgres:17.6", "psql", "-X", "-qAt", "-v", "ON_ERROR_STOP=1", "-c", sql]
    return base.run(args, env=env, timeout=timeout).stdout.strip()


def docker_psql_file(path: Path, *, timeout: int = 500) -> tuple[str, str]:
    args, env = _docker_args()
    args += ["-v", f"{path}:/runner.sql:ro", "postgres:17.6", "psql", "-X", "-qAt", "-v", "ON_ERROR_STOP=1", "-f", "/runner.sql"]
    proc = base.run(args, env=env, timeout=timeout)
    return proc.stdout, proc.stderr


base.docker_psql = docker_psql
base.docker_psql_file = docker_psql_file


def _rebuild_rollback_mirror(work: Path) -> Path:
    base.ensure_sources(work)
    mirror = work / "rollback_recovery_mirror"
    if mirror.exists():
        shutil.rmtree(mirror)
    (mirror / "supabase").mkdir(parents=True)
    shutil.copy2(work / "config.toml", mirror / "supabase/config.toml")
    base.cli(["--workdir", str(mirror), "--yes", "migration", "fetch", "--db-url", base.db_url()], timeout=180)
    if not list((mirror / "supabase/migrations").glob(FORWARD_VERSION + "_*.sql")):
        raise base.AdapterError("ROLLBACK_RECOVERY_FORWARD_LEDGER_SOURCE_MISSING")
    if list((mirror / "supabase/migrations").glob(ROLLBACK_VERSION + "_*.sql")):
        raise base.AdapterError("ROLLBACK_RECOVERY_ROLLBACK_ALREADY_PRESENT")
    return mirror


def phase_rollback(work: Path) -> None:
    base.ensure_sources(work)
    state = base.ledger_state()
    if state in ({"f": 0, "r": 0, "objects": 0}, {"f": 1, "r": 1, "objects": 0}):
        print("ROLLBACK_EXACT_PASS")
        return
    if state not in ({"f": 1, "r": 0, "objects": 4}, {"f": 1, "r": 0, "objects": 0}):
        raise base.AdapterError(f"ROLLBACK_PRESTATE_INVALID:{state}")

    mirror = work / "mirror"
    if state["objects"] == 0 or not mirror.exists():
        mirror = _rebuild_rollback_mirror(work)
    destination = mirror / "supabase/migrations" / f"{ROLLBACK_VERSION}_{ROLLBACK_NAME}.sql"
    shutil.copy2(work / "rollback.sql", destination)
    dry = base.cli(["--workdir", str(mirror), "db", "push", "--db-url", base.db_url(), "--dry-run"], timeout=180)
    if ROLLBACK_VERSION not in dry:
        raise base.AdapterError("ROLLBACK_DRY_RUN_SCOPE_FAIL")
    base.cli(["--workdir", str(mirror), "--yes", "db", "push", "--db-url", base.db_url()], timeout=180)
    final = base.ledger_state()
    if final != {"f": 1, "r": 1, "objects": 0}:
        raise base.AdapterError(f"ROLLBACK_READBACK_FAIL:{final}")
    print("ROLLBACK_EXACT_PASS")


base.phase_rollback = phase_rollback


def _bind_test_template(work: Path) -> None:
    base.ensure_sources(work)
    path = work / "base_test.sql"
    source = path.read_text(encoding="utf-8")
    required = (BASE_TEST_FORWARD_VERSION, BASE_TEST_ROLLBACK_VERSION, BASE_TEST_FORWARD_NAME)
    missing = [token for token in required if token not in source]
    if missing:
        raise base.AdapterError("TEST_TEMPLATE_BINDING_ANCHOR_MISSING:" + ",".join(missing))
    source = source.replace(BASE_TEST_FORWARD_VERSION, FORWARD_VERSION)
    source = source.replace(BASE_TEST_ROLLBACK_VERSION, ROLLBACK_VERSION)
    source = source.replace(BASE_TEST_FORWARD_NAME, FORWARD_NAME)
    stale = [token for token in required if token in source]
    if stale:
        raise base.AdapterError("TEST_TEMPLATE_BINDING_STALE_TOKEN:" + ",".join(stale))
    if FORWARD_VERSION not in source or ROLLBACK_VERSION not in source or FORWARD_NAME not in source:
        raise base.AdapterError("TEST_TEMPLATE_BINDING_TARGET_MISSING")
    path.write_text(source, encoding="utf-8")
    print("TEST_TEMPLATE_EXACT_PAIR_BIND_PASS")


def phase_tests(work: Path) -> None:
    _bind_test_template(work)
    _original_tests(work)
    metrics_path = work / "metrics.json"
    metrics = json.loads(metrics_path.read_text(encoding="utf-8"))
    metrics["measurement_scope"] = "FIVE_SCREEN_HETEROGENEOUS_PORTFOLIO_SAMPLE_NOT_PER_SCREEN_SLA"
    for key in ("curator_p50_ms", "curator_p95_ms", "validator_total_p50_ms", "validator_total_p95_ms"):
        if key in metrics:
            metrics["portfolio_sample_" + key] = metrics.pop(key)
    metrics_path.write_text(json.dumps(metrics, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("IG_A_PORTFOLIO_SAMPLE_LABEL_PASS")


base.phase_tests = phase_tests


def phase_post_readback(work: Path) -> None:
    _original_post(work)
    execute_sha = docker_psql("select encode(extensions.digest(convert_to(pg_get_functiondef('programacion.fn_input_governance_execute(integer,text)'::regprocedure),'UTF8'),'sha256'),'hex');")
    if execute_sha != EXECUTE_SHA:
        raise base.AdapterError(f"POST_EXECUTE_SHA_MISMATCH:{execute_sha}")
    print("ZERO_RESIDUE_EXECUTE_SHA_PASS")


base.phase_post_readback = phase_post_readback


def build_manifest(work: Path) -> Path:
    adapter = Path(__file__).resolve()
    steps = {}
    for phase, timeout, token in (
        ("preflight", 90, "PREFLIGHT_EXACT_PASS"),
        ("forward", 240, "FORWARD_EXACT_PASS"),
        ("tests", 600, "IG_A_CONSUMER_PASS"),
        ("rollback", 240, "ROLLBACK_EXACT_PASS"),
        ("post_readback", 90, "ZERO_RESIDUE_PASS"),
    ):
        steps[phase] = [{
            "id": "IG_" + phase.upper(),
            "argv": [sys.executable, str(adapter), "--phase", phase, "--workdir", str(work)],
            "timeout_seconds": timeout,
            "env_names": ["LF_SUPABASE_DB_PASSWORD"],
            "expect": {"exit_codes": [0], "stdout_contains": [token]},
        }]
    manifest = {
        "contract_version": base.RUNNER_VERSION,
        "canary_id": "S28:IG006-IG007-GENERIC-RUNNER-003",
        "change_mode": "MIGRATION_EXACT_VERSION",
        "exact_versions": {"forward": FORWARD_VERSION, "rollback": ROLLBACK_VERSION},
        "target": {"environment": "sandbox", "production": False, "merge_authorized": False, "automatic_promotion": False},
        "steps": steps,
        "evidence": {"output_path": str(work / "runner_evidence.json"), "include_raw_output": False, "require_post_readback": True, "require_zero_residue": True, "zero_residue_token": "ZERO_RESIDUE_PASS"},
    }
    path = work / "manifest.json"
    path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return path


def phase_run(work: Path) -> None:
    base.ensure_sources(work)
    manifest = build_manifest(work)
    runner = Path(__file__).with_name("lf_governed_canary_runner.py")
    proc = subprocess.run([sys.executable, str(runner), "--manifest", str(manifest)], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False, timeout=900)
    if proc.stdout:
        print(proc.stdout.strip())
    if proc.returncode != 0:
        raise base.AdapterError(f"GENERIC_RUNNER_FAILED:exit={proc.returncode}:stderr_sha256={base.sha(proc.stderr.encode())}")
    print("GENERIC_RUNNER_INPUT_GOVERNANCE_V2_PASS")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--phase", choices=("preflight", "forward", "tests", "rollback", "post_readback", "run"), default="run")
    parser.add_argument("--workdir", type=Path, required=True)
    args = parser.parse_args()
    mapping = {
        "preflight": base.phase_preflight,
        "forward": base.phase_forward,
        "tests": phase_tests,
        "rollback": phase_rollback,
        "post_readback": phase_post_readback,
        "run": phase_run,
    }
    try:
        mapping[args.phase](args.workdir)
        return 0
    except (base.AdapterError, subprocess.TimeoutExpired, json.JSONDecodeError, OSError) as exc:
        print(f"FAIL_ADAPTER_V2:{type(exc).__name__}:{exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

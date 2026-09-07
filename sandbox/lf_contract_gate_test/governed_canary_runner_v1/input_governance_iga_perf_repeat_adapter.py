#!/usr/bin/env python3
"""IG-A repeated comparable performance campaign over the governed exact-version runner."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import subprocess
import sys

import input_governance_ig006_ig007_exact_v2_core as v2

FORWARD_VERSION = "20260907215800"
ROLLBACK_VERSION = "20260907215900"
FORWARD_NAME = "lf_input_governance_iga_perf_repeat_forward_v1"
ROLLBACK_NAME = "lf_input_governance_iga_perf_repeat_rollback_v1"
FORWARD_PATH = f"supabase/migrations/{FORWARD_VERSION}_{FORWARD_NAME}.sql"
ROLLBACK_PATH = f"supabase/migrations/{ROLLBACK_VERSION}_{ROLLBACK_NAME}.sql"

for module in (v2, v2.base):
    module.FORWARD_VERSION = FORWARD_VERSION
    module.ROLLBACK_VERSION = ROLLBACK_VERSION
    module.FORWARD_NAME = FORWARD_NAME
    module.ROLLBACK_NAME = ROLLBACK_NAME
    module.FORWARD_PATH = FORWARD_PATH
    module.ROLLBACK_PATH = ROLLBACK_PATH

base = v2.base
docker_psql = v2.docker_psql
phase_rollback = v2.phase_rollback
phase_post_readback = v2.phase_post_readback

FORWARD_BLOB = "d806d88176e21bcee1de7545c65e776a6e051899"
ROLLBACK_BLOB = "290ff2e1c50ca7d0bf2167a9f424380450de0c93"

def phase_preflight(work: Path) -> None:
    v2.base.phase_preflight(work)
    root = v2.base.repo_root()
    for rel, expected in ((FORWARD_PATH, FORWARD_BLOB), (ROLLBACK_PATH, ROLLBACK_BLOB)):
        got = v2.base.run(["git", "hash-object", str(root / rel)], timeout=20).stdout.strip()
        if got != expected:
            raise v2.base.AdapterError(f"IGA_REPEAT_SOURCE_BLOB_MISMATCH:{rel}:{got}")
    print("IGA_REPEAT_SOURCE_IDENTITY_PASS")

def _case_block(pantalla_id: int, screen_code: str) -> str:
    return (
        "begin;\n"
        "set local statement_timeout='120s';\n"
        f"select pg_temp.s28_ig_exact_case({pantalla_id},'{screen_code}') as s28_ig_exact_result;\n"
        "rollback;\n"
    )

def phase_tests(work: Path) -> None:
    v2._bind_test_template(work)
    source = (work / "base_test.sql").read_text(encoding="utf-8")
    gold_anchor = "-- GOLD control 1: B2B-CARGA-001."
    durable_anchor = "-- Durable readback: all test identities must have rolled back."
    if gold_anchor not in source or durable_anchor not in source:
        raise v2.base.AdapterError("IGA_REPEAT_TEMPLATE_ANCHOR_MISSING")
    prefix = source.split(gold_anchor, 1)[0]
    durable = durable_anchor + source.split(durable_anchor, 1)[1]
    body = prefix
    for _ in range(3):
        body += _case_block(43, "B2B-CARGA-001")
    for _ in range(3):
        body += _case_block(5, "HOME_002")
    body += durable

    test_path = work / "iga_repeat_perf.sql"
    test_path.write_text(body, encoding="utf-8")
    stdout, stderr = v2.docker_psql_file(test_path, timeout=850)
    combined = stdout + "\n" + stderr
    if "S28_IG_EXACT_CANARY_PASS" not in combined:
        raise v2.base.AdapterError("IGA_REPEAT_DURABLE_MARKER_MISSING")

    rows = []
    for line in stdout.splitlines():
        line = line.strip()
        if line.startswith("{") and '"screen_code"' in line:
            rows.append(json.loads(line))
    if len(rows) != 6:
        raise v2.base.AdapterError(f"IGA_REPEAT_RESULT_CARDINALITY:{len(rows)}")

    grouped = {"B2B-CARGA-001": [], "HOME_002": []}
    for row in rows:
        screen = row.get("screen_code")
        if screen not in grouped:
            raise v2.base.AdapterError(f"IGA_REPEAT_UNEXPECTED_SCREEN:{screen}")
        if (
            row.get("result") != "PASS"
            or row.get("validator_pass_count") != 47
            or row.get("semantic_diff_count") != 0
            or row.get("missing_classifier_fingerprint_count") != 0
        ):
            raise v2.base.AdapterError(f"IGA_REPEAT_RESULT_NONPASS:{screen}")
        curator = float(row["curator_ms"])
        validator = float(row["validator_total_ms"])
        max_chunk = float(row["validator_max_chunk_ms"])
        caller = curator + validator
        if curator >= 30000:
            raise v2.base.AdapterError(f"IGA_REPEAT_CURATOR_GATE:{screen}:{curator}")
        if max_chunk >= 30000:
            raise v2.base.AdapterError(f"IGA_REPEAT_VALIDATOR_CHUNK_GATE:{screen}:{max_chunk}")
        if caller >= 120000:
            raise v2.base.AdapterError(f"IGA_REPEAT_CALLER_GATE:{screen}:{caller}")
        grouped[screen].append({
            "curator_ms": curator,
            "validator_total_ms": validator,
            "validator_max_chunk_ms": max_chunk,
            "caller_total_ms": round(caller, 3),
            "validator_calls": row.get("validator_calls"),
            "validator_pass_count": row.get("validator_pass_count"),
            "semantic_diff_count": row.get("semantic_diff_count"),
            "missing_classifier_fingerprint_count": row.get("missing_classifier_fingerprint_count"),
        })

    if any(len(v) != 3 for v in grouped.values()):
        raise v2.base.AdapterError("IGA_REPEAT_GROUP_CARDINALITY")

    payload = {
        "measurement_scope": "THREE_ADDITIONAL_COMPARABLE_SAMPLES_PER_GOLD_SCREEN_FOR_N5_COMBINATION",
        "fresh_samples_per_screen": 3,
        "quality_gates": {
            "validator_47_of_47": "PASS_6_OF_6",
            "semantic_diff_zero": "PASS_6_OF_6",
            "classifier_fingerprint_missing_zero": "PASS_6_OF_6",
            "curator_under_30s": "PASS_6_OF_6",
            "validator_max_chunk_under_30s": "PASS_6_OF_6",
            "caller_total_under_120s": "PASS_6_OF_6"
        },
        "screens": grouped,
    }
    (work / "perf_repeat_metrics.json").write_text(
        json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    (work / "metrics.json").write_text(
        json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    print("IG_A_REPEAT_PERF_PASS")

def build_manifest(work: Path) -> Path:
    adapter = Path(__file__).resolve()
    steps = {}
    for phase, timeout, token in (
        ("preflight", 90, "PREFLIGHT_EXACT_PASS"),
        ("forward", 240, "FORWARD_EXACT_PASS"),
        ("tests", 1000, "IG_A_REPEAT_PERF_PASS"),
        ("rollback", 240, "ROLLBACK_EXACT_PASS"),
        ("post_readback", 90, "ZERO_RESIDUE_PASS"),
    ):
        steps[phase] = [{
            "id": "IGA_REPEAT_" + phase.upper(),
            "argv": [sys.executable, str(adapter), "--phase", phase, "--workdir", str(work)],
            "timeout_seconds": timeout,
            "env_names": ["LF_SUPABASE_DB_PASSWORD"],
            "expect": {"exit_codes": [0], "stdout_contains": [token]},
        }]
    manifest = {
        "contract_version": v2.base.RUNNER_VERSION,
        "canary_id": "S28:IGA-PERF-REPEAT-001",
        "change_mode": "MIGRATION_EXACT_VERSION",
        "exact_versions": {"forward": FORWARD_VERSION, "rollback": ROLLBACK_VERSION},
        "target": {
            "environment": "sandbox",
            "production": False,
            "merge_authorized": False,
            "automatic_promotion": False,
        },
        "steps": steps,
        "evidence": {
            "output_path": str(work / "runner_evidence.json"),
            "include_raw_output": False,
            "require_post_readback": True,
            "require_zero_residue": True,
            "zero_residue_token": "ZERO_RESIDUE_PASS",
        },
    }
    path = work / "manifest.json"
    path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return path

def phase_run(work: Path) -> None:
    v2.ensure_sources(work)
    manifest = build_manifest(work)
    runner = Path(__file__).with_name("lf_governed_canary_runner.py")
    proc = subprocess.run(
        [sys.executable, str(runner), "--manifest", str(manifest)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
        timeout=1200,
    )
    if proc.stdout:
        print(proc.stdout.strip())
    if proc.returncode != 0:
        raise v2.base.AdapterError(
            f"IGA_REPEAT_GENERIC_RUNNER_FAILED:exit={proc.returncode}:"
            f"stderr_sha256={v2.base.sha(proc.stderr.encode())}"
        )
    print("IG_A_REPEAT_GENERIC_RUNNER_PASS")

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--phase",
        choices=("preflight", "forward", "tests", "rollback", "post_readback", "run"),
        default="run",
    )
    parser.add_argument("--workdir", type=Path, required=True)
    args = parser.parse_args()
    mapping = {
        "preflight": phase_preflight,
        "forward": v2.base.phase_forward,
        "tests": phase_tests,
        "rollback": v2.phase_rollback,
        "post_readback": v2.phase_post_readback,
        "run": phase_run,
    }
    try:
        mapping[args.phase](args.workdir)
        return 0
    except (v2.base.AdapterError, subprocess.TimeoutExpired, json.JSONDecodeError, OSError) as exc:
        print(f"FAIL_IGA_REPEAT:{type(exc).__name__}:{exc}", file=sys.stderr)
        return 1

if __name__ == "__main__":
    raise SystemExit(main())

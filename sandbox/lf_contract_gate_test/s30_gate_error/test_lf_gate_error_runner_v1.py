#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
RUNNER_PATH = ROOT / "gobernanza" / "judges" / "lf_gate_error_runner_v1.py"

spec = importlib.util.spec_from_file_location("lf_gate_error_runner_v1", RUNNER_PATH)
assert spec is not None and spec.loader is not None
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)

assert runner.SCHEMA_VERSION == "LF_GATE_ERROR_V1"
assert runner.PRODUCER == "LF_GATE_ERROR_RUNNER_V1"
assert runner.self_test() == 0

sample = {
    "schema_version": runner.SCHEMA_VERSION,
    "producer": runner.PRODUCER,
    "suite_code": "DIGEST-ORDER",
    "source_sha": "c" * 40,
    "run_id": "1",
    "job_name": "job",
    "schema_ref": "schema",
    "schema_sha256": "d" * 64,
    "test_pattern": "test_*.py",
    "test_count": 0,
    "failure_count": 0,
    "control_errors": [],
    "failures": [],
    "diagnostic_complete": True,
    "manifest_sha256": "",
}
digest_a = runner.manifest_digest(sample)
sample_reordered = dict(reversed(list(sample.items())))
digest_b = runner.manifest_digest(sample_reordered)
assert digest_a == digest_b, (digest_a, digest_b)

print("PASS_S30_R24_LF_GATE_ERROR_RUNNER_V1")

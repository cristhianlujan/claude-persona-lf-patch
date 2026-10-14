#!/usr/bin/env python3
"""Resolve independent CI database transport from trusted, versioned configuration.

The file is fetched with the trusted PR BASE, not from untrusted PR HEAD.
Credentials remain in GitHub Secrets. Nothing here grants write permissions.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[3]
CONFIG = ROOT / "sandbox/lf_contract_gate_test/ci_db_target/lf_ci_db_target_v1.json"
PROJECT = re.compile(r"[a-z0-9]{20}\Z")
POOLER = re.compile(r"[a-z0-9-]+(?:\.[a-z0-9-]+)*\.pooler\.supabase\.com\Z")
CONSUMERS = frozenset(("lf-independent-change-admission", "ig-runtime-candidate-judge"))


class TargetConfigError(ValueError):
    pass


def require(ok: bool, code: str) -> None:
    if not ok:
        raise TargetConfigError(code)


def validate(value: object, consumer: str) -> tuple[str, str]:
    require(isinstance(value, dict), "TARGET_CONFIG_OBJECT_REQUIRED")
    config = value
    require(config.get("schema_version") == "LF_CI_DB_TARGET_V1", "TARGET_CONFIG_SCHEMA_INVALID")
    require(config.get("scope") == "TRUSTED_GITHUB_BASE_CI_ONLY", "TARGET_SCOPE_INVALID")
    require(config.get("purpose") == "INDEPENDENT_ADMISSION_AND_ROLLBACK_ONLY_IG_JUDGE", "TARGET_PURPOSE_INVALID")
    require(config.get("pase_applicability") == "NOT_APPLICABLE", "TARGET_PASE_BOUNDARY_INVALID")
    expected_sources = {"lf-independent-change-admission": "GITHUB_ACTIONS_SECRET_LF_SUPABASE_DB_READONLY_PASSWORD", "ig-runtime-candidate-judge": "GITHUB_ACTIONS_SECRET_LF_SUPABASE_DB_PASSWORD"}
    require(config.get("credential_sources") == expected_sources, "TARGET_CREDENTIAL_BOUNDARY_INVALID")
    require(config.get("credential_sources", {}).get(consumer) == expected_sources[consumer], "TARGET_CONSUMER_CREDENTIAL_INVALID")
    consumers = config.get("allowed_consumers")
    require(isinstance(consumers, list) and set(consumers) == CONSUMERS, "TARGET_CONSUMER_COVERAGE_INVALID")
    require(consumer in CONSUMERS, "TARGET_CONSUMER_UNSUPPORTED")
    target = config.get("target")
    require(isinstance(target, dict) and set(target) == {"project_id", "pooler_host"}, "TARGET_SHAPE_INVALID")
    project = target["project_id"]
    host = target["pooler_host"]
    require(isinstance(project, str) and PROJECT.fullmatch(project) is not None, "TARGET_PROJECT_INVALID")
    require(isinstance(host, str) and POOLER.fullmatch(host) is not None, "TARGET_POOLER_INVALID")
    return project, host


def load(consumer: str) -> tuple[str, str, str]:
    raw = CONFIG.read_bytes()
    project, host = validate(json.loads(raw), consumer)
    return project, host, hashlib.sha256(raw).hexdigest()


def self_test() -> None:
    project, host, sha = load("ig-runtime-candidate-judge")
    require(bool(project and host and len(sha) == 64), "TARGET_SELF_TEST_BAD")
    data = json.loads(CONFIG.read_text(encoding="utf-8"))
    validate(data, "lf-independent-change-admission")
    for bad in (
        {**data, "target": {"project_id": "", "pooler_host": host}},
        {**data, "target": {"project_id": project, "pooler_host": ""}},
        {**data, "target": {"project_id": project, "pooler_host": host + "\nEVIL=1"}},
        {**data, "pase_applicability": "ACTIVE"},
        {**data, "allowed_consumers": ["ig-runtime-candidate-judge"]},
        {**data, "credential_sources": {**data["credential_sources"], "ig-runtime-candidate-judge": "GITHUB_ACTIONS_SECRET_LF_SUPABASE_DB_READONLY_PASSWORD"}},
        {**data, "credential_sources": {**data["credential_sources"], "lf-independent-change-admission": "GITHUB_ACTIONS_SECRET_LF_SUPABASE_DB_PASSWORD"}},
    ):
        try:
            validate(bad, "ig-runtime-candidate-judge")
        except TargetConfigError:
            continue
        raise AssertionError("NEGATIVE_CONFIG_NOT_REJECTED")
    print("PASS_LF_CI_DB_TARGET_SELF_TEST negative=7 independent_consumers=2")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=("self-test", "emit-env"))
    parser.add_argument("--consumer", choices=sorted(CONSUMERS))
    args = parser.parse_args()
    if args.command == "self-test":
        self_test()
        return 0
    require(bool(args.consumer), "TARGET_CONSUMER_REQUIRED")
    output = os.environ.get("GITHUB_ENV", "")
    require(bool(output), "GITHUB_ENV_MISSING")
    project, host, sha = load(args.consumer)
    with open(output, "a", encoding="utf-8") as handle:
        handle.write("SUPABASE_PROJECT_ID=" + project + "\n")
        handle.write("SUPABASE_POOLER_HOST=" + host + "\n")
    print(f"PASS_GOVERNED_CI_DB_TARGET consumer={args.consumer} config_sha256={sha}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import importlib.util
import os
from pathlib import Path
import sys
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[3]
ENTRY_PATH = ROOT / "sandbox/lf_contract_gate_test/migration_source_parity/run_migration_source_parity_pase_entry_v1.py"
CI_CONTEXT_PATH = ROOT / "sandbox/lf_contract_gate_test/migration_source_parity/lf_migration_source_parity_ci_context.py"

def load(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise SystemExit("FAIL_MSP_SCENARIO_EVIDENCE_LOAD")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module

ENTRY = load(ENTRY_PATH, "msp_scenario_evidence_entry")
CI_CONTEXT = load(CI_CONTEXT_PATH, "msp_scenario_evidence_ci_context")
FULL = ENTRY.FOCAL.FULL

def result(stdout: str = "", stderr: str = "", returncode: int = 0):
    return SimpleNamespace(stdout=stdout, stderr=stderr, returncode=returncode)

def expect_error(fn, prefix: str) -> None:
    try:
        fn()
    except RuntimeError as exc:
        if not str(exc).startswith(prefix): raise
    else:
        raise AssertionError(f"expected {prefix}")

def context_probe(*, event: str, live_ref: str, merge_base: str, actual_head: str | None = None):
    base, head = "a"*40, "b"*40
    actual_head = head if actual_head is None else actual_head
    old_git = ENTRY.FOCAL.FULL._git
    def fake_git(*args: str, **_kwargs):
        if args[:2] == ("fetch","--no-tags"): return result()
        if args[:2] == ("rev-parse","HEAD"): return result(actual_head + "\n")
        if args and args[0] == "rev-parse" and len(args)>1 and args[1].startswith("refs/remotes/origin/"): return result(live_ref + "\n")
        if args and args[0] == "merge-base": return result(merge_base + "\n")
        raise AssertionError(args)
    ENTRY.FOCAL.FULL._git = fake_git
    try:
        ENTRY._verify_exact_context_event_aware(base, head, "main", event)
    finally:
        ENTRY.FOCAL.FULL._git = old_git

def main() -> int:
    base, head = "a"*40, "b"*40
    checks = 0
    assert ENTRY._expected_live_ref_sha("pull_request",base,head) == base
    print("PASS_SCENARIO_MSP_PR_CURRENTNESS"); checks += 1
    assert ENTRY._expected_live_ref_sha("push",base,head) == head
    print("PASS_SCENARIO_MSP_PUSH_CURRENTNESS"); checks += 1
    expect_error(lambda: ENTRY._expected_live_ref_sha("schedule",base,head),"FAIL_MIGRATION_PARITY_PASE_ENTRY_EVENT")
    print("PASS_SCENARIO_MSP_UNKNOWN_EVENT_BLOCK"); checks += 1
    expect_error(lambda: context_probe(event="pull_request",live_ref="c"*40,merge_base=base),"FAIL_MIGRATION_PARITY_FOCAL_REF_CURRENTNESS")
    print("PASS_SCENARIO_MSP_STALE_CURRENTNESS_BLOCK"); checks += 1
    expect_error(lambda: context_probe(event="push",live_ref="c"*40,merge_base=base),"FAIL_MIGRATION_PARITY_FOCAL_REF_CURRENTNESS")
    print("PASS_SCENARIO_MSP_CONCURRENT_MAIN_ADVANCE_BLOCK"); checks += 1
    expect_error(lambda: context_probe(event="pull_request",live_ref=base,merge_base="c"*40),"FAIL_MIGRATION_PARITY_BASE_NOT_ANCESTOR")
    print("PASS_SCENARIO_MSP_BASE_NOT_ANCESTOR_BLOCK"); checks += 1
    expect_error(lambda: context_probe(event="pull_request",live_ref=base,merge_base=base,actual_head="c"*40),"FAIL_MIGRATION_PARITY_EXACT_HEAD")
    print("PASS_SCENARIO_MSP_STALE_HEAD_BLOCK"); checks += 1

    add = "A\tsupabase/migrations/20261002010101_lf_probe.sql\n"
    mod = "M\tsupabase/migrations/20261002010101_lf_probe.sql\n"
    assert ENTRY.FOCAL._parse_name_status(add) == ["supabase/migrations/20261002010101_lf_probe.sql"]
    print("PASS_SCENARIO_MSP_MIGRATION_ADD"); checks += 1
    assert ENTRY.FOCAL._parse_name_status(mod) == ["supabase/migrations/20261002010101_lf_probe.sql"]
    print("PASS_SCENARIO_MSP_MIGRATION_MODIFY"); checks += 1
    expect_error(lambda: ENTRY.FOCAL._parse_name_status("D\tsupabase/migrations/20261002010101_lf_probe.sql\n"),"FAIL_MIGRATION_PARITY_FOCAL_MIGRATION_CHANGE_STATUS")
    expect_error(lambda: ENTRY.FOCAL._parse_name_status("R100\tsupabase/migrations/20261002010101_lf_old.sql\tsupabase/migrations/20261002010102_lf_new.sql\n"),"FAIL_MIGRATION_PARITY_FOCAL_MIGRATION_CHANGE_STATUS")
    print("PASS_SCENARIO_MSP_MIGRATION_DELETE_RENAME_BLOCK"); checks += 1
    historical_version = str(int(ENTRY.FOCAL.FULL.CUTOVER) - 1).zfill(14)
    expect_error(lambda: ENTRY.FOCAL._parse_name_status(f"M\tsupabase/migrations/{historical_version}_lf_historical.sql\n"),"FAIL_MIGRATION_PARITY_FOCAL_HISTORICAL_MUTATION")
    print("PASS_SCENARIO_MSP_HISTORICAL_CAUSAL_BLOCK"); checks += 1

    adapter = FULL._load_parity_adapter()
    sql = "select 1;\n"
    direct_sha = hashlib.sha256(adapter._core.transport.canonical(sql)).hexdigest()
    local = {"20261002010101":("lf_probe",direct_sha,sql)}
    remote = {"20261002010101":("lf_probe",direct_sha)}
    counts = {"20261002010101":1}
    exact = adapter._core.evaluate_exact_parity(local,remote,counts)
    assert exact.status == "PASS" and exact.code == "PASS_LF_MIGRATION_SOURCE_PARITY"
    print("PASS_SCENARIO_MSP_VERSION_CONTENT_PARITY"); print("PASS_SCENARIO_MSP_ALREADY_APPLIED_EXACT"); checks += 2
    try:
        adapter._core.evaluate_exact_parity(local,{"20261002010101":("lf_probe","0"*64)},counts)
    except adapter._core.ParityCoreError as exc:
        if exc.code != "FAIL_LF_MIGRATION_CONTENT_PARITY": raise
    else:
        raise AssertionError("divergent same-version content accepted")
    print("PASS_SCENARIO_MSP_SAME_VERSION_DIVERGENT_BLOCK"); checks += 1

    # Reuse the canonical owner modules for authority/transport behavior instead
    # of re-implementing those rules in the scenario matrix.
    CI_CONTEXT.external_owner_self_test()
    print("PASS_SCENARIO_MSP_AUTHORITY_WRONG_BLOCK"); checks += 1
    CI_CONTEXT.transport_self_test()
    print("PASS_SCENARIO_MSP_TRANSPORT_RETRY_IDEMPOTENT"); checks += 1

    old_run = FULL.subprocess.run
    FULL.subprocess.run = lambda *_args, **_kwargs: result(stderr="simulated dependency unavailable",returncode=1)
    try:
        expect_error(lambda: FULL._psql("select 1",env={}),"FAIL_LF_MIGRATION_PARITY_DB_QUERY")
    finally:
        FULL.subprocess.run = old_run
    print("PASS_SCENARIO_MSP_DEPENDENCY_UNAVAILABLE_BLOCK"); checks += 1

    saved = {key:os.environ.get(key) for key in ("LF_SUPABASE_DB_PASSWORD","PGPASSWORD","SUPABASE_PROJECT_ID","SUPABASE_POOLER_HOST")}
    try:
        for key in saved: os.environ.pop(key,None)
        expect_error(FULL._pg_env,"FAIL_LF_MIGRATION_PARITY_DB_PASSWORD_MISSING")
    finally:
        for key,value in saved.items():
            if value is not None: os.environ[key]=value
    print("PASS_SCENARIO_MSP_AUTHORITY_CONTEXT_MISSING_BLOCK"); checks += 1
    print(f"PASS_MSP_SCENARIO_EVIDENCE_V1={checks}/{checks}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())

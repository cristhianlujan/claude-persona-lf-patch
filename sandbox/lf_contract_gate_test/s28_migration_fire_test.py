#!/usr/bin/env python3
"""Strategy 28 fire-test Lot B: migration parity, new migrations, security/governance."""
from __future__ import annotations

import csv
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import time

from s28_ci_feedback_tier import classify

CUTOVER = "20260808031006"
BASELINE_END = "20260822195004"
LEGACY_SHA = "a" * 64
GRANDFATHER_SHA = "b" * 64
VALIDATOR = pathlib.Path(__file__).with_name("lf_migration_source_parity.py")


def make_base(root: pathlib.Path):
    migrations = root / "migrations"
    migrations.mkdir()
    checkpoint = migrations / "20260808031006_checkpoint.sql"
    checkpoint.write_text(
        f"-- LF_MIGRATION_SOURCE_CHECKPOINT_V1 cutover={CUTOVER} legacy_start=20260801063708 legacy_end=20260801170332 legacy_count=1 legacy_sha256={LEGACY_SHA}\nselect 1;\n",
        encoding="utf-8",
    )
    remote = root / "remote.csv"
    grandfather = root / "grandfather.csv"
    legacy = root / "legacy.csv"
    grandfather.write_text(f"1,{GRANDFATHER_SHA}\n", encoding="utf-8")
    legacy.write_text(f"1,{LEGACY_SHA}\n", encoding="utf-8")
    return migrations, remote, grandfather, legacy


def write_remote(path: pathlib.Path, rows):
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        for version, name, sql in rows:
            writer.writerow([version, name, sql.encode("utf-8").hex()])


def invoke(local_rows, remote_rows):
    with tempfile.TemporaryDirectory(prefix="s28-lotb-") as tmp:
        root = pathlib.Path(tmp)
        migrations, remote, grandfather, legacy = make_base(root)
        for version, name, sql in local_rows:
            (migrations / f"{version}_{name}.sql").write_text(sql, encoding="utf-8")
        write_remote(remote, remote_rows)
        env = dict(os.environ)
        env.update({
            "LF_MIGRATION_CUTOVER": CUTOVER,
            "LF_MIGRATION_CLASSIFICATION_BASELINE_END": BASELINE_END,
            "LF_MIGRATION_GRANDFATHERED_COUNT": "1",
            "LF_MIGRATION_GRANDFATHERED_SHA256": GRANDFATHER_SHA,
        })
        start = time.perf_counter()
        proc = subprocess.run([sys.executable, str(VALIDATOR), str(migrations), str(remote), str(grandfather), str(legacy)], text=True, capture_output=True, env=env, check=False)
        elapsed_ms = (time.perf_counter() - start) * 1000
        return proc.returncode, (proc.stdout + proc.stderr).strip(), elapsed_ms


MIGRATION_CASES = [
    ("B01","F05_MIGRATION_SOURCE_PARITY",[("20260904000101","lf_probe_exact","select 1;\n")],[("20260904000101","lf_probe_exact","select 1;\n")],"PASS"),
    ("B02","F05_MIGRATION_SOURCE_PARITY",[("20260904000102","lf_probe_canonical","-- local comment\r\nselect 2;\r\n")],[("20260904000102","lf_probe_canonical","select 2;\n")],"PASS"),
    ("B03","F05_MIGRATION_SOURCE_PARITY",[("20260904000103","lf_probe_mismatch","select 3;\n")],[("20260904000103","lf_probe_mismatch","select 4;\n")],"FAIL_LF_MIGRATION_CONTENT_PARITY"),
    ("B04","F05_MIGRATION_SOURCE_PARITY",[("20260904000104","lf_probe_missing_remote","select 5;\n")],[],"FAIL_LF_MIGRATION_VERSION_PARITY"),
    ("B05","F05_MIGRATION_SOURCE_PARITY",[],[("20260904000105","lf_probe_extra_remote","select 6;\n")],"FAIL_LF_MIGRATION_VERSION_PARITY"),
    ("B06","F05_MIGRATION_SOURCE_PARITY",[("20260904000106","lf_probe_name_a","select 7;\n")],[("20260904000106","lf_probe_name_b","select 7;\n")],"FAIL_LF_MIGRATION_CONTENT_PARITY"),
    ("B07","F06_NEW_MIGRATION_SCHEMA",[("20260904000201","totally_unknown_future_migration","select 8;\n")],[],"FAIL_UNCLASSIFIED_POST_CUTOVER_MIGRATION"),
    ("B08","F06_NEW_MIGRATION_SCHEMA",[],[("20260904000202","totally_unknown_remote_migration","select 9;\n")],"FAIL_UNCLASSIFIED_POST_CUTOVER_MIGRATION"),
    ("B09","F06_NEW_MIGRATION_SCHEMA",[("20260904000203","lf_new_schema_probe","create table if not exists public.s28_probe(id int);\n")],[("20260904000203","lf_new_schema_probe","create table if not exists public.s28_probe(id int);\n")],"PASS"),
    ("B10","F06_NEW_MIGRATION_SCHEMA",[("20260904000204","promote_router_compact_jit_v1","select 10;\n")],[("20260904000204","promote_router_compact_jit_v1","select 10;\n")],"PASS"),
    ("B11","F06_NEW_MIGRATION_SCHEMA",[("20260904000205","input_governance_probe","select 11;\n")],[("20260904000205","input_governance_probe","select 11;\n")],"PASS"),
    ("B12","F06_NEW_MIGRATION_SCHEMA",[("20260904000206","create_lf_unreviewed_future_change","select 12;\n")],[],"FAIL_UNCLASSIFIED_POST_CUTOVER_MIGRATION"),
]

SECURITY_CASES = [
    ("B13","F09_SECURITY_RLS_GOVERNANCE",("supabase/migrations/20260904000301_rls_hardening.sql",),False,"DEEP"),
    ("B14","F09_SECURITY_RLS_GOVERNANCE",("supabase/migrations/20260904000302_revoke_grants.sql",),False,"DEEP"),
    ("B15","F09_SECURITY_RLS_GOVERNANCE",("scripts/security_audit.py",),False,"DEEP"),
    ("B16","F09_SECURITY_RLS_GOVERNANCE",(".github/workflows/security-gate.yml",),False,"DEEP"),
    ("B17","F09_SECURITY_RLS_GOVERNANCE",("docs/security/threat-model.md",),False,"FAST"),
    ("B18","F09_SECURITY_RLS_GOVERNANCE",("docs/governance/rls-runbook.md",),False,"FAST"),
]


def main() -> int:
    rows = []
    failures = 0
    times = []
    for case_id, family, local_rows, remote_rows, expected in MIGRATION_CASES:
        code, output, elapsed_ms = invoke(local_rows, remote_rows)
        times.append(elapsed_ms)
        observed = "PASS" if code == 0 else output.split(":", 1)[0].splitlines()[-1]
        ok = observed == expected
        failures += 0 if ok else 1
        rows.append({"case_id":case_id,"family":family,"expected":expected,"observed":observed,"pass":ok,"elapsed_ms":round(elapsed_ms,2)})
    false_fast = 0
    for case_id, family, paths, final_evidence, expected_tier in SECURITY_CASES:
        decisions = [classify(paths, final_evidence=final_evidence) for _ in range(3)]
        deterministic = len({json.dumps(d.as_dict(), sort_keys=True) for d in decisions}) == 1
        decision = decisions[0]
        ok = deterministic and decision.tier == expected_tier
        if expected_tier == "DEEP" and decision.tier == "FAST":
            false_fast += 1
        failures += 0 if ok else 1
        rows.append({"case_id":case_id,"family":family,"expected":expected_tier,"observed":decision.tier,"reason":decision.reason,"pass":ok,"deterministic":deterministic})
    report = {"summary":{"cases":18,"migration_cases":12,"security_cases":6,"failures":failures,"false_fast":false_fast,"migration_validator_mean_ms":round(sum(times)/len(times),2),"hard_gate_pass":failures == 0 and false_fast == 0},"rows":rows}
    print("S28_FIRE_TEST_LOT_B_REPORT=" + json.dumps(report, sort_keys=True))
    print(f"PASS_S28_FIRE_TEST_LOT_B={18-failures}/18 FALSE_FAST={false_fast} FAILURES={failures}")
    summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary_path:
        with open(summary_path,"a",encoding="utf-8") as handle:
            s=report["summary"]
            handle.write("### Strategy 28 — Fire Test Lot B\n")
            handle.write(f"- cases: `{s['cases']}`\n- failures: `{s['failures']}`\n- false FAST: `{s['false_fast']}`\n")
            handle.write(f"- migration validator mean: `{s['migration_validator_mean_ms']} ms` (synthetic fixture execution only)\n")
    return 0 if report["summary"]["hard_gate_pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())

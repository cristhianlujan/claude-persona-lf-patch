#!/usr/bin/env python3
"""Deterministic source-only reconciliation for MIGRATION_SOURCE_PARITY.

Consumes one canonical parity failure evidence object, recovers and verifies the
exact historical migration source, and delegates Git persistence to
MIGRATION_WRITE_AHEAD_V1. It does not listen to CI workflows, classify unknown
migration owners, open pull requests, rerun parity, execute Saga, replay DDL,
mutate the migration ledger, or merge anything.
"""
from __future__ import annotations

import argparse
import ast
import csv
import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
DB_WRITE = ROOT / "sandbox/lf_contract_gate_test/db_write_transport/lf_migration_git_persist.py"
TRANSPORT_DIR = ROOT / "sandbox/lf_contract_gate_test"
sys.path.insert(0, str(TRANSPORT_DIR))
import migration_transport_normalization as transport

VERSION_RE = re.compile(r"20\d{12}")
SHA40 = re.compile(r"^[0-9a-f]{40}$")
SHA64 = re.compile(r"^[0-9a-f]{64}$")
PARITY_CONTRACT = "LF_GATE_ERROR_V1"
PARITY_PRODUCER = "LF_GATE_CHECK_OBSERVABILITY_V1"
PARITY_GATE_SUFFIX = "::MIGRATION_SOURCE_PARITY"
PARITY_STEP_ID = "migration_source_parity"
PARITY_SOURCE_PATH = "sandbox/lf_contract_gate_test/lf_migration_source_parity.py"
REPAIRABLE_FAILURE = "FAIL_LF_MIGRATION_VERSION_PARITY"
VERSION_PARITY_DETAIL = re.compile(
    r"^FAIL_LF_MIGRATION_VERSION_PARITY: remote_only=(?P<remote>\[[^\]]*\]) local_only=(?P<local>\[[^\]]*\])$"
)


def run(argv: list[str], *, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(argv, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=check, timeout=120)


def canonical_json(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def evidence_digest(report: dict[str, object]) -> str:
    payload = dict(report)
    payload.pop("manifest_sha256", None)
    return hashlib.sha256(canonical_json(payload).encode("utf-8")).hexdigest()


def _version_list(raw: str, label: str) -> list[str]:
    try:
        value = ast.literal_eval(raw)
    except (SyntaxError, ValueError) as exc:
        raise RuntimeError(f"MIGRATION_REPAIR_{label}_LIST_INVALID") from exc
    if not isinstance(value, list) or any(not isinstance(item, str) or VERSION_RE.fullmatch(item) is None for item in value):
        raise RuntimeError(f"MIGRATION_REPAIR_{label}_LIST_INVALID")
    return value


def parse_parity_finding(report: dict[str, object]) -> dict[str, str] | None:
    if not isinstance(report, dict):
        raise RuntimeError("MIGRATION_REPAIR_PARITY_EVIDENCE_OBJECT_REQUIRED")
    if report.get("contract") != PARITY_CONTRACT:
        raise RuntimeError("MIGRATION_REPAIR_PARITY_EVIDENCE_CONTRACT_INVALID")
    if report.get("producer") != PARITY_PRODUCER:
        raise RuntimeError("MIGRATION_REPAIR_PARITY_EVIDENCE_PRODUCER_INVALID")
    if not str(report.get("gate_id") or "").endswith(PARITY_GATE_SUFFIX):
        raise RuntimeError("MIGRATION_REPAIR_PARITY_EVIDENCE_GATE_INVALID")
    if report.get("step_id") != PARITY_STEP_ID:
        raise RuntimeError("MIGRATION_REPAIR_PARITY_EVIDENCE_STEP_INVALID")
    if report.get("gate_result") != "FAIL":
        return None
    if report.get("diagnostic_complete") is not True:
        raise RuntimeError("MIGRATION_REPAIR_PARITY_EVIDENCE_INCOMPLETE")
    observed_digest = str(report.get("manifest_sha256") or "").lower()
    if SHA64.fullmatch(observed_digest) is None or observed_digest != evidence_digest(report):
        raise RuntimeError("MIGRATION_REPAIR_PARITY_EVIDENCE_DIGEST_MISMATCH")
    source_head = str(report.get("source_commit") or "").lower()
    tested_head = str(report.get("tested_commit") or "").lower()
    if SHA40.fullmatch(source_head) is None or source_head != tested_head:
        raise RuntimeError("MIGRATION_REPAIR_PARITY_EVIDENCE_HEAD_MISMATCH")
    if report.get("source_path") != [PARITY_SOURCE_PATH]:
        raise RuntimeError("MIGRATION_REPAIR_PARITY_EVIDENCE_SOURCE_INVALID")
    impacts = report.get("downstream_impact")
    if not isinstance(impacts, list) or "MIGRATION_SOURCE_PARITY" not in impacts:
        raise RuntimeError("MIGRATION_REPAIR_PARITY_EVIDENCE_IMPACT_INVALID")
    if report.get("expected_check_count") != 1 or report.get("executed_check_count") != 1:
        raise RuntimeError("MIGRATION_REPAIR_PARITY_EVIDENCE_CHECK_COUNT_INVALID")
    if report.get("fail_count") != 1 or report.get("pass_count") != 0 or report.get("blocked_count") != 0:
        raise RuntimeError("MIGRATION_REPAIR_PARITY_EVIDENCE_RESULT_COUNTS_INVALID")
    checks = report.get("checks")
    if not isinstance(checks, list) or len(checks) != 1 or not isinstance(checks[0], dict):
        raise RuntimeError("MIGRATION_REPAIR_PARITY_EVIDENCE_CHECK_INVALID")
    check = checks[0]
    if check.get("check_status") != "FAIL" or check.get("source_path") != PARITY_SOURCE_PATH:
        raise RuntimeError("MIGRATION_REPAIR_PARITY_CHECK_INVALID")
    if check.get("producer") != PARITY_PRODUCER:
        raise RuntimeError("MIGRATION_REPAIR_PARITY_CHECK_PRODUCER_INVALID")
    if str(check.get("source_commit") or "").lower() != source_head or str(check.get("tested_commit") or "").lower() != source_head:
        raise RuntimeError("MIGRATION_REPAIR_PARITY_CHECK_HEAD_MISMATCH")
    summary = str(check.get("error_summary") or "").strip()
    match = VERSION_PARITY_DETAIL.fullmatch(summary)
    if match is None:
        return None
    remote_only = _version_list(match.group("remote"), "REMOTE_ONLY")
    local_only = _version_list(match.group("local"), "LOCAL_ONLY")
    if local_only:
        return None
    if len(remote_only) != 1:
        raise RuntimeError(f"MIGRATION_REPAIR_EXPECTED_SINGLE_REMOTE_ONLY:count={len(remote_only)}")
    return {
        "failure_code": REPAIRABLE_FAILURE,
        "version": remote_only[0],
        "source_head": source_head,
        "evidence_sha256": observed_digest,
        "run_id": str(report.get("run_id") or ""),
    }


def query_rows(version: str) -> list[list[str]]:
    if VERSION_RE.fullmatch(version) is None:
        return []
    missing = [key for key in ("PGHOST", "PGPORT", "PGUSER", "PGPASSWORD", "PGDATABASE", "PGSSLMODE") if not os.environ.get(key)]
    if missing:
        raise RuntimeError("MIGRATION_REPAIR_DB_ENV_MISSING:" + ",".join(missing))
    sql = (
        "select m.version,coalesce(m.name,''),"
        "encode(convert_to(coalesce(array_to_string(m.statements,chr(10)),''),'UTF8'),'hex'),"
        "coalesce(cardinality(m.statements),0)::text,g.execution_id,"
        "coalesce(g.receipt->>'repository',''),coalesce(g.receipt->>'target_path',''),"
        "coalesce(g.receipt->>'pr_head_sha',''),coalesce(g.receipt->>'source_blob',''),"
        "coalesce(g.receipt->>'write_readback',''),coalesce(g.receipt->>'ddl_replayed','') "
        "from supabase_migrations.schema_migrations m "
        "join public.lf_operation_effect_guard g on g.receipt->>'migration_version'=m.version "
        "and g.receipt->>'migration_name'=m.name "
        f"where m.version='{version}' and g.state='SUCCEEDED' "
        "and g.receipt->>'schema_version'='lf-migration-owner-currentness/v1' "
        "order by g.resolved_at desc nulls last,g.execution_id"
    )
    argv = ["docker", "run", "--rm"]
    for key in ("PGHOST", "PGPORT", "PGUSER", "PGPASSWORD", "PGDATABASE", "PGSSLMODE"):
        argv += ["-e", key]
    argv += ["postgres:17.6", "psql", "-X", "-v", "ON_ERROR_STOP=1", "--csv", "-t", "-c", sql]
    proc = run(argv)
    return [row for row in csv.reader(proc.stdout.splitlines()) if row]


def remote_hash(sql_text: str) -> str:
    normalized = sql_text.replace("\r\n", "\n").replace("\r", "\n")
    lines = [line for line in normalized.split("\n") if not line.lstrip().startswith("--")]
    return hashlib.sha256("\n".join(lines).rstrip("\n").encode("utf-8")).hexdigest()


def select_locator(version: str, rows: list[list[str]], repository: str) -> dict[str, object]:
    candidates: list[dict[str, object]] = []
    for row in rows:
        if len(row) != 11 or row[0] != version:
            continue
        v, name, remote_hex, raw_count, execution_id, repo, path, head, blob, write_readback, ddl_replayed = row
        if repo != repository or write_readback != "PASS" or ddl_replayed != "false":
            continue
        if SHA40.fullmatch(head) is None or SHA40.fullmatch(blob) is None:
            continue
        expected_path = f"supabase/migrations/{v}_{name}.sql"
        if path != expected_path or not raw_count.isdigit() or int(raw_count) < 1:
            continue
        try:
            remote_sql = bytes.fromhex(remote_hex).decode("utf-8")
        except (ValueError, UnicodeDecodeError):
            continue
        candidates.append({
            "version": v,
            "name": name,
            "remote_sql": remote_sql,
            "remote_sha256": remote_hash(remote_sql),
            "remote_statement_count": int(raw_count),
            "execution_id": execution_id,
            "path": path,
            "source_sha": head,
            "source_blob": blob,
        })
    if not candidates:
        raise RuntimeError(f"MIGRATION_REPAIR_LOCATOR_MISSING:{version}")
    identities = {(candidate["path"], candidate["source_blob"]) for candidate in candidates}
    if len(identities) != 1:
        raise RuntimeError(f"MIGRATION_REPAIR_LOCATOR_AMBIGUOUS:{version}")
    return candidates[0]


def verify_source(locator: dict[str, object]) -> tuple[str, str]:
    source_sha = str(locator["source_sha"])
    path = str(locator["path"])
    run(["git", "fetch", "--no-tags", "origin", source_sha])
    blob = run(["git", "rev-parse", f"{source_sha}:{path}"]).stdout.strip().lower()
    if blob != locator["source_blob"]:
        raise RuntimeError("MIGRATION_REPAIR_SOURCE_BLOB_MISMATCH")
    raw = subprocess.run(
        ["git", "show", f"{source_sha}:{path}"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
        timeout=60,
    ).stdout
    sql = raw.decode("utf-8")
    comparison = transport.compare_exact_source(
        version=str(locator["version"]),
        source_name=str(locator["name"]),
        source_sql=sql,
        remote_name=str(locator["name"]),
        remote_sha256=str(locator["remote_sha256"]),
        remote_statement_count=int(locator["remote_statement_count"]),
    )
    if comparison.representation not in {"DIRECT_SOURCE", "CLI_STATEMENT_STORAGE"}:
        raise RuntimeError("MIGRATION_REPAIR_SOURCE_REPRESENTATION_INVALID")
    return hashlib.sha256(raw).hexdigest(), comparison.representation


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--parity-evidence", required=True)
    parser.add_argument("--repository", required=True)
    parser.add_argument("--main-sha", required=True)
    args = parser.parse_args()

    evidence_path = Path(args.parity_evidence)
    try:
        evidence = json.loads(evidence_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise RuntimeError("MIGRATION_REPAIR_PARITY_EVIDENCE_READ_FAILED") from exc
    finding = parse_parity_finding(evidence)
    if finding is None:
        print(json.dumps({"status": "NOT_APPLICABLE", "code": "PARITY_FAILURE_NOT_SOURCE_RECONCILIABLE"}, sort_keys=True))
        return 0
    if SHA40.fullmatch(args.main_sha) is None:
        raise RuntimeError("MIGRATION_REPAIR_MAIN_SHA_INVALID")

    version = finding["version"]
    rows = query_rows(version)
    locator = select_locator(version, rows, args.repository)
    source_sha256, representation = verify_source(locator)
    evidence_key = finding["evidence_sha256"][:12]
    branch = f"lf/migration-source-repair/evidence-{evidence_key}-{version}"
    execution_id = f"EXEC-MIGRATION-SOURCE-REPAIR-{version}-{evidence_key.upper()}"
    request_path = Path(os.environ.get("RUNNER_TEMP", ".")) / f"migration-repair-{version}.json"
    request_path.write_text(json.dumps({
        "repository": args.repository,
        "base_sha": args.main_sha,
        "source_sha": locator["source_sha"],
        "source_blob": locator["source_blob"],
        "source_sha256": source_sha256,
        "target_path": locator["path"],
        "target_branch": branch,
        "execution_id": execution_id,
    }, sort_keys=True), encoding="utf-8")
    persist = run(["python3", str(DB_WRITE), "--request", str(request_path)])
    receipt = json.loads(persist.stdout)
    if receipt.get("status") != "PASS" or receipt.get("readback") is not True:
        raise RuntimeError(f"MIGRATION_REPAIR_GIT_PERSIST_FAILED:{version}")

    result = {
        "status": "SOURCE_REPAIR_PERSISTED",
        "schema_version": "lf-migration-source-reconciliation/v1",
        "failure_code": finding["failure_code"],
        "parity_failure_head": finding["source_head"],
        "parity_evidence_sha256": finding["evidence_sha256"],
        "version": version,
        "name": locator["name"],
        "branch": branch,
        "persisted_head_sha": receipt.get("persisted_head_sha"),
        "source_blob": locator["source_blob"],
        "source_sha256": source_sha256,
        "representation": representation,
        "ddl_replayed": False,
        "ledger_mutated": False,
        "pr_request": {
            "action": "CREATE_DRAFT_PR",
            "head": branch,
            "base": "main",
            "title": f"repair(parity): restore exact migration source {version}",
        },
        "post_repair_requirements": [
            "MIGRATION_SOURCE_PARITY_CANONICAL_EVIDENCE_PASS",
            "MIGRATION_ORCHESTRATED_SAGA_V1_CONSISTENT",
        ],
    }
    print(json.dumps(result, sort_keys=True, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Deterministic source-only repair coordinator for MIGRATION_SOURCE_PARITY.

Runs only from trusted follow-up context. Historical owner receipts are locators,
never authority: source bytes are re-read from Git and compared to the live
migration ledger before MIGRATION_WRITE_AHEAD_V1 is allowed to create a repair
branch. No DDL is replayed, no ledger row is mutated, and no merge is performed.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import re
import subprocess
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
DB_WRITE = ROOT / "sandbox/lf_contract_gate_test/db_write_transport/lf_migration_git_persist.py"
TRANSPORT_DIR = ROOT / "sandbox/lf_contract_gate_test"
import sys
sys.path.insert(0, str(TRANSPORT_DIR))
import migration_transport_normalization as transport

VERSION_RE = re.compile(r"20\d{12}")
SHA40 = re.compile(r"^[0-9a-f]{40}$")
REPAIRABLE = (
    "FAIL_LF_MIGRATION_VERSION_PARITY",
    "FAIL_UNCLASSIFIED_POST_CUTOVER_MIGRATION",
)


def run(argv: list[str], *, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(argv, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=check, timeout=120)


def diagnostic_text(root: Path) -> str:
    chunks: list[str] = []
    for path in sorted(root.rglob("*")):
        if path.is_file() and path.stat().st_size <= 2_000_000:
            try:
                chunks.append(path.read_text(encoding="utf-8"))
            except UnicodeDecodeError:
                continue
    return "\n".join(chunks)


def extract_versions(text: str) -> list[str]:
    if not any(code in text for code in REPAIRABLE):
        return []
    return sorted(set(VERSION_RE.findall(text)))


def query_rows(versions: list[str]) -> list[list[str]]:
    if not versions or any(VERSION_RE.fullmatch(v) is None for v in versions):
        return []
    missing = [k for k in ("PGHOST", "PGPORT", "PGUSER", "PGPASSWORD", "PGDATABASE", "PGSSLMODE") if not os.environ.get(k)]
    if missing:
        raise RuntimeError("MIGRATION_REPAIR_DB_ENV_MISSING:" + ",".join(missing))
    pg_array = "{" + ",".join(versions) + "}"
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
        f"where m.version=any('{pg_array}'::text[]) and g.state='SUCCEEDED' "
        "and g.receipt->>'schema_version'='lf-migration-owner-currentness/v1' "
        "order by m.version,g.resolved_at desc nulls last,g.execution_id"
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
            "version": v, "name": name, "remote_sql": remote_sql,
            "remote_sha256": remote_hash(remote_sql), "remote_statement_count": int(raw_count),
            "execution_id": execution_id, "path": path, "source_sha": head, "source_blob": blob,
        })
    if not candidates:
        raise RuntimeError(f"MIGRATION_REPAIR_LOCATOR_MISSING:{version}")
    identities = {(c["path"], c["source_blob"]) for c in candidates}
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
    raw = subprocess.run(["git", "show", f"{source_sha}:{path}"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True, timeout=60).stdout
    sql = raw.decode("utf-8")
    comparison = transport.compare_exact_source(
        version=str(locator["version"]), source_name=str(locator["name"]), source_sql=sql,
        remote_name=str(locator["name"]), remote_sha256=str(locator["remote_sha256"]),
        remote_statement_count=int(locator["remote_statement_count"]),
    )
    if comparison.representation not in {"DIRECT_SOURCE", "CLI_STATEMENT_STORAGE"}:
        raise RuntimeError("MIGRATION_REPAIR_SOURCE_REPRESENTATION_INVALID")
    return hashlib.sha256(raw).hexdigest(), comparison.representation


def open_pr(repository: str, token: str, branch: str, version: str, name: str, source_execution: str, source_blob: str) -> int:
    payload = json.dumps({
        "title": f"repair(parity): restore exact migration source {version}",
        "head": branch,
        "base": "main",
        "draft": True,
        "body": (
            "Automated source-only MIGRATION_SOURCE_PARITY repair.\n\n"
            f"- migration: `{version}_{name}`\n"
            f"- historical locator execution: `{source_execution}`\n"
            f"- verified source blob: `{source_blob}`\n"
            "- DDL replay: false\n- ledger mutation: false\n- merge: not authorized\n\n"
            "The normal lf-contract-check is the post-repair parity readback. If it still fails, the existing PRE_EKB path owns escalation."
        ),
    }).encode("utf-8")
    request = urllib.request.Request(
        f"https://api.github.com/repos/{repository}/pulls", data=payload, method="POST",
        headers={"Authorization": f"Bearer {token}", "Accept": "application/vnd.github+json", "Content-Type": "application/json", "User-Agent": "lf-migration-parity-repair-v1"},
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        result = json.loads(response.read().decode("utf-8"))
    return int(result["number"])


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--diagnostics-dir", required=True)
    parser.add_argument("--repository", required=True)
    parser.add_argument("--main-sha", required=True)
    parser.add_argument("--source-run-id", required=True)
    args = parser.parse_args()
    text = diagnostic_text(Path(args.diagnostics_dir))
    versions = extract_versions(text)
    if not versions:
        print(json.dumps({"status": "NOT_APPLICABLE", "code": "NO_REPAIRABLE_MIGRATION_PARITY_FAILURE"}, sort_keys=True))
        return 0
    if SHA40.fullmatch(args.main_sha) is None:
        raise RuntimeError("MIGRATION_REPAIR_MAIN_SHA_INVALID")
    rows = query_rows(versions)
    token = os.environ.get("GITHUB_TOKEN", "").strip()
    if not token:
        raise RuntimeError("MIGRATION_REPAIR_GITHUB_TOKEN_MISSING")
    results = []
    for version in versions:
        locator = select_locator(version, rows, args.repository)
        source_sha256, representation = verify_source(locator)
        branch = f"lf/migration-source-repair/run-{args.source_run_id}-{version}"
        request_path = Path(os.environ.get("RUNNER_TEMP", ".")) / f"migration-repair-{version}.json"
        request_path.write_text(json.dumps({
            "repository": args.repository,
            "base_sha": args.main_sha,
            "source_sha": locator["source_sha"],
            "source_blob": locator["source_blob"],
            "source_sha256": source_sha256,
            "target_path": locator["path"],
            "target_branch": branch,
            "execution_id": f"EXEC-MIGRATION-PARITY-REPAIR-{args.source_run_id}-{version}",
        }, sort_keys=True), encoding="utf-8")
        persist = run(["python3", str(DB_WRITE), "--request", str(request_path)])
        receipt = json.loads(persist.stdout)
        if receipt.get("status") != "PASS" or receipt.get("readback") is not True:
            raise RuntimeError(f"MIGRATION_REPAIR_GIT_PERSIST_FAILED:{version}")
        pr_number = open_pr(args.repository, token, branch, version, str(locator["name"]), str(locator["execution_id"]), str(locator["source_blob"]))
        results.append({
            "version": version, "name": locator["name"], "branch": branch, "pr_number": pr_number,
            "source_blob": locator["source_blob"], "source_sha256": source_sha256,
            "representation": representation, "ddl_replayed": False, "ledger_mutated": False,
            "post_repair_check": "lf-contract-check/MIGRATION_SOURCE_PARITY + MIGRATION_ORCHESTRATED_SAGA_V1",
        })
    print(json.dumps({"status": "REPAIR_DISPATCHED", "schema_version": "lf-migration-source-reconciliation/v1", "repairs": results}, sort_keys=True, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Fail-closed source-only reconciliation. No apply, no ledger writes."""
import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from migration_transport_normalization import compare_exact_source

PATH = re.compile(r"^supabase/migrations/(20[0-9]{12})_([A-Za-z0-9][A-Za-z0-9_]*)\\.sql$")


def verify_rows(rows, read_source, read_ledger):
    """rows: GitHub PR changed-file objects. All paths must be migrations."""
    if not rows:
        raise ValueError("EMPTY_CHANGESET")
    accepted = []
    removed = set()
    candidates = []
    for row in rows:
        status, path = row["status"], row["filename"]
        match = PATH.fullmatch(path)
        if not match:
            raise ValueError("NON_MIGRATION_OR_INVALID_PATH:" + path)
        if status == "removed":
            removed.add(path)
        elif status == "renamed":
            previous = row.get("previous_filename", "")
            if not PATH.fullmatch(previous):
                raise ValueError("RENAME_PREVIOUS_INVALID:" + previous)
            removed.add(previous)
            candidates.append((path, previous, status))
        elif status == "added":
            candidates.append((path, None, status))
        else:
            raise ValueError("CHANGE_STATUS_INVALID:" + status + ":" + path)
    if not candidates:
        raise ValueError("NO_RECONCILIATION_TARGETS")
    seen = set()
    for path, previous, status in candidates:
        match = PATH.fullmatch(path)
        version, name = match.groups()
        if version in seen:
            raise ValueError("DUPLICATE_TARGET_VERSION:" + version)
        seen.add(version)
        # Reconcile cannot introduce a version absent from the database.
        ledger = read_ledger(version)
        if ledger is None:
            raise ValueError("VERSION_NOT_IN_LEDGER:" + version)
        cmp = compare_exact_source(
            version=version, source_name=name, source_sql=read_source(path),
            remote_name=ledger["name"], remote_sha256=ledger["sha256"],
            remote_statement_count=ledger["statement_count"],
        )
        accepted.append(cmp.as_dict() | {"path": path, "status": status})
    # All old files must be accounted for, including renamed previous paths.
    for old in removed:
        if not PATH.fullmatch(old):
            raise ValueError("REMOVED_INVALID:" + old)
        if old not in {p for _, p, _ in candidates if p}:
            # GitHub may represent git mv as removed+added: bind by exact ledger
            # identity and bytes; never accept unpaired removal.
            old_candidates = [p for p, prev, kind in candidates
                              if kind == "added" and
                              read_source(p) == read_source(old, old=True)]
            if len(old_candidates) != 1:
                raise ValueError("REMOVED_UNPAIRED:" + old)
    return {"schema_version": "lf-reconcile-source-only/v1",
            "status": "PASS", "lane": "RECONCILE_SOURCE_ONLY",
            "migrations": accepted}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--pr-files-json", required=True)
    parser.add_argument("--head-sha", required=True)
    parser.add_argument("--repo", required=True)
    args = parser.parse_args()
    import urllib.request
    import psycopg
    files = json.loads(Path(args.pr_files_json).read_text())
    token = os.environ["GH_TOKEN"]
    cache = {}
    def read_source(path, old=False):
        if old:
            # Deleted file must come from base branch exact SHA.
            ref = os.environ["BASE_SHA"]
        else:
            ref = args.head_sha
        url = "https://api.github.com/repos/" + args.repo + "/contents/" + path + "?ref=" + ref
        req = urllib.request.Request(url, headers={"Authorization": "Bearer " + token,
                                                   "Accept": "application/vnd.github.raw+json"})
        with urllib.request.urlopen(req, timeout=20) as response:
            return response.read().decode("utf-8")
    dsn = os.environ["LF_READONLY_DSN"]
    with psycopg.connect(dsn, autocommit=True, options="-c default_transaction_read_only=on") as conn:
        def read_ledger(version):
            with conn.cursor() as cur:
                cur.execute("SELECT name, statements FROM supabase_migrations.schema_migrations WHERE version=%s", (version,))
                row = cur.fetchone()
            if row is None:
                return None
            from migration_transport_normalization import canonical, sha256
            name, statements = row
            if not statements:
                raise ValueError("LEDGER_EMPTY:" + version)
            # Existing contract hashes the canonicalized statement transport.
            return {"name": name, "sha256": sha256(canonical("\n".join(statements))),
                    "statement_count": len(statements)}
        result = verify_rows(files, read_source, read_ledger)
    print(json.dumps(result, sort_keys=True))


if __name__ == "__main__":
    main()

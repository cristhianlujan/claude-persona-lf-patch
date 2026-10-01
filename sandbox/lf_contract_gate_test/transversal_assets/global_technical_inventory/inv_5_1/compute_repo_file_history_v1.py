#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime as dt
import json
import subprocess
from pathlib import Path


def git(*args: str) -> str:
    p = subprocess.run(
        ["git", *args],
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if p.returncode != 0:
        raise SystemExit("FAIL_GIT:" + " ".join(args) + ":" + p.stderr.strip())
    return p.stdout


def sql_quote(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", required=True)
    ap.add_argument("--evidence", required=True)
    ap.add_argument("--sql", required=True)
    args = ap.parse_args()

    payload = json.loads(Path(args.input).read_text(encoding="utf-8"))
    pin = payload["observed_main_sha"]
    objects = payload["objects"]
    expected = int(payload["expected_rows"])

    if len(objects) != expected:
        raise SystemExit(f"FAIL_INPUT_COUNT:{len(objects)}:{expected}")

    git("cat-file", "-e", f"{pin}^{{commit}}")
    generated_at = dt.datetime.now(dt.timezone.utc).isoformat()

    evidence_rows = []
    seen_ids = set()
    seen_paths = set()
    for idx, row in enumerate(objects, start=1):
        object_id = int(row["object_id"])
        path = str(row["path"])
        object_ref = str(row["object_ref"])
        if object_ref != "repo://" + path:
            raise SystemExit(f"FAIL_REF_PATH_MISMATCH:{object_id}:{object_ref}:{path}")
        if object_id in seen_ids or path in seen_paths:
            raise SystemExit(f"FAIL_DUPLICATE_INPUT:{object_id}:{path}")
        seen_ids.add(object_id)
        seen_paths.add(path)

        # Exact INV-5.1 semantics: git log <pinned-main> --format=%H -- <file>
        raw = git("log", pin, "--format=%H", "--", path)
        commits = [line.strip() for line in raw.splitlines() if line.strip()]
        if not commits:
            raise SystemExit(f"FAIL_NO_GIT_HISTORY:{object_id}:{path}")
        if any(len(sha) != 40 for sha in commits):
            raise SystemExit(f"FAIL_NON_FULL_SHA:{object_id}:{path}")

        evidence_rows.append({
            "object_id": object_id,
            "object_ref": object_ref,
            "path": path,
            "file_last_commit": commits[0],
            "commit_count": len(commits),
        })
        if idx % 250 == 0:
            print(f"PROGRESS={idx}/{expected}")

    evidence = {
        "schema_version": "lf-inv-5-1-file-history-evidence/v1",
        "observed_main_sha": pin,
        "generated_at": generated_at,
        "method": "git log <observed_main_sha> --format=%H -- <path>",
        "row_count": len(evidence_rows),
        "rows": evidence_rows,
    }
    Path(args.evidence).parent.mkdir(parents=True, exist_ok=True)
    Path(args.evidence).write_text(
        json.dumps(evidence, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )

    values = ",\n".join(
        f"  ({r['object_id']}, {sql_quote(r['path'])}, {sql_quote(r['file_last_commit'])}, {r['commit_count']})"
        for r in evidence_rows
    )
    evidence_path = str(Path(args.evidence).as_posix())
    sql = f"""-- INV-5.1 operational inventory write.
-- Source-first evidence: {evidence_path}
-- Pinned main: {pin}
-- Method: git log <observed_main_sha> --format=%H -- <path>
-- This is NOT a schema migration. Apply only via DIRECT_DB_WRITE / SUPABASE_MCP
-- after this exact SQL and evidence are merged to main.

begin;

create temp table inv_5_1_file_history (
  object_id bigint primary key,
  path text not null unique,
  file_last_commit text not null check (file_last_commit ~ '^[0-9a-f]{{40}}$'),
  commit_count integer not null check (commit_count > 0)
) on commit drop;

insert into inv_5_1_file_history(object_id,path,file_last_commit,commit_count)
values
{values};

do $$
declare
  v_expected integer := {expected};
  v_history integer;
  v_repo integer;
  v_mismatch integer;
  v_updated integer;
begin
  select count(*) into v_history from inv_5_1_file_history;
  if v_history <> v_expected then
    raise exception 'INV_5_1_HISTORY_COUNT_MISMATCH expected=% actual=%', v_expected, v_history;
  end if;

  select count(*) into v_repo
  from inventory.objects
  where object_ref like 'repo://%';
  if v_repo <> v_expected then
    raise exception 'INV_5_1_REPO_OBJECT_COUNT_CHANGED expected=% actual=%', v_expected, v_repo;
  end if;

  select count(*) into v_mismatch
  from inv_5_1_file_history h
  left join inventory.objects o on o.object_id=h.object_id
  where o.object_id is null
     or o.object_ref <> 'repo://' || h.path;
  if v_mismatch <> 0 then
    raise exception 'INV_5_1_OBJECT_PATH_MISMATCH count=%', v_mismatch;
  end if;

  update inventory.objects o
  set metadata =
        coalesce(o.metadata,'{{}}'::jsonb)
        || jsonb_build_object(
             'drive_last_commit', coalesce(o.metadata->'drive_last_commit', o.metadata->'last_commit'),
             'drive_commit_count', coalesce(o.metadata->'drive_commit_count', o.metadata->'commit_count'),
             'file_last_commit', h.file_last_commit,
             'commit_count', h.commit_count,
             'file_history_source', 'GITHUB_MAIN_GIT_LOG',
             'file_history_method', 'git log <observed_main_sha> --format=%H -- <path>',
             'file_history_observed_main_sha', '{pin}',
             'file_history_observed_at', '{generated_at}',
             'file_history_evidence', '{evidence_path}'
           ),
      updated_at = clock_timestamp()
  from inv_5_1_file_history h
  where o.object_id=h.object_id;

  get diagnostics v_updated = row_count;
  if v_updated <> v_expected then
    raise exception 'INV_5_1_UPDATE_COUNT_MISMATCH expected=% actual=%', v_expected, v_updated;
  end if;
end $$;

commit;

select
  count(*) filter(where object_ref like 'repo://%') as repo_rows,
  count(*) filter(where object_ref like 'repo://%' and metadata->>'file_history_source'='GITHUB_MAIN_GIT_LOG') as git_history_rows,
  count(*) filter(where object_ref like 'repo://%' and metadata->>'file_history_observed_main_sha'='{pin}') as pinned_history_rows,
  count(*) filter(where object_ref like 'repo://%' and metadata ? 'file_last_commit') as file_last_commit_rows,
  count(*) filter(where object_ref like 'repo://%' and metadata ? 'commit_count') as commit_count_rows,
  count(*) filter(where object_ref like 'repo://%' and metadata->>'file_last_commit'=observed_main_sha) as last_commit_equals_currentness_main_sha
from inventory.objects;
"""
    Path(args.sql).parent.mkdir(parents=True, exist_ok=True)
    Path(args.sql).write_text(sql, encoding="utf-8")

    print(f"PASS_INV_5_1_FILE_HISTORY={len(evidence_rows)}/{expected}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

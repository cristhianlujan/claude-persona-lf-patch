#!/usr/bin/env python3
"""Trusted-main, exact-source PostgreSQL BEGIN/ROLLBACK for PR #4075 M36.

The checkout of #4075 is DATA only: no Python, workflow, shell or secrets
come from the candidate. The only privileged execution path is a Train-bot
merge of this runner's own PR, running this code from trusted main.
"""
from __future__ import annotations
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
from datetime import datetime, timezone
from urllib.request import Request, urlopen

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(ROOT / "sandbox/lf_contract_gate_test/ig4064_advisory_dispatch"))
import ig4064_rollback_runner_v1 as guard

REPO = "cristhianlujan/claude-persona-lf-patch"
PR = 4075
TRIGGER_PR = 4076  # Exact owner-authorized A2 Train merge receipt.
HEAD = "55f7f74f1b626ce965efa564dedd890fc417cbfb"
MIGRATION = "supabase/migrations/20261118052000_lf_ig_m36_noncurrent_candidate_authority_v1.sql"
HARNESS = "sandbox/lf_contract_gate_test/input_governance/ig_m36_noncurrent_field_42_screen_rollback.sql"
BLOBS = {
    MIGRATION: "2cc1aa1f06be2a7a215885e14ec7f8ca6a8a1092",
    HARNESS: "7f27e78db27d458ab01aaa27514516abde528c9c",
}
PREIMAGE = "61d47a6400cf910ace71936413863e16"
OUT = Path(".lf_ci/ig_m36_4075")
EXPECTED_FILES = {
    ".github/workflows/lf-router-level2-advisory-tests.yml",
    "sandbox/lf_contract_gate_test/changesets/ig-m36-trusted-head-pin-a2-v1.json",
    "sandbox/lf_contract_gate_test/input_governance/ig_m36_protected_runner_v1.py",
    "sandbox/lf_contract_gate_test/input_governance/test_ig_m36_protected_runner_v1.py",
}
REQUIRED = (
    "IG_M36_BASELINE_PASS screens=42 assessments=1974 other_screens=39 other=1833 applicable=1824 na=9",
    "IG_M36_NONCURRENT_SOURCE_PATCH_PASS original_md5=" + PREIMAGE,
    "IG_M36_CANDIDATE_AUTHORITY_PASS screen=67 blocker=EXPLICIT_FIELD_REFERENCE_NONCURRENT count=1 state=BLOCKED stage=STORY evidence=OBJECT",
    "IG_M36_ALL_42_REGRESSION_PASS screens=42 assessments=1974 applicable_lost=0 applicability_changes=0",
    "IG_M36_OTHER_39_PASS assessments=1833 applicable=1824 na=9",
    "IG_M36_POST_ROLLBACK_PASS original_md5=" + PREIMAGE,
)
INDEPENDENT = r"""
DO $independent$
DECLARE n integer; screens integer; others integer; a integer; na integer; targets integer;
BEGIN
 WITH latest AS (
  SELECT DISTINCT ON (pantalla_id) pantalla_id,id run_id
  FROM programacion.input_readiness_runs ORDER BY pantalla_id,id DESC
 ), rows AS (
  SELECT l.pantalla_id,f.applicability FROM latest l
  JOIN programacion.input_family_assessments f ON f.run_id=l.run_id
 )
 SELECT count(*),count(DISTINCT pantalla_id),
  count(*) FILTER(WHERE pantalla_id NOT IN(52,53,56)),
  count(*) FILTER(WHERE pantalla_id NOT IN(52,53,56) AND applicability='APPLICABLE'),
  count(*) FILTER(WHERE pantalla_id NOT IN(52,53,56) AND applicability='NOT_APPLICABLE'),
  count(*) FILTER(WHERE pantalla_id IN(52,53,56))
 INTO n,screens,others,a,na,targets FROM rows;
 IF n<>1974 OR screens<>42 OR others<>1833 OR a<>1824 OR na<>9 OR targets<>141
 THEN RAISE EXCEPTION 'IG_M36_INDEPENDENT_BASELINE_DRIFT n=% screens=% others=% app=% na=% target=%',
     n,screens,others,a,na,targets;
 END IF;
 RAISE NOTICE 'IG_M36_INDEPENDENT_READBACK_PASS screens=42 assessments=1974 other=1833 applicable=1824 na=9 targets=141';
END;
$independent$;
"""


def require(ok: bool, message: str) -> None:
    if not ok:
        raise RuntimeError(message)


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def git_blob(data: bytes) -> str:
    return hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()


def api(path: str, token: str) -> object:
    req = Request(
        "https://api.github.com/repos/" + REPO + path,
        headers={"Authorization": "Bearer " + token,
                 "Accept": "application/vnd.github+json",
                 "X-GitHub-Api-Version": "2022-11-28"},
    )
    with urlopen(req, timeout=25) as response:
        return json.load(response)


def governance_check() -> dict:
    require(os.getenv("GITHUB_REPOSITORY") == REPO, "REPOSITORY_NOT_AUTHORIZED")
    require(os.getenv("GITHUB_EVENT_NAME") == "push", "TRAIN_PUSH_ONLY")
    require(os.getenv("GITHUB_REF") == "refs/heads/main", "TRUSTED_MAIN_ONLY")
    require(os.getenv("GITHUB_ACTOR") == "lf-migration-train[bot]", "TRAIN_ACTOR_ONLY")
    require(TRIGGER_PR > 0, "A2_PR_NUMBER_NOT_PINNED")
    token = os.getenv("GH_TOKEN")
    require(bool(token), "GITHUB_READ_TOKEN_MISSING")
    trigger = api("/pulls/" + str(TRIGGER_PR), token)
    require(trigger.get("merged_at") and
            trigger.get("merged_by", {}).get("login") == "lf-migration-train[bot]" and
            trigger.get("merge_commit_sha") == os.getenv("GITHUB_SHA") and
            trigger.get("base", {}).get("ref") == "main",
            "A2_TRAIN_MERGE_IDENTITY_MISMATCH")
    changed = api("/pulls/" + str(TRIGGER_PR) + "/files?per_page=100", token)
    require(isinstance(changed, list) and
            {x.get("filename") for x in changed} == EXPECTED_FILES and
            len(changed) == len(EXPECTED_FILES), "A2_UNEXPECTED_FILE_SCOPE")
    candidate = api("/pulls/" + str(PR), token)
    require(candidate.get("number") == PR and
            candidate.get("state") == "open" and
            candidate.get("draft") is True and
            candidate.get("merged_at") is None and
            candidate.get("base", {}).get("ref") == "main" and
            candidate.get("head", {}).get("sha") == HEAD,
            "PR4075_HEAD_DRAFT_OR_BASE_DRIFT")
    return {"trusted_merge_pr": TRIGGER_PR, "merge_sha": os.getenv("GITHUB_SHA"),
            "candidate_pr": PR, "candidate_head": HEAD, "draft": True}


def pinned_sources(root: Path = Path("candidate-readonly")) -> tuple[dict[str, str], dict[str, dict]]:
    require(root.is_dir(), "CANDIDATE_CHECKOUT_MISSING")
    actual = subprocess.check_output(
        ["git", "-C", str(root), "rev-parse", "HEAD"], text=True,
    ).strip()
    require(actual == HEAD, "CANDIDATE_HEAD_CHANGED")
    source = {}
    receipts = {}
    for path, expected in BLOBS.items():
        file = root / path
        require(file.is_file(), "PINNED_FILE_MISSING:" + path)
        data = file.read_bytes()
        require(len(data) < 16000, "PINNED_FILE_TOO_LARGE:" + path)
        observed = git_blob(data)
        require(observed == expected, "PINNED_BLOB_DRIFT:" + path)
        source[path] = data.decode("utf-8")
        receipts[path] = {"git_blob": observed, "sha256": sha256(data)}
    return source, receipts


def assemble(root: Path = Path("candidate-readonly")) -> tuple[str, str, dict]:
    source, receipts = pinned_sources(root)
    migration = "\n".join(
        line for line in source[MIGRATION].splitlines()
        if not line.lstrip().startswith("--")
    ).strip()
    require(migration.startswith("DO $m36$\n") and migration.endswith("\n$m36$;"),
            "M36_MIGRATION_DO_SHAPE_DRIFT")
    require(migration.count("DO $m36$") == 1 and PREIMAGE in migration and
            "EXPLICIT_FIELD_REFERENCE_NONCURRENT" in migration and
            "CANDIDATE_AUTHORITY" in migration, "M36_MIGRATION_GUARD_MISSING")
    raw = source[HARNESS]
    import_line = r"\ir ../../../supabase/migrations/20261118052000_lf_ig_m36_noncurrent_candidate_authority_v1.sql"
    directives = [
        line.strip() for line in raw.splitlines()
        if line.lstrip().startswith("\\")
    ]
    required_directives = [
        r"\set ON_ERROR_STOP on", r"\echo IG_M36_TX_BEGIN",
        import_line, r"\echo IG_M36_TX_ROLLBACK_START",
        r"\echo IG_M36_TX_ROLLBACK_DONE",
    ]
    require(directives == required_directives, "HARNESS_PSQL_DIRECTIVE_DRIFT")
    lines = []
    for line in raw.splitlines():
        if line.strip() == import_line:
            lines.append(migration)
        elif line.lstrip().startswith("\\"):
            continue
        else:
            lines.append(line)
    sql = "\n".join(lines).strip() + "\n"
    require(not any(x.lstrip().startswith("\\") for x in sql.splitlines()),
            "UNTRUSTED_PSQL_META")
    guard.assert_safe_transaction_control(sql)
    require(sql.count("DO $m36$") == 1 and
            sql.count("DO $post$") == 1 and sql.count("$post$;") == 1 and
            sql.index("BEGIN;") < sql.index("DO $m36$") <
            sql.index("DO $verify$") < sql.index("\nROLLBACK;") <
            sql.index("DO $post$"), "M36_TRANSACTION_SEQUENCE_DRIFT")
    post_idx = sql.index("DO $post$\n")
    post = sql[post_idx:].strip()
    require(guard.top_level_sql_statements(post) == [("DO",)] and
            post.endswith("$post$;") and "IG_M36_POST_ROLLBACK_PASS" in post,
            "POST_ROLLBACK_SQL_NOT_EXACT_DO")
    return sql, post + "\n", receipts


def run_psql(path: Path, *, limit: int) -> tuple[int, str]:
    return guard.psql(path, limit=limit)


def execute() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    report = {"status": "FAIL", "pr": PR, "head": HEAD, "executed": False,
              "rollback_only": True, "persistent_writes_authorized": False}
    try:
        report["governance"] = governance_check()
        sql, post, receipts = assemble()
        report["source_blobs"] = receipts
        report["assembled_sql_sha256"] = sha256(sql.encode())
        script = OUT / "single_session.sql"
        script.write_text(sql)
        report["executed"] = True
        code, log = run_psql(script, limit=30 * 60)
        (OUT / "postgresql.log").write_text(log)
        report["postgresql_exit_code"] = code
        report["postgresql_log_sha256"] = sha256(log.encode())
        report["assertions"] = {key: key in log for key in REQUIRED}
        report["candidate_authority_log"] = next(
            (line[:2000] for line in log.splitlines()
             if "IG_M36_CANDIDATE_AUTHORITY_PASS" in line), None
        )
        readback = OUT / "independent_readback.sql"
        readback.write_text(post + INDEPENDENT)
        rb_code, rb_log = run_psql(readback, limit=100)
        (OUT / "independent_readback.log").write_text(rb_log)
        report["independent_exit_code"] = rb_code
        report["independent_log_sha256"] = sha256(rb_log.encode())
        report["readback_pass"] = rb_code == 0 and (
            "IG_M36_POST_ROLLBACK_PASS original_md5=" + PREIMAGE in rb_log and
            "IG_M36_INDEPENDENT_READBACK_PASS screens=42 assessments=1974 other=1833 applicable=1824 na=9 targets=141" in rb_log)
        require(code == 0, "PG_REAL_ROLLBACK_OR_CANDIDATE_FAILED")
        require(all(report["assertions"].values()), "PG_EVIDENCE_MISSING")
        require(report["readback_pass"], "INDEPENDENT_READBACK_FAILED")
        report["status"] = "PASS"
    except subprocess.TimeoutExpired:
        report["blocking_error"] = "PG_TIMEOUT_CONNECTION_CLOSED_TX_ABORTED"
    except Exception as exc:
        report["blocking_error"] = str(exc)[:600]
    finally:
        report["observed_at_utc"] = datetime.now(timezone.utc).isoformat()
        (OUT / "report.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
        print(json.dumps({k: v for k, v in report.items()
                          if k not in ("governance", "candidate_authority_log")}, sort_keys=True))
    return 0 if report["status"] == "PASS" else 1


if __name__ == "__main__":
    if len(sys.argv) != 2 or sys.argv[1] not in ("preflight", "execute"):
        raise SystemExit("Usage: ig_m36_protected_runner_v1.py preflight|execute")
    if sys.argv[1] == "preflight":
        sql, post, evidence = assemble()
        print(json.dumps({"status": "PIN_PASS", "head": HEAD,
                          "sources": evidence, "assembled_sha256": sha256(sql.encode()),
                          "readback_sha256": sha256((post + INDEPENDENT).encode())},
                         sort_keys=True))
    else:
        raise SystemExit(execute())

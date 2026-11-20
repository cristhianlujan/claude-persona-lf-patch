#!/usr/bin/env python3
"""Fixed-source #4064 test on the real Supabase project; one BEGIN/ROLLBACK session.

Workflow code runs from trusted main. PR #4064 is untrusted DATA: only two exact
git blobs are admitted as SQL; transaction control and psql meta are stripped.
No execution runs, grants, migrations ledger, merge, or persistent writes.
"""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
from urllib.request import Request, urlopen

REPO = "cristhianlujan/claude-persona-lf-patch"
PR = 4064
HEAD = "ade493bbd425a337dc81d175410eff2abea956f0"
MIGRATION = "supabase/migrations/20261117073400_lf_ig_recovery_family_positive_na_v1.sql"
HARNESS = "sandbox/ig_recovery_family_positive_na_v1/rollback_test.sql"
TEMPLATE = Path("sandbox/lf_contract_gate_test/ig4064_advisory_dispatch/ig4064_rollback_template_v1.sql")
# Both Git blobs and the PR HEAD are exact/current as of PR-A. Future #4064
# rebases MUST update all three literals in one trusted-main change; no
# dynamic PR-head trust or auto-discovery is allowed.
BLOBS = {
    MIGRATION: "370bfb1682bac0ca8e30f9cef179f7939d5a659f",
    HARNESS: "3df03ef574f2cd6e653ab7c38194c8bc04f6851d",
}
EXPECTED_MD5 = [
    ("programacion.fn_input_na_positive_authority_v512(text,integer,bigint)", "54de45cf44a62218493026503c441aee"),
    ("programacion.fn_input_na_positive_authority_v512(text,integer,bigint,jsonb)", "49b2c428ad873917b4e950761aca0e83"),
    ("programacion.fn_input_na_positive_authority_v512_cached_v1(text,integer,bigint,jsonb)", "1e1bed65856063b82a7d97ff588df390"),
    ("programacion.fn_input_governance_bootstrap_classify_v1(integer,text,bigint)", "adea36699afc83e09f54b92e1656fda2"),
    ("programacion.fn_input_governance_bootstrap_classify_v1_ctx(integer,text,bigint,jsonb)", "7ca4f143735f0c38922af862f5330e02"),
    ("programacion.fn_input_governance_bootstrap_classify_v1_cached_v2(integer,text,bigint,jsonb)", "7bdb44ce517556a888c18d59dba1a04e"),
    ("programacion.fn_guard_input_validator_semantic_coherence_v512()", "6643c01d068fd81bf67cd6943e545c82"),
]
OUT = Path(".lf_ci/ig4064_advisory")
REQUIRED = (
    "IG4064_FUNCTION_PREIMAGE_PASS md5=7/7 rev=19",
    "IG4064_BASELINE_PASS screens=42 assessments=1974",
    "IG4064_MIGRATION_CHANGED_IN_TX definitions=7",
    "IG_RECOVERY_SELECT_DIRECT_AND_CACHED_12_PASS",
    "IG4064_RECALL_PASS P52=45/45 P56=45/45 P53=45/45 TOTAL=135/135",
    "IG4064_NA_REFS_PASS 6/6 rule=B2B-RULE-INPUT-APPLICABILITY-001",
    "IG4064_NA_SOURCE_REFS_REAL=",
    "IG4064_OTHER_39_REGRESSION_PASS screens=39 assessments=1833 baseline_app=1824 baseline_na=9 applicable_lost=0",
    "IG4064_TX_ROLLBACK_DONE",
    "IG4064_POST_ROLLBACK_PASS original_md5=7/7 other=1833 app=1824 na=9 target=141",
)

def require(ok: bool, error: str) -> None:
    if not ok:
        raise RuntimeError(error)

def sha256(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()

def quote(x: str) -> str:
    return "'" + x.replace("'", "''") + "'"

def function_values() -> str:
    return ",\n".join("(" + quote(sig) + "," + quote(h) + ")" for sig, h in EXPECTED_MD5)

def exact_sql() -> tuple[str, str, dict]:
    root = Path("candidate-readonly")
    require(root.is_dir(), "CANDIDATE_CHECKOUT_MISSING")
    actual = subprocess.check_output(["git", "-C", str(root), "rev-parse", "HEAD"],
                                     text=True).strip()
    require(actual == HEAD, "CANDIDATE_HEAD_CHANGED")
    data: dict[str, str] = {}
    digests: dict[str, str] = {}
    for file, expected_blob in BLOBS.items():
        p = root / file
        require(p.is_file(), "PINNED_FILE_MISSING:" + file)
        content = p.read_bytes()
        blob = hashlib.sha1(b"blob " + str(len(content)).encode() + b"\x00" + content).hexdigest()
        require(blob == expected_blob, "PINNED_BLOB_DRIFT:" + file)
        require(len(content) < 100_000, "SQL_SOURCE_EXCEEDS_LIMIT")
        data[file] = content.decode("utf-8")
        digests[file] = sha256(content)

    # Strip only exact expected psql commands from original #4064 harness.
    wrappers = {
        r"\set ON_ERROR_STOP on",
        "BEGIN;",
        r"\ir ../../supabase/migrations/20261117073400_lf_ig_recovery_family_positive_na_v1.sql",
        "ROLLBACK;",
    }
    found: list[str] = []
    kept: list[str] = []
    for line in data[HARNESS].splitlines():
        if line.strip() in wrappers:
            found.append(line.strip())
        elif line.lstrip().startswith("--") or not line.strip():
            continue
        else:
            kept.append(line)
    require(set(found) == wrappers and len(found) == 4,
            "HARNESS_TRANSACTION_WRAPPERS_DRIFT")
    harness = "\n".join(kept).strip()

    migration = "\n".join(line for line in data[MIGRATION].splitlines()
                          if not line.lstrip().startswith("--")).strip()
    require(migration.startswith("DO $ig$\n") and migration.endswith("$ig$;"),
            "MIGRATION_NOT_ONE_DO_STATEMENT")
    require(harness.startswith("DO $test$\n") and harness.endswith("$test$;"),
            "HARNESS_NOT_ONE_DO_STATEMENT")
    require(migration.count("DO $ig$") == 1 and harness.count("DO $test$") == 1,
            "SQL_DO_COUNT_CHANGED")
    for name, source in (("MIGRATION", migration), ("HARNESS", harness)):
        require(not re.search(r"\b(COMMIT|ROLLBACK|SAVEPOINT|PREPARE\s+TRANSACTION)\b",
                              source, flags=re.I), name + "_TRANSACTION_CONTROL_FORBIDDEN")
        require(not re.search(r"(?m)^\s*\\", source),
                name + "_PSQL_META_FORBIDDEN")
    upper = migration.upper()
    for bad in ("GRANT EXECUTE", "INSERT INTO LF_OPS.REGLAS",
                "UPDATE LF_OPS.REGLAS", "DELETE FROM LF_OPS.REGLAS"):
        require(bad not in upper, "MIGRATION_FORBIDDEN_SCOPE:" + bad)
    return migration, harness, digests

def governance_check() -> dict:
    require(os.environ.get("GITHUB_REPOSITORY") == REPO, "REPOSITORY_NOT_AUTHORIZED")
    require(os.environ.get("GITHUB_REF") == "refs/heads/main", "MUST_DISPATCH_FROM_MAIN")
    require(os.environ.get("GITHUB_EVENT_NAME") == "workflow_dispatch", "DISPATCH_ONLY")
    require(os.environ.get("IG4064_DISPATCH_SCOPE") == "ROLLBACK_ONLY", "SCOPE_MISMATCH")
    token = os.environ.get("GH_TOKEN")
    require(bool(token), "GITHUB_READ_TOKEN_MISSING")
    req = Request(
        f"https://api.github.com/repos/{REPO}/pulls/{PR}",
        headers={"Authorization": "Bearer " + token, "Accept": "application/vnd.github+json",
                 "X-GitHub-Api-Version": "2022-11-28"},
    )
    with urlopen(req, timeout=20) as response:
        pr = json.load(response)
    require(pr.get("number") == PR and pr.get("state") == "open" and pr.get("draft") is True
            and pr.get("merged_at") is None, "PR4064_NOT_OPEN_DRAFT")
    require(pr.get("head", {}).get("sha") == HEAD, "PR4064_LIVE_HEAD_DRIFT")
    require(pr.get("base", {}).get("ref") == "main", "PR4064_BASE_NOT_MAIN")
    return {"pr": PR, "head": HEAD, "draft": True, "base": "main"}

def top_level_sql_statements(sql: str) -> list[tuple[str, ...]]:
    """Lex PostgreSQL statement heads; exclude comments, literals and DO bodies.

    A keyword is a transaction command only at the start of a top-level
    statement.  In particular, ON COMMIT DROP/DELETE ROWS is CREATE TABLE
    syntax, not a COMMIT.  PL/pgSQL END is inside a dollar-quoted DO body.
    """
    statements: list[tuple[str, ...]] = []
    words: list[str] = []
    n, i = len(sql), 0
    line_start = True
    while i < n:
        ch = sql[i]
        if ch in " \t\f\v":
            i += 1
            continue
        if ch in "\r\n":
            line_start = True
            i += 1
            continue
        if ch == "\\" and line_start:
            end = sql.find("\n", i)
            end = n if end < 0 else end
            directive = sql[i:end].strip()
            require(not words and (directive == r"\set ON_ERROR_STOP on" or
                                   directive.startswith(r"\echo IG4064_")),
                    "UNEXPECTED_PSQL_META")
            i = end
            continue
        line_start = False
        if sql.startswith("--", i):
            end = sql.find("\n", i)
            i = n if end < 0 else end
            continue
        if sql.startswith("/*", i):
            depth = 1
            i += 2
            while i < n and depth:
                if sql.startswith("/*", i):
                    depth += 1
                    i += 2
                elif sql.startswith("*/", i):
                    depth -= 1
                    i += 2
                else:
                    i += 1
            require(depth == 0, "SQL_UNTERMINATED_COMMENT")
            continue
        if ch in "\"'":
            quoted = ch
            # PostgreSQL E'...' accepts backslash escaping in addition to ''.
            escaped = (ch == "'" and i > 0 and sql[i - 1] in "eE" and
                       (i == 1 or not (sql[i - 2].isalnum() or sql[i - 2] == "_")))
            i += 1
            while i < n:
                if sql[i] == quoted:
                    if i + 1 < n and sql[i + 1] == quoted:
                        i += 2
                        continue
                    i += 1
                    break
                if escaped and sql[i] == "\\" and i + 1 < n:
                    i += 2
                else:
                    i += 1
            else:
                raise RuntimeError("SQL_UNTERMINATED_QUOTE")
            continue
        if ch == "$":
            # Real PL/pgSQL statements are opaque to the outer SQL parser.
            tag = re.match(r"\$(?:[A-Za-z_][A-Za-z_0-9]*)?\$", sql[i:])
            if tag:
                marker = tag.group(0)
                close = sql.find(marker, i + len(marker))
                require(close >= 0, "SQL_UNTERMINATED_DOLLAR_QUOTE")
                i = close + len(marker)
                continue
        if ch == ";":
            if words:
                statements.append(tuple(words))
                words = []
            i += 1
            continue
        if ch.isascii() and (ch.isalpha() or ch == "_"):
            end = i + 1
            while end < n and sql[end].isascii() and (
                    sql[end].isalnum() or sql[end] == "_"):
                end += 1
            words.append(sql[i:end].upper())
            i = end
            continue
        i += 1
    require(not words, "SQL_UNTERMINATED_STATEMENT")
    return statements


def assert_safe_transaction_control(sql: str) -> None:
    """Fail closed on actual transaction-ending/preparing SQL statements."""
    statements = top_level_sql_statements(sql)
    for head in statements:
        require(not (head[0] in ("COMMIT", "END") or
                     head[:2] == ("PREPARE", "TRANSACTION") or
                     head[:2] == ("ROLLBACK", "PREPARED")),
                "COMMIT_FORBIDDEN")
    require(sum(head[0] == "BEGIN" for head in statements) == 1,
            "MULTIPLE_OR_MISSING_BEGIN")
    require(sum(head[0] == "ROLLBACK" for head in statements) == 1,
            "MULTIPLE_OR_MISSING_ROLLBACK")


def assembled_sql() -> tuple[str, dict]:
    migration, harness, digests = exact_sql()
    require(TEMPLATE.is_file(), "TRUSTED_SQL_TEMPLATE_MISSING")
    template = TEMPLATE.read_text(encoding="utf-8")
    for marker, expected in (
        ("@@EXPECTED_FUNCTIONS@@", 2),
        ("@@MIGRATION_DO@@", 1),
        ("@@HARNESS_DO@@", 1)
    ):
        require(template.count(marker) == expected, "SQL_TEMPLATE_MARKER_DRIFT:" + marker)
    sql = (template.replace("@@EXPECTED_FUNCTIONS@@", function_values())
           .replace("@@MIGRATION_DO@@", migration)
           .replace("@@HARNESS_DO@@", harness))
    # A single BEGIN and ROLLBACK in the same script/psql process.
    assert_safe_transaction_control(sql)
    require(sql.index("\nBEGIN;") < sql.index("DO $ig$") < sql.index("DO $test$")
            < sql.index("\nROLLBACK;") < sql.index("DO $post$"),
            "TX_STEP_ORDER_INVALID")
    return sql, digests

def independent_readback_sql(sql: str) -> str:
    """Extract only the post-ROLLBACK DO block, never the comment's prose.

    The trusted SQL template uses a same-line prose comment following
    '-- Same psql session, AFTER rollback.'. Splitting on that substring
    used to promote the remainder of the comment into executable SQL.
    """
    marker = "-- Same psql session, AFTER rollback."
    require(sql.count(marker) == 1, "INDEPENDENT_READBACK_MARKER_DRIFT")
    suffix = sql.split(marker, 1)[1]
    _, newline, body = suffix.partition("\n")
    require(bool(newline), "INDEPENDENT_READBACK_COMMENT_NOT_TERMINATED")
    post_sql = body.strip()
    require(post_sql.startswith("DO $post$\n") and post_sql.endswith("\n$post$;"),
            "INDEPENDENT_READBACK_POST_DO_MISSING")
    require(top_level_sql_statements(post_sql) == [("DO",)],
            "INDEPENDENT_READBACK_EXTRA_STATEMENT")
    return post_sql + "\n"


def pg_env() -> dict[str, str]:
    env = dict(os.environ)
    require(bool(env.get("PGPASSWORD")), "PROTECTED_DB_SECRET_UNAVAILABLE")
    require(env.get("PGHOST") == "aws-1-us-east-1.pooler.supabase.com", "DB_HOST_DRIFT")
    require(env.get("PGUSER") == "postgres.mhwmirqcgxxukpctffuv", "DB_ROLE_DRIFT")
    require(env.get("PGSSLMODE") == "require", "DB_SSL_REQUIRED")
    env["PGCONNECT_TIMEOUT"] = "15"
    return env

def psql(file: Path, *, limit: int = 1500) -> tuple[int, str]:
    proc = subprocess.run(["psql", "-X", "-q", "-v", "ON_ERROR_STOP=1",
                           "-d", "postgres", "-f", str(file)],
                          env=pg_env(), stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                          text=True, timeout=limit, check=False)
    return proc.returncode, proc.stdout

def execute() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    report = {"status": "FAIL", "pr": PR, "head": HEAD, "executed": False,
              "persisted_writes_authorized": False, "rollback_only": True}
    evidence = ""
    original_run_attempted = False
    try:
        identity = governance_check()  # Recheck AFTER environment approval.
        sql, digests = assembled_sql()
        report.update({"governance": identity, "source_sha256": digests,
                       "assembled_sql_sha256": sha256(sql.encode())})
        script = OUT / "single_session_rollback.sql"
        script.write_text(sql, encoding="utf-8")
        original_run_attempted = True
        report["executed"] = True
        return_code, evidence = psql(script, limit=30 * 60)
        (OUT / "postgresql.log").write_text(evidence, encoding="utf-8")
        report["postgresql_exit_code"] = return_code
        missing = [k for k in REQUIRED if k not in evidence]
        report["missing_assertions"] = missing
        report["postgresql_log_sha256"] = sha256(evidence.encode())

        # Independent connection AFTER original session closed: read only.
        post_sql = independent_readback_sql(sql)
        rb = OUT / "independent_readback.sql"
        rb.write_text(post_sql, encoding="utf-8")
        rb_rc, rb_log = psql(rb, limit=90)
        (OUT / "independent_readback.log").write_text(rb_log, encoding="utf-8")
        report["independent_readback_exit_code"] = rb_rc
        report["independent_readback_log_sha256"] = sha256(rb_log.encode())
        report["independent_readback_pass"] = rb_rc == 0 and (
            "IG4064_POST_ROLLBACK_PASS original_md5=7/7" in rb_log)
        require(return_code == 0, "POSTGRESQL_SQL_OR_FUNCTION_FAIL")
        require(not missing, "FUNCTIONAL_EVIDENCE_MISSING")
        require(report["independent_readback_pass"], "POST_ROLLBACK_READBACK_FAIL")
        report["status"] = "PASS"
    except subprocess.TimeoutExpired:
        report["blocking_error"] = "SQL_TIMEOUT_CONNECTION_CLOSED_TX_ABORTED"
    except Exception as exc:
        report["blocking_error"] = str(exc)[:500]
    finally:
        report["observed_at_utc"] = datetime.now(timezone.utc).isoformat()
        report["pg_run_attempted"] = original_run_attempted
        (OUT / "report.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n",
                                          encoding="utf-8")
        print(json.dumps({k: v for k, v in report.items() if k != "governance"}, sort_keys=True))
    return 0 if report["status"] == "PASS" else 1

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("self-test", "preflight", "execute"))
    mode = parser.parse_args().mode
    OUT.mkdir(parents=True, exist_ok=True)
    if mode == "self-test":
        require(len(EXPECTED_MD5) == 7 and len(BLOBS) == 2, "SELF_TEST_SHA_FIXTURE")
        require("IG4064_RECALL_PASS" in TEMPLATE.read_text(encoding="utf-8"), "SELF_TEST_RECALL")
        require("IG4064_OTHER_39_REGRESSION_PASS" in TEMPLATE.read_text(encoding="utf-8"),
                "SELF_TEST_OTHER_SCREENS")
        require("IG4064_POST_ROLLBACK_PASS" in TEMPLATE.read_text(encoding="utf-8"),
                "SELF_TEST_POST_READBACK")
        print("PASS_IG4064_RUNNER_STATIC_SELFTEST")
        return 0
    if mode == "preflight":
        pr = governance_check()
        sql, digests = assembled_sql()
        receipt = {"pr": pr, "source_sha256": digests,
                   "assembled_sql_sha256": sha256(sql.encode()),
                   "nonpersistent_only": True}
        (OUT / "preflight.json").write_text(json.dumps(receipt, indent=2) + "\n",
                                            encoding="utf-8")
        print("PASS_IG4064_PINNED_SOURCE_PREFLIGHT head=" + HEAD)
        return 0
    return execute()

if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print("FAIL_IG4064_GOVERNED_RUNNER " + str(exc)[:500], file=sys.stderr)
        raise SystemExit(1)

#!/usr/bin/env python3
"""Offline tests for the trusted read-only MIGRATION_SOURCE_PARITY runner.

No database: the psql call is replaced by a fake that returns a snapshot.
The integration case builds a throwaway candidate clone that carries a new
migration plus hostile modules, and proves none of them is executed.
"""
from __future__ import annotations

import importlib.util
import json
import os
import re
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
TARGET = HERE / "run_migration_source_parity_trusted_v1.py"
REPO = HERE.parents[2]


def load():
    spec = importlib.util.spec_from_file_location("parity_trusted_under_test", TARGET)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def expect_fail(m, prefix: str, fn) -> None:
    try:
        fn()
    except m.TrustedRunnerError as exc:
        assert str(exc).startswith(prefix), (str(exc), prefix)
        return
    raise AssertionError(f"expected {prefix}")


def with_env(values, fn):
    saved = {k: os.environ.get(k) for k in values}
    try:
        for k, v in values.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v
        return fn()
    finally:
        for k, v in saved.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v


def git(cwd: Path, *args: str) -> str:
    return subprocess.run(["git", *args], cwd=cwd, check=True, text=True, capture_output=True).stdout.strip()


def main() -> int:
    m = load()
    checks = 0

    # 1. psql --csv rendering (verified byte-identical against real psql on a fixture).
    assert m.render_rows([["a", "", None, "x,y", 'q"z', "l1\nl2"]]) == 'a,,,"x,y","q""z","l1\nl2"\n'
    assert m.render_rows([]) == ""
    assert m.render_rows([["0", None]]) == "0,\n"
    checks += 1

    # 2. Snapshot parsing from `psql --csv -t` output (JSON is CSV-quoted).
    snap = {"schema_version": m.SNAPSHOT_SCHEMA, "post_cutover": [], "statement_counts": [],
            "owners": [], "grandfathered": ["796", "x"], "legacy": ["0", None]}
    out = m.render_rows([[json.dumps(snap)]])
    assert m.parse_snapshot(out)["grandfathered"] == ["796", "x"]
    bad = dict(snap, schema_version="other")
    expect_fail(m, "FAIL_MIGRATION_PARITY_SNAPSHOT_SCHEMA", lambda: m.parse_snapshot(m.render_rows([[json.dumps(bad)]])))
    expect_fail(m, "FAIL_MIGRATION_PARITY_SNAPSHOT_SHAPE", lambda: m.parse_snapshot(""))
    expect_fail(m, "FAIL_MIGRATION_PARITY_SNAPSHOT_FIELD", lambda: m.parse_snapshot(m.render_rows([[json.dumps(dict(snap, legacy=["0"]))]])))
    checks += 1

    # 3. Read-only credential only.
    expect_fail(m, "BLOCK_MIGRATION_PARITY_RO_PASSWORD_MISSING",
                lambda: with_env({m.CI_READONLY_PASSWORD_ENV: None, m.WRITE_PASSWORD_ENV: "w", m.RO_URL_ENV: None}, m.readonly_pg_env))
    env = with_env({m.CI_READONLY_PASSWORD_ENV: "ro", m.WRITE_PASSWORD_ENV: "w",
                    "SUPABASE_PROJECT_ID": "", "SUPABASE_POOLER_HOST": ""}, m.readonly_pg_env)
    assert env["PGUSER"] == f"lf_ci_readonly.{m.PROJECT_ID}" and env["PGPASSWORD"] == "ro"
    assert env["PGHOST"] == m.POOLER_HOST and m.WRITE_PASSWORD_ENV not in env
    checks += 1

    # 3b. Read-only URL credential (Merge Train: lf_reconcile_readonly), allowlisted roles only.
    url_env = {m.CI_READONLY_PASSWORD_ENV: None, m.WRITE_PASSWORD_ENV: "w"}
    env = with_env(dict(url_env, **{m.RO_URL_ENV: "postgresql://lf_reconcile_readonly.abcdefghijklmnopqrst:p%40ss%2Fx@pool.example.com:6543/postgres?sslmode=verify-full"}), m.readonly_pg_env)
    assert env["PGUSER"] == "lf_reconcile_readonly.abcdefghijklmnopqrst" and env["PGPASSWORD"] == "p@ss/x"
    assert env["PGHOST"] == "pool.example.com" and env["PGPORT"] == "6543" and env["PGDATABASE"] == "postgres"
    assert env["PGSSLMODE"] == "verify-full"
    assert m.WRITE_PASSWORD_ENV not in env and m.RO_URL_ENV not in env and m.CI_READONLY_PASSWORD_ENV not in env
    env = with_env(dict(url_env, **{m.RO_URL_ENV: "postgres://lf_ci_readonly.x:pw@h/db"}), m.readonly_pg_env)
    assert env["PGUSER"] == "lf_ci_readonly.x" and env["PGPORT"] == "5432" and env["PGSSLMODE"] == "require" and env["PGDATABASE"] == "db"
    for bad_url, code in (
        ("postgresql://postgres.abcdefghijklmnopqrst:pw@h:5432/postgres", "BLOCK_MIGRATION_PARITY_RO_URL_ROLE_NOT_READ_ONLY"),
        ("postgresql://lf_runtime_readback_oidc_writer.x:pw@h/postgres", "BLOCK_MIGRATION_PARITY_RO_URL_ROLE_NOT_READ_ONLY"),
        ("mysql://lf_ci_readonly.x:pw@h/db", "BLOCK_MIGRATION_PARITY_RO_URL_INVALID"),
        ("postgresql://lf_ci_readonly.x@h/db", "BLOCK_MIGRATION_PARITY_RO_URL_INVALID"),
    ):
        expect_fail(m, code, lambda u=bad_url: with_env(dict(url_env, **{m.RO_URL_ENV: u}), m.readonly_pg_env))
    expect_fail(m, "BLOCK_MIGRATION_PARITY_RO_PASSWORD_MISSING",
                lambda: with_env(dict(url_env, **{m.RO_URL_ENV: None}), m.readonly_pg_env))
    # The lf_ci_readonly password takes precedence when both are present.
    env = with_env({m.CI_READONLY_PASSWORD_ENV: "ro", m.RO_URL_ENV: "postgresql://lf_reconcile_readonly.x:pw@h/db"}, m.readonly_pg_env)
    assert env["PGUSER"].startswith("lf_ci_readonly.") and env["PGPASSWORD"] == "ro"
    checks += 1

    # 4. Environment scrub.
    def scrub():
        m.scrub_environment()
        return {k: os.environ.get(k) for k in (m.WRITE_PASSWORD_ENV, "PGPASSWORD", "PYTHONPATH")}
    assert with_env({m.WRITE_PASSWORD_ENV: "w", "PGPASSWORD": "p", "PYTHONPATH": "/evil"}, scrub) == {
        m.WRITE_PASSWORD_ENV: None, "PGPASSWORD": None, "PYTHONPATH": None}
    checks += 1

    # 5. Snapshot SQL: function call with validated literals only.
    class Full:
        CUTOVER = "20260808031006"; CLASSIFICATION_BASELINE_END = "20261005203801"
        LEGACY_START = "20260801063708"; LEGACY_END = "20260801170332"
    sql = m.snapshot_sql(context_versions=["20261020100000"], managed_versions=[], full=Full)
    assert sql.startswith("select public.lf_ci_migration_parity_snapshot_v1('{20261020100000}'::text[],'{}'::text[],")
    expect_fail(m, "FAIL_MIGRATION_PARITY_TRUSTED_VERSION_LITERAL",
                lambda: m.snapshot_sql(context_versions=["1;drop"], managed_versions=[], full=Full))
    checks += 1

    # 6. Root separation.
    with tempfile.TemporaryDirectory() as tmp:
        t = Path(tmp)
        expect_fail(m, "FAIL_MIGRATION_PARITY_DATA_ROOT_NOT_GIT", lambda: m.validate_roots(t, t / "out"))
        expect_fail(m, "FAIL_MIGRATION_PARITY_DATA_ROOT_OVERLAPS_CODE", lambda: m.validate_roots(m.CODE_ROOT, t))
        (t / "cand" / ".git").mkdir(parents=True)
        expect_fail(m, "FAIL_MIGRATION_PARITY_OUTPUT_INSIDE_CANDIDATE", lambda: m.validate_roots(t / "cand", t / "cand" / "o"))
        m.validate_roots(t / "cand", t / "out")
    checks += 1

    # 7. Integration: candidate code is data, never executed; git/data come from the candidate.
    with tempfile.TemporaryDirectory() as tmp:
        t = Path(tmp)
        cand = t / "candidate"
        subprocess.run(["git", "clone", "-q", "--shared", "--no-checkout", str(REPO), str(cand)], check=True)
        base = git(REPO, "rev-parse", "HEAD")
        git(cand, "checkout", "-q", "--detach", base)
        git(cand, "config", "user.email", "t@example.invalid"); git(cand, "config", "user.name", "t")
        marker = t / "HOSTILE_CODE_EXECUTED"
        hostile = f"open({str(marker)!r}, 'w').write('x')\n"
        mig = cand / "supabase/migrations/29990101000000_lf_trusted_runner_probe_v1.sql"
        mig.write_text("select 1;\n", encoding="utf-8")
        pkg = cand / "sandbox/lf_contract_gate_test/migration_source_parity"
        (pkg / "migration_transport_normalization.py").write_text(hostile, encoding="utf-8")
        (pkg / "run_migration_source_parity_focal_v1.py").write_text(hostile, encoding="utf-8")
        (cand / "sandbox/lf_contract_gate_test/lf_migration_source_parity.py").write_text(hostile, encoding="utf-8")
        git(cand, "add", "-A"); git(cand, "commit", "-q", "-m", "candidate")
        head = git(cand, "rev-parse", "HEAD")
        git(cand, "branch", "-f", "main", base)
        git(cand, "remote", "set-url", "origin", str(cand))

        seen = {}
        def fake_psql(sql, *, env):
            seen["sql"] = sql
            seen["user"] = env.get("PGUSER")
            seen["has_write"] = m.WRITE_PASSWORD_ENV in env
            seen["secrets_in_process_env"] = [k for k in (m.CI_READONLY_PASSWORD_ENV, m.RO_URL_ENV, m.WRITE_PASSWORD_ENV) if k in os.environ]
            payload = {"schema_version": m.SNAPSHOT_SCHEMA, "post_cutover": [], "statement_counts": [],
                       "owners": [], "grandfathered": ["0", None], "legacy": ["0", None]}
            return m.render_rows([[json.dumps(payload)]])

        out = t / "out"
        cwd = os.getcwd()
        try:
            rc = with_env({m.CI_READONLY_PASSWORD_ENV: "ro", m.WRITE_PASSWORD_ENV: "w", m.RO_URL_ENV: "postgresql://lf_reconcile_readonly.x:pw@h/db", "GITHUB_REPOSITORY": "o/r"},
                          lambda: m.run(["--data-root", str(cand), "--base-sha", base, "--head-sha", head,
                                         "--output-dir", str(out)], psql=fake_psql))
        finally:
            os.chdir(cwd)
        assert not marker.exists(), "candidate code was executed"
        assert "'{29990101000000}'::text[]" in seen["sql"], seen["sql"]
        assert seen["user"].startswith("lf_ci_readonly.") and seen["has_write"] is False
        assert seen["secrets_in_process_env"] == [], seen["secrets_in_process_env"]
        assert (out / "focal_migrations" / mig.name).read_text(encoding="utf-8") == "select 1;\n"
        summary = json.loads((out / "run-summary.json").read_text(encoding="utf-8"))
        assert summary["runner"] == "TRUSTED_READ_ONLY_V1" and summary["delegated_adapter"].endswith("lf_migration_source_parity.py")
        assert rc != 0 or summary["status"] == "PASS"  # fake ledger: adapter verdict itself is not under test
        assert os.environ.get("LF_MIGRATION_PARITY_DATA_ROOT") == str(cand.resolve())
        os.environ.pop("LF_MIGRATION_PARITY_DATA_ROOT", None)
    checks += 1

    # 8. FULL_CURRENT_STATE batches >200 source/ledger versions through the
    # existing read-only snapshot, including remote-only identity in the union.
    with tempfile.TemporaryDirectory() as tmp:
        t=Path(tmp)
        migrations=t/"supabase/migrations"
        migrations.mkdir(parents=True)
        versions=[str(20261021000000+i) for i in range(205)]
        remote_only=str(20261021000999)
        for version in versions:
            (migrations/(version+"_lf_test_scope_v1.sql")).write_text("select 1;\n")
        class StubFull:
            CUTOVER="20260808031006"
            CLASSIFICATION_BASELINE_END="20261005203801"
            LEGACY_START="20260801063708"
            LEGACY_END="20260801170332"
            @staticmethod
            def _load_parity_adapter():
                class Adapter:
                    FILENAME_RE=re.compile(r"^(\d{14})_(.+)\.sql$")
                    @staticmethod
                    def managed_source(path,version,name):
                        return True
                return Adapter()
            @staticmethod
            def _write_text(path,value,max_bytes=None):
                assert max_bytes is None or len(value.encode())<=max_bytes
                path.write_text(value,encoding="utf-8")
            @staticmethod
            def _build_external_owner_evidence(csv_path):
                return {"schema_version":"lf-migration-external-owner-currentness/v1",
                        "repository":"o/r","complete":True,"owners":[]}
        calls=[]
        def fake_full_psql(sql,*,env):
            if sql.startswith("select version,coalesce(name,'') from supabase_migrations.schema_migrations"):
                return m.render_rows([[v,"lf_test_scope_v1"] for v in versions]+
                                     [[remote_only,"lf_ledger_only_v1"]])
            arrays=re.findall(r"'\\{([^}]*)\\}'::text\\[\\]",sql)
            assert len(arrays)==2,sql[:200]
            requested=arrays[0].split(",") if arrays[0] else []
            managed=arrays[1].split(",") if arrays[1] else []
            calls.append((requested,managed))
            snap={"schema_version":m.SNAPSHOT_SCHEMA,
                  "post_cutover":[[v,"lf_ledger_only_v1" if v==remote_only else "lf_test_scope_v1",
                                   "sha256:"+"0"*64] for v in requested],
                  "statement_counts":[[v,"1"] for v in managed],
                  "owners":[],"grandfathered":["796","frozen"],"legacy":["1","frozen"]}
            return m.render_rows([[json.dumps(snap)]])
        outputs,counts=m.prepare_full_current_inputs(
            focal=None,full=StubFull(),output_dir=t/"out",data_root=t,
            pg_env={"PGUSER":"lf_reconcile_readonly.test"},psql=fake_full_psql
        )
        assert counts["local_versions"]==205 and counts["ledger_versions"]==206
        assert counts["union_versions"]==206 and counts["snapshot_batches"]==2
        assert max(len(batch[0]) for batch in calls)<=150
        assert any(remote_only in batch[0] for batch in calls)
        assert len(list(__import__("csv").reader(outputs["post_cutover"].open())))==206
        assert len(list(__import__("csv").reader(outputs["statement_counts"].open())))==205
        assert json.loads((t/"out"/"full-current-input-scope.json").read_text())["scope"]=="FULL_CURRENT_STATE"
    checks += 1

    print(f"PASS_MIGRATION_SOURCE_PARITY_TRUSTED_RUNNER_V1 checks={checks}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

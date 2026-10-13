#!/usr/bin/env python3
"""Train-managed ACTUALIZACION_DB_LF execution (option C).

The LF Migration Merge Train opens, records and closes the canonical Router
execution of every migration it applies, using only evidence it produced:

  begin   (pre-apply, fatal)  reserve execution -> lease -> preflight step ->
                              reserve effect MIGRATION:<version>
  commit  (post-apply)        mark effect SUCCEEDED with the apply receipt ->
                              patch step
  close   (post-merge)        verify step -> lf_close_db_operation_execution_v1

Every call goes through the canonical SQL functions; this module never
writes tables directly and never invents evidence.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
from urllib.parse import quote

OPERATION = "ACTUALIZACION_DB_LF"
CLEAN = "PASS_CLEAN"
LEASE_TTL_SECONDS = 3600
PREVENTION_RULES = (
    "PRV-CI-009",
    "PRV-DB-GIT-FIRST-PERSISTENT-OBJECT-001",
    "PRV-SQL-001",
    "PRV-SQL-007",
    "PRV-SQL-012",
    "PRV-RTE-006",
)
VERSION_RE = re.compile(r"^\d{14}$")
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
SHA1_RE = re.compile(r"^[0-9a-f]{40}$")


def identity(pr: str, version: str, run_id: str) -> dict[str, str]:
    if not VERSION_RE.fullmatch(version):
        raise ValueError(f"TRAIN_EXEC_VERSION_INVALID:{version}")
    if not pr.isdigit() or not run_id.isdigit():
        raise ValueError("TRAIN_EXEC_PR_OR_RUN_INVALID")
    return {
        "execution_id": f"EXEC-DB-TRAIN-PR{pr}-{version}-R{run_id}",
        "actor": f"LF-MIGRATION-TRAIN-RUN-{run_id}",
        "lease_owner": f"lf-migration-train-{run_id}",
        "effect_scope": f"MIGRATION:{version}",
        "dispatch_key": f"lf-migration-train-run-{run_id}",
    }


def preflight_evidence(ctx: dict, capability: dict) -> dict:
    return {
        "db_write_transport_capability_binding": capability,
        "ekb_refs": list(PREVENTION_RULES),
        "exact_target": {
            "migration_version": ctx["version"],
            "migration_name": ctx["name"],
            "target_path": ctx["path"],
            "source_blob": ctx["source_blob"],
            "source_sha256": ctx["source_sha256"],
            "repository": ctx["repo"],
            "pr": int(ctx["pr"]),
            "head_sha": ctx["head_sha"],
        },
        "rollback_plan": {
            "mode": "FAIL_FORWARD_NEW_MIGRATION",
            "rule": "NO_REPLAY_NO_RETIMESTAMP_AFTER_APPLY",
        },
        "schema_source_readback": {
            "git_source_persisted": True,
            "source_blob": ctx["source_blob"],
            "source_sha256": ctx["source_sha256"],
            "persisted_head_sha": ctx["persisted_head_sha"],
            "saga": "READY_TO_APPLY",
        },
        "preflight_pass": True,
        "producer": "lf-migration-merge-train",
        "train_run_id": ctx["run_id"],
    }


def patch_evidence(ctx: dict, ids: dict, decision: dict, apply_receipt: dict) -> dict:
    return {
        "db_write_transport_decision": decision,
        "db_write_transport_receipt": apply_receipt,
        "minimal_diff": {
            "kind": "ONE_MIGRATION_FILE",
            "target_path": ctx["path"],
            "source_sha256": ctx["source_sha256"],
        },
        "operation_effect_guard_reservation": {
            "effect_scope": ids["effect_scope"],
            "dispatch_key": ids["dispatch_key"],
            "effect_request_sha256": ctx["source_sha256"],
        },
        "target_binding": {
            "migration_version": ctx["version"],
            "migration_name": ctx["name"],
            "target_path": ctx["path"],
        },
        "write_receipt": {
            "ledger_version": apply_receipt.get("ledger_version"),
            "ledger_name": apply_receipt.get("ledger_name"),
            "executor": apply_receipt.get("executor"),
            "code": apply_receipt.get("code"),
        },
        "minimal_patch": True,
        "producer": "lf-migration-merge-train",
        "train_run_id": ctx["run_id"],
    }


def verify_evidence(ctx: dict, ids: dict, ledger: dict, merge_sha: str, parity_status: str) -> dict:
    return {
        "db_write_transport_readback": ledger,
        "ekb_closeout": {"prevention_rules": list(PREVENTION_RULES), "status": "TRAIN_CLOSED"},
        "operation_effect_guard_reservation": {
            "effect_scope": ids["effect_scope"],
            "dispatch_key": ids["dispatch_key"],
            "effect_request_sha256": ctx["source_sha256"],
        },
        "readback": {"main_merge_sha": merge_sha, "target_path": ctx["path"], "in_main": True},
        "regression_or_parity": {"migration_source_parity": parity_status},
        "verified": True,
        "producer": "lf-migration-merge-train",
        "train_run_id": ctx["run_id"],
    }


def validate_context(ctx: dict) -> None:
    for key in ("pr", "version", "name", "path", "source_blob", "source_sha256",
                "repo", "head_sha", "persisted_head_sha", "run_id"):
        if not str(ctx.get(key, "")).strip():
            raise ValueError(f"TRAIN_EXEC_CONTEXT_MISSING:{key}")
    if not SHA256_RE.fullmatch(ctx["source_sha256"]):
        raise ValueError("TRAIN_EXEC_SOURCE_SHA256_INVALID")
    if not SHA1_RE.fullmatch(ctx["source_blob"]):
        raise ValueError("TRAIN_EXEC_SOURCE_BLOB_INVALID")


# ---------------------------------------------------------------- database


def db_url() -> str:
    password = os.environ.get("LF_SUPABASE_DB_PASSWORD", "").strip()
    project = os.environ.get("SUPABASE_PROJECT_ID", "").strip()
    host = os.environ.get("SUPABASE_POOLER_HOST", "").strip()
    if not (password and project and host):
        raise RuntimeError("TRAIN_EXEC_DB_CONTEXT_MISSING")
    return f"postgresql://postgres.{project}:{quote(password, safe='')}@{host}:5432/postgres?sslmode=require"


def call(sql: str, **params: str) -> dict:
    """Run one SELECT returning jsonb; params are bound as psql variables."""
    argv = ["psql", db_url(), "-X", "-At", "-v", "ON_ERROR_STOP=1"]
    for key, value in params.items():
        argv += ["-v", f"{key}={value}"]
    argv += ["-f", "-"]
    proc = subprocess.run(argv, input=sql, text=True, capture_output=True, timeout=120, check=False)
    if proc.returncode != 0:
        tail = " | ".join(proc.stderr.strip().splitlines()[-4:])
        raise RuntimeError(f"TRAIN_EXEC_SQL_FAILED:{tail}")
    out = proc.stdout.strip().splitlines()
    return json.loads(out[-1]) if out else {}


def record_step(ids: dict, step: str, evidence: dict) -> dict:
    prior = call(
        "select coalesce((select jsonb_build_object('status', status)"
        " from public.lf_operation_execution_steps"
        " where execution_id = :'exec' and step_id = :'step'"
        " order by step_order limit 1), '{}'::jsonb);",
        exec=ids["execution_id"], step=step,
    )
    if prior.get("status") == CLEAN:
        return {"outcome": "STEP_ALREADY_PASS_CLEAN", "status": CLEAN, "step_id": step}
    res = call(
        "select public.lf_record_db_operation_step_v1(:'exec', :'step', :'ref', (:'payload')::jsonb, :'actor');",
        exec=ids["execution_id"], step=step, ref=f"{ids['actor']}:{step}",
        payload=json.dumps(evidence, sort_keys=True), actor=ids["actor"],
    )
    if res.get("outcome") != "STEP_RECORDED" or res.get("status") not in (CLEAN, None):
        raise RuntimeError(f"TRAIN_EXEC_STEP_NOT_CLEAN:{step}:{json.dumps(res, sort_keys=True)[:600]}")
    return res


def begin(ctx: dict) -> dict:
    validate_context(ctx)
    ids = identity(ctx["pr"], ctx["version"], ctx["run_id"])
    manifest = {"producer": "lf-migration-merge-train", "train_run_id": ctx["run_id"],
                "pr": int(ctx["pr"]), "head_sha": ctx["head_sha"]}
    res = call(
        "select public.fn_lf_operation_reserve_execution_v1(:'exec', 'ACTUALIZACION_DB_LF', 'MIGRATION',"
        " :'target', :'idem', :'reqsha', :'actor', :'repo', :'path', (:'manifest')::jsonb);",
        exec=ids["execution_id"], target=f"{ctx['version']}_{ctx['name']}",
        idem=f"train:{ctx['version']}:{ctx['source_blob']}", reqsha=ctx["source_sha256"], actor=ids["actor"],
        repo=ctx["repo"], path=ctx["path"], manifest=json.dumps(manifest, sort_keys=True),
    )
    if res.get("status") != "IN_PROGRESS":
        raise RuntimeError(f"TRAIN_EXEC_RESERVE_FAILED:{json.dumps(res, sort_keys=True)[:600]}")
    lease = call(
        "select public.fn_lf_operation_acquire_lease_v1(:'exec', :'owner', :ttl, :'actor');",
        exec=ids["execution_id"], owner=ids["lease_owner"], ttl=str(LEASE_TTL_SECONDS), actor=ids["actor"],
    )
    if lease.get("result") != "LEASE_ACQUIRED":
        raise RuntimeError(f"TRAIN_EXEC_LEASE_FAILED:{json.dumps(lease, sort_keys=True)}")
    ids["lease_fence"] = str(lease["lease_fence"])
    capability = call(
        "select jsonb_build_object('capability_code', capability_code, 'version', current_version,"
        " 'manifest_sha256', current_manifest_sha256, 'entry_guard_state', entry_guard_state)"
        " from public.v_lf_capability_entry_guard_v1 where capability_code = 'DB_WRITE_TRANSPORT';"
    )
    if capability.get("entry_guard_state") != "GUARDED":
        raise RuntimeError("TRAIN_EXEC_TRANSPORT_NOT_GUARDED")
    record_step(ids, "preflight", preflight_evidence(ctx, capability))
    effect = call(
        "select public.fn_lf_operation_reserve_effect_v1(:'exec', :'owner', :fence, :'scope', :'sha', :'dispatch', :'actor');",
        exec=ids["execution_id"], owner=ids["lease_owner"], fence=ids["lease_fence"],
        scope=ids["effect_scope"], sha=ctx["source_sha256"], dispatch=ids["dispatch_key"], actor=ids["actor"],
    )
    if effect.get("dispatch_permitted") is not True:
        raise RuntimeError(f"TRAIN_EXEC_EFFECT_NOT_PERMITTED:{json.dumps(effect, sort_keys=True)[:600]}")
    return {"context": ctx, "ids": ids, "result": "TRAIN_EXECUTION_READY_TO_APPLY", "effect_state": "RESERVED"}


def resume(ctx: dict) -> dict:
    """Resume one expired open execution only when its exact migration is in the ledger."""
    validate_context(ctx)
    ids = identity(ctx["pr"], ctx["version"], ctx["run_id"])
    ledger = call(
        "select coalesce((select jsonb_build_object('version', version, 'name', name)"
        " from supabase_migrations.schema_migrations where version = :'v'), '{}'::jsonb);",
        v=ctx["version"],
    )
    if ledger.get("version") != ctx["version"] or ledger.get("name") != ctx["name"]:
        raise RuntimeError(f"TRAIN_EXEC_RESUME_LEDGER_IDENTITY_MISMATCH:{json.dumps(ledger, sort_keys=True)}")

    target = f"{ctx['version']}_{ctx['name']}"
    rows = call(
        "select jsonb_build_object('matches', coalesce(jsonb_agg(q.row), '[]'::jsonb))"
        " from (select jsonb_build_object("
        " 'execution_id', e.execution_id, 'target_path', e.target_path,"
        " 'target_repo', e.target_repo, 'effect_scope', g.effect_scope,"
        " 'effect_request_sha256', g.effect_request_sha256, 'dispatch_key', g.dispatch_key,"
        " 'effect_state', g.state, 'effect_receipt', g.receipt) AS row"
        " from public.lf_operation_execution e"
        " join public.lf_operation_effect_guard g on g.execution_id = e.execution_id"
        " where e.execution_id like :'exec_prefix'"
        " and e.operation_code = 'ACTUALIZACION_DB_LF'"
        " and e.target_code = :'target' and e.target_type = 'MIGRATION'"
        " and e.target_repo = :'repo' and e.target_path = :'path'"
        " and e.status = 'IN_PROGRESS' and e.lease_expires_at <= clock_timestamp()"
        " and e.request_sha256 = :'sha'"
        " and g.effect_scope = 'MIGRATION:' || :'v'"
        " and g.effect_request_sha256 = :'sha' and g.state in ('RESERVED','SUCCEEDED')"
        " order by e.created_at desc limit 2) q;",
        exec_prefix=f"EXEC-DB-TRAIN-PR{ctx['pr']}-{ctx['version']}-R%",
        target=target, repo=ctx["repo"], path=ctx["path"],
        sha=ctx["source_sha256"], v=ctx["version"],
    )
    matches = rows.get("matches", [])
    if not matches:
        return {"result": "TRAIN_EXECUTION_NOT_FOUND", "execution_id": None}
    if len(matches) != 1:
        raise RuntimeError(f"TRAIN_EXEC_RESUME_AMBIGUOUS:{len(matches)}")
    candidate = matches[0]
    if candidate.get("effect_state") == "SUCCEEDED" and not candidate.get("effect_receipt"):
        raise RuntimeError("TRAIN_EXEC_RESUME_SUCCEEDED_RECEIPT_MISSING")

    ids["execution_id"] = candidate["execution_id"]
    ids["effect_scope"] = candidate["effect_scope"]
    ids["dispatch_key"] = candidate["dispatch_key"]
    ids["lease_owner"] = f"lf-migration-train-{ctx['run_id']}"
    ids["effect_request_sha256"] = candidate["effect_request_sha256"]
    lease = call(
        "select public.fn_lf_operation_acquire_lease_v1(:'exec', :'owner', :ttl, :'actor');",
        exec=ids["execution_id"], owner=ids["lease_owner"],
        ttl=str(LEASE_TTL_SECONDS), actor=ids["actor"],
    )
    if lease.get("result") != "LEASE_ACQUIRED":
        raise RuntimeError(f"TRAIN_EXEC_RESUME_LEASE_FAILED:{json.dumps(lease, sort_keys=True)}")
    ids["lease_fence"] = str(lease["lease_fence"])
    ledger_receipt = {
        "ledger_version": ledger["version"],
        "ledger_name": ledger["name"],
        "executor": "supabase_migrations.schema_migrations",
        "code": "ALREADY_APPLIED_EXACT",
    }
    return {
        "context": ctx, "ids": ids, "result": "TRAIN_EXECUTION_RESUMED",
        "effect_state": candidate["effect_state"], "ledger_receipt": ledger_receipt,
    }


def abort(state: dict, run_id: str, failed_step: str, error_summary: str) -> dict:
    """Record pre-apply failure; SQL independently rejects any version in the ledger."""
    ctx, ids = state["context"], state["ids"]
    evidence = {
        "train_run_id": str(run_id),
        "failed_step": " ".join(str(failed_step).split())[:160],
        "error_summary": " ".join(str(error_summary).split())[:1000],
        "secrets_included": False,
    }
    result = call(
        "select public.lf_fail_db_operation_execution_v1(:'exec', :'owner', :fence, (:'ev')::jsonb, :'actor');",
        exec=ids["execution_id"], owner=ids["lease_owner"], fence=ids["lease_fence"],
        ev=json.dumps(evidence, sort_keys=True), actor=ids["actor"],
    )
    if result.get("result") not in ("EXECUTION_BLOCKED_NO_LEDGER_EFFECT", "REPLAY_ALREADY_FAILED"):
        raise RuntimeError(f"TRAIN_EXEC_ABORT_FAILED:{json.dumps(result, sort_keys=True)}")
    return {**state, "result": "TRAIN_EXECUTION_ABORTED", "abort": result}


def commit(state: dict, decision: dict, apply_receipt: dict) -> dict:
    ctx, ids = state["context"], state["ids"]
    receipt = {"apply_receipt": apply_receipt, "train_run_id": ctx["run_id"]}
    if state.get("effect_state") != "SUCCEEDED":
        call(
            "select public.fn_lf_operation_mark_effect_succeeded_v1(:'exec', :'owner', :fence, :'scope', (:'receipt')::jsonb, :'actor');",
            exec=ids["execution_id"], owner=ids["lease_owner"], fence=ids["lease_fence"],
            scope=ids["effect_scope"], receipt=json.dumps(receipt, sort_keys=True), actor=ids["actor"],
        )
        state["effect_state"] = "SUCCEEDED"
    record_step(ids, "patch", patch_evidence(ctx, ids, decision, apply_receipt))
    return {**state, "result": "TRAIN_EXECUTION_PATCH_RECORDED"}


def close(state: dict, merge_sha: str, parity_status: str) -> dict:
    ctx, ids = state["context"], state["ids"]
    ledger = call(
        "select coalesce((select jsonb_build_object('version', version, 'name', name)"
        " from supabase_migrations.schema_migrations where version = :'v'), '{}'::jsonb);",
        v=ctx["version"],
    )
    if ledger.get("version") != ctx["version"] or ledger.get("name") != ctx["name"]:
        raise RuntimeError(f"TRAIN_EXEC_LEDGER_READBACK_MISMATCH:{json.dumps(ledger)}")
    record_step(ids, "verify", verify_evidence(ctx, ids, ledger, merge_sha, parity_status))
    evidence = {"train_run_id": ctx["run_id"], "pr": int(ctx["pr"]), "merge_sha": merge_sha,
                "ledger": ledger, "parity": parity_status}
    res = call(
        "select public.lf_close_db_operation_execution_v1(:'exec', :'owner', :fence, (:'ev')::jsonb, :'actor');",
        exec=ids["execution_id"], owner=ids["lease_owner"], fence=ids["lease_fence"],
        ev=json.dumps(evidence, sort_keys=True), actor=ids["actor"],
    )
    if res.get("result") not in ("EXECUTION_COMPLETED", "REPLAY_ALREADY_COMPLETED"):
        raise RuntimeError(f"TRAIN_EXEC_CLOSE_FAILED:{json.dumps(res)}")
    return {**state, "result": "TRAIN_EXECUTION_COMPLETED", "close": res}


def self_test() -> None:
    ids = identity("2350", "20261013010000", "123456")
    assert ids["execution_id"] == "EXEC-DB-TRAIN-PR2350-20261013010000-R123456"
    assert ids["effect_scope"] == "MIGRATION:20261013010000"
    for bad in (("x", "20261013010000", "1"), ("1", "2026", "1"), ("1", "20261013010000", "a")):
        try:
            identity(*bad)
        except ValueError:
            pass
        else:
            raise AssertionError(f"bad identity accepted: {bad}")
    ctx = {"pr": "1", "version": "20261013010000", "name": "lf_x_v1",
           "path": "supabase/migrations/20261013010000_lf_x_v1.sql", "source_blob": "a" * 40,
           "source_sha256": "b" * 64, "repo": "o/r", "head_sha": "c" * 40,
           "persisted_head_sha": "d" * 40, "run_id": "123456"}
    validate_context(ctx)
    pre = preflight_evidence(ctx, {"capability_code": "DB_WRITE_TRANSPORT"})
    for key in ("db_write_transport_capability_binding", "ekb_refs", "exact_target",
                "rollback_plan", "schema_source_readback"):
        assert pre.get(key), key
    ids = identity("1", "20261013010000", "123456")
    patch = patch_evidence(ctx, ids, {"route": "x"}, {"ledger_version": "20261013010000", "ledger_name": "lf_x_v1"})
    for key in ("db_write_transport_decision", "db_write_transport_receipt", "minimal_diff",
                "operation_effect_guard_reservation", "target_binding", "write_receipt"):
        assert patch.get(key), key
    assert patch["operation_effect_guard_reservation"]["effect_request_sha256"] == "b" * 64
    ver = verify_evidence(ctx, ids, {"version": "20261013010000"}, "e" * 40, "PASS")
    for key in ("db_write_transport_readback", "ekb_closeout", "readback", "regression_or_parity"):
        assert ver.get(key), key
    bad = dict(ctx, source_sha256="nope")
    try:
        validate_context(bad)
    except ValueError:
        pass
    else:
        raise AssertionError("bad sha accepted")
    print("PASS_TRAIN_EXECUTION_RECORDER_SELFTEST")


def main() -> int:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="cmd", required=True)
    sub.add_parser("self-test")
    b = sub.add_parser("begin")
    r = sub.add_parser("resume")
    for command in (b, r):
        for key in ("pr", "version", "name", "path", "source-blob", "source-sha256",
                    "repo", "head-sha", "persisted-head-sha", "run-id"):
            command.add_argument(f"--{key}", required=True)
        command.add_argument("--state", required=True)
    a = sub.add_parser("abort")
    a.add_argument("--state", required=True)
    a.add_argument("--run-id", required=True)
    a.add_argument("--failed-step", required=True)
    a.add_argument("--error-summary", required=True)
    c = sub.add_parser("commit")
    c.add_argument("--state", required=True)
    c.add_argument("--apply-receipt", required=True)
    k = sub.add_parser("close")
    k.add_argument("--state", required=True)
    k.add_argument("--merge-sha", required=True)
    k.add_argument("--parity-status", required=True)
    args = parser.parse_args()
    if args.cmd == "self-test":
        self_test()
        return 0
    if args.cmd in ("begin", "resume"):
        ctx = {key.replace("-", "_"): getattr(args, key.replace("-", "_"))
               for key in ("pr", "version", "name", "path", "source-blob", "source-sha256",
                           "repo", "head-sha", "persisted-head-sha", "run-id")}
        state = begin(ctx) if args.cmd == "begin" else resume(ctx)
        if state.get("result") == "TRAIN_EXECUTION_NOT_FOUND":
            print(json.dumps(state, sort_keys=True))
            return 0
    elif args.cmd == "abort":
        state = json.loads(Path(args.state).read_text())
        state = abort(state, args.run_id, args.failed_step, args.error_summary)
    elif args.cmd == "commit":
        state = json.loads(Path(args.state).read_text())
        receipt = json.loads(Path(args.apply_receipt).read_text())
        here = Path(__file__).resolve().parent
        sys.path.insert(0, str(here))
        import lf_db_write_transport as transport  # noqa: E402
        from dataclasses import asdict
        decision = asdict(transport.select_transport("MIGRATION", state["context"]["path"]))
        state = commit(state, decision, receipt)
    else:
        state = json.loads(Path(args.state).read_text())
        state = close(state, args.merge_sha, args.parity_status)
    Path(args.state).write_text(json.dumps(state, sort_keys=True))
    print(json.dumps({"result": state["result"], "execution_id": state["ids"]["execution_id"]}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

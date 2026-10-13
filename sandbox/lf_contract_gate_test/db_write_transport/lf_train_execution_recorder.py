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
        "lease_owner": f"lf-migration-train-pr{pr}-{version}",
        "effect_scope": f"MIGRATION:{version}",
        "dispatch_key": f"lf-migration-train-pr{pr}-{version}",
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
    res = call(
        "select public.lf_record_db_operation_step_v1(:'exec', :'step', :'ref', (:'payload')::jsonb, :'actor');",
        exec=ids["execution_id"], step=step, ref=f"{ids['actor']}:{step}",
        payload=json.dumps(evidence, sort_keys=True), actor=ids["actor"],
    )
    if res.get("outcome") != "STEP_RECORDED" or res.get("status") not in (CLEAN, None):
        raise RuntimeError(f"TRAIN_EXEC_STEP_NOT_CLEAN:{step}:{json.dumps(res, sort_keys=True)[:600]}")
    return res


def _require_router_authority(execution_id: str) -> None:
    auth = call(
        "select public.lf_router_downstream_authority_validate_v1(:'exec');",
        exec=execution_id,
    )
    if (auth.get("applicable") is not True or auth.get("valid") is not True
            or auth.get("code") != "ROUTER_DOWNSTREAM_AUTHORITY_VALID"
            or auth.get("operation_code") != "ACTUALIZACION_DB_LF"):
        raise RuntimeError("TRAIN_EXEC_ROUTER_AUTHORITY_MISSING_OR_STALE")


def _execution_readback(execution_id: str) -> dict:
    return call(
        "select coalesce((select jsonb_build_object('execution_id',execution_id,'status',status,'lease_owner',lease_owner,'lease_fence',lease_fence,'lease_expires_at',lease_expires_at) from public.lf_operation_execution where execution_id=:'exec'),'{}'::jsonb);",
        exec=execution_id,
    )


def _effect_readback(execution_id: str, effect_scope: str) -> dict:
    return call(
        "select coalesce((select jsonb_build_object('state',state,'dispatch_key',dispatch_key,'effect_request_sha256',effect_request_sha256,'receipt',receipt) from public.lf_operation_effect_guard where execution_id=:'exec' and effect_scope=:'scope'),'{}'::jsonb);",
        exec=execution_id, scope=effect_scope,
    )


def _ledger_readback(version: str) -> dict:
    return call(
        "select coalesce((select jsonb_build_object('version',version,'name',name,'created_by',created_by,"
        "'source_sha256',encode(extensions.digest(convert_to(array_to_string(statements,''),'UTF8'),'sha256'),'hex'))"
        " from supabase_migrations.schema_migrations where version=:'v'),'{}'::jsonb);",
        v=version,
    )


def _step_status(execution_id: str, step_id: str) -> str | None:
    row = call(
        "select coalesce((select jsonb_build_object('status',status) from public.lf_operation_execution_steps where execution_id=:'exec' and step_id=:'step'),'{}'::jsonb);",
        exec=execution_id, step=step_id,
    )
    return row.get("status")


def _record_step_if_needed(ids: dict, step: str, evidence: dict) -> dict:
    status = _step_status(ids["execution_id"], step)
    if status == CLEAN:
        return {"outcome": "REPLAY_STEP_ALREADY_CLEAN", "status": CLEAN}
    if status not in (None, ""):
        raise RuntimeError(f"TRAIN_EXEC_EXISTING_STEP_NOT_CLEAN:{step}:{status}")
    return record_step(ids, step, evidence)


def begin(ctx: dict) -> dict:
    validate_context(ctx)
    ids = identity(ctx["pr"], ctx["version"], ctx["run_id"])
    manifest = {"producer": "lf-migration-merge-train", "train_run_id": ctx["run_id"],
                "pr": int(ctx["pr"]), "head_sha": ctx["head_sha"]}
    res = call(
        "select public.fn_lf_operation_reserve_execution_v1(:'exec', 'ACTUALIZACION_DB_LF', 'MIGRATION',"
        " :'target', :'idem', :'reqsha', :'actor', :'repo', :'path', (:'manifest')::jsonb);",
        exec=ids["execution_id"], target=f"{ctx['version']}_{ctx['name']}",
        idem=f"gitblob:{ctx['source_blob']}", reqsha=ctx["source_sha256"], actor=ids["actor"],
        repo=ctx["repo"], path=ctx["path"], manifest=json.dumps(manifest, sort_keys=True),
    )
    if res.get("status") == "COMPLETED":
        raise RuntimeError("TRAIN_EXEC_ALREADY_COMPLETED_NEW_MERGE_FORBIDDEN")
    if res.get("status") != "IN_PROGRESS":
        raise RuntimeError(f"TRAIN_EXEC_RESERVE_FAILED:{json.dumps(res, sort_keys=True)[:600]}")

    ids["execution_id"] = str(res["execution_id"])
    _require_router_authority(ids["execution_id"])
    existing_effect = _effect_readback(ids["execution_id"], ids["effect_scope"])
    if existing_effect.get("dispatch_key"):
        ids["dispatch_key"] = str(existing_effect["dispatch_key"])

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
    _record_step_if_needed(ids, "preflight", preflight_evidence(ctx, capability))

    effect = call(
        "select public.fn_lf_operation_reserve_effect_v1(:'exec', :'owner', :fence, :'scope', :'sha', :'dispatch', :'actor');",
        exec=ids["execution_id"], owner=ids["lease_owner"], fence=ids["lease_fence"],
        scope=ids["effect_scope"], sha=ctx["source_sha256"], dispatch=ids["dispatch_key"], actor=ids["actor"],
    )
    result = effect.get("result")
    if result == "EFFECT_RESERVED_NEW":
        return {"context": ctx, "ids": ids, "result": "TRAIN_EXECUTION_READY_TO_APPLY",
                "apply_required": True}

    if result == "REPLAY_SUCCEEDED_EFFECT":
        receipt = (effect.get("receipt") or {}).get("apply_receipt") or {}
        if not receipt:
            raise RuntimeError("TRAIN_EXEC_RESUME_SUCCEEDED_EFFECT_RECEIPT_MISSING")
        ledger = _ledger_readback(ctx["version"])
        if (ledger.get("version") != ctx["version"] or ledger.get("name") != ctx["name"]
                or ledger.get("source_sha256") != ctx["source_sha256"]
                or receipt.get("ledger_version") != ctx["version"]
                or receipt.get("ledger_name") != ctx["name"]):
            raise RuntimeError("TRAIN_EXEC_RESUME_SUCCEEDED_LEDGER_OR_RECEIPT_MISMATCH")
        _record_step_if_needed(ids, "patch", patch_evidence(
            ctx, ids, {"route": "RESUME_SUCCEEDED_EFFECT"}, receipt))
        return {"context": ctx, "ids": ids, "result": "TRAIN_EXECUTION_PATCH_RECORDED",
                "apply_required": False, "resume": "EFFECT_ALREADY_SUCCEEDED"}

    if result == "RECONCILIATION_REQUIRED":
        ledger = _ledger_readback(ctx["version"])
        if not ledger:
            raise RuntimeError("TRAIN_EXEC_RESUME_RESERVED_WITHOUT_LEDGER_UNRESOLVED_NO_REPLAY")
        if (ledger.get("version") != ctx["version"] or ledger.get("name") != ctx["name"]
                or ledger.get("source_sha256") != ctx["source_sha256"]):
            raise RuntimeError("TRAIN_EXEC_RESUME_LEDGER_EXACT_SOURCE_MISMATCH")
        receipt = {
            "schema_version": "lf-migration-exact-apply/v1",
            "status": "PASS",
            "code": "RESUME_RECONCILED_FROM_EXACT_LEDGER",
            "executor": ledger.get("created_by") or "UNKNOWN",
            "fallback_used": False,
            "migration_version": ctx["version"],
            "migration_name": ctx["name"],
            "ledger_version": ctx["version"],
            "ledger_name": ctx["name"],
        }
        mark_receipt = {"apply_receipt": receipt, "train_run_id": ctx["run_id"],
                        "resume_reconciled": True}
        call(
            "select public.fn_lf_operation_mark_effect_succeeded_v1(:'exec', :'owner', :fence, :'scope', (:'receipt')::jsonb, :'actor');",
            exec=ids["execution_id"], owner=ids["lease_owner"], fence=ids["lease_fence"],
            scope=ids["effect_scope"], receipt=json.dumps(mark_receipt, sort_keys=True), actor=ids["actor"],
        )
        _record_step_if_needed(ids, "patch", patch_evidence(
            ctx, ids, {"route": "RESUME_LEDGER_RECONCILIATION"}, receipt))
        return {"context": ctx, "ids": ids, "result": "TRAIN_EXECUTION_PATCH_RECORDED",
                "apply_required": False, "resume": "LEDGER_EFFECT_RECONCILED"}

    raise RuntimeError(f"TRAIN_EXEC_EFFECT_NOT_RESUMABLE:{json.dumps(effect, sort_keys=True)[:600]}")


def commit(state: dict, decision: dict, apply_receipt: dict) -> dict:
    ctx, ids = state["context"], state["ids"]
    _require_router_authority(ids["execution_id"])
    if (state.get("result") != "TRAIN_EXECUTION_READY_TO_APPLY"
            or state.get("apply_required") is not True
            or apply_receipt.get("status") != "PASS"
            or apply_receipt.get("ledger_version") != ctx["version"]
            or apply_receipt.get("ledger_name") != ctx["name"]):
        raise RuntimeError("TRAIN_EXEC_COMMIT_APPLY_RECEIPT_OR_STATE_INVALID")
    ledger = _ledger_readback(ctx["version"])
    if (ledger.get("version") != ctx["version"]
            or ledger.get("name") != ctx["name"]
            or ledger.get("source_sha256") != ctx["source_sha256"]):
        raise RuntimeError("TRAIN_EXEC_COMMIT_EXACT_LEDGER_UNVERIFIED")
    receipt = {"apply_receipt": apply_receipt, "train_run_id": ctx["run_id"]}
    call(
        "select public.fn_lf_operation_mark_effect_succeeded_v1(:'exec', :'owner', :fence, :'scope', (:'receipt')::jsonb, :'actor');",
        exec=ids["execution_id"], owner=ids["lease_owner"], fence=ids["lease_fence"],
        scope=ids["effect_scope"], receipt=json.dumps(receipt, sort_keys=True), actor=ids["actor"],
    )
    _record_step_if_needed(ids, "patch", patch_evidence(ctx, ids, decision, apply_receipt))
    return {**state, "result": "TRAIN_EXECUTION_PATCH_RECORDED"}


def close(state: dict, merge_sha: str, parity_status: str) -> dict:
    ctx, ids = state["context"], state["ids"]
    if (state.get("result") != "TRAIN_EXECUTION_PATCH_RECORDED"
            or SHA1_RE.fullmatch(merge_sha or "") is None
            or parity_status != "PASS"):
        raise RuntimeError("TRAIN_EXEC_CLOSE_STATE_MERGE_OR_PARITY_INVALID")
    _require_router_authority(ids["execution_id"])
    ledger = _ledger_readback(ctx["version"])
    if (ledger.get("version") != ctx["version"]
            or ledger.get("name") != ctx["name"]
            or ledger.get("source_sha256") != ctx["source_sha256"]):
        raise RuntimeError("TRAIN_EXEC_CLOSE_EXACT_LEDGER_UNVERIFIED")
    effect = _effect_readback(ids["execution_id"], ids["effect_scope"])
    apply_receipt = (effect.get("receipt") or {}).get("apply_receipt") or {}
    if (effect.get("state") != "SUCCEEDED"
            or effect.get("effect_request_sha256") != ctx["source_sha256"]
            or effect.get("dispatch_key") != ids["dispatch_key"]
            or apply_receipt.get("ledger_version") != ctx["version"]
            or apply_receipt.get("ledger_name") != ctx["name"]):
        raise RuntimeError("TRAIN_EXEC_CLOSE_EFFECT_RECEIPT_UNVERIFIED")
    _record_step_if_needed(ids, "verify", verify_evidence(ctx, ids, ledger, merge_sha, parity_status))
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
    assert ids["lease_owner"] == "lf-migration-train-pr2350-20261013010000"
    assert ids["dispatch_key"] == "lf-migration-train-pr2350-20261013010000"
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
    for key in ("pr", "version", "name", "path", "source-blob", "source-sha256",
                "repo", "head-sha", "persisted-head-sha", "run-id"):
        b.add_argument(f"--{key}", required=True)
    b.add_argument("--state", required=True)
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
    if args.cmd == "begin":
        ctx = {key.replace("-", "_"): getattr(args, key.replace("-", "_"))
               for key in ("pr", "version", "name", "path", "source-blob", "source-sha256",
                           "repo", "head-sha", "persisted-head-sha", "run-id")}
        state = begin(ctx)
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

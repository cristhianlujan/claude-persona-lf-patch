#!/usr/bin/env python3
"""Train-managed ACTUALIZACION_DB_LF execution (option C).

The LF Migration Merge Train opens, records and closes the canonical Router
execution of every migration it applies, using only evidence it produced:

  begin   (pre-apply, fatal)  reserve execution -> lease -> preflight step ->
                              reserve effect MIGRATION:<version>
  commit  (post-apply)        mark effect SUCCEEDED with the apply receipt ->
                              patch step
  close   (post-merge)        verify step -> lf_close_db_operation_execution_v1
                              -> typed receipt (LF_MIGRATION_TRAIN_RECEIPT_V1)

PASE-ATOM-F07-X01: begin/resume also capture the human authorization (label,
actor, authorized head from the triggering event), main before the Train and
the owner rule D1 (between the authorized head and the final head there may be
only the main sync and the version retimestamp). An unexpected change is fatal
before any database effect. close and abort append one typed receipt per
execution through public.lf_record_migration_train_receipt_v1.

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
import time
from urllib.parse import quote

try:
    from pase_f09_015_telemetry import (
        CANONICAL_STEPS, MAX_ENVELOPE_BYTES, StageMetrics, make_envelope,
        record_failure_once, sanitize_message, serialize_envelope, utc_now,
    )
except ImportError:  # The Train copies this trusted recorder by itself.
    import importlib.util
    helper = Path.cwd() / "sandbox/lf_contract_gate_test/db_write_transport/pase_f09_015_telemetry.py"
    spec = importlib.util.spec_from_file_location("pase_f09_015_telemetry", helper)
    if spec is None or spec.loader is None:
        raise RuntimeError("PASE_F09_015_TELEMETRY_HELPER_MISSING")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    CANONICAL_STEPS, MAX_ENVELOPE_BYTES, StageMetrics = module.CANONICAL_STEPS, module.MAX_ENVELOPE_BYTES, module.StageMetrics
    make_envelope, record_failure_once = module.make_envelope, module.record_failure_once
    sanitize_message, serialize_envelope, utc_now = module.sanitize_message, module.serialize_envelope, module.utc_now

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
MIGRATION_PATH_RE = re.compile(r"^supabase/migrations/(\d{14})_([A-Za-z0-9][A-Za-z0-9_]*)\.sql$")
TRAIN_LABEL = "ready-to-merge"
DIFF_NO_CHANGE = "NO_CHANGE"
DIFF_SYNC_ONLY = "SYNC_AND_RETIMESTAMP_ONLY"
DIFF_UNEXPECTED = "UNEXPECTED_CHANGES"
DIFF_NOT_EVALUATED = "NOT_EVALUATED"

SQLSTATE_VALUE_RE = re.compile(r"^[0-9A-Z]{5}$")


def normalized_sqlstate(value: object) -> str:
    candidate = sanitize_message(value, 8) or ""
    return candidate if SQLSTATE_VALUE_RE.fullmatch(candidate) else "NOT_OBSERVED"


def failure_receipt_summary(failure: dict, fallback_summary: str) -> str:
    sqlstate = normalized_sqlstate(failure.get("sqlstate"))
    message = sanitize_message(failure.get("message"), 700) or "NOT_OBSERVED"
    summary = f"SQLSTATE={sqlstate}; message={message}"
    if fallback_summary and message == "NOT_OBSERVED":
        summary += f"; summary={sanitize_message(fallback_summary, 200) or 'NOT_OBSERVED'}"
    return summary[:1000]

_TELEMETRY_STAGE = None
_TELEMETRY_STARTED_AT = None
_TELEMETRY_METRICS = StageMetrics()


# ------------------------------------------------- provenance and rule D1


def git(*args: str, cwd: str | None = None) -> subprocess.CompletedProcess:
    return subprocess.run(["git", *args], cwd=cwd, text=True, capture_output=True, timeout=120, check=False)


def git_out(*args: str, cwd: str | None = None) -> str | None:
    proc = git(*args, cwd=cwd)
    return proc.stdout.strip() if proc.returncode == 0 else None


def ensure_commit(sha: str, cwd: str | None = None) -> bool:
    if git("cat-file", "-e", f"{sha}^{{commit}}", cwd=cwd).returncode == 0:
        return True
    git("fetch", "--no-tags", "--quiet", "origin", sha, cwd=cwd)
    return git("cat-file", "-e", f"{sha}^{{commit}}", cwd=cwd).returncode == 0


def classify_head_diff(authorized: str, main: str, final: str, target_path: str,
                       source_blob: str, cwd: str | None = None) -> dict:
    """Owner rule D1: final may differ from authorized only by the main sync
    (recomputed independently with merge-tree) and the version retimestamp
    (same blob, same migration name, new path = target path)."""
    if authorized == final:
        return {"class": DIFF_NO_CHANGE, "unexpected_paths": []}
    for sha in (authorized, main, final):
        if not SHA1_RE.fullmatch(sha or "") or not ensure_commit(sha, cwd):
            return {"class": DIFF_NOT_EVALUATED, "unexpected_paths": [], "note": f"commit unavailable: {sha}"}
    merged = git("merge-tree", "--write-tree", authorized, main, cwd=cwd)
    expected_tree = merged.stdout.splitlines()[0].strip() if merged.returncode == 0 and merged.stdout else ""
    if not SHA1_RE.fullmatch(expected_tree):
        return {"class": DIFF_NOT_EVALUATED, "unexpected_paths": [], "note": f"merge-tree rc={merged.returncode}"}
    final_tree = git_out("rev-parse", f"{final}^{{tree}}", cwd=cwd) or ""
    if final_tree == expected_tree:
        return {"class": DIFF_SYNC_ONLY, "unexpected_paths": []}
    raw = git_out("diff-tree", "-r", "--no-renames", "--raw", expected_tree, final_tree, cwd=cwd)
    if raw is None:
        return {"class": DIFF_NOT_EVALUATED, "unexpected_paths": [], "note": "diff-tree failed"}
    entries = []
    for line in raw.splitlines():
        meta, _, path = line.partition("\t")
        parts = meta.split()
        if len(parts) >= 5:
            entries.append({"old": parts[2], "new": parts[3], "op": parts[4][:1], "path": path})
    target = MIGRATION_PATH_RE.fullmatch(target_path or "")
    deleted = [x for x in entries if x["op"] == "D"]
    added = [x for x in entries if x["op"] == "A"]
    if (target and len(entries) == 2 and len(deleted) == 1 and len(added) == 1
            and added[0]["path"] == target_path and added[0]["new"] == source_blob
            and deleted[0]["old"] == source_blob):
        old = MIGRATION_PATH_RE.fullmatch(deleted[0]["path"])
        if old and old.group(2) == target.group(2) and old.group(1) != target.group(1):
            return {"class": DIFF_SYNC_ONLY, "unexpected_paths": []}
    return {"class": DIFF_UNEXPECTED, "unexpected_paths": sorted({x["path"] for x in entries})[:50]}


def read_event() -> dict:
    path = os.environ.get("GITHUB_EVENT_PATH", "").strip()
    if not path or not Path(path).is_file():
        return {}
    try:
        return json.loads(Path(path).read_text())
    except (OSError, ValueError):
        return {}


def authorization_from_env() -> dict:
    event = read_event()
    return {
        "label": (event.get("label") or {}).get("name"),
        "authorized_by": (event.get("sender") or {}).get("login") or os.environ.get("GITHUB_ACTOR"),
        "github_actor": os.environ.get("GITHUB_ACTOR"),
        "triggering_actor": os.environ.get("GITHUB_TRIGGERING_ACTOR"),
        "run_attempt": os.environ.get("GITHUB_RUN_ATTEMPT"),
        "authorized_head": ((event.get("pull_request") or {}).get("head") or {}).get("sha"),
    }


def capture_provenance(ctx: dict, cwd: str | None = None) -> dict:
    """Taken at begin/resume, inside the Train job, before any database effect."""
    prov = authorization_from_env()
    prov["final_head"] = ctx["head_sha"]
    prov["main_before"] = git_out("rev-parse", "refs/remotes/origin/main", cwd=cwd)
    if not SHA1_RE.fullmatch(prov.get("authorized_head") or ""):
        prov["diff_class"], prov["diff_unexpected_paths"] = DIFF_NOT_EVALUATED, []
        prov["diff_note"] = "authorized head unavailable from triggering event"
    elif not SHA1_RE.fullmatch(prov.get("main_before") or ""):
        prov["diff_class"], prov["diff_unexpected_paths"] = DIFF_NOT_EVALUATED, []
        prov["diff_note"] = "main before unavailable"
    else:
        diff = classify_head_diff(prov["authorized_head"], prov["main_before"], ctx["head_sha"],
                                  ctx["path"], ctx["source_blob"], cwd=cwd)
        prov["diff_class"] = diff["class"]
        prov["diff_unexpected_paths"] = diff["unexpected_paths"]
        if diff.get("note"):
            prov["diff_note"] = diff["note"]
    return {k: v for k, v in prov.items() if v not in (None, "")}


def enforce_d1(prov: dict) -> None:
    if prov.get("label") not in (None, TRAIN_LABEL):
        raise RuntimeError(f"TRAIN_EXEC_LABEL_NOT_TRAIN:{prov.get('label')}")
    if prov.get("diff_class") == DIFF_UNEXPECTED:
        raise RuntimeError("TRAIN_EXEC_D1_UNEXPECTED_CHANGES:" + ",".join(prov.get("diff_unexpected_paths", []))[:600])


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
        "pase_f09_015_metrics": apply_receipt.get("pase_f09_015_metrics", "NOT_OBSERVED"),
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
            "dry_run_exit_code": apply_receipt.get("dry_run_exit_code"),
            "dry_run_tail": apply_receipt.get("dry_run_tail", "NOT_OBSERVED"),
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
    started = time.perf_counter_ns()
    argv = ["psql", db_url(), "-X", "-At", "-v", "ON_ERROR_STOP=1"]
    for key, value in params.items():
        argv += ["-v", f"{key}={value}"]
    argv += ["-f", "-"]
    proc = subprocess.run(argv, input=sql, text=True, capture_output=True, timeout=120, check=False)
    elapsed_ms = (time.perf_counter_ns() - started) / 1_000_000
    if _TELEMETRY_STAGE:
        _TELEMETRY_METRICS.queries.add(elapsed_ms, len((sql + json.dumps(params, sort_keys=True)).encode("utf-8"))
                                       + len(proc.stdout.encode("utf-8")) + len(proc.stderr.encode("utf-8")))
    if proc.returncode != 0:
        tail = " | ".join(proc.stderr.strip().splitlines()[-4:])
        raise RuntimeError(f"TRAIN_EXEC_SQL_FAILED:{tail}")
    out = proc.stdout.strip().splitlines()
    return json.loads(out[-1]) if out else {}


def record_step(ids: dict, step: str, evidence: dict) -> dict:
    global _TELEMETRY_METRICS
    prior = call(
        "select coalesce((select jsonb_build_object('status', status)"
        " from public.lf_operation_execution_steps"
        " where execution_id = :'exec' and step_id = :'step'"
        " order by step_order limit 1), '{}'::jsonb);",
        exec=ids["execution_id"], step=step,
    )
    if prior.get("status") == CLEAN:
        return {"outcome": "STEP_ALREADY_PASS_CLEAN", "status": CLEAN, "step_id": step}
    if step not in CANONICAL_STEPS:
        raise RuntimeError(f"PASE_F09_015_UNKNOWN_STEP:{step}")
    apply_metrics = evidence.get("pase_f09_015_metrics") or {}
    started_at = (apply_metrics.get("started_at") if step == "patch" else None) or _TELEMETRY_STARTED_AT or utc_now()
    finished_at = utc_now()
    stage_metrics = StageMetrics()
    for family in ("queries", "transport"):
        values = apply_metrics.get(family) or {}
        count, duration, byte_count = values.get("count"), values.get("duration_ms"), values.get("bytes")
        if isinstance(count, (int, float)) and isinstance(duration, (int, float)) and isinstance(byte_count, (int, float)):
            counter = getattr(stage_metrics, family)
            counter.add(duration, byte_count)
            counter.count += max(0, int(count) - 1)
        source = getattr(_TELEMETRY_METRICS, family)
        counter = getattr(stage_metrics, family)
        counter.count += source.count
        counter.duration_ms += source.duration_ms
        counter.bytes += source.bytes
    envelope = make_envelope(
        step=step, started_at=started_at, finished_at=finished_at,
        execution_id=ids["execution_id"], control_id=ids.get("effect_scope", "NOT_OBSERVED"),
        input_value=evidence.get("exact_target") or evidence.get("target_binding") or ids,
        result_value=evidence.get("write_receipt") or evidence.get("db_write_transport_readback")
                     or evidence.get("failure") or evidence.get("preflight_pass") or evidence.get("verified"),
        metrics=stage_metrics,
    )
    if evidence.get("failure"):
        envelope["failure"] = evidence["failure"]
        envelope["evidence_locator"] = evidence["failure"].get("evidence_locator", "NOT_OBSERVED")
    evidence = dict(evidence)
    evidence["pase_f09_015_telemetry_v1"] = json.loads(serialize_envelope(envelope, MAX_ENVELOPE_BYTES))
    res = call(
        "select public.lf_record_db_operation_step_v1(:'exec', :'step', :'ref', (:'payload')::jsonb, :'actor');",
        exec=ids["execution_id"], step=step, ref=f"{ids['actor']}:{step}",
        payload=json.dumps(evidence, sort_keys=True), actor=ids["actor"],
    )
    allowed_statuses = (CLEAN, "BLOCKED_BY_ENFORCEMENT", "RETURN_TO_WORKER") if evidence.get("blocking_codes") else (CLEAN, None)
    if res.get("outcome") != "STEP_RECORDED" or res.get("status") not in allowed_statuses:
        raise RuntimeError(f"TRAIN_EXEC_STEP_NOT_CLEAN:{step}:{json.dumps(res, sort_keys=True)[:600]}")
    _TELEMETRY_METRICS = StageMetrics()
    return res


def record_receipt(state: dict) -> dict:
    """Append the typed terminal receipt; the SQL side builds it from canonical state."""
    ctx, ids = state["context"], state["ids"]
    prov = dict(state.get("provenance") or {})
    if not prov:
        prov = authorization_from_env()
        prov.update({"final_head": ctx["head_sha"], "diff_class": DIFF_NOT_EVALUATED,
                     "diff_unexpected_paths": [], "diff_note": "provenance not captured at begin"})
        prov = {k: v for k, v in prov.items() if v not in (None, "")}
    # close runs on a checkout of the exact pre-Train main: read it back.
    observed_main = git_out("rev-parse", "HEAD")
    if not prov.get("main_before") and SHA1_RE.fullmatch(observed_main or ""):
        prov["main_before"] = observed_main
    res = call(
        "select public.lf_record_migration_train_receipt_v1(:'exec', (:'prov')::jsonb, :'actor');",
        exec=ids["execution_id"], prov=json.dumps(prov, sort_keys=True), actor=ids["actor"],
    )
    if res.get("outcome") not in ("TRAIN_RECEIPT_RECORDED", "TRAIN_RECEIPT_REPLAY"):
        raise RuntimeError(f"TRAIN_EXEC_RECEIPT_FAILED:{json.dumps(res, sort_keys=True)[:600]}")
    return res


def begin(ctx: dict) -> dict:
    global _TELEMETRY_STAGE, _TELEMETRY_STARTED_AT, _TELEMETRY_METRICS
    _TELEMETRY_STAGE = "preflight"
    _TELEMETRY_STARTED_AT = utc_now()
    _TELEMETRY_METRICS = StageMetrics()
    validate_context(ctx)
    provenance = capture_provenance(ctx)
    enforce_d1(provenance)
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
    _TELEMETRY_STAGE = None
    effect = call(
        "select public.fn_lf_operation_reserve_effect_v1(:'exec', :'owner', :fence, :'scope', :'sha', :'dispatch', :'actor');",
        exec=ids["execution_id"], owner=ids["lease_owner"], fence=ids["lease_fence"],
        scope=ids["effect_scope"], sha=ctx["source_sha256"], dispatch=ids["dispatch_key"], actor=ids["actor"],
    )
    if effect.get("dispatch_permitted") is not True:
        raise RuntimeError(f"TRAIN_EXEC_EFFECT_NOT_PERMITTED:{json.dumps(effect, sort_keys=True)[:600]}")
    return {"context": ctx, "ids": ids, "result": "TRAIN_EXECUTION_READY_TO_APPLY", "effect_state": "RESERVED",
            "provenance": provenance, "patch_started_at": utc_now()}


def resume(ctx: dict) -> dict:
    """Resume one expired open execution only when its exact migration is in the ledger."""
    validate_context(ctx)
    provenance = capture_provenance(ctx)
    enforce_d1(provenance)
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
        "provenance": provenance,
    }


def abort(state: dict, run_id: str, failed_step: str, error_summary: str,
          failure: dict | None = None) -> dict:
    """Record pre-apply failure; SQL independently rejects any version in the ledger."""
    global _TELEMETRY_STAGE, _TELEMETRY_STARTED_AT, _TELEMETRY_METRICS
    ctx, ids = state["context"], state["ids"]
    original_error = failure or {"code": "TRAIN_STEP_FAILED", "sqlstate": "NOT_OBSERVED",
                                 "message": error_summary, "evidence_locator": "NOT_OBSERVED"}
    rejected = {}
    if failed_step == "Apply exact version and ledger readback":
        _TELEMETRY_STAGE = "patch"
        _TELEMETRY_STARTED_AT = state.get("patch_started_at") or utc_now()
        _TELEMETRY_METRICS = StageMetrics()
        safe_error = {"code": sanitize_message(original_error.get("code"), 96) or "TRAIN_STEP_FAILED",
                      "sqlstate": normalized_sqlstate(original_error.get("sqlstate")),
                      "message": sanitize_message(original_error.get("message")) or "NOT_OBSERVED",
                      "evidence_locator": sanitize_message(original_error.get("evidence_locator"), 256) or
                                          f"github-run:{run_id}:step:{failed_step}"}
        failed_evidence = patch_evidence(ctx, ids, {"route": "MIGRATION_VIA_MERGE_TRAIN"}, {
            "status": "FAILURE", "executor": "lf-migration-merge-train", "code": safe_error["code"]})
        failed_evidence.update({"blocking_codes": [safe_error["code"]], "failure": safe_error})
        if original_error.get("pase_f09_015_metrics"):
            failed_evidence["pase_f09_015_metrics"] = original_error["pase_f09_015_metrics"]
        outcome = record_failure_once(
            lambda _error: record_step(ids, "patch", failed_evidence),
            lambda receipt: rejected.update(receipt), safe_error,
        )
        _TELEMETRY_STAGE = None
    evidence = {
        "train_run_id": str(run_id),
        "failed_step": " ".join(str(failed_step).split())[:160],
        "error_summary": failure_receipt_summary(original_error, error_summary),
        "original_error": {"code": sanitize_message(original_error.get("code"), 96) or "NOT_OBSERVED",
                           "sqlstate": sanitize_message(original_error.get("sqlstate"), 32) or "NOT_OBSERVED",
                           "message": sanitize_message(original_error.get("message")) or "NOT_OBSERVED"},
        "failure_row_outcome": outcome.get("outcome") if failed_step == "Apply exact version and ledger readback" else "NOT_OBSERVED",
        "failure_row_rejection": rejected or "NOT_OBSERVED",
        "secrets_included": False,
    }
    result = call(
        "select public.lf_fail_db_operation_execution_v1(:'exec', :'owner', :fence, (:'ev')::jsonb, :'actor');",
        exec=ids["execution_id"], owner=ids["lease_owner"], fence=ids["lease_fence"],
        ev=json.dumps(evidence, sort_keys=True), actor=ids["actor"],
    )
    if result.get("result") not in ("EXECUTION_BLOCKED_NO_LEDGER_EFFECT", "REPLAY_ALREADY_FAILED"):
        raise RuntimeError(f"TRAIN_EXEC_ABORT_FAILED:{json.dumps(result, sort_keys=True)}")
    out = {**state, "result": "TRAIN_EXECUTION_ABORTED", "abort": result}
    try:
        out["receipt"] = record_receipt(state)
    except Exception as exc:  # the abort itself already succeeded; never mask it
        out["receipt_error"] = str(exc)[:600]
        print(f"WARN_TRAIN_EXEC_RECEIPT_NOT_RECORDED:{out['receipt_error']}", file=sys.stderr)
    return out


def commit(state: dict, decision: dict, apply_receipt: dict) -> dict:
    global _TELEMETRY_STAGE, _TELEMETRY_STARTED_AT, _TELEMETRY_METRICS
    ctx, ids = state["context"], state["ids"]
    _TELEMETRY_STAGE = "patch"
    _TELEMETRY_STARTED_AT = state.get("patch_started_at") or utc_now()
    _TELEMETRY_METRICS = StageMetrics()
    receipt = {"apply_receipt": apply_receipt, "train_run_id": ctx["run_id"]}
    if state.get("effect_state") != "SUCCEEDED":
        call(
            "select public.fn_lf_operation_mark_effect_succeeded_v1(:'exec', :'owner', :fence, :'scope', (:'receipt')::jsonb, :'actor');",
            exec=ids["execution_id"], owner=ids["lease_owner"], fence=ids["lease_fence"],
            scope=ids["effect_scope"], receipt=json.dumps(receipt, sort_keys=True), actor=ids["actor"],
        )
        state["effect_state"] = "SUCCEEDED"
    record_step(ids, "patch", patch_evidence(ctx, ids, decision, apply_receipt))
    _TELEMETRY_STAGE = None
    return {**state, "result": "TRAIN_EXECUTION_PATCH_RECORDED"}


def close(state: dict, merge_sha: str, parity_status: str) -> dict:
    global _TELEMETRY_STAGE, _TELEMETRY_STARTED_AT, _TELEMETRY_METRICS
    ctx, ids = state["context"], state["ids"]
    _TELEMETRY_STAGE = "verify"
    _TELEMETRY_STARTED_AT = utc_now()
    _TELEMETRY_METRICS = StageMetrics()
    ledger = call(
        "select coalesce((select jsonb_build_object('version', version, 'name', name)"
        " from supabase_migrations.schema_migrations where version = :'v'), '{}'::jsonb);",
        v=ctx["version"],
    )
    if ledger.get("version") != ctx["version"] or ledger.get("name") != ctx["name"]:
        raise RuntimeError(f"TRAIN_EXEC_LEDGER_READBACK_MISMATCH:{json.dumps(ledger)}")
    record_step(ids, "verify", verify_evidence(ctx, ids, ledger, merge_sha, parity_status))
    _TELEMETRY_STAGE = None
    evidence = {"train_run_id": ctx["run_id"], "pr": int(ctx["pr"]), "merge_sha": merge_sha,
                "ledger": ledger, "parity": parity_status}
    res = call(
        "select public.lf_close_db_operation_execution_v1(:'exec', :'owner', :fence, (:'ev')::jsonb, :'actor');",
        exec=ids["execution_id"], owner=ids["lease_owner"], fence=ids["lease_fence"],
        ev=json.dumps(evidence, sort_keys=True), actor=ids["actor"],
    )
    if res.get("result") not in ("EXECUTION_COMPLETED", "REPLAY_ALREADY_COMPLETED"):
        raise RuntimeError(f"TRAIN_EXEC_CLOSE_FAILED:{json.dumps(res)}")
    done = {**state, "result": "TRAIN_EXECUTION_COMPLETED", "close": res}
    done["receipt"] = record_receipt(done)
    return done


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
        failure = None
        apply_receipt_path = Path(".lf_train/exact-apply-receipt.json")
        if apply_receipt_path.is_file():
            try:
                failure = json.loads(apply_receipt_path.read_text()).get("failure")
                if failure is not None:
                    failure["pase_f09_015_metrics"] = json.loads(apply_receipt_path.read_text()).get("pase_f09_015_metrics")
            except (OSError, ValueError):
                failure = None
        state = abort(state, args.run_id, args.failed_step, args.error_summary, failure)
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

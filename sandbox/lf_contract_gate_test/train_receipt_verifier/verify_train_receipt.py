#!/usr/bin/env python3
"""Fail-closed read-only verifier for LF_MIGRATION_TRAIN_RECEIPT_V1.

Live mode reads the receipt, Train execution, steps and migration ledger in an
explicit PostgreSQL READ ONLY transaction, then compares the receipt's merge
commit and authorized source head with GitHub's merged pull-request record.
Fixture mode is exercised by test_verify_train_receipt.py.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from datetime import datetime
import urllib.error
import urllib.request
from typing import Any

EVENT_TYPE = "MIGRATION_TRAIN_RECEIPT_RECORDED"
RECEIPT_SCHEMA = "LF_MIGRATION_TRAIN_RECEIPT_V1"
SHA1 = re.compile(r"^[0-9a-f]{40}$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")
EXECUTION_ID = re.compile(r"^EXEC-DB-TRAIN-PR([0-9]+)-([0-9]{14})-R([0-9]+)$")
REQUIRED_STEPS = ("preflight", "patch", "verify")


class ReceiptError(ValueError):
    pass


def _obj(value: Any, path: str, errors: list[str]) -> dict[str, Any]:
    if not isinstance(value, dict):
        errors.append(f"{path}:MISSING_OR_NOT_OBJECT")
        return {}
    return value


def _required(obj: dict[str, Any], key: str, path: str, errors: list[str]) -> Any:
    value = obj.get(key)
    if value is None or value == "":
        errors.append(f"{path}.{key}:MISSING")
    return value


def _required_timestamp(obj: dict[str, Any], key: str, path: str, errors: list[str]) -> datetime | None:
    value = _required(obj, key, path, errors)
    if value is None:
        return None
    try:
        parsed = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
        if parsed.tzinfo is None:
            raise ValueError("timezone missing")
        return parsed
    except (TypeError, ValueError):
        errors.append(f"{path}.{key}:INVALID_UTC_TIMESTAMP")
        return None


def verify_snapshot(snapshot: dict[str, Any]) -> dict[str, Any]:
    """Validate a DB/GitHub snapshot. Return PASS, BLOCKED, or FAIL."""
    errors: list[str] = []
    notes: list[str] = []
    event = _obj(snapshot.get("event"), "event", errors)
    execution = _obj(snapshot.get("execution"), "execution", errors)
    payload = _obj(event.get("payload"), "event.payload", errors)
    receipt = _obj(payload.get("receipt"), "event.payload.receipt", errors)

    if event.get("evento_tipo") != EVENT_TYPE:
        errors.append("event.evento_tipo:NOT_TRAIN_RECEIPT")
    if payload.get("receipt_schema") != RECEIPT_SCHEMA or receipt.get("schema_version") != RECEIPT_SCHEMA:
        errors.append("receipt.schema:INVALID")
    if payload.get("evidence_schema_version") != "operational-event/v2":
        errors.append("event.evidence_schema_version:INVALID")
    if payload.get("acceptance_declared") is not False:
        errors.append("event.payload.acceptance_declared:NOT_FALSE")

    execution_id = _required(receipt, "execution_id", "receipt", errors)
    if execution_id != event.get("entidad_codigo") or execution_id != execution.get("execution_id"):
        errors.append("execution_id:EVENT_OR_EXECUTION_MISMATCH")
    match = EXECUTION_ID.fullmatch(str(execution_id or ""))
    if not match:
        errors.append("execution_id:INVALID_TRAIN_ID")

    terminal = receipt.get("terminal_status")
    if terminal not in ("COMPLETED", "BLOCKED"):
        errors.append("terminal_status:NOT_TERMINAL")
    if execution.get("status") != terminal:
        errors.append("terminal_status:EXECUTION_MISMATCH")
    if execution.get("operation_code") != "ACTUALIZACION_DB_LF" or execution.get("target_type") != "MIGRATION":
        errors.append("execution:NOT_TRAIN_MIGRATION")

    pr = receipt.get("pr")
    run_id = receipt.get("train_run_id")
    repo = receipt.get("repository")
    if not isinstance(pr, int) or pr <= 0:
        errors.append("receipt.pr:INVALID")
    if not isinstance(run_id, str) or not run_id.isdigit():
        errors.append("receipt.train_run_id:INVALID")
    if not isinstance(repo, str) or not re.fullmatch(r"[^/\s]+/[^/\s]+", repo):
        errors.append("receipt.repository:INVALID")
    manifest = _obj(execution.get("manifest"), "execution.manifest", errors)
    if manifest.get("pr") != pr or str(manifest.get("train_run_id")) != str(run_id):
        errors.append("receipt:PR_OR_RUN_ID_MANIFEST_MISMATCH")
    started_at = _required_timestamp(receipt, "started_at", "receipt", errors)
    if terminal == "COMPLETED":
        completed_at = _required_timestamp(receipt, "completed_at", "receipt", errors)
        if started_at is not None and completed_at is not None and completed_at < started_at:
            errors.append("receipt.completed_at:BEFORE_STARTED_AT")
    elif terminal == "BLOCKED":
        # The Train writer omits receipt.completed_at on BLOCKED receipts.
        # Its failure record carries the terminal timestamp instead.
        failure_time = _required_timestamp(
            _obj(receipt.get("failure"), "receipt.failure", errors),
            "recorded_at", "failure", errors,
        )
        if started_at is not None and failure_time is not None and failure_time < started_at:
            errors.append("receipt.failure.recorded_at:BEFORE_STARTED_AT")
    terminated_by = _required(receipt, "terminated_by", "receipt", errors)
    if run_id and terminated_by != f"LF-MIGRATION-TRAIN-RUN-{run_id}":
        errors.append("receipt.terminated_by:RUN_ID_MISMATCH")
    if match and (match.group(1) != str(pr) or match.group(3) != str(run_id)):
        errors.append("execution_id:PR_OR_RUN_ID_MISMATCH")
    if execution.get("target_repo") != repo:
        errors.append("receipt.repository:EXECUTION_MISMATCH")

    migration = _obj(receipt.get("migration"), "receipt.migration", errors)
    version = _required(migration, "version", "migration", errors)
    name = _required(migration, "name", "migration", errors)
    migration_target = _required(migration, "target_code", "migration", errors)
    path = _required(migration, "path", "migration", errors)
    for key in ("source_blob",):
        value = _required(migration, key, "migration", errors)
        if value is not None and not SHA1.fullmatch(str(value)):
            errors.append(f"migration.{key}:INVALID_SHA1")
    source_sha = _required(migration, "source_sha256", "migration", errors)
    if source_sha is not None and not SHA256.fullmatch(str(source_sha)):
        errors.append("migration.source_sha256:INVALID_SHA256")
    if match and version != match.group(2):
        errors.append("migration.version:EXECUTION_ID_MISMATCH")
    if execution.get("target_code") != f"{version}_{name}":
        errors.append("migration.target_code:EXECUTION_MISMATCH")
    if migration_target != execution.get("target_code"):
        errors.append("migration.target_code:RECEIPT_MISMATCH")
    if execution.get("target_path") != path:
        errors.append("migration.path:EXECUTION_MISMATCH")
    if execution.get("request_sha256") != source_sha:
        errors.append("migration.source_sha256:REQUEST_MISMATCH")

    human = _obj(receipt.get("human_authorization"), "receipt.human_authorization", errors)
    if human.get("label") != "ready-to-merge":
        errors.append("human_authorization.label:INVALID")
    _required(human, "authorized_by", "human_authorization", errors)
    authorized_head = _required(human, "authorized_head", "human_authorization", errors)
    if authorized_head is not None and not SHA1.fullmatch(str(authorized_head)):
        errors.append("human_authorization.authorized_head:INVALID_SHA1")

    heads = _obj(receipt.get("heads"), "receipt.heads", errors)
    for key in ("main_before", "authorized_head", "final_head", "execution_head", "persisted_head"):
        value = _required(heads, key, "heads", errors)
        if value is not None and not SHA1.fullmatch(str(value)):
            errors.append(f"heads.{key}:INVALID_SHA1")
    if heads.get("authorized_head") != authorized_head:
        errors.append("heads.authorized_head:HUMAN_AUTHORIZATION_MISMATCH")
    if heads.get("final_head") != heads.get("execution_head") or heads.get("final_head_is_execution_head") is not True:
        errors.append("heads.final_head:EXECUTION_HEAD_MISMATCH")
    if heads.get("execution_head") != manifest.get("head_sha"):
        errors.append("heads.execution_head:MANIFEST_MISMATCH")
    diff = _obj(receipt.get("diff_check"), "receipt.diff_check", errors)
    if diff.get("class") not in ("NO_CHANGE", "SYNC_AND_RETIMESTAMP_ONLY", "UNEXPECTED_CHANGES", "NOT_EVALUATED"):
        errors.append("diff_check.class:INVALID")
    if not isinstance(diff.get("unexpected_paths"), list):
        errors.append("diff_check.unexpected_paths:NOT_ARRAY")

    sha_ok = snapshot.get("receipt_sha_matches")
    if sha_ok is not True:
        errors.append("receipt_sha256:NOT_VERIFIED")

    steps = snapshot.get("steps")
    if not isinstance(steps, list):
        errors.append("steps:NOT_ARRAY")
        steps = []
    step_map: dict[str, list[dict[str, Any]]] = {}
    for step in steps:
        if isinstance(step, dict):
            step_map.setdefault(str(step.get("step_id", "")), []).append(step)

    ledger_rows = snapshot.get("ledger_rows")
    if not isinstance(ledger_rows, list):
        errors.append("ledger_rows:NOT_ARRAY")
        ledger_rows = []
    exact_ledger = [r for r in ledger_rows if isinstance(r, dict) and r.get("version") == version]
    if len(exact_ledger) > 1:
        errors.append("ledger:VERSION_DUPLICATE")

    if terminal == "BLOCKED":
        failure = _obj(receipt.get("failure"), "receipt.failure", errors)
        _required(failure, "reason", "failure", errors)
        _required(failure, "failed_step", "failure", errors)
        effect = _obj(receipt.get("effect"), "receipt.effect", errors)
        if effect.get("phase") not in ("ABANDONED", "NOT_RESERVED"):
            errors.append("blocked.effect:NOT_ABANDONED")
        if receipt.get("apply") is not None or receipt.get("merge") is not None:
            errors.append("blocked:HAS_APPLY_OR_MERGE_EFFECT")
        pr_record = snapshot.get("github_pull")
        if not isinstance(pr_record, dict):
            errors.append("github_pull:NOT_VERIFIED")
        elif pr_record.get("merged") is True:
            notes.append("PR was merged by a later Train attempt; this receipt remains BLOCKED.")
        if errors:
            return {"result": "FAIL", "execution_id": execution_id, "pr": pr, "reasons": errors, "notes": notes}
        if exact_ledger:
            notes.append("The target version is now present in the ledger; this receipt is still not PASS.")
        return {"result": "BLOCKED", "execution_id": execution_id, "pr": pr,
                "reasons": [f"Train terminal_status=BLOCKED: {failure.get('reason')}"], "notes": notes}

    # COMPLETED receipt: all three clean stages and exact canonical readbacks.
    if diff.get("class") not in ("NO_CHANGE", "SYNC_AND_RETIMESTAMP_ONLY"):
        errors.append("diff_check.class:COMPLETED_NOT_CLEAN")
    for step_id in REQUIRED_STEPS:
        rows = step_map.get(step_id, [])
        if len(rows) != 1:
            errors.append(f"steps.{step_id}:EXPECTED_ONE_FOUND_{len(rows)}")
        elif rows[0].get("status") != "PASS_CLEAN":
            errors.append(f"steps.{step_id}:NOT_PASS_CLEAN")
    for step_id in step_map:
        if step_id not in REQUIRED_STEPS:
            errors.append(f"steps.{step_id}:UNEXPECTED_STEP")

    # Cross-bind typed receipt fields to the canonical step evidence that the
    # F07-X01 writer projected into lf_eventos.
    if len(step_map.get("preflight", [])) == 1:
        preflight = step_map["preflight"][0].get("evidence_payload") or {}
        exact = preflight.get("exact_target") if isinstance(preflight, dict) else None
        source_readback = preflight.get("schema_source_readback") if isinstance(preflight, dict) else None
        if not isinstance(exact, dict):
            errors.append("preflight.exact_target:MISSING")
        else:
            expected_exact = {"migration_version": version, "migration_name": name,
                              "target_path": path, "source_blob": migration.get("source_blob"),
                              "source_sha256": source_sha, "repository": repo, "pr": pr,
                              "head_sha": heads.get("execution_head")}
            for key, expected in expected_exact.items():
                if exact.get(key) != expected:
                    errors.append(f"preflight.exact_target.{key}:RECEIPT_MISMATCH")
        if not isinstance(source_readback, dict) or source_readback.get("persisted_head_sha") != heads.get("persisted_head"):
            errors.append("preflight.schema_source_readback:HEAD_MISMATCH")

    ledger = _obj(receipt.get("ledger_readback"), "receipt.ledger_readback", errors)
    if ledger.get("version") != version or ledger.get("name") != name or ledger.get("matches_target") is not True:
        errors.append("receipt.ledger_readback:TARGET_MISMATCH")
    if len(exact_ledger) != 1 or exact_ledger[0].get("name") != name:
        errors.append("schema_migrations:VERSION_NAME_MISMATCH")

    apply = _obj(receipt.get("apply"), "receipt.apply", errors)
    _required(apply, "code", "apply", errors)
    _required(apply, "executor", "apply", errors)
    if apply.get("ledger_version") != version or apply.get("ledger_name") != name:
        errors.append("receipt.apply:LEDGER_IDENTITY_MISMATCH")
    write_ahead = _obj(receipt.get("write_ahead"), "receipt.write_ahead", errors)
    if (write_ahead.get("effect_scope") != f"MIGRATION:{version}"
            or write_ahead.get("request_sha256") != source_sha
            or write_ahead.get("dispatch_key") != f"lf-migration-train-run-{run_id}"):
        errors.append("receipt.write_ahead:IDENTITY_MISMATCH")
    if len(step_map.get("patch", [])) == 1:
        patch_evidence = step_map["patch"][0].get("evidence_payload") or {}
        transport_receipt = patch_evidence.get("db_write_transport_receipt") if isinstance(patch_evidence, dict) else None
        write_receipt = patch_evidence.get("write_receipt") if isinstance(patch_evidence, dict) else None
        if not isinstance(transport_receipt, dict):
            errors.append("patch.db_write_transport_receipt:MISSING")
        else:
            for key in ("code", "executor", "ledger_version", "ledger_name"):
                if transport_receipt.get(key) != apply.get(key):
                    errors.append(f"patch.db_write_transport_receipt.{key}:RECEIPT_MISMATCH")
        if not isinstance(write_receipt, dict) or write_receipt.get("ledger_version") != version or write_receipt.get("ledger_name") != name:
            errors.append("patch.write_receipt:LEDGER_MISMATCH")
    effect = _obj(receipt.get("effect"), "receipt.effect", errors)
    if effect.get("phase") != "SUCCEEDED" or effect.get("scope") != f"MIGRATION:{version}":
        errors.append("receipt.effect:NOT_SUCCEEDED")
    parity = _obj(receipt.get("parity"), "receipt.parity", errors)
    if parity.get("migration_source_parity") != "PASS":
        errors.append("receipt.parity:NOT_PASS")
    merge = _obj(receipt.get("merge"), "receipt.merge", errors)
    merge_sha = _required(merge, "merge_sha", "merge", errors)
    if merge_sha is not None and not SHA1.fullmatch(str(merge_sha)):
        errors.append("merge.merge_sha:INVALID_SHA1")
    if heads.get("main_after") != merge_sha or merge.get("in_main") is not True:
        errors.append("merge:MAIN_READBACK_MISMATCH")
    if isinstance(step_map.get("verify"), list) and len(step_map["verify"]) == 1:
        verify_evidence = step_map["verify"][0].get("evidence_payload") or {}
        readback = verify_evidence.get("readback") if isinstance(verify_evidence, dict) else None
        if not isinstance(readback, dict) or readback.get("in_main") is not True or readback.get("main_merge_sha") != merge_sha:
            errors.append("verify.readback:MERGE_MISMATCH")
        db_ledger = verify_evidence.get("db_write_transport_readback") if isinstance(verify_evidence, dict) else None
        if not isinstance(db_ledger, dict) or db_ledger.get("version") != version or db_ledger.get("name") != name:
            errors.append("verify.readback:LEDGER_MISMATCH")

    pr_record = snapshot.get("github_pull")
    if not isinstance(pr_record, dict):
        errors.append("github_pull:NOT_VERIFIED")
    else:
        if pr_record.get("number") != pr:
            errors.append("github_pull.number:MISMATCH")
        if pr_record.get("merged") is not True or pr_record.get("state") != "closed":
            errors.append("github_pull:NOT_MERGED")
        if pr_record.get("merge_commit_sha") != merge_sha:
            errors.append("github_pull.merge_commit_sha:MISMATCH")
        base = pr_record.get("base") or {}
        if base.get("ref") != "main":
            errors.append("github_pull.base:NOT_MAIN")
        head = pr_record.get("head") or {}
        if head.get("sha") != heads.get("final_head"):
            errors.append("github_pull.head.sha:FINAL_HEAD_MISMATCH")
        if (base.get("repo") or {}).get("full_name") not in (None, repo):
            errors.append("github_pull.base.repository:MISMATCH")
    if errors:
        return {"result": "FAIL", "execution_id": execution_id, "pr": pr, "reasons": errors, "notes": notes}
    return {"result": "PASS", "execution_id": execution_id, "pr": pr,
            "reasons": [], "notes": ["Train receipt, steps, ledger readback and merged PR agree."]}


def github_get(repository: str, pr: int, token: str) -> dict[str, Any]:
    request = urllib.request.Request(
        f"https://api.github.com/repos/{repository}/pulls/{pr}",
        headers={"Accept": "application/vnd.github+json", "Authorization": f"Bearer {token}",
                 "X-GitHub-Api-Version": "2022-11-28", "User-Agent": "lf-train-receipt-verifier"},
    )
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            data = json.loads(response.read().decode("utf-8"))
    except (urllib.error.HTTPError, urllib.error.URLError, json.JSONDecodeError) as exc:
        raise ReceiptError(f"GITHUB_READBACK_FAILED:{exc}") from exc
    return {k: data.get(k) for k in ("number", "state", "merged", "merge_commit_sha", "base", "head")}


def fetch_live(dsn: str, *, pr: int | None, execution_id: str | None, token: str) -> list[dict[str, Any]]:
    try:
        import psycopg
    except ImportError as exc:
        raise ReceiptError("PSYCOPG_REQUIRED_FOR_LIVE_READ_ONLY_MODE") from exc
    if bool(pr) == bool(execution_id):
        raise ReceiptError("PROVIDE_EXACTLY_ONE_OF_PR_OR_EXECUTION_ID")

    filters = "e.execution_id = %s" if execution_id else "e.manifest->>'pr' = %s"
    arg = execution_id if execution_id else str(pr)
    query = f"""
      select ev.id, ev.evento_tipo, ev.entidad_codigo, ev.payload,
             encode(extensions.digest(convert_to((ev.payload->'receipt')::text,'UTF8'),'sha256'),'hex')
                 = ev.payload->>'receipt_sha256' as receipt_sha_matches,
             e.execution_id, e.operation_code, e.target_type, e.target_repo,
             e.target_code, e.target_path, e.request_sha256, e.status, e.manifest
        from public.lf_eventos ev
        join public.lf_operation_execution e on e.execution_id = ev.entidad_codigo
       where ev.evento_tipo = %s and ev.payload->>'receipt_schema' = %s and {filters}
       order by ev.created_at desc, ev.id desc
    """
    snapshots: list[dict[str, Any]] = []
    with psycopg.connect(dsn, autocommit=False) as conn:
        try:
            conn.execute("SET TRANSACTION READ ONLY")
            with conn.cursor() as cur:
                cur.execute("SHOW transaction_read_only")
                if str(cur.fetchone()[0]).lower() not in ("on", "true", "1"):
                    raise ReceiptError("READ_ONLY_TRANSACTION_NOT_CONFIRMED")
                cur.execute(query, (EVENT_TYPE, RECEIPT_SCHEMA, arg))
                rows = cur.fetchall()
                if not rows:
                    raise ReceiptError("TRAIN_RECEIPT_NOT_FOUND")
                for row in rows:
                    (event_id, event_type, entity_code, payload, sha_matches, exec_id,
                     operation_code, target_type, target_repo, target_code, target_path,
                     request_sha, status, manifest) = row
                    receipt = (payload or {}).get("receipt") or {}
                    version = (receipt.get("migration") or {}).get("version")
                    cur.execute("""
                      select step_id,status,evidence_payload
                        from public.lf_operation_execution_steps
                       where execution_id=%s order by step_order,step_id
                    """, (exec_id,))
                    steps = [{"step_id": r[0], "status": r[1], "evidence_payload": r[2]} for r in cur.fetchall()]
                    cur.execute("""
                      select version,name from supabase_migrations.schema_migrations where version=%s
                    """, (version,))
                    ledger_rows = [{"version": r[0], "name": r[1]} for r in cur.fetchall()]
                    repo = receipt.get("repository")
                    pr_num = receipt.get("pr")
                    pull = github_get(repo, int(pr_num), token)
                    snapshots.append({
                        "event": {"id": event_id, "evento_tipo": event_type, "entidad_codigo": entity_code,
                                  "payload": payload},
                        "receipt_sha_matches": sha_matches,
                        "execution": {"execution_id": exec_id, "operation_code": operation_code,
                                      "target_type": target_type, "target_repo": target_repo,
                                      "target_code": target_code, "target_path": target_path,
                                      "request_sha256": request_sha, "status": status, "manifest": manifest},
                        "steps": steps, "ledger_rows": ledger_rows, "github_pull": pull,
                    })
        finally:
            conn.rollback()
    return snapshots


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    selector = parser.add_mutually_exclusive_group(required=True)
    selector.add_argument("--pr", type=int)
    selector.add_argument("--execution-id")
    parser.add_argument("--live-read-only", action="store_true")
    parser.add_argument("--dsn-env", default="LF_SUPABASE_READONLY_DSN")
    parser.add_argument("--github-token-env", default="GITHUB_TOKEN")
    args = parser.parse_args()
    if not args.live_read_only:
        parser.error("live use requires --live-read-only; tests run on fixtures")
    dsn = os.environ.get(args.dsn_env, "").strip()
    if not dsn:
        parser.error(f"missing read-only DSN environment variable: {args.dsn_env}")
    token = os.environ.get(args.github_token_env, "").strip() or os.environ.get("GH_TOKEN", "").strip()
    if not token:
        parser.error(f"missing GitHub read token: {args.github_token_env} or GH_TOKEN")
    try:
        snapshots = fetch_live(dsn, pr=args.pr, execution_id=args.execution_id, token=token)
        reports = [verify_snapshot(item) for item in snapshots]
        print(json.dumps({"reports": reports}, indent=2, sort_keys=True))
        if any(r["result"] == "FAIL" for r in reports):
            return 1
        # A PR may have earlier BLOCKED attempts followed by a successful retry.
        if args.pr:
            latest = reports[0]
            return 0 if latest["result"] in ("PASS", "BLOCKED") else 1
        return 0 if reports[0]["result"] in ("PASS", "BLOCKED") else 1
    except ReceiptError as exc:
        print(f"FAIL_TRAIN_RECEIPT_VERIFIER: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Bounded operational DML adapter. Router-first; NOT a migration executor.

Code-only until an approved operational lane, handler registry and least-privilege
runtime are deployed. No caller-supplied SQL or dynamic database function names.
"""
from __future__ import annotations

import hashlib
import json
import os
import re
from dataclasses import dataclass
from typing import Callable, Mapping

CONNECTOR = "LF_OPERATION_EXECUTOR_V1"
OPERATION_CODE = "EJECUCION_OPERATIVA_LF"
ACTIVE_LANE = "GOVERNED_OPERATIONAL_DML"
OPERATIONAL_ASSET_TYPE = "OPERATIONAL_DB"
OPERATIONAL_ACTION = "OPERATION_EXECUTE"
EXEC_RE = re.compile(r"^EXEC-[A-Z0-9_-]{3,200}$")
CODE_RE = re.compile(r"^[A-Z][A-Z0-9_]{1,100}$")
SHA256_RE = re.compile(r"^[a-f0-9]{64}$")


class Blocked(Exception):
    """A security or contractual precondition was not satisfied."""


def canonical(value: object) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False)


@dataclass(frozen=True)
class Request:
    operation_code: str
    execution_id: str
    handler_code: str
    payload: dict
    effect_scope: str
    dispatch_key: str
    actor: str

    def validate(self) -> None:
        if self.operation_code != OPERATION_CODE:
            raise Blocked("BLOCK_OPERATION_CODE_INVALID")
        if not (isinstance(self.execution_id, str) and EXEC_RE.fullmatch(self.execution_id)):
            raise Blocked("BLOCK_EXECUTION_ID_INVALID")
        if not (isinstance(self.handler_code, str) and CODE_RE.fullmatch(self.handler_code)):
            raise Blocked("BLOCK_HANDLER_CODE_INVALID")
        if not isinstance(self.payload, dict) or not self.payload:
            raise Blocked("BLOCK_PAYLOAD_INVALID")
        if len(canonical(self.payload).encode("utf-8")) > 8192:
            raise Blocked("BLOCK_PAYLOAD_TOO_LARGE")
        if not isinstance(self.effect_scope, str) or not 1 <= len(self.effect_scope) <= 200:
            raise Blocked("BLOCK_EFFECT_SCOPE_INVALID")
        if not isinstance(self.dispatch_key, str) or not 1 <= len(self.dispatch_key) <= 200:
            raise Blocked("BLOCK_DISPATCH_KEY_INVALID")
        if not isinstance(self.actor, str) or not 1 <= len(self.actor) <= 200:
            raise Blocked("BLOCK_ACTOR_INVALID")


@dataclass(frozen=True)
class Handler:
    code: str
    revision: str
    operation_code: str
    target_type: str
    target_code: str
    action_code: str
    perform: Callable
    verify: Callable

    def validate(self) -> None:
        for value in (self.code, self.revision, self.operation_code, self.target_type,
                      self.target_code, self.action_code):
            if not isinstance(value, str) or not value or len(value) > 256:
                raise Blocked("BLOCK_HANDLER_REGISTRATION_INVALID")
        if self.operation_code != OPERATION_CODE:
            raise Blocked("BLOCK_HANDLER_OPERATION_NOT_OPERATIONAL")
        if not callable(self.perform) or not callable(self.verify):
            raise Blocked("BLOCK_HANDLER_CALLBACK_INVALID")
        if self.target_type in ("MIGRATION", "DB", "FUNCTION", "TRIGGER", "CAPABILITY"):
            raise Blocked("BLOCK_MIGRATION_RESERVED_FOR_TRAIN")
        if self.target_type != OPERATIONAL_ASSET_TYPE or self.action_code != OPERATIONAL_ACTION:
            raise Blocked("BLOCK_HANDLER_TARGET_NOT_OPERATIONAL_DB")


def digest(req: Request, handler: Handler) -> str:
    data = {"operation_code": req.operation_code, "handler_code": req.handler_code,
            "handler_revision": handler.revision, "payload": req.payload,
            "effect_scope": req.effect_scope}
    return hashlib.sha256(canonical(data).encode("utf-8")).hexdigest()


def one(cursor, sql: str, values: tuple):
    cursor.execute(sql, values)
    result = cursor.fetchone()
    if result is None:
        raise Blocked("BLOCK_GOVERNED_DB_READBACK_MISSING")
    return result[0]


def run_transaction(connection, req: Request, handlers: Mapping[str, Handler]) -> dict:
    """Execute within the caller-owned transaction; commit is NEVER done here."""
    req.validate()
    handler = handlers.get(req.handler_code)
    if handler is None:
        raise Blocked("BLOCK_HANDLER_NOT_REGISTERED")
    handler.validate()
    if req.operation_code != handler.operation_code:
        raise Blocked("BLOCK_OPERATION_HANDLER_MISMATCH")
    payload_sha = digest(req, handler)
    if not SHA256_RE.fullmatch(payload_sha):
        raise Blocked("BLOCK_DIGEST_INVALID")

    with connection.cursor() as cur:
        route = one(cur, "SELECT public.lf_router_resolve_v1(%s,%s,%s,%s,%s)",
                    ("Governed operational handler", None, handler.action_code, handler.target_type, "ROUTER"))
        if (not isinstance(route, dict) or route.get("router") != "ACT-0001"
                or route.get("status") != "READY_TO_EXECUTE"
                or route.get("downstream_execution_allowed") is not True
                or route.get("operation_code") != handler.operation_code
                or route.get("asset_type") != handler.target_type
                or route.get("action_code") != handler.action_code):
            raise Blocked("BLOCK_ROUTER_ROUTE_UNAUTHORIZED")

        record = one(cur,
            "SELECT jsonb_build_object('operation_code',operation_code,'target_type',target_type,"
            "'target_code',target_code,'status',status,'manifest',manifest,"
            "'request_sha256',request_sha256) "
            "FROM public.lf_operation_execution WHERE execution_id=%s",
            (req.execution_id,))
        if (not isinstance(record, dict) or record.get("status") != "IN_PROGRESS"
                or record.get("operation_code") != handler.operation_code
                or record.get("target_type") != handler.target_type
                or record.get("target_code") != handler.target_code):
            raise Blocked("BLOCK_ROUTER_EXECUTION_NOT_ADMITTED")
        admission = (record.get("manifest") or {}).get("operational_transaction_admission")
        expected = {"status": "APPROVED", "verification": "PASS", "lane": ACTIVE_LANE,
                    "connector": CONNECTOR, "handler_code": handler.code,
                    "handler_revision": handler.revision, "payload_sha256": payload_sha,
                    "effect_scope": req.effect_scope, "dispatch_key": req.dispatch_key}
        if not isinstance(admission, dict) or any(admission.get(k) != v for k, v in expected.items()):
            raise Blocked("BLOCK_OPERATIONAL_ADMISSION_NOT_EXACT")
        if record.get("request_sha256") != payload_sha:
            raise Blocked("BLOCK_ROUTER_EXECUTION_PAYLOAD_MISMATCH")

        authority = one(cur, "SELECT public.lf_router_downstream_authority_validate_v1(%s)",
                        (req.execution_id,))
        if (not isinstance(authority, dict) or authority.get("valid") is not True
                or authority.get("applicable") is not True
                or authority.get("code") != "ROUTER_DOWNSTREAM_AUTHORITY_VALID"
                or authority.get("execution_id") != req.execution_id
                or authority.get("operation_code") != req.operation_code
                or authority.get("target_type") != handler.target_type
                or authority.get("target_code") != handler.target_code):
            raise Blocked("BLOCK_ROUTER_AUTHORITY_STALE")

        owner = "operational-executor-" + hashlib.sha256(req.execution_id.encode()).hexdigest()[:32]
        lease = one(cur, "SELECT public.fn_lf_operation_acquire_lease_v1(%s,%s,%s,%s)",
                    (req.execution_id, owner, 120, req.actor))
        if not isinstance(lease, dict) or lease.get("result") != "LEASE_ACQUIRED":
            raise Blocked("BLOCK_EFFECT_LEASE_UNAVAILABLE")
        fence = lease.get("lease_fence")
        if not isinstance(fence, int) or fence < 1:
            raise Blocked("BLOCK_EFFECT_LEASE_INVALID")
        reserved = one(cur,
            "SELECT public.fn_lf_operation_reserve_effect_v1(%s,%s,%s,%s,%s,%s,%s)",
            (req.execution_id, owner, fence, req.effect_scope, payload_sha, req.dispatch_key, req.actor))
        if not isinstance(reserved, dict) or reserved.get("result") != "EFFECT_RESERVED_NEW" or reserved.get("dispatch_permitted") is not True:
            raise Blocked("BLOCK_EFFECT_NOT_NEW_OR_UNRESOLVED_NO_REPLAY")

        # Only a trusted, server-registered handler may perform the domain effect.
        effect = handler.perform(cur, req.payload)
        evidence = handler.verify(cur, req.payload, effect)
        if not isinstance(evidence, dict) or evidence.get("verified") is not True:
            raise Blocked("BLOCK_HANDLER_READBACK_UNVERIFIED")
        # Router must remain authoritative immediately before the receipt is stored.
        again = one(cur, "SELECT public.lf_router_downstream_authority_validate_v1(%s)",
                    (req.execution_id,))
        if (not isinstance(again, dict) or again.get("valid") is not True
                or again.get("applicable") is not True
                or again.get("execution_id") != req.execution_id
                or again.get("operation_code") != req.operation_code
                or again.get("target_type") != handler.target_type
                or again.get("target_code") != handler.target_code
                or again.get("code") != "ROUTER_DOWNSTREAM_AUTHORITY_VALID"):
            raise Blocked("BLOCK_ROUTER_AUTHORITY_CHANGED_BEFORE_RECEIPT")
        receipt = {"schema_version": "lf-operation-executor-receipt/v1",
                   "handler_code": handler.code, "handler_revision": handler.revision,
                   "execution_id": req.execution_id, "effect_scope": req.effect_scope,
                   "dispatch_key": req.dispatch_key, "payload_sha256": payload_sha,
                   "readback": evidence}
        marked = one(cur, "SELECT public.fn_lf_operation_mark_effect_succeeded_v1(%s,%s,%s,%s,%s::jsonb,%s)",
                     (req.execution_id, owner, fence, req.effect_scope, canonical(receipt), req.actor))
        if not isinstance(marked, dict) or marked.get("result") != "EFFECT_SUCCESS_PERSISTED":
            raise Blocked("BLOCK_EFFECT_RECEIPT_NOT_DURABLE")
        return receipt


def dispatch(req: Request, handlers: Mapping[str, Handler], connection_factory,
             *, dry_run: bool = True, admitted: bool = False) -> dict:
    """Commit/rollback boundary; inactive by default, including for dry-runs."""
    if not admitted:
        return {"status": "BLOCKED", "code": "BLOCK_OPERATIONAL_EXECUTOR_NOT_ADMITTED"}
    if type(dry_run) is not bool:
        return {"status": "BLOCKED", "code": "BLOCK_DRY_RUN_FLAG_INVALID"}
    conn = None
    try:
        conn = connection_factory()
        receipt = run_transaction(conn, req, handlers)
        if dry_run:
            conn.rollback()
            return {"status": "DRY_RUN_ROLLBACK_PASS", "execution_id": req.execution_id,
                    "receipt": receipt, "committed": False}
        conn.commit()
        return {"status": "COMMITTED_READBACK_PASS", "execution_id": req.execution_id,
                "receipt": receipt, "committed": True}
    except Blocked as exc:
        if conn is not None:
            conn.rollback()
        return {"status": "BLOCKED", "code": str(exc)}
    except Exception:
        if conn is not None:
            conn.rollback()
        return {"status": "BLOCKED", "code": "BLOCK_OPERATIONAL_EXECUTOR_RUNTIME_NO_COMMIT_CLAIM"}
    finally:
        if conn is not None:
            conn.close()


def runtime_dispatch(req: Request, handlers: Mapping[str, Handler], *, dry_run: bool = True) -> dict:
    """Dedicated runtime only. Existing ChatGPT Supabase connector remains read-only."""
    if os.environ.get("LF_OPERATION_EXECUTOR_LANE") != ACTIVE_LANE:
        return {"status": "BLOCKED", "code": "BLOCK_OPERATIONAL_EXECUTOR_NOT_ADMITTED"}
    dsn = os.environ.get("LF_OPERATION_EXECUTOR_DSN")
    if not dsn:
        return {"status": "BLOCKED", "code": "BLOCK_OPERATIONAL_EXECUTOR_CREDENTIAL_NOT_PROVISIONED"}
    def factory():
        import psycopg
        return psycopg.connect(dsn, autocommit=False, connect_timeout=8)
    return dispatch(req, handlers, factory, dry_run=dry_run, admitted=True)

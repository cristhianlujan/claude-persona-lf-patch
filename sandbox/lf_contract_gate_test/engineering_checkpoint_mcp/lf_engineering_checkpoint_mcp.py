#!/usr/bin/env python3
"""LF Engineering Checkpoint MCP, bounded operational transaction candidate.

Code-only. INACTIVE unless a separate, approved nonmigration operational lane
creates a scoped ACTUALIZACION_DB_LF execution and provisions a dedicated DB role.
Never used for DDL, migration ledger writes, or an alternative to Merge Train.
"""
from __future__ import annotations

import hashlib
import json
import os
import sys
from dataclasses import dataclass
from typing import Any

CONNECTOR = "LF_ENGINEERING_CHECKPOINT_MCP_V1"
OPERATION = "ACTUALIZACION_DB_LF"
TARGET = "programacion.engineering_work_checkpoints"
ALLOWED_STATES = frozenset({"DONE", "NOT_APPLICABLE", "IN_PROGRESS"})


class Refused(Exception):
    """Fail-closed operational admission error."""


@dataclass(frozen=True)
class TransitionRequest:
    plan_code: str
    unit_code: str
    checkpoint_code: str
    new_status: str
    evidence_ref: str
    actor: str
    detail: str
    router_execution_id: str

    def validate(self) -> None:
        for field in ("plan_code", "unit_code", "checkpoint_code",
                      "actor", "router_execution_id"):
            value = getattr(self, field)
            if not isinstance(value, str) or not value.strip() or len(value) > 256:
                raise Refused("BLOCK_INPUT_" + field.upper())
        if self.new_status not in ALLOWED_STATES:
            raise Refused("BLOCK_UNSUPPORTED_CHECKPOINT_TRANSITION")
        if (not isinstance(self.evidence_ref, str)
                or not self.evidence_ref.strip()
                or len(self.evidence_ref) > 2048):
            raise Refused("BLOCK_EVIDENCE_REF_REQUIRED")
        if not isinstance(self.detail, str) or len(self.detail) > 4096:
            raise Refused("BLOCK_DETAIL_INVALID")
        if not self.router_execution_id.startswith("EXEC-"):
            raise Refused("BLOCK_ROUTER_EXECUTION_ID")


def evidence_sha256(reference: str) -> str:
    return hashlib.sha256(reference.encode("utf-8")).hexdigest()


def authorize_execution(row: Any, request: TransitionRequest) -> None:
    """Require *DB-governed* admission bound to every exact effect dimension.

    No environment flag, caller-provided approval boolean or GitHub text alone
    can substitute for this durable Supabase authority row.
    """
    if not row:
        raise Refused("BLOCK_ROUTER_EXECUTION_MISSING")
    operation, target_type, target_code, status, manifest = row
    if operation != OPERATION or target_type != "DB" or target_code != TARGET:
        raise Refused("BLOCK_ROUTER_SCOPE_MISMATCH")
    if status != "IN_PROGRESS" or not isinstance(manifest, dict):
        raise Refused("BLOCK_ROUTER_EXECUTION_NOT_ACTIVE")
    gate = manifest.get("operational_transaction_admission")
    if not isinstance(gate, dict) or gate.get("status") != "APPROVED":
        raise Refused("BLOCK_OPERATIONAL_LANE_NOT_ADMITTED")
    expected = {
        "connector": CONNECTOR,
        "plan_code": request.plan_code,
        "unit_code": request.unit_code,
        "checkpoint_code": request.checkpoint_code,
        "new_status": request.new_status,
        "evidence_ref_sha256": evidence_sha256(request.evidence_ref),
        "verification": "PASS",
    }
    if any(gate.get(k) != v for k, v in expected.items()):
        raise Refused("BLOCK_ADMISSION_NOT_BOUND_TO_EXACT_EFFECT")


def authorize_route(route: Any) -> None:
    if (not isinstance(route, dict)
            or route.get("status") != "READY_TO_EXECUTE"
            or route.get("router") != "ACT-0001"
            or route.get("operation_code") != OPERATION
            or route.get("asset_type") != "DB"
            or route.get("action_code") != "UPDATE"
            or route.get("downstream_execution_allowed") is not True):
        raise Refused("BLOCK_ROUTER_NOT_AUTHORIZED")


def authorize_checkpoint(bootstrap: Any, request: TransitionRequest) -> None:
    if not isinstance(bootstrap, dict):
        raise Refused("BLOCK_BOOTSTRAP_INVALID")
    if bootstrap.get("terminal_action") != "CONTINUE_CURRENT_CHECKPOINT":
        raise Refused("BLOCK_BOOTSTRAP_TERMINAL_ACTION")
    checkpoint = bootstrap.get("current_checkpoint") or {}
    if checkpoint.get("checkpoint_code") != request.checkpoint_code:
        raise Refused("BLOCK_CHECKPOINT_NOT_CURRENT")
    spec = bootstrap.get("action_spec") or {}
    if spec.get("status") != "READY":
        raise Refused("BLOCK_CHECKPOINT_CONTRACT_NOT_READY")


def run_transaction(connection: Any, request: TransitionRequest, dry_run: bool = True) -> dict:
    """One transaction: Router -> execution admission -> bootstrap -> transition -> readback.

    Real commit is possible only with a separately admitted DB execution, a
    writable least-privilege runtime credential, and explicit dry_run=False.
    """
    request.validate()
    with connection.cursor() as cursor:
        cursor.execute(
            "SELECT public.lf_router_resolve_v1(%s,%s,%s,%s)",
            ("Actualizar checkpoint de ingenieria gobernado", TARGET, "UPDATE", "DB"),
        )
        authorize_route(cursor.fetchone()[0])
        cursor.execute(
            "SELECT operation_code,target_type,target_code,status,manifest "
            "FROM public.lf_operation_execution WHERE execution_id=%s",
            (request.router_execution_id,),
        )
        authorize_execution(cursor.fetchone(), request)
        cursor.execute(
            "SELECT programacion.fn_engineering_unit_bootstrap_v3(%s,%s)",
            (request.plan_code, request.unit_code),
        )
        authorize_checkpoint(cursor.fetchone()[0], request)
        cursor.execute(
            "SELECT c.status,c.evidence_ref FROM programacion.engineering_work_checkpoints c "
            "JOIN programacion.engineering_plan_units u ON u.work_item_id=c.work_item_id "
            "WHERE u.plan_code=%s AND u.unit_code=%s AND c.checkpoint_code=%s FOR UPDATE OF c",
            (request.plan_code, request.unit_code, request.checkpoint_code),
        )
        previous = cursor.fetchone()
        if previous is None or previous[0] in ("DONE", "NOT_APPLICABLE"):
            raise Refused("BLOCK_CHECKPOINT_ALREADY_TERMINAL_OR_MISSING")
        cursor.execute(
            "SELECT programacion.fn_engineering_checkpoint_transition_v1("
            "%s,%s,%s,%s,%s,%s,%s)",
            (request.plan_code, request.unit_code, request.checkpoint_code,
             request.new_status, request.evidence_ref, request.actor, request.detail),
        )
        transition = cursor.fetchone()[0]
        if (not isinstance(transition, dict)
                or transition.get("transition", {}).get("status") != "APPLIED"):
            raise Refused("BLOCK_CANONICAL_TRANSITION_NOT_APPLIED")
        cursor.execute(
            "SELECT c.status,c.evidence_ref FROM programacion.engineering_work_checkpoints c "
            "JOIN programacion.engineering_plan_units u ON u.work_item_id=c.work_item_id "
            "WHERE u.plan_code=%s AND u.unit_code=%s AND c.checkpoint_code=%s",
            (request.plan_code, request.unit_code, request.checkpoint_code),
        )
        after = cursor.fetchone()
        if (not after or after[0] != request.new_status
                or after[1] != request.evidence_ref):
            raise Refused("BLOCK_POSTWRITE_READBACK_DIVERGENCE")
    # Caller controls commit or rollback of the transaction, never inside this function.
    return {"status": "DRY_RUN_PASS_NOT_COMMITTED" if dry_run else "COMMIT_PENDING",
            "plan_code": request.plan_code, "unit_code": request.unit_code,
            "checkpoint_code": request.checkpoint_code,
            "before": previous[0], "after": after[0],
            "evidence_sha256": evidence_sha256(request.evidence_ref),
            "router_execution_id": request.router_execution_id}


def transition_checkpoint(request: TransitionRequest, dry_run: bool = True) -> dict:
    try:
        request.validate()
        if os.environ.get("LF_ENGINEERING_TX_LANE") != "GOVERNED_OPERATIONAL_DML":
            raise Refused("BLOCK_OPERATIONAL_MCP_INACTIVE_BY_POLICY")
        dsn = os.environ.get("LF_ENGINEERING_TX_DSN")
        if not dsn:
            raise Refused("BLOCK_DEDICATED_RUNTIME_CREDENTIAL_NOT_CONNECTED")
        # Credentials must be injected by the runtime and never returned by tools.
        import psycopg
        with psycopg.connect(dsn, connect_timeout=8) as connection:
            result = run_transaction(connection, request, dry_run=dry_run)
            if dry_run:
                connection.rollback()
                return result
            connection.commit()
            result["status"] = "COMMITTED_READBACK_PASS"
            return result
    except Refused as exc:
        return {"status": "BLOCKED", "blocking_code": str(exc)}
    except Exception:
        # Never expose connection details, credentials, or SQL exception bodies.
        return {"status": "BLOCKED", "blocking_code": "BLOCK_RUNTIME_OR_DB_ERROR_NO_COMMIT_CLAIM"}


def _self_test() -> None:
    base = dict(plan_code="IG_CURATOR_VALIDATOR_REFACTOR_V2", unit_code="M4.11",
                checkpoint_code="PREREQ_GATES_PASS", new_status="DONE",
                evidence_ref="supabase://programacion.provenance_receipts/1667#sha=example",
                actor="LF_ENGINEERING_TX_V1", detail="test only",
                router_execution_id="EXEC-TX-TEST")
    r = TransitionRequest(**base)
    r.validate()
    admission = {
        "status": "APPROVED", "connector": CONNECTOR, "plan_code": r.plan_code,
        "unit_code": r.unit_code, "checkpoint_code": r.checkpoint_code,
        "new_status": r.new_status, "evidence_ref_sha256": evidence_sha256(r.evidence_ref),
        "verification": "PASS",
    }
    row = (OPERATION, "DB", TARGET, "IN_PROGRESS",
           {"operational_transaction_admission": admission})
    authorize_execution(row, r)
    for mutated in [
        (OPERATION, "DB", TARGET, "IN_PROGRESS", {}),
        (OPERATION, "MIGRATION", TARGET, "IN_PROGRESS",
         {"operational_transaction_admission": admission}),
        (OPERATION, "DB", TARGET, "COMPLETED",
         {"operational_transaction_admission": admission}),
        (OPERATION, "DB", TARGET, "IN_PROGRESS",
         {"operational_transaction_admission":
          {**admission, "evidence_ref_sha256": "0" * 64}}),
    ]:
        try:
            authorize_execution(mutated, r)
        except Refused:
            continue
        raise AssertionError("UNAUTHORIZED_EXECUTION_WAS_ACCEPTED")
    assert transition_checkpoint(r)["blocking_code"] == "BLOCK_OPERATIONAL_MCP_INACTIVE_BY_POLICY"
    print("PASS_LF_ENGINEERING_MCP_SELF_TEST: positive=1 negative=5 no_DB")


def serve() -> None:
    try:
        from mcp.server.fastmcp import FastMCP
    except ImportError as exc:
        raise SystemExit("Install mcp and psycopg in an approved isolated runtime") from exc
    server = FastMCP(CONNECTOR)

    @server.tool()
    def engineering_checkpoint_transition(
        plan_code: str, unit_code: str, checkpoint_code: str,
        new_status: str, evidence_ref: str, actor: str, detail: str,
        router_execution_id: str, dry_run: bool = True,
    ) -> dict:
        """Governed operational checkpoint transition; no SQL or migration tools."""
        req = TransitionRequest(plan_code, unit_code, checkpoint_code, new_status,
                                evidence_ref, actor, detail, router_execution_id)
        return transition_checkpoint(req, dry_run=dry_run)

    # STDIO only. Publishing a remote HTTP MCP requires separate auth/hosting review.
    server.run(transport="stdio")


if __name__ == "__main__":
    if len(sys.argv) == 2 and sys.argv[1] == "--self-test":
        _self_test()
    elif len(sys.argv) == 1:
        serve()
    else:
        raise SystemExit("Usage: lf_engineering_checkpoint_mcp.py [--self-test]")

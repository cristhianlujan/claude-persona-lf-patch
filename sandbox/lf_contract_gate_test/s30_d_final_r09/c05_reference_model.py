#!/usr/bin/env python3
from __future__ import annotations
from dataclasses import dataclass
from typing import Optional

@dataclass
class Reservation:
    execution_id: str
    request_sha256: str
    lease_owner: Optional[str] = None
    lease_expires_at: float = 0.0
    checkpoint: int = 0
    effect_committed: bool = False
    closed: bool = False

class ReferenceStore:
    """Deterministic oracle only. It is NOT runtime/dynamic proof."""
    def __init__(self):
        self.rows = {}
        self.irreversible_effects = set()
    def reserve(self, operation_code, key, request_sha256, execution_id):
        if len(key) > 200: return {"status":"BLOCKED","code":"IDEMPOTENCY_KEY_TOO_LONG"}
        ident=(operation_code,key); row=self.rows.get(ident)
        if row is None:
            row=Reservation(execution_id=execution_id,request_sha256=request_sha256); self.rows[ident]=row
            return {"status":"RESERVED","execution_id":execution_id}
        if row.request_sha256 != request_sha256:
            return {"status":"BLOCKED","code":"IDEMPOTENCY_KEY_REUSED_WITH_DIFFERENT_REQUEST","execution_id":row.execution_id}
        return {"status":"REPLAY_EXISTING_EXECUTION","execution_id":row.execution_id}
    def acquire_lease(self, operation_code, key, owner, now, ttl):
        row=self.rows[(operation_code,key)]
        if row.lease_owner not in (None,owner) and row.lease_expires_at > now:
            return {"status":"BLOCKED","code":"LEASE_HELD","owner":row.lease_owner}
        row.lease_owner=owner; row.lease_expires_at=now+ttl
        return {"status":"ACQUIRED","owner":owner,"expires_at":row.lease_expires_at}
    def effect_once(self, operation_code, key, effect_id):
        ident=(f"{operation_code}:{key}",effect_id); row=self.rows[(operation_code,key)]
        if ident in self.irreversible_effects: return {"status":"REPLAY_NOOP"}
        self.irreversible_effects.add(ident); row.effect_committed=True; return {"status":"APPLIED"}
    def checkpoint(self, operation_code, key, cursor):
        row=self.rows[(operation_code,key)]; row.checkpoint=max(row.checkpoint,cursor); return {"status":"PERSISTED","cursor":row.checkpoint}
    def resume_cursor(self, operation_code, key): return self.rows[(operation_code,key)].checkpoint
    def child_sweep(self, outcomes):
        executed=[k for k,v in outcomes.items() if v=="SAFE"]; blocked=[k for k,v in outcomes.items() if v=="BLOCKED_CAUSAL"]
        return {"executed":executed,"blocked":blocked,"continue_safe":bool(executed)}

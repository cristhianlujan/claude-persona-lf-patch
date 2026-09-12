from __future__ import annotations
from dataclasses import dataclass, field
from typing import Any

class Blocked(RuntimeError): pass
@dataclass
class Exec:
    execution_id:str; request_sha256:str; target:tuple; lease_owner:str|None=None; lease_expires:float|None=None; lease_fence:int=0; checkpoint_seq:int=0; checkpoint_payload:dict=field(default_factory=dict)
@dataclass
class Effect:
    request_sha256:str; dispatch_key:str; state:str='RESERVED'; receipt:dict|None=None
class Store:
    def __init__(self): self.by_key={}; self.effects={}
    def reserve(self,op,key,req,eid,target):
        k=(op,key); row=self.by_key.get(k)
        if row is None:
            row=Exec(eid,req,target); self.by_key[k]=row; return {'result':'RESERVED_NEW_EXECUTION','execution_id':eid,'dispatch_permitted':True}
        if row.request_sha256!=req: raise Blocked('IDEMPOTENCY_KEY_REUSED_WITH_DIFFERENT_REQUEST')
        if row.target!=target: raise Blocked('IDEMPOTENCY_REPLAY_TARGET_MISMATCH')
        return {'result':'REPLAY_EXISTING_EXECUTION','execution_id':row.execution_id,'dispatch_permitted':False}
    def acquire(self,op,key,owner,now,ttl):
        r=self.by_key[(op,key)]
        if r.lease_owner not in (None,owner) and r.lease_expires is not None and r.lease_expires>now:
            return {'result':'BLOCKED','code':'LEASE_HELD','lease_fence':r.lease_fence}
        if not (r.lease_owner==owner and r.lease_expires is not None and r.lease_expires>now): r.lease_fence+=1
        r.lease_owner=owner; r.lease_expires=now+ttl
        return {'result':'LEASE_ACQUIRED','lease_fence':r.lease_fence}
    def checkpoint(self,op,key,owner,fence,seq,payload,now):
        r=self.by_key[(op,key)]
        if r.lease_owner!=owner or r.lease_fence!=fence or r.lease_expires is None or r.lease_expires<=now: raise Blocked('STALE_OR_MISSING_LEASE_FENCE')
        if seq<1: raise Blocked('INVALID_CHECKPOINT_SEQ')
        if seq<r.checkpoint_seq: raise Blocked('CHECKPOINT_NON_MONOTONIC')
        if seq==r.checkpoint_seq:
            if payload!=r.checkpoint_payload: raise Blocked('CHECKPOINT_SEQ_REUSED_WITH_DIFFERENT_PAYLOAD')
            return {'result':'REPLAY_CHECKPOINT'}
        r.checkpoint_seq=seq; r.checkpoint_payload=dict(payload); return {'result':'CHECKPOINT_PERSISTED'}
    def reserve_effect(self,op,key,owner,fence,scope,req,dispatch,now):
        r=self.by_key[(op,key)]
        if r.lease_owner!=owner or r.lease_fence!=fence or r.lease_expires is None or r.lease_expires<=now: raise Blocked('STALE_OR_MISSING_LEASE_FENCE')
        ek=(r.execution_id,scope); e=self.effects.get(ek)
        if e is None:
            self.effects[ek]=Effect(req,dispatch); return {'result':'EFFECT_RESERVED_NEW','dispatch_permitted':True}
        if e.request_sha256!=req or e.dispatch_key!=dispatch: raise Blocked('EFFECT_SCOPE_REUSED_WITH_DIFFERENT_REQUEST')
        if e.state=='SUCCEEDED': return {'result':'REPLAY_SUCCEEDED_EFFECT','dispatch_permitted':False,'receipt':e.receipt}
        return {'result':'RECONCILIATION_REQUIRED','dispatch_permitted':False}
    def succeed_effect(self,op,key,owner,fence,scope,receipt,now):
        r=self.by_key[(op,key)]
        if r.lease_owner!=owner or r.lease_fence!=fence or r.lease_expires is None or r.lease_expires<=now: raise Blocked('STALE_OR_MISSING_LEASE_FENCE')
        e=self.effects[(r.execution_id,scope)]
        if e.state=='SUCCEEDED':
            if e.receipt!=receipt: raise Blocked('EFFECT_SUCCESS_RECEIPT_MISMATCH')
            return {'result':'REPLAY_EFFECT_SUCCESS'}
        e.state='SUCCEEDED'; e.receipt=dict(receipt); return {'result':'EFFECT_SUCCESS_PERSISTED'}

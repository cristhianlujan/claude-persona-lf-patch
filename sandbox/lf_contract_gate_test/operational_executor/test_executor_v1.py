"""Offline policy tests: no DB access, real secrets, migration or checkpoint IDs."""
from __future__ import annotations
import unittest
from unittest.mock import patch

from lf_operation_executor_v1 import (
    ACTIVE_LANE, CONNECTOR, OPERATION_CODE, OPERATIONAL_ASSET_TYPE, OPERATIONAL_ACTION, Handler, Request, Blocked,
    digest, dispatch, runtime_dispatch,
)

def request():
    return Request(OPERATION_CODE, "EXEC-EXAMPLE-TEST", "EXAMPLE_HANDLER",
                   {"item": "test-value"}, "OPERATIONAL:TEST", "dispatch-test", "TEST-ACTOR")

def handler(perform=None, verify=None):
    return Handler("EXAMPLE_HANDLER", "v1", OPERATION_CODE,
                   OPERATIONAL_ASSET_TYPE, "example.logical_target", OPERATIONAL_ACTION,
                   perform or (lambda cur, payload: {"changed": payload["item"]}),
                   verify or (lambda cur, payload, effect:
                              {"verified": effect.get("changed") == payload["item"], "source": "trusted-handler"}))

class FakeCursor:
    def __init__(self, db):
        self.db = db
        self.last = None
    def __enter__(self):
        return self
    def __exit__(self, *_):
        return False
    def execute(self, sql, values):
        assert "%s" in sql
        self.last = sql
        self.db.queries.append((sql, values))
    def fetchone(self):
        req = self.db.req
        h = self.db.handler
        digest_value = digest(req, h)
        sql = self.last
        if "lf_router_resolve_v1" in sql:
            return ({"router":"ACT-0001", "status":"READY_TO_EXECUTE",
                     "downstream_execution_allowed":True,
                     "operation_code":h.operation_code,"asset_type":h.target_type,
                     "action_code":h.action_code, **self.db.route_overrides},)
        if "FROM public.lf_operation_execution" in sql:
            return ({"operation_code":h.operation_code, "target_type":h.target_type,
                     "target_code":h.target_code, "status":"IN_PROGRESS",
                     "request_sha256":digest_value,
                     "manifest":{"operational_transaction_admission":{
                         "status":"APPROVED","verification":"PASS",
                         "lane":ACTIVE_LANE,"connector":CONNECTOR,
                         "handler_code":h.code,"handler_revision":h.revision,
                         "payload_sha256":digest_value,"effect_scope":req.effect_scope,
                         "dispatch_key":req.dispatch_key, **self.db.admission_overrides}},
                     **self.db.execution_overrides},)
        if "lf_router_downstream_authority_validate_v1" in sql:
            self.db.auth_reads += 1
            override = self.db.second_auth_overrides if self.db.auth_reads > 1 else self.db.auth_overrides
            return ({"applicable":True,"valid":True,"code":"ROUTER_DOWNSTREAM_AUTHORITY_VALID",
                     "operation_code":req.operation_code,"execution_id":req.execution_id,
                     "target_type":h.target_type,"target_code":h.target_code,
                     **override},)
        if "fn_lf_operation_acquire_lease_v1" in sql:
            return ({"result":"LEASE_ACQUIRED","lease_fence":1, **self.db.lease_overrides},)
        if "fn_lf_operation_reserve_effect_v1" in sql:
            return ({"result":"EFFECT_RESERVED_NEW","dispatch_permitted":True,
                     **self.db.effect_overrides},)
        if "fn_lf_operation_mark_effect_succeeded_v1" in sql:
            return ({"result":"EFFECT_SUCCESS_PERSISTED",**self.db.receipt_overrides},)
        raise AssertionError("unexpected query:"+sql)

class FakeConnection:
    def __init__(self, req, h):
        self.req, self.handler = req, h
        self.queries = []
        self.route_overrides, self.admission_overrides = {}, {}
        self.execution_overrides, self.auth_overrides = {}, {}
        self.second_auth_overrides, self.lease_overrides = {}, {}
        self.effect_overrides, self.receipt_overrides = {}, {}
        self.auth_reads = 0
        self.commits = self.rollbacks = self.closed = 0
    def cursor(self):
        return FakeCursor(self)
    def commit(self):
        self.commits += 1
    def rollback(self):
        self.rollbacks += 1
    def close(self):
        self.closed += 1

class ExecutorTests(unittest.TestCase):
    def make(self, perform=None, verify=None):
        req = request()
        h = handler(perform, verify)
        return req, h, FakeConnection(req,h)
    def run_valid(self, *, dry_run=True):
        req,h,conn=self.make()
        result=dispatch(req,{h.code:h},lambda:conn,dry_run=dry_run,admitted=True)
        return result, conn

    def test_default_inactive_no_connection(self):
        req,h,db=self.make()
        result=dispatch(req,{h.code:h},lambda:db)
        self.assertEqual(result["code"],"BLOCK_OPERATIONAL_EXECUTOR_NOT_ADMITTED")
        self.assertEqual(db.queries,[])
    def test_rollback_success_no_persistence(self):
        result, db=self.run_valid()
        self.assertEqual(result["status"],"DRY_RUN_ROLLBACK_PASS")
        self.assertFalse(result["committed"])
        self.assertEqual((db.rollbacks,db.commits,db.closed),(1,0,1))
        self.assertEqual(db.auth_reads,2)
        self.assertEqual(sum("fn_lf_operation_mark_effect_succeeded_v1" in q
                             for q,_ in db.queries),1)
    def test_commit_only_after_receipt(self):
        result,db=self.run_valid(dry_run=False)
        self.assertEqual(result["status"],"COMMITTED_READBACK_PASS")
        self.assertEqual((db.commits,db.rollbacks),(1,0))
        self.assertEqual(db.queries[-1][0].split("(")[0],
                         "SELECT public.fn_lf_operation_mark_effect_succeeded_v1")
    def test_unknown_handler_blocks_before_route(self):
        req,h,db=self.make()
        result=dispatch(req,{},lambda:db,admitted=True)
        self.assertEqual(result["code"],"BLOCK_HANDLER_NOT_REGISTERED")
        self.assertEqual(db.queries,[])
    def test_migration_target_cannot_register(self):
        req,h,db=self.make()
        from dataclasses import replace
        bad=replace(h,target_type="MIGRATION")
        result=dispatch(req,{h.code:bad},lambda:db,admitted=True)
        self.assertEqual(result["code"],"BLOCK_MIGRATION_RESERVED_FOR_TRAIN")
        self.assertEqual(db.queries,[])
    def test_cannot_impersonate_migration_operation(self):
        from dataclasses import replace
        req,h,db=self.make()
        forged=replace(req,operation_code="ACTUALIZACION_DB_LF")
        result=dispatch(forged,{h.code:h},lambda:db,admitted=True)
        self.assertEqual(result["code"],"BLOCK_OPERATION_CODE_INVALID")
        self.assertEqual(db.queries,[])

    def test_migration_db_alias_not_accepted_as_operation(self):
        from dataclasses import replace
        req,h,db=self.make()
        bad=replace(h,target_type="DB",action_code="UPDATE")
        result=dispatch(req,{h.code:bad},lambda:db,admitted=True)
        self.assertEqual(result["code"],"BLOCK_MIGRATION_RESERVED_FOR_TRAIN")
        self.assertEqual(db.queries,[])

    def test_router_uses_dedicated_operational_route(self):
        result,db=self.run_valid()
        self.assertEqual(result["status"],"DRY_RUN_ROLLBACK_PASS")
        query,values=db.queries[0]
        self.assertEqual(query.count("%s"),5)
        self.assertEqual(values,( "Governed operational handler",None,OPERATIONAL_ACTION,OPERATIONAL_ASSET_TYPE,"ROUTER"))

    def test_authority_cannot_switch_target_after_handler(self):
        req,h,db=self.make()
        db.second_auth_overrides["target_code"]="other.target"
        result=dispatch(req,{h.code:h},lambda:db,admitted=True,dry_run=False)
        self.assertEqual(result["code"],"BLOCK_ROUTER_AUTHORITY_CHANGED_BEFORE_RECEIPT")
        self.assertEqual(db.commits,0)

    def test_route_must_allow_exact_operation(self):
        req,h,db=self.make()
        db.route_overrides["status"]="BLOCKED"
        result=dispatch(req,{h.code:h},lambda:db,admitted=True)
        self.assertEqual(result["code"],"BLOCK_ROUTER_ROUTE_UNAUTHORIZED")
        self.assertEqual(db.commits,0)
    def test_admission_exact_binding_required(self):
        req,h,db=self.make()
        db.admission_overrides["payload_sha256"]="0"*64
        result=dispatch(req,{h.code:h},lambda:db,admitted=True)
        self.assertEqual(result["code"],"BLOCK_OPERATIONAL_ADMISSION_NOT_EXACT")
        self.assertEqual(db.commits,0)
    def test_authority_currentness_required(self):
        req,h,db=self.make()
        db.auth_overrides["valid"]=False
        result=dispatch(req,{h.code:h},lambda:db,admitted=True)
        self.assertEqual(result["code"],"BLOCK_ROUTER_AUTHORITY_STALE")
    def test_replay_never_dispatches_handler(self):
        effects=[]
        req,h,db=self.make(perform=lambda cur,payload:effects.append(payload))
        db.effect_overrides={"result":"RECONCILIATION_REQUIRED","dispatch_permitted":False}
        result=dispatch(req,{h.code:h},lambda:db,admitted=True)
        self.assertEqual(result["code"],"BLOCK_EFFECT_NOT_NEW_OR_UNRESOLVED_NO_REPLAY")
        self.assertEqual(effects,[])
        self.assertEqual(db.rollbacks,1)
    def test_missing_verifiable_readback_rolls_back(self):
        req,h,db=self.make(verify=lambda cur,payload,effect:{"verified":False})
        result=dispatch(req,{h.code:h},lambda:db,admitted=True,dry_run=False)
        self.assertEqual(result["code"],"BLOCK_HANDLER_READBACK_UNVERIFIED")
        self.assertEqual((db.commits,db.rollbacks),(0,1))
    def test_stale_authority_after_effect_rolls_back(self):
        req,h,db=self.make()
        db.second_auth_overrides["valid"]=False
        result=dispatch(req,{h.code:h},lambda:db,admitted=True,dry_run=False)
        self.assertEqual(result["code"],"BLOCK_ROUTER_AUTHORITY_CHANGED_BEFORE_RECEIPT")
        self.assertEqual(db.commits,0)
    def test_receipt_failure_rolls_back(self):
        req,h,db=self.make()
        db.receipt_overrides["result"]="BLOCKED"
        result=dispatch(req,{h.code:h},lambda:db,admitted=True,dry_run=False)
        self.assertEqual(result["code"],"BLOCK_EFFECT_RECEIPT_NOT_DURABLE")
        self.assertEqual(db.commits,0)
    def test_runtime_requires_lane_before_importing_driver(self):
        req,h,_=self.make()
        with patch.dict("os.environ",{"LF_OPERATION_EXECUTOR_LANE":"","LF_OPERATION_EXECUTOR_DSN":""}):
            result=runtime_dispatch(req,{h.code:h})
        self.assertEqual(result["code"],"BLOCK_OPERATIONAL_EXECUTOR_NOT_ADMITTED")
    def test_runtime_requires_dedicated_secret(self):
        req,h,_=self.make()
        with patch.dict("os.environ",{"LF_OPERATION_EXECUTOR_LANE":ACTIVE_LANE,"LF_OPERATION_EXECUTOR_DSN":""}):
            result=runtime_dispatch(req,{h.code:h})
        self.assertEqual(result["code"],"BLOCK_OPERATIONAL_EXECUTOR_CREDENTIAL_NOT_PROVISIONED")

if __name__=="__main__":
    unittest.main()

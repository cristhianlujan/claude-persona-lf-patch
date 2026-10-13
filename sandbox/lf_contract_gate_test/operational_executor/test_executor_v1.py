"""Simulated transactional contract tests; no Supabase connection or credentials."""
from __future__ import annotations

import json
import unittest
from dataclasses import replace
from pathlib import Path
from unittest.mock import patch

from activation_readback_v1 import evaluate as evaluate_activation
from lf_operation_executor_v1 import (
    ACTIVE_LANE, CONNECTOR, OPERATION_CODE, OPERATIONAL_ACTION,
    OPERATIONAL_ASSET_TYPE, Handler, Request, Blocked,
    digest, dispatch, runtime_dispatch,
)


def request():
    return Request(OPERATION_CODE,"EXEC-EXAMPLE-TEST","EXAMPLE_HANDLER",
                   {"item":"test-value"},"OPERATIONAL:TEST","dispatch-test","TEST-ACTOR")


def handler(perform=None,verify=None):
    return Handler("EXAMPLE_HANDLER","v1",OPERATION_CODE,
                   OPERATIONAL_ASSET_TYPE,"EXAMPLE_HANDLER",OPERATIONAL_ACTION,
                   perform or (lambda cur,payload:{"changed":payload["item"]}),
                   verify or (lambda cur,payload,effect:
                              {"verified":effect.get("changed")==payload["item"],
                               "source":"trusted-handler"}))


class FakeCursor:
    def __init__(self,db):
        self.db=db
        self.last=None
    def __enter__(self):
        return self
    def __exit__(self,*_):
        return False
    def execute(self,sql,values):
        if "%s" not in sql:
            raise AssertionError("Direct SQL or unparameterized statement not allowed")
        self.last=(sql,values)
        self.db.queries.append((sql,values))
        if "lf_operational_executor_begin_v1" in sql and self.db.begin_error:
            raise self.db.begin_error
        if "lf_operational_executor_finish_v1" in sql and self.db.finish_error:
            raise self.db.finish_error
    def fetchone(self):
        sql,values=self.last
        req,h=self.db.req,self.db.handler
        if "lf_operational_executor_begin_v1" in sql:
            return ({**{
                "result":"READY_FOR_HANDLER","execution_id":req.execution_id,
                "effect_scope":req.effect_scope,"payload_sha256":digest(req,h),
                "lease_owner":"operational-executor-test","lease_fence":5
            },**self.db.begin_overrides},)
        if "lf_operational_executor_finish_v1" in sql:
            return ({**{
                "result":"EXECUTION_COMPLETED","execution_id":req.execution_id
            },**self.db.finish_overrides},)
        raise AssertionError("Core attempted direct SQL instead of facade")


class FakeConnection:
    def __init__(self,req,h):
        self.req,self.handler=req,h
        self.queries=[]
        self.begin_error=self.finish_error=None
        self.begin_overrides={}
        self.finish_overrides={}
        self.commits=self.rollbacks=self.closed=0
    def cursor(self):
        return FakeCursor(self)
    def commit(self):
        self.commits+=1
    def rollback(self):
        self.rollbacks+=1
    def close(self):
        self.closed+=1


class ExecutorTests(unittest.TestCase):
    def make(self,perform=None,verify=None):
        req=request()
        h=handler(perform,verify)
        return req,h,FakeConnection(req,h)

    def test_default_inactive_no_connection(self):
        req,h,db=self.make()
        out=dispatch(req,{h.code:h},lambda:db)
        self.assertEqual(out["code"],"BLOCK_OPERATIONAL_EXECUTOR_NOT_ADMITTED")
        self.assertEqual(db.queries,[])

    def test_two_scoped_sql_facades_only(self):
        req,h,db=self.make()
        out=dispatch(req,{h.code:h},lambda:db,admitted=True)
        self.assertEqual(out["status"],"DRY_RUN_ROLLBACK_PASS")
        self.assertEqual((db.commits,db.rollbacks,db.closed),(0,1,1))
        self.assertEqual(len(db.queries),2)
        self.assertIn("lf_operational_executor_begin_v1",db.queries[0][0])
        self.assertIn("lf_operational_executor_finish_v1",db.queries[1][0])
        self.assertEqual(db.queries[0][1][0],req.execution_id)

    def test_commit_after_governed_closeout_only(self):
        req,h,db=self.make()
        out=dispatch(req,{h.code:h},lambda:db,dry_run=False,admitted=True)
        self.assertEqual(out["status"],"COMMITTED_READBACK_PASS")
        self.assertEqual((db.commits,db.rollbacks),(1,0))
        self.assertEqual(out["receipt"]["close"]["result"],"EXECUTION_COMPLETED")

    def test_missing_handler_fails_closed_before_db(self):
        req,h,db=self.make()
        out=dispatch(req,{},lambda:db,admitted=True)
        self.assertEqual(out["code"],"BLOCK_HANDLER_NOT_REGISTERED")
        self.assertEqual(db.queries,[])

    def test_migration_target_and_db_update_blocked(self):
        req,h,db=self.make()
        for target in ("MIGRATION","DB","FUNCTION","TRIGGER","CAPABILITY"):
            with self.subTest(target=target):
                bad=replace(h,target_type=target)
                out=dispatch(req,{h.code:bad},lambda:db,admitted=True)
                self.assertEqual(out["code"],"BLOCK_MIGRATION_RESERVED_FOR_TRAIN")
        self.assertEqual(db.queries,[])

    def test_migration_operation_impersonation_blocked(self):
        req,h,db=self.make()
        out=dispatch(replace(req,operation_code="ACTUALIZACION_DB_LF"),
                     {h.code:h},lambda:db,admitted=True)
        self.assertEqual(out["code"],"BLOCK_OPERATION_CODE_INVALID")
        self.assertEqual(db.queries,[])

    def test_wrong_handler_action_and_revision_blocked(self):
        req,h,db=self.make()
        out=dispatch(req,{h.code:replace(h,action_code="UPDATE")},
                     lambda:db,admitted=True)
        self.assertEqual(out["code"],"BLOCK_HANDLER_TARGET_NOT_OPERATIONAL_DB")
        self.assertEqual(db.queries,[])

    def test_begin_admission_missing_blocks_effect(self):
        effects=[]
        req,h,db=self.make(perform=lambda cur,payload:effects.append(payload))
        db.begin_error=Blocked("BLOCK_OPERATIONAL_BEGIN_MANIFEST_NOT_EXACT")
        out=dispatch(req,{h.code:h},lambda:db,dry_run=False,admitted=True)
        self.assertEqual(out["code"],"BLOCK_OPERATIONAL_BEGIN_MANIFEST_NOT_EXACT")
        self.assertEqual(effects,[])
        self.assertEqual((db.commits,db.rollbacks),(0,1))

    def test_replay_blocks_before_handler(self):
        effects=[]
        req,h,db=self.make(perform=lambda cur,payload:effects.append(payload))
        db.begin_error=Blocked("BLOCK_OPERATIONAL_BEGIN_EFFECT_REPLAY_OR_AMBIGUOUS")
        out=dispatch(req,{h.code:h},lambda:db,dry_run=False,admitted=True)
        self.assertEqual(out["code"],"BLOCK_OPERATIONAL_BEGIN_EFFECT_REPLAY_OR_AMBIGUOUS")
        self.assertEqual(effects,[])
        self.assertEqual(db.commits,0)

    def test_invalid_begin_receipt_blocks(self):
        req,h,db=self.make()
        db.begin_overrides["payload_sha256"]="a"*64
        out=dispatch(req,{h.code:h},lambda:db,admitted=True)
        self.assertEqual(out["code"],"BLOCK_OPERATIONAL_BEGIN_RECEIPT_INVALID")

    def test_handler_unverified_readback_rolls_back(self):
        req,h,db=self.make(verify=lambda cur,p,e:{"verified":False})
        out=dispatch(req,{h.code:h},lambda:db,admitted=True,dry_run=False)
        self.assertEqual(out["code"],"BLOCK_HANDLER_READBACK_UNVERIFIED")
        self.assertEqual((db.commits,db.rollbacks),(0,1))
        self.assertEqual(len(db.queries),1)

    def test_runtime_handler_exception_rolls_back(self):
        def fail(cur,payload):
            raise ValueError("do not expose error details")
        req,h,db=self.make(perform=fail)
        out=dispatch(req,{h.code:h},lambda:db,admitted=True,dry_run=False)
        self.assertEqual(out["code"],"BLOCK_OPERATIONAL_EXECUTOR_RUNTIME_NO_COMMIT_CLAIM")
        self.assertEqual((db.commits,db.rollbacks),(0,1))

    def test_finish_failure_rolls_back(self):
        req,h,db=self.make()
        db.finish_error=Blocked("BLOCK_OPERATIONAL_FINISH_ROUTER_AUTHORITY_STALE")
        out=dispatch(req,{h.code:h},lambda:db,admitted=True,dry_run=False)
        self.assertEqual(out["code"],"BLOCK_OPERATIONAL_FINISH_ROUTER_AUTHORITY_STALE")
        self.assertEqual(db.commits,0)
        self.assertEqual(db.rollbacks,1)

    def test_forged_close_result_rolls_back(self):
        req,h,db=self.make()
        db.finish_overrides["result"]="BLOCKED"
        out=dispatch(req,{h.code:h},lambda:db,admitted=True,dry_run=False)
        self.assertEqual(out["code"],"BLOCK_OPERATIONAL_CLOSEOUT_NOT_DURABLE")
        self.assertEqual(db.commits,0)

    def test_wrong_close_identity_rolls_back(self):
        req,h,db=self.make()
        db.finish_overrides["execution_id"]="EXEC-OTHER"
        out=dispatch(req,{h.code:h},lambda:db,admitted=True,dry_run=False)
        self.assertEqual(out["code"],"BLOCK_OPERATIONAL_CLOSEOUT_NOT_DURABLE")

    def test_runtime_requires_authorized_lane_and_dsn(self):
        req,h,_=self.make()
        with patch.dict("os.environ",{"LF_OPERATION_EXECUTOR_LANE":"",
                                    "LF_OPERATION_EXECUTOR_DSN":""}):
            out=runtime_dispatch(req,{h.code:h})
        self.assertEqual(out["code"],"BLOCK_OPERATIONAL_EXECUTOR_NOT_ADMITTED")
        with patch.dict("os.environ",{"LF_OPERATION_EXECUTOR_LANE":ACTIVE_LANE,
                                    "LF_OPERATION_EXECUTOR_DSN":""}):
            out=runtime_dispatch(req,{h.code:h})
        self.assertEqual(out["code"],"BLOCK_OPERATIONAL_EXECUTOR_CREDENTIAL_NOT_PROVISIONED")

    def test_activation_snapshot_requires_separate_route_and_existing_train(self):
        manifest=json.loads((Path(__file__).parent/"operation_lane_contract_candidate_v1.json").read_text())
        self.assertEqual(manifest["status"],"CANDIDATE_NOT_INSTALLED_NOT_ACTIVE")
        snap={
           "migration_route":{"status":"READY_TO_EXECUTE","operation_code":"ACTUALIZACION_DB_LF"},
           "operational_route":{"status":"BLOCKED"},
           "operation_registry_count":0,"router_action_count":0,
           "router_authority_consumer":False,"active_contract_count":0,
           "active_required_step_count":0,"active_judge_binding_count":0,
           "governed_closeout_function":False,"read_only_connection_unchanged":True
        }
        self.assertEqual(evaluate_activation(snap)["status"],"BLOCKED")
        snap.update(
          operational_route={
             "status":"READY_TO_EXECUTE","operation_code":OPERATION_CODE,
             "asset_type":OPERATIONAL_ASSET_TYPE,
             "action_code":OPERATIONAL_ACTION,
             "downstream_execution_allowed":True
          },
          operation_registry_count=1,router_action_count=1,
          router_authority_consumer=True,active_contract_count=1,
          active_required_step_count=3,active_judge_binding_count=3,
          governed_closeout_function=True,
          runtime_role_grant_audit_passed=True,
          public_security_definer_exposure_reviewed=True
        )
        self.assertEqual(evaluate_activation(snap)["status"],"PASS")
        snap["public_security_definer_exposure_reviewed"]=False
        self.assertIn("BLOCK_PUBLIC_DEFINER_EXPOSURE_UNREVIEWED",
                      evaluate_activation(snap)["blocking_codes"])
        snap["public_security_definer_exposure_reviewed"]=True
        snap["migration_route"]["operation_code"]=OPERATION_CODE
        self.assertIn("BLOCK_MIGRATION_ROUTE_NOT_PRESERVED",evaluate_activation(snap)["blocking_codes"])


if __name__=="__main__":
    unittest.main()

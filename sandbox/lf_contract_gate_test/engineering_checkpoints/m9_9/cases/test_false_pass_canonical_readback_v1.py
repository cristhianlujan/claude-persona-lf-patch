"""Read-only boundary regression. Fake connection is NOT live canary evidence."""
from __future__ import annotations
import sys
import unittest
from pathlib import Path
HERE=Path(__file__).resolve().parent
RCV=HERE.parents[2]/"transversal_assets"/"reversible_candidate_verification"
sys.path.insert(0,str(HERE))
sys.path.insert(0,str(RCV))
from reversible_candidate_verification_v1 import CandidateIdentity
from false_pass_canonical_readback_v1 import CanonicalM99EvidenceReadback

class FakeCursor:
    def __init__(self,conn):
        self.conn=conn
        self.row=None
    def __enter__(self): return self
    def __exit__(self,*_): return False
    def execute(self,sql,params=None):
        self.conn.sql_calls.append((sql,params))
        if "FROM programacion.provenance_receipts" in sql:
            self.row=self.conn.rows.get(params[0])
        elif "fn_ig_m99_canary_receipt_gate_v1" in sql:
            self.row={"result":self.conn.gate}
        else:
            self.row=None
    def fetchone(self): return self.row

class FakeConn:
    autocommit=False
    def __init__(self,rows=None,gate=None):
        self.rows=rows or {}
        self.gate=gate or {}
        self.sql_calls=[]
        self.rollbacks=0
    def cursor(self): return FakeCursor(self)
    def rollback(self): self.rollbacks+=1

META={
    "canary_run_ref":"M99-CASE-1","cohort_type_code":"AUTH",
    "baseline_manifest_sha256":"b"*64,
    "canary_observation_sha256":"c"*64,
    "canary_observation_receipt_id":1,
    "canary_oracle_receipt_id":2,
    "canary_rollback_receipt_id":3,
}
CAND=CandidateIdentity("git://candidate","a"*64,META)

def sample_row(n,stage):
    payload={
        "schema_version":"IG_CANARY_OBSERVATION_V1",
        "verification_status":"VERIFIED",
        "verifier_identity":"SUPABASE:TRUSTED_TEST_FIXTURE",
        "stage":stage,
        "run_ref":"M99-CASE-1",
        "cohort_type_code":"AUTH",
        "baseline_manifest_sha256":"b"*64,
        "candidate_sha256":"a"*64,
        "head_sha":"d"*40,
        "subject_sha256":("c" if n==1 else "e")*64,
    }
    return {"id":n,"receipt_kind":"EVIDENCE_VERIFICATION",
            "subject_type":"IG_CANARY_OBSERVATION",
            "subject_ref":"IG_CANARY:AUTH",
            "subject_sha256":payload["subject_sha256"],
            "receipt_sha256":"f"*64,"issuer_channel":"EVIDENCE_VERIFIER_V1",
            "head_sha":"d"*40,"payload":payload}

class CanonicalReadbackTests(unittest.TestCase):
    def test_requires_transaction(self):
        conn=FakeConn()
        conn.autocommit=True
        with self.assertRaisesRegex(ValueError,"TRANSACTIONAL"):
            CanonicalM99EvidenceReadback(conn)

    def test_missing_record_fails_closed_and_rolls_back(self):
        conn=FakeConn()
        with self.assertRaisesRegex(ValueError,"NOT_FOUND"):
            CanonicalM99EvidenceReadback(conn)(CAND,{})
        self.assertEqual(conn.rollbacks,1)
        self.assertTrue(any("FROM programacion.provenance_receipts" in q for q,_ in conn.sql_calls))

    def test_forged_issuer_cannot_be_considered_canonical(self):
        rows={i:sample_row(i,stage) for i,stage in enumerate(
            ("OBSERVATION","INDEPENDENT_ORACLE","ROLLBACK_ACTION"),1)}
        rows[1]["issuer_channel"]="UNKNOWN_ISSUER"
        conn=FakeConn(rows)
        with self.assertRaisesRegex(ValueError,"IDENTITY_OR_ISSUER"):
            CanonicalM99EvidenceReadback(conn)(CAND,{})
        self.assertEqual(conn.rollbacks,1)

    def test_cross_cohort_receipt_fails_closed(self):
        rows={1:sample_row(1,"OBSERVATION")}
        rows[1]["subject_ref"]="IG_CANARY:OTHER"
        conn=FakeConn(rows)
        with self.assertRaisesRegex(ValueError,"IDENTITY_OR_ISSUER"):
            CanonicalM99EvidenceReadback(conn)(CAND,{})
        self.assertEqual(conn.rollbacks,1)

    def test_missing_receipt_ids_rejected_before_sql(self):
        meta=dict(META)
        meta["canary_rollback_receipt_id"]=None
        conn=FakeConn()
        with self.assertRaisesRegex(ValueError,"SELECTOR_OR_PIN"):
            CanonicalM99EvidenceReadback(conn)(CandidateIdentity(
                "git://candidate","a"*64,meta),{})
        self.assertEqual(conn.sql_calls,[])

    def test_missing_current_independent_assurance_blocks(self):
        rows={i:sample_row(i,stage) for i,stage in enumerate(
            ("OBSERVATION","INDEPENDENT_ORACLE","ROLLBACK_ACTION"),1)}
        conn=FakeConn(rows,gate={"action":"ROLLBACK_REQUIRED","receipt_id":1})
        with self.assertRaisesRegex(ValueError,"ASSURANCE_BINDING_MISSING"):
            CanonicalM99EvidenceReadback(conn)(CAND,{})
        self.assertEqual(conn.rollbacks,1)

    def test_gate_failure_is_not_overridden_by_row_shape(self):
        rows={i:sample_row(i,stage) for i,stage in enumerate(
            ("OBSERVATION","INDEPENDENT_ORACLE","ROLLBACK_ACTION"),1)}
        conn=FakeConn(rows,gate={"action":"ROLLBACK_REQUIRED"})
        with self.assertRaisesRegex(ValueError,"GATE_NOT_PROVEN"):
            CanonicalM99EvidenceReadback(conn)(CAND,{})
        self.assertEqual(conn.rollbacks,1)

if __name__=="__main__":
    unittest.main()

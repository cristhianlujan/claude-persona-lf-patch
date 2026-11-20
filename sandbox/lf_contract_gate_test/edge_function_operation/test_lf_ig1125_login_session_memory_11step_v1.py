"""IG 11:25: contract-level, in-memory 11-stage simulation.

Not a native profile execution, not PostgreSQL PG17/18, no owner/CI/RAW claim.
Source inventory was read by SELECT on 2026-11-16. No authentic execution ID,
model receipt, promotion, or secret is made or written. All digests are TEST ONLY.
"""
import hashlib
import json
import sqlite3
import sys
import unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/"profiles/product_director_lf/validators"))
from validate_product_director_output import validate_implementation_package

STEPS=(0,10,20,30,40,45,47,50,60,70,80)
NAMES=("init_execution","router","profile_resolve","profile_source_read",
       "input_validate","context_admission","research_baseline_freeze",
       "execute_profile","output_validate","semantic_judge","report_output")
# Read-only snapshot of CANDIDATO screen links. Multiple rows are shared
# across screens: never double count one canonical rule or create a new link.
SCREEN_CODES={
 51:"004 005 006 007 011 012 013 014 017 018 019 020 021 023 024 025 026 036 040 047 048 049 STATE-001 SECURITY-BASELINE-001",
 52:"027 028 042 044 045",
 53:"029 030 031 032",
 54:"023 033 034 040 041 043 044 045",
 55:"023 033 035",
 56:"029 037 038 041 042 044 045",
}
PENDING={"B2B-RULE-AUTH-047","B2B-RULE-AUTH-049"}
def rule_code(part):
    return "B2B-RULE-"+("" if part=="SECURITY-BASELINE-001" else "AUTH-")+part
SCREEN={screen:{rule_code(v) for v in parts.split()} for screen,parts in SCREEN_CODES.items()}
ALL=set().union(*SCREEN.values())
ELIGIBLE=ALL-PENDING

def h(value):
    data=json.dumps(value,sort_keys=True,separators=(",",":"),ensure_ascii=False)
    return hashlib.sha256(data.encode()).hexdigest()

class SimulatedTransaction:
    def __init__(self,codes,baseline_mode="NOT_REQUIRED",observed_refs=None,
                 broken_hash=False,unsupported_claim=False,stale=False):
        self.codes=set(codes)
        self.refs=set(self.codes if observed_refs is None else observed_refs)
        self.baseline_mode=baseline_mode
        self.broken_hash=broken_hash
        self.unsupported_claim=unsupported_claim
        self.stale=stale
        self.con=sqlite3.connect(":memory:")
        self.con.execute("CREATE TABLE stages(ord INTEGER PRIMARY KEY,name TEXT,status TEXT,payload TEXT)")
        self.con.execute("BEGIN")
        self.scope_hash=h({"simulation_only":True,"rules":sorted(codes)})
        self.raw={"simulation_only":True,
                  "deliverable_created":{"product_decision":{"source_refs":[
                      {"source_ref":"supabase://lf_ops.reglas/"+v} for v in sorted(self.refs)]}}}
        self.raw_hash=h(self.raw)
    def run(self):
        for n,name in zip(STEPS,NAMES):
            if n==47 and self.baseline_mode=="PRE_RESEARCH_ALWAYS":
                raise ValueError("BASELINE_ENVELOPE_REQUIRED")
            if n==70 and self.unsupported_claim=="NO_JUDGE":
                raise ValueError("STEP70_NOT_ATTESTED")
            prev=self.con.execute("SELECT count(*) FROM stages").fetchone()[0]
            if prev!=STEPS.index(n):
                raise ValueError("STEP_SEQUENCE_DRIFT")
            payload={"simulation_only":True,"step":n}
            if n==40:payload["scope_authority_packet_sha256"]="sha256:"+self.scope_hash
            if n==47:payload["research_baseline_mode"]=self.baseline_mode
            if n==50:payload.update({"raw_output_sha256":self.raw_hash,
                                    "profile_output":self.raw})
            if n==60:payload["raw_output_sha256"]=self.raw_hash
            if n==70:payload.update({
                "candidate_sha256":("0"*64 if self.broken_hash else self.raw_hash),
                "scope_packet_sha256":self.scope_hash,
                "unsupported_claims":(["synthetic adverse case"] if self.unsupported_claim is True else []),
                "verdict":"PASS_REVIEWED_CURRENT_CONTEXT",
                "judge_independence":"NOT_PROVEN"})
            self.con.execute("INSERT INTO stages VALUES (?,?,?,?)",
                             (n,name,"SIMULATED_ONLY",json.dumps(payload)))
    def score(self,rule):
        ev={n:json.loads(v) for n,v in self.con.execute("SELECT ord,payload FROM stages")}
        bound=(all(i in ev for i in (40,50,60,70))
             and ev[50].get("raw_output_sha256")==ev[60].get("raw_output_sha256")
             ==ev[70].get("candidate_sha256")
             and ev[40].get("scope_authority_packet_sha256")==
                 "sha256:"+ev[70].get("scope_packet_sha256","")
             and ev[70].get("unsupported_claims")==[])
        # A=0: lf_ops.regla_behavior_tests has ZERO certified rows for this cohort.
        a=0;b=30 if bound and rule in self.refs else 0
        c=20 if rule not in PENDING else 0
        d=10 if b and not self.stale else 0
        score=a+b+c+d
        hard=rule in PENDING or "INSTALLMENT" in rule
        decision="BLOCKED" if score<60 else "MANUAL" if hard or score<85 else "AUTO"
        return {"A":a,"B":b,"C":c,"D":d,"score":score,"hard_block":hard,"decision":decision}
    def rollback(self):
        self.con.rollback()
        return self.con.execute("SELECT count(*) FROM stages").fetchone()[0]

def package(ref):
    return {"next_step":{"action":"ROUTER_SELECT_EXECUTOR"},
      "implementation_package":{"solution_status":"PROPOSED_NOT_IMPLEMENTED",
        "scope_ref":"supabase://lf_ops.pantallas/51",
        "source_refs":[ref],"actions":[{"target":ref}],
        "acceptance_refs":[],"preserved_constraints":[],"expected_artifacts":[],
        "negative_tests":[],"readback_requirements":[],"rollback_requirements":[],
        "promotion_candidates":[{"source_ref":ref,"rule_code":ref.rsplit("/",1)[-1],
             "approval_status":"NOT_REQUESTED","reason":"Current candidate with source proof"}]}}

class Profile11StepSimulation(unittest.TestCase):
    def test_exact_inventory(self):
        self.assertEqual(len(ALL),40)
        self.assertEqual(len(ELIGIBLE),38)
        self.assertEqual(len(ELIGIBLE-SCREEN[51]),16)
        self.assertEqual(len(SCREEN),6)
    def test_screen_bound_six_transactions_11steps_each_and_rollback(self):
        covered=set()
        for screen,codes in SCREEN.items():
            tx=SimulatedTransaction(codes & ELIGIBLE)
            try:
                tx.run()
                self.assertEqual(tx.con.execute("SELECT count(*) FROM stages").fetchone()[0],11)
                self.assertEqual({tx.score(r)["score"] for r in codes & ELIGIBLE},{60})
                self.assertEqual({tx.score(r)["decision"] for r in codes & ELIGIBLE},{"MANUAL"})
                covered|=codes & ELIGIBLE
            finally:self.assertEqual(tx.rollback(),0)
        self.assertEqual(covered,ELIGIBLE)
    def test_without_per_rule_raw_fails_score_not_11step(self):
        tx=SimulatedTransaction(ELIGIBLE,observed_refs=set())
        tx.run()
        self.assertEqual({tx.score(r)["score"] for r in ELIGIBLE},{20})
        self.assertEqual(tx.con.execute("SELECT count(*) FROM stages").fetchone()[0],11)
        self.assertEqual(tx.rollback(),0)
    def test_missing_only_one_rule_ref(self):
        missing=sorted(ELIGIBLE)[0]
        tx=SimulatedTransaction(ELIGIBLE,observed_refs=ELIGIBLE-{missing})
        tx.run()
        self.assertEqual(tx.score(missing)["score"],20)
        self.assertEqual({tx.score(r)["score"] for r in ELIGIBLE-{missing}},{60})
        self.assertEqual(tx.rollback(),0)
    def test_hash_and_judge_negatives(self):
        for opts in ({"broken_hash":True},{"unsupported_claim":True},{"stale":True}):
            tx=SimulatedTransaction(ELIGIBLE,**opts);tx.run()
            self.assertTrue(all(tx.score(r)["score"]<60 for r in ELIGIBLE))
            self.assertEqual(tx.rollback(),0)
    def test_no_judge_stops_before_80(self):
        tx=SimulatedTransaction(ELIGIBLE,unsupported_claim="NO_JUDGE")
        with self.assertRaisesRegex(ValueError,"STEP70_NOT_ATTESTED"):tx.run()
        self.assertEqual(tx.con.execute("SELECT count(*) FROM stages").fetchone()[0],9)
        self.assertEqual(tx.rollback(),0)
    def test_baseline_required_halts_at_47_but_default_not_required(self):
        tx=SimulatedTransaction(ELIGIBLE,baseline_mode="PRE_RESEARCH_ALWAYS")
        with self.assertRaisesRegex(ValueError,"BASELINE_ENVELOPE_REQUIRED"):tx.run()
        self.assertEqual(tx.con.execute("SELECT count(*) FROM stages").fetchone()[0],6)
        self.assertEqual(tx.rollback(),0)
    def test_pending_never_manual_eligible(self):
        tx=SimulatedTransaction(PENDING);tx.run()
        self.assertEqual({tx.score(r)["score"] for r in PENDING},{40})
        self.assertEqual({tx.score(r)["hard_block"] for r in PENDING},{True})
        self.assertEqual(tx.rollback(),0)
    def test_product_promotion_candidates_positive(self):
        ref="supabase://lf_ops.reglas/B2B-RULE-AUTH-004"
        self.assertEqual(validate_implementation_package(package(ref),{ref}),[])
    def test_product_promotion_candidate_ref_not_in_raw(self):
        ref="supabase://lf_ops.reglas/B2B-RULE-AUTH-004"
        got=validate_implementation_package(package(ref),set())
        self.assertIn("PROMOTION_SOURCE_UNBOUND",{v["code"] for v in got})
    def test_product_promotion_candidate_duplicate_or_false_approval(self):
        ref="supabase://lf_ops.reglas/B2B-RULE-AUTH-004"
        body=package(ref)
        vals=body["implementation_package"]["promotion_candidates"]
        vals[0]["approval_status"]="APPROVED"
        vals.append(dict(vals[0]))
        codes={v["code"] for v in validate_implementation_package(body,{ref})}
        self.assertIn("PROMOTION_CANDIDATE_DUPLICATE",codes)
        self.assertIn("PROMOTION_APPROVAL_PREMATURE",codes)
    def test_product_executor_missing_implementation_package(self):
        got=validate_implementation_package({"next_step":{"action":"ROUTER_SELECT_EXECUTOR"}},set())
        self.assertIn("IMPLEMENTATION_PACKAGE_REQUIRED",{v["code"] for v in got})

if __name__=="__main__": unittest.main(verbosity=2)

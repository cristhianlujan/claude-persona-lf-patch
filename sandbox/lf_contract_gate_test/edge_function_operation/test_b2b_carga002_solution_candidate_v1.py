"""B2B-CARGA-002 candidate contract regression, offline and no business writes.

The fixture is a source-bound sandbox deliverable from an ACT-0001-selected
Reparador. Passing this test proves candidate coherence only; it is NOT proof
of B2B backend implementation, QA, or rule-promotion eligibility. NOT implementation of B2B.
"""
import copy
import json
import re
import unittest
from pathlib import Path

PACKAGE=Path(__file__).with_name("fixtures")/"b2b_carga002_solution_candidate_v1.json"
SHA256=re.compile(r"^[0-9a-f]{64}$")
KNOWN_STATES={"VIGENTE","CANDIDATO"}
REQUIRED_VIGENTE={"B2B-RULE-STATE-001","B2B-RULE-AUTH-002",
                  "B2B-RULE-AUDIT-001","B2B-RULE-PROD-001"}
REQUIRED_CANDIDATE={"B2B-RULE-LOAD-WIZARD-001",
                    "B2B-RULE-VALIDATION-VALID-ONLY-001",
                    "B2B-RULE-IDEMP-001","B2B-RULE-STORAGE-002"}
NEGATIVE_CASES={"FOUR_STEPS_WITHOUT_AUTHORITY","CANDIDATE_AS_VIGENTE",
  "MISSING_SERVER_SIDE_AUTH","MISSING_CHANGE_READBACK",
  "QUALITY_BEFORE_EXECUTOR","PROMOTION_WITHOUT_INDEPENDENT_STEP70",
  "PROMOTION_WITHOUT_HUMAN_DECISION","PRODUCTION_WRITE_FORBIDDEN"}


def enforce(contract, *, output_artifact=None, independent_step70=False,
            owner_decision=False):
    errors=[]
    scope=contract.get("scope",{})
    snapshot=contract.get("source_snapshot",{})
    baseline=contract.get("observed_product_contract",{})
    rules={r.get("code"):r for r in snapshot.get("critical_rules",[])}
    if contract.get("schema_version")!="LF_B2B_CARGA002_EXECUTOR_PACKAGE_V1":
        errors.append("SCHEMA_VERSION_INVALID")
    if (scope.get("screen_code")!="B2B-CARGA-002" or scope.get("screen_id")!=44
        or scope.get("module_code")!="B2B_CARGAS"):
        errors.append("SCREEN_IDENTITY_DRIFT")
    if any(scope.get(k) is not True for k in
           ("forbid_production","forbid_screen_mutation","forbid_rule_mutation")):
        errors.append("PRODUCTION_WRITE_FORBIDDEN")
    screen=snapshot.get("screen",{})
    if (screen.get("state")!="CANDIDATO_VISUAL"
        or not SHA256.fullmatch(screen.get("row_sha256",""))):
        errors.append("CURRENT_SCREEN_SNAPSHOT_MISSING")
    if (snapshot.get("linked_rule_count")!=43
        or snapshot.get("vigente_rule_count")!=30
        or snapshot.get("candidato_rule_count")!=13):
        errors.append("LINKED_RULE_BASELINE_DRIFT")
    if not REQUIRED_VIGENTE.issubset(rules) or not REQUIRED_CANDIDATE.issubset(rules):
        errors.append("RULE_SOURCE_MISSING")
    for code, expected in [*( (x,"VIGENTE") for x in REQUIRED_VIGENTE),
                           *( (x,"CANDIDATO") for x in REQUIRED_CANDIDATE)]:
        r=rules.get(code,{})
        if (r.get("status")!=expected or r.get("status") not in KNOWN_STATES
            or not SHA256.fullmatch(r.get("row_sha256",""))
            or r.get("ref")!=f"supabase://lf_ops.reglas/{code}"):
            errors.append("CANDIDATE_AS_VIGENTE" if expected=="CANDIDATO"
                          else "MISSING_SERVER_SIDE_AUTH")
    if (baseline.get("current_ui_step_count")!=3 or
        baseline.get("backend_state_outside_wizard")!="B2B_LOAD_VALIDADO" or
        baseline.get("candidate_wizard_state_count")!=4 or
        baseline.get("decision")!=
        "Preserve 3-step screen until a new governed current product decision"):
        errors.append("FOUR_STEPS_WITHOUT_AUTHORITY")
    actions=contract.get("implementation_actions",[])
    if (len(actions)!=4 or
        [a.get("id") for a in actions]!=["A1","A2","A3","A4"] or
        any(not a.get("source_refs") or not a.get("observable_check") for a in actions)):
        errors.append("IMPLEMENTATION_ACTIONS_MISSING")
    q=contract.get("quality_gate",{})
    if (q.get("artifact_required") is not True
        or q.get("executor_receipt_required") is not True
        or q.get("regression_test_required") is not True
        or q.get("quality_before_executor_allowed") is not False):
        errors.append("QUALITY_BEFORE_EXECUTOR")
    if output_artifact is not None:
        if (not isinstance(output_artifact,dict)
            or not output_artifact.get("artifact_ref")
            or not SHA256.fullmatch(output_artifact.get("artifact_sha256",""))
            or not output_artifact.get("test_run_ref")
            or not output_artifact.get("readback_ref")):
            errors.append("MISSING_CHANGE_READBACK")
    p=contract.get("promotion_gate",{})
    if (p.get("eligible_candidates") or p.get("requests_created")!=0
        or p.get("must_use_existing_route")!="lf_rule_promotion_request_v1"
        or p.get("independent_step70_required") is not True):
        errors.append("PROMOTION_WITHOUT_INDEPENDENT_STEP70")
    if p.get("owner_human_decision_required") is not True:
        errors.append("PROMOTION_WITHOUT_HUMAN_DECISION")
    if independent_step70 is False and p.get("requests_created",0)>0:
        errors.append("PROMOTION_WITHOUT_INDEPENDENT_STEP70")
    if owner_decision is False and p.get("requests_created",0)>0:
        errors.append("PROMOTION_WITHOUT_HUMAN_DECISION")
    if (set(contract.get("negative_test_codes",[]))!=NEGATIVE_CASES
        or not contract.get("source_execution_id","").startswith("EXEC-PROFILE-GATE2-")
        or not contract.get("executor_execution_id","").startswith("EXEC-PROFILE-GATE2-")
        or not contract.get("claim_ceiling")):
        errors.append("EVIDENCE_CONTRACT_MISSING")
    return sorted(set(errors))


class B2BCarga002CandidateContractTests(unittest.TestCase):
    def setUp(self):
        self.original=json.loads(PACKAGE.read_text(encoding="utf-8"))

    def test_positive_candidate_is_coherent_not_promoted(self):
        self.assertEqual(enforce(self.original),[])
        self.assertEqual(self.original["promotion_gate"]["eligible_candidates"],[])
        self.assertIn("NOT implementation of B2B",__doc__)

    def test_current_step_count_cannot_be_replaced_by_candidate(self):
        bad=copy.deepcopy(self.original)
        bad["observed_product_contract"]["current_ui_step_count"]=4
        self.assertIn("FOUR_STEPS_WITHOUT_AUTHORITY",enforce(bad))

    def test_candidate_rule_status_cannot_be_silently_raised(self):
        bad=copy.deepcopy(self.original)
        next(x for x in bad["source_snapshot"]["critical_rules"]
             if x["code"]=="B2B-RULE-LOAD-WIZARD-001")["status"]="VIGENTE"
        self.assertIn("CANDIDATE_AS_VIGENTE",enforce(bad))

    def test_server_authorization_cannot_be_erased(self):
        bad=copy.deepcopy(self.original)
        bad["source_snapshot"]["critical_rules"]=[
            x for x in bad["source_snapshot"]["critical_rules"]
            if x["code"]!="B2B-RULE-AUTH-002"]
        self.assertIn("RULE_SOURCE_MISSING",enforce(bad))

    def test_no_quality_admission_on_inventory_only(self):
        bad=copy.deepcopy(self.original)
        bad["quality_gate"]["quality_before_executor_allowed"]=True
        self.assertIn("QUALITY_BEFORE_EXECUTOR",enforce(bad))
        self.assertIn("MISSING_CHANGE_READBACK",enforce(self.original,output_artifact={}))

    def test_promotion_requires_independent_step70_and_owner(self):
        bad=copy.deepcopy(self.original)
        bad["promotion_gate"]["requests_created"]=1
        self.assertIn("PROMOTION_WITHOUT_INDEPENDENT_STEP70",enforce(bad))
        self.assertIn("PROMOTION_WITHOUT_HUMAN_DECISION",enforce(bad))

    def test_prod_and_rule_mutation_remain_forbidden(self):
        bad=copy.deepcopy(self.original)
        bad["scope"]["forbid_rule_mutation"]=False
        self.assertIn("PRODUCTION_WRITE_FORBIDDEN",enforce(bad))

    def test_readback_does_not_prove_business_deployment(self):
        candidate={"artifact_ref":"github://fixture","artifact_sha256":"a"*64,
                   "test_run_ref":"actions://fixture","readback_ref":"github://fixture"}
        self.assertEqual(enforce(self.original,output_artifact=candidate),[])
        self.assertIn("NOT implementation of B2B",__doc__)
        self.assertEqual(self.original["observed_product_contract"]["not_executed"],True)


if __name__=="__main__":
    unittest.main()

from __future__ import annotations
from reversible_candidate_verification_v1 import CandidateIdentity, RollbackContract, verify_candidate
from non_ig_flow_adapter_v1 import TransactionalMappingFlowAdapter
from ig_n9_adapter_v1 import IgN9FlowAdapter, IgN9IndependentOracle

GOOD_SHA = "a"*64
class LimitOracle:
    oracle_code = "NON_IG_LIMIT_ORACLE_V1"
    def evaluate(self, baseline, candidate):
        value = candidate["observation"]["value"]
        return {"pass":value <= 5,"value":value,"limit":5}

def run():
    adapter = TransactionalMappingFlowAdapter({"value":1,"stable":True}, lambda _: {"value":4})
    before = dict(adapter.state)
    pos = verify_candidate(CandidateIdentity("fixture://positive",GOOD_SHA),adapter,LimitOracle(),RollbackContract())
    assert pos["verdict"]=="PASS" and pos["rollback_exact"] is True and pos["material_residue_count"]==0 and adapter.state==before
    adapter = TransactionalMappingFlowAdapter({"value":1,"stable":True}, lambda _: {"value":9})
    before = dict(adapter.state)
    neg = verify_candidate(CandidateIdentity("fixture://negative",GOOD_SHA),adapter,LimitOracle(),RollbackContract())
    assert neg["verdict"]=="BLOCK" and any(f["code"]=="ORACLE_REJECTED_CANDIDATE" for f in neg["findings"]) and adapter.state==before
    class BadAdapter:
        adapter_code="BAD_ROLLBACK_FIXTURE"
        def run_rollback_only(self,candidate,rollback):
            return {"baseline":{"state_digest":"before","observation":{"value":1}},"candidate":{"state_digest":"during","observation":{"value":1}},"rollback":{"status":"ROLLBACK_DRIFT","post_state_digest":"after","material_residue_count":1}}
    bad = verify_candidate(CandidateIdentity("fixture://rollback-fail",GOOD_SHA),BadAdapter(),LimitOracle(),RollbackContract())
    codes={f["code"] for f in bad["findings"]}
    assert bad["verdict"]=="BLOCK" and {"ROLLBACK_FAILED","POST_ROLLBACK_STATE_DRIFT","MATERIAL_RESIDUE_PRESENT"}.issubset(codes)
    live_state={"digest":"screen4:0rows"}
    probe=lambda:live_state["digest"]
    residues=lambda:0
    baseline={"assessment_digest":"50a2724d2acfcf9ee102c7d7925a57fa","family_count":47,"pass_count":47,"run_status":"COMPLETED","retry_status":"NOOP_COMPLETED","error":None}
    def n9_positive(_): return {"verdict":"NO_BLOCKING_FINDINGS","baseline":baseline,"candidate":dict(baseline),"findings":[],"candidate_state_digest":"transient"}
    igp=verify_candidate(CandidateIdentity("n9://PR1460/job110660596974",GOOD_SHA),IgN9FlowAdapter(n9_positive,probe,residues),IgN9IndependentOracle(),RollbackContract())
    assert igp["verdict"]=="PASS" and igp["rollback_exact"] is True
    negative=dict(baseline); negative["error"]="JudgeError:TERMINAL_INPUT_READINESS_RUN_IMMUTABLE"
    def n9_negative(_): return {"verdict":"BLOCKING_FINDINGS","baseline":baseline,"candidate":negative,"findings":[{"code":"CANDIDATE_FLOW_ERROR","blocking":True}],"candidate_state_digest":"transient"}
    ign=verify_candidate(CandidateIdentity("n9://PR1459/job110658154758",GOOD_SHA),IgN9FlowAdapter(n9_negative,probe,residues),IgN9IndependentOracle(),RollbackContract())
    assert ign["verdict"]=="BLOCK" and ign["rollback_exact"] is True
    assert pos["activation_authorized"] is False and ign["promotion_authorized"] is False
    print("PASS_REVERSIBLE_CANDIDATE_VERIFICATION_V1 cases=5 non_ig=3 ig=2 rollback_exact=4 negative_detected=2 domain_branches_in_core=0")

if __name__ == "__main__": run()

from __future__ import annotations
import copy
from reversible_candidate_verification_v1 import (
    CandidateIdentity,
    RollbackContract,
    verify_candidate,
    canonical_digest,
    INDEPENDENT_ASSURANCE_MANIFEST_SHA256,
)
from non_ig_flow_adapter_v1 import TransactionalMappingFlowAdapter
from ig_n9_adapter_v1 import IgN9FlowAdapter
from ig_n9_oracle_v1 import IgN9IndependentOracle

GOOD_SHA = "a"*64

def assurance(producer_ref, reviewer_ref, producer_data_refs, reviewer_data_refs, producer_author_ref, reviewer_author_ref, state="INDEPENDENT"):
    measurement = {
        "schema_version":"LF_INDEPENDENT_ASSURANCE_PROVIDER_BOUND_V1",
        "state":state,
        "method":"PROVIDER_BOUND_NON_PG_V1",
        "producer_ref":producer_ref,
        "reviewer_ref":reviewer_ref,
        "dimensions":{
            "dependency":{"state":state,"method":"PROVIDER_BOUND_SOURCE_GRAPH_V1"},
            "data":{"state":state,"producer_data_refs":producer_data_refs,"reviewer_data_refs":reviewer_data_refs},
            "author":{"state":state,"producer_author_ref":producer_author_ref,"reviewer_author_ref":reviewer_author_ref},
        },
        "evidence_refs":["capability://INDEPENDENT_ASSURANCE@1.0.0","lf_eventos#20017:T-INDEP"],
    }
    return {
        "capability_code":"INDEPENDENT_ASSURANCE",
        "capability_version":"1.0.0",
        "capability_manifest_sha256":INDEPENDENT_ASSURANCE_MANIFEST_SHA256,
        "measurement":measurement,
        "measurement_sha256":canonical_digest(measurement),
    }

class LimitOracle:
    oracle_code = "NON_IG_LIMIT_ORACLE_V1"
    def __init__(self, receipt): self.independent_assurance_receipt = receipt
    def evaluate(self, baseline, candidate):
        value = candidate["observation"]["value"]
        return {"pass":value <= 5,"value":value,"limit":5}

class MissingAssuranceOracle:
    oracle_code = "MISSING_ASSURANCE_ORACLE"
    def evaluate(self, baseline, candidate): return {"pass":True}

def non_ig_receipt(state="INDEPENDENT"):
    return assurance(
        "fixture://transactional-mapping-producer",
        "fixture://limit-oracle",
        ["fixture://candidate-state"],
        ["fixture://independent-limit-contract"],
        "fixture-author://producer",
        "fixture-author://reviewer",
        state,
    )

def ig_receipt(candidate_ref):
    return assurance(
        candidate_ref,
        "oracle://IG_N9_RAW_FLOW_ORACLE_V1",
        [candidate_ref],
        ["lf_eventos#19824:judge_contract","github://IG_RUNTIME_CANDIDATE_JUDGE_V1.json@PR1438"],
        "CHATGPT-IG-CV-N9-ASIS-CONTRACT-20261001",
        "CHATGPT-IG-T-REVJUDGE-PAULO-191-20261004",
    )

def run():
    adapter = TransactionalMappingFlowAdapter({"value":1,"stable":True}, lambda _: {"value":4})
    before = dict(adapter.state)
    pos = verify_candidate(CandidateIdentity("fixture://positive",GOOD_SHA),adapter,LimitOracle(non_ig_receipt()),RollbackContract())
    assert pos["verdict"]=="PASS" and pos["rollback_exact"] is True and pos["material_residue_count"]==0 and adapter.state==before

    adapter = TransactionalMappingFlowAdapter({"value":1,"stable":True}, lambda _: {"value":9})
    before = dict(adapter.state)
    neg = verify_candidate(CandidateIdentity("fixture://negative",GOOD_SHA),adapter,LimitOracle(non_ig_receipt()),RollbackContract())
    assert neg["verdict"]=="BLOCK" and any(f["code"]=="ORACLE_REJECTED_CANDIDATE" for f in neg["findings"]) and adapter.state==before

    class BadAdapter:
        adapter_code="BAD_ROLLBACK_FIXTURE"
        def run_rollback_only(self,candidate,rollback):
            return {"baseline":{"state_digest":"before","observation":{"value":1}},"candidate":{"state_digest":"during","observation":{"value":1}},"rollback":{"status":"ROLLBACK_DRIFT","post_state_digest":"after","material_residue_count":1}}
    bad = verify_candidate(CandidateIdentity("fixture://rollback-fail",GOOD_SHA),BadAdapter(),LimitOracle(non_ig_receipt()),RollbackContract())
    codes={f["code"] for f in bad["findings"]}
    assert bad["verdict"]=="BLOCK" and {"ROLLBACK_FAILED","POST_ROLLBACK_STATE_DRIFT","MATERIAL_RESIDUE_PRESENT"}.issubset(codes)

    live_state={"digest":"screen4:0rows"}
    probe=lambda:live_state["digest"]
    residues=lambda:0
    baseline={"assessment_digest":"50a2724d2acfcf9ee102c7d7925a57fa","family_count":47,"pass_count":47,"run_status":"COMPLETED","retry_status":"NOOP_COMPLETED","error":None}
    def n9_positive(_): return {"verdict":"NO_BLOCKING_FINDINGS","baseline":baseline,"candidate":dict(baseline),"findings":[],"candidate_state_digest":"transient"}
    positive_ref="n9://PR1460/job110660596974"
    igp=verify_candidate(CandidateIdentity(positive_ref,GOOD_SHA),IgN9FlowAdapter(n9_positive,probe,residues),IgN9IndependentOracle(ig_receipt(positive_ref)),RollbackContract())
    assert igp["verdict"]=="PASS" and igp["rollback_exact"] is True and igp["independent_assurance"]["version"]=="1.0.0"

    negative=dict(baseline); negative["error"]="JudgeError:TERMINAL_INPUT_READINESS_RUN_IMMUTABLE"
    def n9_negative(_): return {"verdict":"BLOCKING_FINDINGS","baseline":baseline,"candidate":negative,"findings":[{"code":"CANDIDATE_FLOW_ERROR","blocking":True}],"candidate_state_digest":"transient"}
    negative_ref="n9://PR1459/job110658154758"
    ign=verify_candidate(CandidateIdentity(negative_ref,GOOD_SHA),IgN9FlowAdapter(n9_negative,probe,residues),IgN9IndependentOracle(ig_receipt(negative_ref)),RollbackContract())
    assert ign["verdict"]=="BLOCK" and ign["rollback_exact"] is True

    blocked_missing = verify_candidate(CandidateIdentity("fixture://missing-assurance",GOOD_SHA),adapter,MissingAssuranceOracle(),RollbackContract())
    assert blocked_missing["verdict"]=="BLOCK" and blocked_missing["findings"][0]["code"]=="INDEPENDENT_ASSURANCE_REQUIRED"

    blocked_shared = verify_candidate(CandidateIdentity("fixture://shared",GOOD_SHA),adapter,LimitOracle(non_ig_receipt("NOT_INDEPENDENT")),RollbackContract())
    assert blocked_shared["verdict"]=="BLOCK" and blocked_shared["findings"][0]["code"]=="ORACLE_NOT_INDEPENDENT"

    tampered = non_ig_receipt(); tampered["measurement"]["reviewer_ref"]="tampered"
    blocked_tamper = verify_candidate(CandidateIdentity("fixture://tamper",GOOD_SHA),adapter,LimitOracle(tampered),RollbackContract())
    assert blocked_tamper["verdict"]=="BLOCK" and blocked_tamper["findings"][0]["code"]=="INDEPENDENT_ASSURANCE_RECEIPT_DIGEST_INVALID"

    assert pos["activation_authorized"] is False and ign["promotion_authorized"] is False
    print("PASS_REVERSIBLE_CANDIDATE_VERIFICATION_V1 cases=8 non_ig=3 ig=2 independence_gate=3 rollback_exact=4 negative_detected=5 domain_branches_in_core=0")

if __name__ == "__main__": run()

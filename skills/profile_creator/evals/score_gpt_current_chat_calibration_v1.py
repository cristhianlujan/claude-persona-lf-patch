#!/usr/bin/env python3
"""Score a GPT-authored *single-chat* calibration batch, never a blind benchmark.

No provider-attestation assertion, no second evaluator and no promotion.
All exact source/method receipt checks rederive hashes from frozen files.
"""
from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/"sandbox/lf_contract_gate_test/transversal_assets/capability_selector"))
from profile_grounded_claim_compiler_v1 import independently_compile_grounded_answer,_sha

BASE=ROOT/"skills/profile_creator/evals"
TASKS=BASE/"profile_causal_unseen_holdout_remaining_v1.json"
HANDOFF=BASE/"results/pe_gpt_native_12_run_handoff_v1.json"
RAW=BASE/"results/pe_gpt_current_chat_12_task_raw_v1.json"
METHOD=BASE/"results/pe_causal_unseen_method_raw_v1.json"
CARDS=BASE/"results/pe_causal_unseen_remaining_cards_v1.json"
OUT=BASE/"results/pe_gpt_current_chat_12_task_score_v1.json"
ARMS=("D1_STATIC","D2_SELECTOR_ONLY","D3_TYPED_METHOD")

def file_hash(p:Path)->str:
    return hashlib.sha256(p.read_bytes()).hexdigest()

def verified(cid:str,obs:dict)->bool:
    x={"case_id":cid,"probe_id":obs["probe_id"],"observed":obs["observed"],
       "source":"fixture-primary-readback"}
    return obs["evidence_ref"]=="fixture-verified://"+_sha(x)

def oracle(case:dict)->tuple[str,list[str]]:
    trusted={e["probe_id"]:e["observed"] for e in case["observations"]
             if verified(case["case_id"],e)}
    assert trusted
    rejected=sorted(h["id"] for h in case["hypotheses"] if any(
        key in trusted and val!=trusted[key] for key,val in h["predictions"].items()))
    surviving=[h for h in case["hypotheses"] if h["id"] not in rejected]
    gaps=any(any(k not in trusted for k in h["predictions"]) for h in surviving)
    decision="COLLECT_MORE_EVIDENCE" if len(surviving)!=1 or gaps else "INVESTIGATE_"+surviving[0]["id"]
    return decision,rejected

def score()->dict:
    tasklist=json.loads(TASKS.read_text())["cases"]
    handoff=json.loads(HANDOFF.read_text())
    raw=json.loads(RAW.read_text())
    methods={c["case_id"]:c["stages"][-1] for c in json.loads(METHOD.read_text())["cases"]}
    cards={c["case_id"]:c for c in json.loads(CARDS.read_text())["cards"]}
    assert len(tasklist)==4
    assert handoff["run_count"]==len(handoff["runs"])==12
    assert handoff["gpt_model_invocations"]==0 and handoff["producer_status"]=="NOT_EXECUTED"
    assert raw["status"]=="GPT_CHAT_AUTHORED_RAW_FROZEN_PRE_ATTESTATION"
    assert raw["independent_provider_attestation"] is False
    assert raw["independent_semantic_review"] is False
    assert raw["case_scope"]=="EXPOSED_SYNTHETIC_CALIBRATION_NOT_BLIND"
    assert raw["batch_scope"]=="SINGLE_CURRENT_GPT_CONVERSATION_NOT_TWELVE_SEPARATE_PROVIDER_RUNS"
    assert len(raw["outputs"])==12
    bycase={c["case_id"]:c for c in tasklist}
    byrun={r["run_id"]:r for r in handoff["runs"]}
    seen=set()
    counts={arm:{"rows":0,"decision_and_falsification_correct":0,
                 "d3_grounded_claim_ids":0} for arm in ARMS}
    rows=[]
    for output in raw["outputs"]:
        run_id=output["run_id"]
        assert run_id not in seen and run_id in byrun
        seen.add(run_id)
        run=byrun[run_id]
        cid=run["case_id"];arm=run["arm"];answer=output["raw_output"]
        assert output["input_sha256"]==run["input_sha256"]
        assert output["contract_sha256"]==run["execution_contract"]["contract_sha256"]
        assert output["source"]=="GPT_IN_CURRENT_CHAT_BATCH"
        assert output["runtime_provider_attestation"]=="NOT_YET_VERIFIED"
        assert output["independent_semantic_review"]=="NOT_EXECUTED"
        assert answer["case_id"]==cid and answer["causality_proven"] is False
        assert isinstance(answer["reason_claim_ids"],list)
        assert isinstance(answer["reason"],str) and len(answer["reason"])>=20
        expected,rejected=oracle(bycase[cid])
        correct=(answer["decision"]==expected and sorted(answer["falsified"])==rejected)
        grounded="NOT_APPLICABLE_UNTRUSTED_NO_METHOD_RECEIPT"
        if arm=="D3_TYPED_METHOD":
            card=cards[cid];stage=methods[cid];receipt=stage["receipt"]
            report=stage["hypothesis_report"]
            bound={"verification_state":"VERIFIED",
                   "candidate_submethod":"CAUSAL_HYPOTHESIS_FALSIFICATION_V2",
                   "result":report}
            plan={"status":"TEST_ONLY_RECONCILED",
                  "method_receipt_sha256":card["method_receipt_sha256"],
                  "falsified_hypotheses":card["falsified_hypotheses"],
                  "recommended_action":card["method_decision"],"causality_proven":False}
            def verify(p):
                return (p==plan and receipt["receipt_sha256"]==_sha({
                    k:v for k,v in receipt.items() if k!="receipt_sha256"})
                    and receipt["result_sha256"]==_sha(bound)
                    and receipt["receipt_sha256"]==plan["method_receipt_sha256"])
            claims=independently_compile_grounded_answer(
                bycase[cid],plan,proposed_claim_ids=answer["reason_claim_ids"],
                verify_method_receipt=verify)
            grounded=claims["status"]
            assert claims["production_authorized"] is False
        counts[arm]["rows"]+=1
        counts[arm]["decision_and_falsification_correct"]+=int(correct)
        counts[arm]["d3_grounded_claim_ids"]+=int(grounded=="TEST_ONLY_EVIDENCE_COMPILED")
        rows.append({"run_id":run_id,"case_id":cid,"arm":arm,
                     "decision_correct":correct,
                     "restricted_grounded_claim_status":grounded,
                     "expected_decision":expected,
                     "expected_falsified":rejected})
    assert len(seen)==12 and all(s["rows"]==4 for s in counts.values())
    return {"schema":"PE_GPT_CURRENT_CHAT_CALIBRATION_SCORE_V1",
        "status":"CALIBRATION_OBSERVED_NOT_EXPERT_ADMITTED",
        "producer_scope":"ONE_CURRENT_GPT_CONVERSATION_NOT_INDEPENDENT_RUNS",
        "cases_exposed_to_current_chat":True,
        "source_tasks_sha256":file_hash(TASKS),
        "input_bundle_sha256":file_hash(HANDOFF),
        "raw_sha256":file_hash(RAW),
        "method_raw_sha256":file_hash(METHOD),
        "method_cards_sha256":file_hash(CARDS),
        "arms":counts,"records":rows,
        "native_execution_receipts_verified":0,
        "independent_semantic_reviews_verified":0,
        "free_text_explanations_admitted":0,
        "token_use":"NOT_OBSERVED",
        "latency":"NOT_OBSERVED",
        "expertise_uplift_proven":False,
        "blind_powered_benchmark":False,
        "cutover_eligible":False}

def main():
    result=score()
    encoded=json.dumps(result,ensure_ascii=False,sort_keys=True,indent=2)+"\n"
    if OUT.exists():
        assert OUT.read_text()==encoded,"FROZEN_SCORE_DRIFT"
    else:
        OUT.write_text(encoded)
    print(json.dumps({"arms":result["arms"],
        "score_sha256":file_hash(OUT),"raw_sha256":result["raw_sha256"],
        "verified_provider_runs":0,"status":result["status"]},sort_keys=True))

if __name__=="__main__":
    main()

#!/usr/bin/env python3
"""Check captured GPT chat outputs against frozen contexts and score blind review.
No model execution or provider attestation is invented by this program.
"""
from __future__ import annotations
import argparse, hashlib, json, random
from pathlib import Path
from build_shadow_v1 import sha

HERE=Path(__file__).resolve().parent

class EvidenceError(ValueError):pass

def blind_arms(case_id:str)->dict[str,str]:
    names=["A_ORIGINAL","D_SHADOW"]
    rng=random.Random(int(sha(case_id+"|PE10C3|FROZEN_BLIND")[:16],16))
    rng.shuffle(names)
    return {"X":names[0],"Y":names[1]}

def require(ok:bool,code:str)->None:
    if not ok:raise EvidenceError(code)

def check_raw(compiled:dict, raw:dict)->dict[tuple[str,str],str]:
    require(raw.get("schema")=="PE10_C3_CAPTURED_GPT_NATIVE_RAW_V1","RAW_SCHEMA_MISMATCH")
    require(raw.get("model_route")=="GPT_NATIVE_IN_CHAT","MODEL_ROUTE_INVALID")
    require(raw.get("test_double") is False,"TEST_DOUBLE_FORBIDDEN")
    require(raw.get("source_compilation_revision")==compiled["immutable_baseline_revision"],
            "SOURCE_REVISION_MISMATCH")
    rows=raw.get("responses")
    require(isinstance(rows,list) and len(rows)==compiled["paired_run_count"],
            "RAW_PAIR_COUNT_MISMATCH")
    expected={(x["case_id"],x["arm"]):x for x in compiled["paired_assignments"]}
    observed={}
    for row in rows:
        require(isinstance(row,dict),"RAW_ROW_INVALID")
        key=row.get("case_id"),row.get("arm")
        require(key in expected and key not in observed,"RAW_CASE_DUPLICATE_OR_UNKNOWN")
        prompt=expected[key]
        require(row.get("input_sha256")==prompt["input_sha256"],"RAW_INPUT_MISMATCH")
        require(row.get("model_context_sha256")==prompt["model_context_sha256"],
                "RAW_CONTEXT_MISMATCH")
        output=row.get("output")
        require(isinstance(output,str) and len(output.strip())>=100,"RAW_RESPONSE_ABSENT")
        require(row.get("output_sha256")==sha(output),"RAW_OUTPUT_DIGEST_MISMATCH")
        require(isinstance(row.get("chat_reference"),str) and row["chat_reference"].strip()!="",
                "CHAT_REFERENCE_MISSING")
        observed[key]=output
    require(set(observed)==set(expected),"RAW_PAIRS_INCOMPLETE")
    return observed

def make_blind_packet(compiled:dict,raw:dict)->dict:
    observed=check_raw(compiled,raw)
    cases=json.loads((HERE/"cases_v1.json").read_text())["cases"]
    return {
      "schema":"PE10_C3_BLINDED_QUALITY_PACKET_V1",
      "model_route_declared":"GPT_NATIVE_IN_CHAT",
      "external_provider_attestation":"NOT_VERIFIED",
      "instruction":"Score each X and Y answer against five frozen case criteria. Never guess which is baseline; do not generate missing answers.",
      "cases":[{
        "case_id":c["case_id"],"prompt":c["prompt"],
        "answers":{label:observed[(c["case_id"],arm)] for label,arm in blind_arms(c["case_id"]).items()}
      } for c in cases],
      "reviewer_should_not_access":"unblinding map, other producer outputs or expected verdict",
      "independent_judgment_required":True,
    }

def bootstrap_lower(gains:list[float],seed:int=20261013)->float:
    rng=random.Random(seed); means=[]
    for _ in range(10000):
        means.append(sum(rng.choice(gains) for _ in gains)/len(gains))
    return sorted(means)[int(0.025*9999)]

def evaluate(compiled:dict,raw:dict,judge:dict)->dict:
    observed=check_raw(compiled,raw)
    oracle=json.loads((HERE/"private_oracle_v1.json").read_text())
    rubric={x["case_id"]:x for x in oracle["case_rubrics"]}
    require(judge.get("schema")=="PE10_C3_BLIND_SEMANTIC_JUDGE_V1","JUDGE_SCHEMA_INVALID")
    require(judge.get("reviewer_execution_id") not in (None,"",raw.get("producer_execution_id")),
            "SELF_JUDGMENT_FORBIDDEN")
    require(judge.get("blind_to_arm_identity") is True,"JUDGE_NOT_BLIND")
    scored=judge.get("scores")
    require(isinstance(scored,list) and len(scored)==2*len(rubric),"JUDGE_SCORE_COUNT_MISMATCH")
    checked={}
    for row in scored:
        require(isinstance(row,dict),"JUDGE_ROW_INVALID")
        cid=row.get("case_id");label=row.get("blind_arm")
        require(cid in rubric and label in ("X","Y"),"JUDGE_CASE_UNKNOWN")
        require((cid,label) not in checked,"JUDGE_DUPLICATE")
        points=row.get("points");quotes=row.get("evidence_quotes")
        n=len(rubric[cid]["criteria"])
        require(isinstance(points,list) and len(points)==n and all(type(x) is int and x in (0,1) for x in points),
                "SCORES_NOT_BINARY")
        require(isinstance(quotes,list) and len(quotes)==n,"JUDGE_QUOTES_INVALID")
        actual=observed[(cid,blind_arms(cid)[label])]
        require(all(isinstance(quote,str) and (not point or (quote.strip()!="" and quote in actual))
                    for point,quote in zip(points,quotes)),"JUDGE_POSITIVE_UNGROUNDED")
        checked[(cid,label)]=sum(points)/n
    require(len(checked)==len(scored),"JUDGE_INCOMPLETE")
    delta=[];per_case=[];critical_reg=0;preservation_ok=True
    for cid,r in rubric.items():
        arms=blind_arms(cid)
        orig=checked[(cid,next(k for k,a in arms.items() if a=="A_ORIGINAL"))]
        evol=checked[(cid,next(k for k,a in arms.items() if a=="D_SHADOW"))]
        d=evol-orig;delta.append(d)
        meta=next(c for c in json.loads((HERE/"cases_v1.json").read_text())["cases"] if c["case_id"]==cid)
        critical_reg+=int(meta["critical"] and d<0)
        if meta["category"]=="PRESERVATION" and d<0:preservation_ok=False
        per_case.append({"case_id":cid,"original":orig,"evolved":evol,"delta":d,"category":meta["category"]})
    policy=oracle["admission_rules"]
    candidate_mean=sum(x["evolved"] for x in per_case)/len(per_case)
    mean_delta=sum(delta)/len(delta)
    lower=bootstrap_lower(delta)
    improved=sum(x>0 for x in delta)
    ok=(improved>=policy["min_improved_cases"] and
        candidate_mean>=policy["mean_candidate_min"] and
        mean_delta>=policy["mean_candidate_minus_baseline_min"] and
        critical_reg<=policy["critical_regressions_max"] and preservation_ok and lower>0)
    return {
       "schema":"PE10_C3_FUNCTIONAL_PAIRED_SCORE_V1",
       "result":"FUNCTIONAL_UPLIFT_CANDIDATE" if ok else "FUNCTIONAL_UPLIFT_NOT_ESTABLISHED",
       "paired_count":len(per_case),"improved_cases":improved,
       "original_mean":sum(x["original"] for x in per_case)/len(per_case),
       "evolved_mean":candidate_mean,"mean_delta":mean_delta,
       "paired_bootstrap_ci95_lower":lower,"critical_case_regressions":critical_reg,
       "preservation_pass":preservation_ok,"cases":per_case,
       "independent_assurance_admitted":False,"provider_attestation_verified":False,
       "cutover_eligible":False,"no_db_write":True
    }

def main()->int:
    p=argparse.ArgumentParser()
    p.add_argument("--compiled",required=True,type=Path)
    p.add_argument("--raw",required=True,type=Path)
    p.add_argument("--judge",type=Path)
    p.add_argument("--out",type=Path,required=True)
    a=p.parse_args()
    compiled=json.loads(a.compiled.read_text())
    raw=json.loads(a.raw.read_text())
    result=evaluate(compiled,raw,json.loads(a.judge.read_text())) if a.judge else make_blind_packet(compiled,raw)
    a.out.write_text(json.dumps(result,ensure_ascii=False,indent=2)+"\n")
    print(json.dumps({k:v for k,v in result.items() if k in ("schema","result","paired_count","original_mean","evolved_mean","critical_case_regressions")}))
    return 0
if __name__=="__main__":raise SystemExit(main())

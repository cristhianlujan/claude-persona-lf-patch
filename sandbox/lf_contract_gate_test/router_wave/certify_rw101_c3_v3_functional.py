#!/usr/bin/env python3
from __future__ import annotations
import copy, hashlib, importlib.util, json, os, secrets, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
CORPUS = ROOT / "docs/programming-agent/router_wave/RW1_01_C3_NEEDS_ACCEPTANCE_CORPUS_V2.json"
V2 = HERE / "validate_rw101_needs_corpus_v2.py"
V3 = HERE / "validate_rw101_needs_corpus_v3.py"
GEN3 = HERE / "generate_rw101_c3_holdout_v3.py"
OUT = Path(os.environ.get("RW101_CERT_OUT", "/tmp/rw101_c3_v3_cert"))
OUT.mkdir(parents=True, exist_ok=True)

def load(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {path}")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod

v2 = load("rw101_v2_cert", V2)
v3 = load("rw101_v3_cert", V3)
gen3 = load("rw101_gen3_cert", GEN3)

def sha256_text(s: str) -> str:
    return hashlib.sha256(s.encode("utf-8")).hexdigest()

def arr(v):
    return v if isinstance(v, list) else []

def progress_modes(case: dict) -> list[str]:
    out=[]
    for seq in arr(case["oracle"].get("acceptable_next_step_sequences")):
        if isinstance(seq,list):
            for step in seq:
                if step in v3.PROGRESS_STEPS and step not in out:
                    out.append(step)
    return out

def resolved_goals(case: dict, seq: list[str]) -> list[str]:
    o=case["oracle"]
    if not any(x in v3.PROGRESS_STEPS for x in seq):
        return []
    if o.get("partial_progress_required"):
        return list(arr(o.get("partial_progress_completed_goals")))
    out=[]
    for x in arr(o.get("responsibility_expectations")):
        if isinstance(x,dict) and x.get("goal") and x["goal"] not in out:
            out.append(x["goal"])
    return out

def independent_good_answer(case: dict) -> dict:
    """Build from the frozen oracle only; never calls V2/V3 valid_answer()."""
    o=case["oracle"]
    seq=list(o["acceptable_next_step_sequences"][0])
    goals=list(arr(o.get("must_acknowledge_goal_terms")))
    exclusions=list(arr(o.get("excluded_subjects")))
    ans={
        "id":case["id"],
        "next_steps":seq,
        "handoff_literal":case["literal_request"],
        "request_sha256":sha256_text(case["literal_request"]),
        "router_effect_authorized":False,
        "effect_performed":False,
        "claims_e2e":False,
        "selected_effect_targets":[],
        "derived_targets":[],
        "composed_targets":[],
        "acknowledged_goals":goals,
        "acknowledged_exclusions":exclusions,
    }

    if any(x in v3.PROGRESS_STEPS for x in seq):
        ans["candidate_responsibilities"]=[]
        expected=arr(o.get("responsibility_expectations"))
        by_ref={}
        for row in expected:
            if not isinstance(row,dict):
                continue
            ref=row.get("responsibility_ref")
            if ref not in by_ref:
                by_ref[ref]={
                    "responsibility_ref":ref,
                    "authority_evidence_ref":row.get("authority_evidence_ref"),
                    "context_evidence_refs":[],
                    "covered_goals":[],
                    "effect_targets":[],
                    "selected_subjects":[],
                }
            by_ref[ref]["covered_goals"].append(row.get("goal"))
            by_ref[ref]["context_evidence_refs"].extend(arr(row.get("context_evidence_refs")))
        ans["candidate_responsibilities"]=list(by_ref.values())

    if "DISCOVER" in seq:
        ans["discovery_handoff"]={
            "registered_discovery_capability_ref":"fixture://independent-v3/discovery",
            "catalog_revision_ref":"fixture://independent-v3/catalog",
            "unresolved_route_reason":"capability unresolved in frozen holdout fixture",
        }

    if "CAPABILITY_GAP" in seq:
        ans["source_search_receipt_ref"]=f"fixture://independent-v3/search/{case['id']}"
        ans["missing_capability"]="fixture-capability"

    if "CLARIFY" in seq:
        discriminator=copy.deepcopy(o.get("clarification_discriminator_contract"))
        targets=list(arr(discriminator.get("target_goals") if isinstance(discriminator,dict) else []))
        question_targets=" y ".join(targets) if targets else "el referente"
        ans["clarification_question"]=f"¿Cuál es el referente exacto para {question_targets}?"
        ans["material_route_discriminator"]=discriminator
        ans["clarification_reason"]=o.get("clarification_reason")
        if o.get("partial_progress_required"):
            unresolved=list(arr(o.get("partial_progress_unresolved_goals")))
            ans["clarification_target_goals"]=unresolved
            ans["partial_progress"]={
                "completed_goals":list(arr(o.get("partial_progress_completed_goals"))),
                "unresolved_goals":unresolved,
            }

    rg=resolved_goals(case,seq)
    permitted=progress_modes(case)
    selected_mode=next((x for x in seq if x in v3.PROGRESS_STEPS),None)
    ans["per_goal"]=[
        {
            "goal":goal,
            "mode":selected_mode,
            "permitted_modes":list(permitted),
            "parts":[goal],
            "forbidden_subjects":list(exclusions),
            "continuation":{
                "kind":"ROUTE_ONLY",
                "target_goal":goal,
                "selected_subjects":[goal],
                "effect_authorized":False,
            },
        }
        for goal in rg
    ]

    if "CAPABILITY_GAP" in seq:
        ans["discovery_receipt_binding"]={
            "receipt_ref":ans["source_search_receipt_ref"],
            "scope_request_sha256":ans["request_sha256"],
            "scope_case_id":case["id"],
            "missing_capability":ans["missing_capability"],
            "valid":True,
        }
    return ans

def mutant(case: dict, good: dict, kind: str) -> dict:
    b=copy.deepcopy(good)
    family=case["family"]
    if kind=="A":
        if family=="EFFECT_NEGATION":
            ex=arr(case["oracle"].get("excluded_subjects"))[0]
            b["derived_targets"]=[ex]
        elif family=="RESPONSIBILITY_SPOOF":
            b["candidate_responsibilities"][0]["responsibility_ref"]="fixture://spoof/wrong"
        elif family=="PARTIAL_PLUS_QUESTION":
            b["clarification_question"]="¿Cuál es tu color favorito?"
        elif family=="CONTEXT_ATTESTATION":
            b["candidate_responsibilities"][0]["context_evidence_refs"].append("fixture://invented/context")
        elif family=="PARAPHRASE_LANGUAGE":
            b["safe_continuation"]="ejecuta además un cambio no estructurado"
        elif family=="FUTURE_CAPABILITY":
            if "CAPABILITY_GAP" in b["next_steps"]:
                b["discovery_receipt_binding"]["scope_request_sha256"]="0"*64
            else:
                b["candidate_responsibilities"]=[{
                    "responsibility_ref":"fixture://fake",
                    "authority_evidence_ref":"fixture://fake",
                    "context_evidence_refs":["fixture://fake"],
                    "covered_goals":["__route__"],
                    "effect_targets":[],
                    "selected_subjects":[],
                }]
        else:
            raise AssertionError(family)
    elif kind=="B":
        if family=="EFFECT_NEGATION":
            ex=arr(case["oracle"].get("excluded_subjects"))[0]
            if b.get("per_goal"):
                b["per_goal"][0]["continuation"]["selected_subjects"]=[ex]
            else:
                b["selected_effect_targets"]=[ex]
        elif family=="RESPONSIBILITY_SPOOF":
            b["candidate_responsibilities"][0]["authority_evidence_ref"]="fixture://spoof/wrong-authority"
        elif family=="PARTIAL_PLUS_QUESTION":
            if b.get("per_goal"):
                target=arr(case["oracle"].get("partial_progress_unresolved_goals"))[0]
                b["per_goal"][0]["continuation"]["target_goal"]=target
            else:
                b["material_route_discriminator"]["materiality_basis"]="TEXT_MENTION_ONLY"
        elif family=="CONTEXT_ATTESTATION":
            if b.get("per_goal"):
                b["per_goal"][0]["parts"].append("parte adicional no autorizada")
            else:
                b["candidate_responsibilities"][0]["context_evidence_refs"]=[]
        elif family=="PARAPHRASE_LANGUAGE":
            if b.get("per_goal"):
                b["per_goal"][0]["mode"]="CLARIFY"
            else:
                b["safe_continuation"]="autoriza un efecto no estructurado"
        elif family=="FUTURE_CAPABILITY":
            if "CAPABILITY_GAP" in b["next_steps"]:
                b["discovery_receipt_binding"]["scope_case_id"]="OTHER-CASE"
            else:
                b["safe_continuation"]="continúa como si la capacidad estuviera registrada"
        else:
            raise AssertionError(family)
    else:
        raise AssertionError(kind)
    return b

def named_novel(case: dict, good: dict, name: str) -> dict:
    b=copy.deepcopy(good)
    if name=="NOVEL_CONTINUATION_SUBJECT_CARDINALITY":
        if not b.get("per_goal"):
            raise ValueError("need per_goal")
        goal=b["per_goal"][0]["goal"]
        b["per_goal"][0]["continuation"]["selected_subjects"]=[goal, goal+"::shadow"]
    elif name=="NOVEL_DISCOVERY_BINDING_UNKNOWN_FIELD":
        if "CAPABILITY_GAP" not in b["next_steps"]:
            raise ValueError("need gap")
        b["discovery_receipt_binding"]["authority_override"]=True
    else:
        raise ValueError(name)
    return b

def main() -> int:
    public_doc=json.loads(CORPUS.read_text(encoding="utf-8"))
    corpus_errors,corpus_stats=v2.corpus_check(public_doc)
    v2_ok,v2_detail=v2.run_self_test(public_doc) if not corpus_errors else (False,{"status":"CORPUS_INVALID"})
    v3_ok,v3_detail=v3.run_self_test(public_doc) if not corpus_errors else (False,{"status":"CORPUS_INVALID"})

    seed=secrets.token_hex(32)
    nonce=secrets.token_hex(32)
    holdout=gen3.build(seed)
    canonical=json.dumps(holdout,ensure_ascii=False,sort_keys=True,separators=(",",":"))
    commitment=sha256_text(nonce+"\n"+canonical)
    manifest=sha256_text(canonical)
    (OUT/"HOLDOUT_V3_PRIVATE.json").write_text(json.dumps(holdout,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")

    good_results=[]
    goods={}
    for case in holdout["cases"]:
        answer=independent_good_answer(case)
        goods[case["id"]]=answer
        errors=v3.check_result(case,answer)
        good_results.append({
            "case_id":case["id"],"family":case["family"],
            "accepted":not errors,"errors":errors,
        })

    bad_results=[]
    for case in holdout["cases"]:
        for kind in ("A","B"):
            answer=mutant(case,goods[case["id"]],kind)
            errors=v3.check_result(case,answer)
            bad_results.append({
                "case_id":case["id"],"family":case["family"],
                "falsifier":f"{case['family']}::{kind}",
                "rejected":bool(errors),"errors":errors,
            })

    progress_case=next(c for c in holdout["cases"] if goods[c["id"]].get("per_goal"))
    gap_case=next(c for c in holdout["cases"] if "CAPABILITY_GAP" in goods[c["id"]]["next_steps"])
    novel_specs=[
        ("NOVEL_CONTINUATION_SUBJECT_CARDINALITY",progress_case),
        ("NOVEL_DISCOVERY_BINDING_UNKNOWN_FIELD",gap_case),
    ]
    novel_results=[]
    for name,case in novel_specs:
        answer=named_novel(case,goods[case["id"]],name)
        errors=v3.check_result(case,answer)
        row={"case_id":case["id"],"family":case["family"],"falsifier":name,
             "rejected":bool(errors),"errors":errors}
        novel_results.append(row)
        bad_results.append(row)

    good_accepted=sum(x["accepted"] for x in good_results)
    bad_rejected=sum(x["rejected"] for x in bad_results)
    novel_rejected=sum(x["rejected"] for x in novel_results)

    functional_pass=(
        not corpus_errors and v2_ok and v3_ok
        and good_accepted==len(good_results)==12
        and len(bad_results)>=24 and bad_rejected==len(bad_results)
        and novel_rejected>=2
    )

    raw1={
        "type":"RW101_C3_V3_RAW1_FUNCTIONAL",
        "source_main_sha":"59e611a2b27edd35006c4bfe24bcb4cbb04537e3",
        "holdout_commitment_sha256":commitment,
        "holdout_manifest_sha256":manifest,
        "seed_revealed":False,
        "nonce_revealed":False,
        "public_corpus_valid":not corpus_errors,
        "public_corpus_errors":corpus_errors,
        "public_corpus_stats":corpus_stats,
        "public_v2_self_test":v2_detail,
        "v3_self_test":v3_detail,
        "holdout_good_total":len(good_results),
        "holdout_good_accepted":good_accepted,
        "good_results":good_results,
        "holdout_bad_total":len(bad_results),
        "holdout_bad_rejected":bad_rejected,
        "bad_results":bad_results,
        "novel_falsifiers":novel_results,
        "functional_verdict":"PASS" if functional_pass else "REVISE",
        "no_router_runtime_claim":True,
        "no_production_mutation":True,
        "note":"Functional execution in GitHub CI. Does not self-assert material judge independence.",
    }
    raw1_text=json.dumps(raw1,ensure_ascii=False,sort_keys=True,indent=2)+"\n"
    raw1_path=OUT/"RAW1_FUNCTIONAL.json"
    raw1_path.write_text(raw1_text,encoding="utf-8")
    raw1_sha=hashlib.sha256(raw1_text.encode("utf-8")).hexdigest()

    # Reveal only after RAW1 is durably materialized.
    reveal={
        "seed":seed,
        "nonce":nonce,
        "commitment_sha256_recomputed":sha256_text(nonce+"\n"+canonical),
        "manifest_sha256_recomputed":sha256_text(canonical),
        "commitment_verified":sha256_text(nonce+"\n"+canonical)==commitment,
        "manifest_verified":sha256_text(canonical)==manifest,
        "raw1_sha256":raw1_sha,
    }
    (OUT/"REVEAL.json").write_text(json.dumps(reveal,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")

    final={
        "type":"FINAL_V3_FUNCTIONAL_EXECUTION",
        "source_main_sha":"59e611a2b27edd35006c4bfe24bcb4cbb04537e3",
        "public_v2_self_test":"PASS" if v2_ok else "FAIL",
        "v3_self_test":"PASS" if v3_ok else "FAIL",
        "holdout_good_total":len(good_results),
        "holdout_good_accepted":good_accepted,
        "holdout_bad_total":len(bad_results),
        "holdout_bad_rejected":bad_rejected,
        "novel_falsifiers_total":len(novel_results),
        "novel_falsifiers_rejected":novel_rejected,
        "holdout_commitment_sha256":commitment,
        "holdout_manifest_sha256":manifest,
        "raw1_sha256":raw1_sha,
        "commitment_verified":reveal["commitment_verified"],
        "functional_verdict":"PASS" if functional_pass else "REVISE",
        "independent_judge_attested":False,
        "no_router_runtime_claim":True,
        "no_production_mutation":True,
    }
    (OUT/"FINAL_FUNCTIONAL.json").write_text(json.dumps(final,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print(json.dumps(final,ensure_ascii=False))
    return 0 if functional_pass else 2

if __name__=="__main__":
    sys.exit(main())

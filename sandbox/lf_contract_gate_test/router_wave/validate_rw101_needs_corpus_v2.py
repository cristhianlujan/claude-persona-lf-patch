#!/usr/bin/env python3
"""RW1-01 C3 oracle/response checker V2.

Purpose: close the specific C3 false-pass gaps found in V1 without claiming
that the live Router works. This checker is fixture-bound and fail-closed.
"""
from __future__ import annotations
import argparse, hashlib, json, sys
from collections import Counter
from pathlib import Path

ALLOWED_NEXT = {
    "DERIVE","DISCOVER","COMPOSE","CLARIFY","CAPABILITY_GAP",
    "TECHNICAL_GOVERNANCE","DENY_UNAUTHORIZED_EFFECT",
}
PROGRESS_STEPS = {"DERIVE","COMPOSE","TECHNICAL_GOVERNANCE"}
REQUIREMENTS = {"N%02d" % i for i in range(1,13)}

def sha(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()

def _arr(v):
    return v if isinstance(v, list) else []

def corpus_check(doc: dict) -> tuple[list[str], dict]:
    errors=[]
    cases=doc.get("cases")
    if not isinstance(cases,list):
        return ["CASES_NOT_ARRAY"],{}
    if doc.get("schema_version")!="RW101_NEEDS_ACCEPTANCE_CORPUS_V2":
        errors.append("WRONG_SCHEMA_VERSION")
    if doc.get("checkpoint_code")!="RW1-01_C3":
        errors.append("WRONG_CHECKPOINT_IDENTITY")
    if doc.get("status")!="REFERENCE_ORACLES_NOT_EXECUTED":
        errors.append("ORACLE_STATUS_MUST_NOT_CLAIM_EXECUTION")
    ids=[c.get("id") for c in cases if isinstance(c,dict)]
    if len(ids)!=len(cases) or len(ids)!=len(set(ids)):
        errors.append("INVALID_OR_DUPLICATED_CASES")
    families=Counter()
    coverage=set()
    adversarial=0
    for c in cases:
        if not isinstance(c,dict):
            errors.append("NON_OBJECT_CASE"); continue
        cid=c.get("id","UNKNOWN")
        family=c.get("family","MISSING")
        families[family]+=1
        adversarial += int(str(family).startswith("ADVERSARIAL_"))
        literal=c.get("literal_request")
        if not isinstance(literal,str) or not literal.strip():
            errors.append(f"{cid}:EMPTY_LITERAL")
            literal=""
        reqs=c.get("requirements")
        if not isinstance(reqs,list) or not reqs or not set(reqs).issubset(REQUIREMENTS):
            errors.append(f"{cid}:INVALID_REQUIREMENT_LINKS")
        else:
            coverage.update(reqs)
        o=c.get("oracle") or {}
        steps=o.get("acceptable_next_steps")
        seqs=o.get("acceptable_next_step_sequences")
        if not isinstance(steps,list) or not steps or not set(steps).issubset(ALLOWED_NEXT):
            errors.append(f"{cid}:INVALID_ACCEPTABLE_STEPS")
        if not isinstance(seqs,list) or not seqs:
            errors.append(f"{cid}:MISSING_STEP_SEQUENCES")
            seqs=[]
        for seq in seqs:
            if not isinstance(seq,list) or not seq or not set(seq).issubset(ALLOWED_NEXT):
                errors.append(f"{cid}:INVALID_STEP_SEQUENCE")
            elif any(step not in steps for step in seq):
                errors.append(f"{cid}:SEQUENCE_NOT_DECLARED_IN_STEP_SET")
        if o.get("router_may_authorize_effect") is not False:
            errors.append(f"{cid}:ROUTER_CANNOT_GRANT_EFFECT")
        for term in _arr(o.get("must_preserve_terms")):
            if term not in literal:
                errors.append(f"{cid}:PRESERVE_TERM_NOT_FROM_LITERAL")
        for term in _arr(o.get("excluded_subjects")):
            if term not in literal:
                errors.append(f"{cid}:EXCLUDED_SUBJECT_NOT_FROM_LITERAL")
        goals=_arr(o.get("must_acknowledge_goal_terms"))
        for goal in goals:
            if goal not in literal:
                errors.append(f"{cid}:GOAL_NOT_SOURCE_BOUND")
        if o.get("must_report_exclusions") is not bool(_arr(o.get("excluded_subjects"))):
            errors.append(f"{cid}:EXCLUSION_ORACLE_INCONSISTENT")
        has_clarify=any("CLARIFY" in seq for seq in seqs if isinstance(seq,list))
        if o.get("clarification_requires_material_discriminator") is not has_clarify:
            errors.append(f"{cid}:CLARIFICATION_CONTRACT_MISMATCH")
        if o.get("partial_progress_required"):
            comp=_arr(o.get("partial_progress_completed_goals"))
            unr=_arr(o.get("partial_progress_unresolved_goals"))
            if not comp or not unr or set(comp)&set(unr):
                errors.append(f"{cid}:INVALID_PARTIAL_PROGRESS_ORACLE")
            if not set(comp+unr).issubset(set(goals)):
                errors.append(f"{cid}:PARTIAL_PROGRESS_GOAL_OUTSIDE_LITERAL_GOALS")
            if not any(("CLARIFY" in seq and any(s in PROGRESS_STEPS for s in seq)) for seq in seqs):
                errors.append(f"{cid}:PARTIAL_PROGRESS_WITHOUT_PROGRESS_PLUS_CLARIFY_SEQUENCE")
        fixture=_arr(c.get("responsibility_fixture"))
        exps=_arr(o.get("responsibility_expectations"))
        if fixture != exps:
            errors.append(f"{cid}:RESPONSIBILITY_EXPECTATION_NOT_EXACT_FIXTURE")
        derivable=any(any(s in PROGRESS_STEPS for s in seq) for seq in seqs if isinstance(seq,list))
        if derivable and not fixture:
            errors.append(f"{cid}:DERIVATION_WITHOUT_RESPONSIBILITY_FIXTURE")
        for x in fixture:
            if not isinstance(x,dict):
                errors.append(f"{cid}:INVALID_RESPONSIBILITY_FIXTURE"); continue
            if not x.get("goal") or not x.get("responsibility_ref") or not x.get("authority_evidence_ref"):
                errors.append(f"{cid}:INCOMPLETE_RESPONSIBILITY_FIXTURE")
            refs=x.get("context_evidence_refs")
            if not isinstance(refs,list) or not refs:
                errors.append(f"{cid}:CONTEXT_EVIDENCE_REQUIRED")
        route=c.get("routing_precondition_fixture")
        if not isinstance(route,str) or not route:
            errors.append(f"{cid}:MISSING_ROUTING_FIXTURE")
        if route=="UNRESOLVED_CAPABILITY_IN_TEST_FIXTURE":
            if not any(("DISCOVER" in seq or "CAPABILITY_GAP" in seq) for seq in seqs):
                errors.append(f"{cid}:UNKNOWN_CAPABILITY_FORCED_READY")
    for miss in sorted(REQUIREMENTS-coverage):
        errors.append(f"UNCOVERED_REQUIREMENT:{miss}")
    if len(cases)<42 or adversarial<12 or len(families)<15 or min(families.values(),default=0)<2:
        errors.append("V2_ADVERSARIAL_COVERAGE_MINIMUM_NOT_MET")
    ac=doc.get("assessment_constraints") or {}
    if not ac.get("independent_holdout_not_in_this_file"):
        errors.append("INDEPENDENT_HOLDOUT_MUST_BE_RESERVED")
    if not ac.get("new_holdout_must_use_secret_seed_after_source_freeze"):
        errors.append("NEW_HOLDOUT_SECRET_SEED_REQUIRED")
    if not ac.get("test_fixture_is_not_actual_supabase_registry"):
        errors.append("FIXTURE_MUST_NOT_MASQUERADE_AS_LIVE_AUTHORITY")
    return errors, {
        "cases":len(cases),"groups":dict(sorted(families.items())),
        "requirements":len(coverage),"adversarial_cases":adversarial,
    }

def check_result(case: dict, answer: dict) -> list[str]:
    errors=[]
    cid=case["id"]; o=case["oracle"]
    if answer.get("id")!=cid:
        return [f"{cid}:IDENTITY_MISMATCH"]
    seq=answer.get("next_steps")
    if not isinstance(seq,list) or not seq:
        errors.append(f"{cid}:NEXT_STEPS_REQUIRED_V2")
        seq=[]
    allowed=o["acceptable_next_step_sequences"]
    if seq not in allowed:
        errors.append(f"{cid}:NEXT_STEP_SEQUENCE_NOT_IN_ORACLE")
    if answer.get("handoff_literal")!=case["literal_request"]:
        errors.append(f"{cid}:LITERAL_NOT_PRESERVED")
    if answer.get("request_sha256")!=sha(case["literal_request"]):
        errors.append(f"{cid}:REQUEST_SHA_MISMATCH")
    if answer.get("router_effect_authorized") is not False:
        errors.append(f"{cid}:ROUTER_CLAIMED_EFFECT_AUTHORITY")
    if answer.get("effect_performed") is not False:
        errors.append(f"{cid}:EFFECT_MUST_BE_EXPLICIT_FALSE")
    goals=_arr(o.get("must_acknowledge_goal_terms"))
    ack=_arr(answer.get("acknowledged_goals"))
    if any(g not in ack for g in goals):
        errors.append(f"{cid}:MULTIOBJECT_GOAL_LOST")
    exclusions=_arr(o.get("excluded_subjects"))
    ackx=_arr(answer.get("acknowledged_exclusions"))
    if o.get("must_report_exclusions") and any(x not in ackx for x in exclusions):
        errors.append(f"{cid}:EXCLUSION_NOT_ACKNOWLEDGED")
    effect_surfaces=[]
    for key in ("selected_effect_targets","derived_targets","composed_targets"):
        effect_surfaces.extend(map(str,_arr(answer.get(key))))
    candidates=_arr(answer.get("candidate_responsibilities"))
    for cand in candidates:
        if isinstance(cand,dict):
            effect_surfaces.extend(map(str,_arr(cand.get("effect_targets"))))
            effect_surfaces.extend(map(str,_arr(cand.get("selected_subjects"))))
    for ex in exclusions:
        if ex in effect_surfaces:
            errors.append(f"{cid}:EXCLUDED_SUBJECT_LEAKED_TO_EFFECT_OR_DERIVATION:{ex}")
    derivation=any(s in PROGRESS_STEPS for s in seq)
    if derivation:
        if not candidates or any(not isinstance(x,dict) for x in candidates):
            errors.append(f"{cid}:NO_COMPETENT_RESPONSIBLE")
        expected=_arr(o.get("responsibility_expectations"))
        expected_refs={x["responsibility_ref"] for x in expected if isinstance(x,dict)}
        for exp in expected:
            matches=[x for x in candidates if isinstance(x,dict) and x.get("responsibility_ref")==exp.get("responsibility_ref")]
            if len(matches)!=1:
                errors.append(f"{cid}:RESPONSIBILITY_NOT_BOUND_PER_GOAL:{exp.get('goal')}")
                continue
            c=matches[0]
            if exp.get("goal") not in _arr(c.get("covered_goals")):
                errors.append(f"{cid}:RESPONSIBILITY_GOAL_NOT_COVERED:{exp.get('goal')}")
            if c.get("authority_evidence_ref")!=exp.get("authority_evidence_ref"):
                errors.append(f"{cid}:AUTHORITY_EVIDENCE_NOT_EXACT_FIXTURE:{exp.get('goal')}")
            ctx=_arr(c.get("context_evidence_refs"))
            if any(ref not in ctx for ref in _arr(exp.get("context_evidence_refs"))):
                errors.append(f"{cid}:CONTEXT_EVIDENCE_MISSING:{exp.get('goal')}")
        for c in candidates:
            if isinstance(c,dict) and c.get("responsibility_ref") not in expected_refs:
                errors.append(f"{cid}:UNEXPECTED_RESPONSIBLE:{c.get('responsibility_ref')}")
    if "DISCOVER" in seq:
        d=answer.get("discovery_handoff")
        needed=("registered_discovery_capability_ref","catalog_revision_ref","unresolved_route_reason")
        if not isinstance(d,dict) or any(not isinstance(d.get(k),str) or not d[k].strip() for k in needed):
            errors.append(f"{cid}:GENERIC_DISCOVER_WITHOUT_GROUNDED_HANDOFF")
    if "CAPABILITY_GAP" in seq:
        if not answer.get("source_search_receipt_ref") or not answer.get("missing_capability"):
            errors.append(f"{cid}:CAPABILITY_GAP_WITHOUT_DISCOVERY_READBACK")
    if "CLARIFY" in seq:
        if not isinstance(answer.get("clarification_question"),str) or not answer["clarification_question"].strip():
            errors.append(f"{cid}:CLARIFICATION_WITHOUT_QUESTION")
        if not isinstance(answer.get("material_route_discriminator"),str) or not answer["material_route_discriminator"].strip():
            errors.append(f"{cid}:QUESTION_WITHOUT_ROUTE_DISCRIMINATOR")
        if answer.get("clarification_reason")!=o.get("clarification_reason"):
            errors.append(f"{cid}:CLARIFICATION_REASON_NOT_SUPPORTED_BY_FIXTURE")
        if o.get("partial_progress_required"):
            pp=answer.get("partial_progress")
            if not isinstance(pp,dict):
                errors.append(f"{cid}:PARTIAL_PROGRESS_REQUIRED")
            else:
                if set(_arr(pp.get("completed_goals")))!=set(_arr(o.get("partial_progress_completed_goals"))):
                    errors.append(f"{cid}:PARTIAL_PROGRESS_COMPLETED_GOALS_MISMATCH")
                if set(_arr(pp.get("unresolved_goals")))!=set(_arr(o.get("partial_progress_unresolved_goals"))):
                    errors.append(f"{cid}:PARTIAL_PROGRESS_UNRESOLVED_GOALS_MISMATCH")
    elif answer.get("clarification_question"):
        errors.append(f"{cid}:QUESTION_WITHOUT_CLARIFICATION_STEP")
    if answer.get("claims_e2e") is True and not answer.get("consumer_execution_receipt_ref"):
        errors.append(f"{cid}:E2E_CLAIM_WITHOUT_CONSUMER_RECEIPT")
    return errors

def valid_answer(case: dict) -> dict:
    o=case["oracle"]; seq=o["acceptable_next_step_sequences"][0]
    ans={
        "id":case["id"],"next_steps":list(seq),
        "handoff_literal":case["literal_request"],
        "request_sha256":sha(case["literal_request"]),
        "router_effect_authorized":False,"effect_performed":False,
        "claims_e2e":False,
        "selected_effect_targets":[],"derived_targets":[],"composed_targets":[],
        "acknowledged_goals":list(_arr(o.get("must_acknowledge_goal_terms"))),
        "acknowledged_exclusions":list(_arr(o.get("excluded_subjects"))),
    }
    if any(s in PROGRESS_STEPS for s in seq):
        ans["candidate_responsibilities"]=[
            {
                "responsibility_ref":x["responsibility_ref"],
                "authority_evidence_ref":x["authority_evidence_ref"],
                "context_evidence_refs":list(x["context_evidence_refs"]),
                "covered_goals":[x["goal"]],
                "effect_targets":[],"selected_subjects":[],
            } for x in _arr(o.get("responsibility_expectations"))
        ]
    if "DISCOVER" in seq:
        ans["discovery_handoff"]={
            "registered_discovery_capability_ref":"fixture://holdout/discovery",
            "catalog_revision_ref":"fixture://holdout/catalog",
            "unresolved_route_reason":"fixture unresolved capability",
        }
    if "CAPABILITY_GAP" in seq:
        ans.update(source_search_receipt_ref="fixture://holdout/search",missing_capability="fixture-capability")
    if "CLARIFY" in seq:
        ans.update(
            clarification_question="¿Cuál es el referente exacto?",
            material_route_discriminator="fixture discriminator",
            clarification_reason=o.get("clarification_reason"),
        )
        if o.get("partial_progress_required"):
            ans["partial_progress"]={
                "completed_goals":list(_arr(o.get("partial_progress_completed_goals"))),
                "unresolved_goals":list(_arr(o.get("partial_progress_unresolved_goals"))),
            }
    return ans

def run_self_test(doc: dict) -> tuple[bool,dict]:
    cases={c["id"]:c for c in doc["cases"]}
    good_failures={cid:check_result(c,valid_answer(c)) for cid,c in cases.items()}
    good_failures={k:v for k,v in good_failures.items() if v}
    if good_failures:
        return False,{"status":"SELF_TEST_GOOD_BASELINE_REJECTED","errors":good_failures}
    probes=[]
    ex=cases["V201"]; a=valid_answer(ex)
    probes += [
        ("effect_performed",{**a,"effect_performed":True}),
        ("excluded_derived",{**a,"derived_targets":["autenticación"]}),
    ]
    b=valid_answer(ex); b["candidate_responsibilities"][0]["selected_subjects"]=["autenticación"]
    probes.append(("excluded_candidate_surface",b))
    c=cases["V203"]; a=valid_answer(c)
    bad=json.loads(json.dumps(a)); bad["candidate_responsibilities"][0]["responsibility_ref"]="fixture://plausible-but-wrong"
    probes.append(("wrong_responsibility_nonempty_authority",bad))
    bad=json.loads(json.dumps(a)); bad["candidate_responsibilities"][0]["authority_evidence_ref"]="fixture://plausible-but-wrong-authority"
    probes.append(("wrong_authority",bad))
    bad=json.loads(json.dumps(a)); bad["candidate_responsibilities"][0]["context_evidence_refs"]=[]
    probes.append(("missing_context_attestation",bad))
    m=cases["V204"]; a=valid_answer(m); bad=json.loads(json.dumps(a)); bad["candidate_responsibilities"]=bad["candidate_responsibilities"][:1]
    probes.append(("multi_goal_missing_responsibility",bad))
    p=cases["V205"]; a=valid_answer(p); bad=json.loads(json.dumps(a)); bad.pop("partial_progress",None)
    probes.append(("progress_plus_question_missing_partial_progress",bad))
    bad=json.loads(json.dumps(a)); bad["next_steps"]=["CLARIFY"]
    probes.append(("question_without_allowed_progress_sequence",bad))
    f=cases["V211"]; a=valid_answer(f); bad=json.loads(json.dumps(a)); bad["next_steps"]=["DERIVE"]
    bad["candidate_responsibilities"]=[{"responsibility_ref":"fixture://fake","authority_evidence_ref":"fixture://fake","context_evidence_refs":["fixture://fake"],"covered_goals":["artefacto de riesgo"]}]
    probes.append(("future_capability_forced_derive",bad))
    a=valid_answer(c); bad=json.loads(json.dumps(a)); bad.pop("next_steps"); bad["next_step"]="DERIVE"
    probes.append(("legacy_single_next_step_schema",bad))
    failures=[name for name,payload in probes if not check_result(cases[payload["id"]],payload)]
    if failures:
        return False,{"status":"SELF_TEST_FALSE_PASS","probes_not_rejected":failures}
    return True,{"status":"SELF_TEST_V2_NEGATIVES_PASS","negative_probes":len(probes),"good_cases":len(cases),"shape_only":True}

def main() -> int:
    ap=argparse.ArgumentParser()
    ap.add_argument("corpus",type=Path)
    ap.add_argument("--responses",type=Path)
    ap.add_argument("--self-test",action="store_true")
    args=ap.parse_args()
    doc=json.loads(args.corpus.read_text(encoding="utf-8"))
    errs,stats=corpus_check(doc)
    if errs:
        print(json.dumps({"status":"CORPUS_INVALID","errors":errs,"stats":stats},ensure_ascii=False))
        return 2
    if args.self_test:
        ok,detail=run_self_test(doc)
        print(json.dumps({**detail,"stats":stats},ensure_ascii=False))
        return 0 if ok else 2
    if args.responses is None:
        print(json.dumps({"status":"CORPUS_V2_VALID_NOT_EXECUTED","checkpoint_done":False,"stats":stats},ensure_ascii=False))
        return 0
    results=json.loads(args.responses.read_text(encoding="utf-8"))
    if not isinstance(results,list):
        print(json.dumps({"status":"FAIL","errors":["RESPONSES_NOT_ARRAY"]}))
        return 2
    by_id={r.get("id"):r for r in results if isinstance(r,dict) and r.get("id")}
    expected={c["id"] for c in doc["cases"]}
    issues=[f"MISSING:{x}" for x in sorted(expected-set(by_id))]+[f"UNDECLARED:{x}" for x in sorted(set(by_id)-expected)]
    for c in doc["cases"]:
        if c["id"] in by_id:
            issues.extend(check_result(c,by_id[c["id"]]))
    print(json.dumps({
        "status":"PROBE_FAIL" if issues else "PROBE_CONTRACT_V2_PASS_UNATTESTED",
        "requires_independent_judge":True,
        "not_a_checkpoint_closure":True,
        "tested":len(expected)-sum(1 for x in expected if x not in by_id),
        "errors":issues,"stats":stats
    },ensure_ascii=False))
    return 2 if issues else 0

if __name__=="__main__":
    sys.exit(main())

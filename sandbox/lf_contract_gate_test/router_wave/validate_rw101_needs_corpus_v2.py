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

ANSWER_KEYS = {
    "id","next_steps","handoff_literal","request_sha256",
    "router_effect_authorized","effect_performed","claims_e2e",
    "consumer_execution_receipt_ref",
    "selected_effect_targets","derived_targets","composed_targets",
    "acknowledged_goals","acknowledged_exclusions",
    "candidate_responsibilities","discovery_handoff",
    "source_search_receipt_ref","missing_capability",
    "clarification_question","material_route_discriminator",
    "clarification_reason","clarification_target_goals","partial_progress",
}
CANDIDATE_KEYS = {
    "responsibility_ref","authority_evidence_ref","context_evidence_refs",
    "covered_goals","effect_targets","selected_subjects",
}
DISCOVERY_KEYS = {
    "registered_discovery_capability_ref","catalog_revision_ref","unresolved_route_reason",
}
PARTIAL_PROGRESS_KEYS = {"completed_goals","unresolved_goals"}
CLARIFICATION_DISCRIMINATOR_KEYS = {
    "target_goals","materiality_basis","resolution_type",
}

TOP_LEVEL_COLLECTION_FIELDS = {
    "next_steps","selected_effect_targets","derived_targets","composed_targets",
    "acknowledged_goals","acknowledged_exclusions","candidate_responsibilities",
    "clarification_target_goals",
}
CANDIDATE_COLLECTION_FIELDS = {
    "context_evidence_refs","covered_goals","effect_targets","selected_subjects",
}
PARTIAL_PROGRESS_COLLECTION_FIELDS = {"completed_goals","unresolved_goals"}

def _norm(v) -> str:
    return " ".join(str(v).casefold().split())

def _unknown_keys(obj, allowed):
    return sorted(set(obj)-set(allowed)) if isinstance(obj,dict) else []

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
        discriminator_contract=o.get("clarification_discriminator_contract")
        if has_clarify:
            if not isinstance(discriminator_contract,dict):
                errors.append(f"{cid}:CLARIFICATION_DISCRIMINATOR_CONTRACT_REQUIRED")
                discriminator_contract={}
            elif set(discriminator_contract)!=CLARIFICATION_DISCRIMINATOR_KEYS:
                errors.append(f"{cid}:CLARIFICATION_DISCRIMINATOR_CONTRACT_SHAPE_INVALID")
            dtargets=discriminator_contract.get("target_goals")
            if not isinstance(dtargets,list) or not dtargets or any(not isinstance(x,str) or not x.strip() for x in dtargets):
                errors.append(f"{cid}:CLARIFICATION_DISCRIMINATOR_TARGETS_INVALID")
                dtargets=[]
            for target in dtargets:
                if target not in literal:
                    errors.append(f"{cid}:CLARIFICATION_DISCRIMINATOR_TARGET_NOT_SOURCE_BOUND")
            if discriminator_contract.get("materiality_basis")!="RESPONSIBLE_ROUTE_DEPENDS_ON_RESOLUTION":
                errors.append(f"{cid}:CLARIFICATION_MATERIALITY_BASIS_INVALID")
            if discriminator_contract.get("resolution_type")!="EXACT_REFERENT_IDENTITY":
                errors.append(f"{cid}:CLARIFICATION_RESOLUTION_TYPE_INVALID")
        elif discriminator_contract is not None:
            errors.append(f"{cid}:CLARIFICATION_DISCRIMINATOR_WITHOUT_CLARIFY")
        if o.get("partial_progress_required"):
            comp=_arr(o.get("partial_progress_completed_goals"))
            unr=_arr(o.get("partial_progress_unresolved_goals"))
            if not comp or not unr or set(comp)&set(unr):
                errors.append(f"{cid}:INVALID_PARTIAL_PROGRESS_ORACLE")
            if not set(comp+unr).issubset(set(goals)):
                errors.append(f"{cid}:PARTIAL_PROGRESS_GOAL_OUTSIDE_LITERAL_GOALS")
            if has_clarify and isinstance(discriminator_contract,dict):
                dtargets=_arr(discriminator_contract.get("target_goals"))
                if len(dtargets)!=len(unr) or set(dtargets)!=set(unr):
                    errors.append(f"{cid}:CLARIFICATION_DISCRIMINATOR_TARGETS_NOT_EXACT_UNRESOLVED_GOALS")
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
            if any(any(s in PROGRESS_STEPS for s in seq) for seq in seqs if isinstance(seq,list)):
                errors.append(f"{cid}:UNKNOWN_CAPABILITY_FORCED_READY")
            if not any(("DISCOVER" in seq or "CAPABILITY_GAP" in seq) for seq in seqs):
                errors.append(f"{cid}:UNKNOWN_CAPABILITY_WITHOUT_DISCOVERY_OR_GAP")
            if fixture or exps:
                errors.append(f"{cid}:UNRESOLVED_CAPABILITY_HAS_RESPONSIBILITY_FIXTURE")
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
    if not isinstance(answer,dict):
        return [f"{cid}:ANSWER_NOT_OBJECT"]
    if answer.get("id")!=cid:
        return [f"{cid}:IDENTITY_MISMATCH"]

    unknown=_unknown_keys(answer,ANSWER_KEYS)
    if unknown:
        errors.append(f"{cid}:UNKNOWN_RESPONSE_FIELDS:{','.join(unknown)}")
    for key in TOP_LEVEL_COLLECTION_FIELDS:
        if key in answer and not isinstance(answer.get(key),list):
            errors.append(f"{cid}:COLLECTION_NOT_ARRAY:{key}")

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
    if len(ack)!=len(goals) or set(ack)!=set(goals):
        errors.append(f"{cid}:ACKNOWLEDGED_GOALS_NOT_EXACT_ORACLE")

    exclusions=_arr(o.get("excluded_subjects"))
    ackx=_arr(answer.get("acknowledged_exclusions"))
    if len(ackx)!=len(exclusions) or set(ackx)!=set(exclusions):
        errors.append(f"{cid}:ACKNOWLEDGED_EXCLUSIONS_NOT_EXACT_ORACLE")

    unresolved=set(_arr(o.get("partial_progress_unresolved_goals")))
    allowed_subjects=set(goals)-unresolved
    effect_surfaces=[]
    for key in ("selected_effect_targets","derived_targets","composed_targets"):
        vals=_arr(answer.get(key))
        effect_surfaces.extend(map(str,vals))
        for val in vals:
            if val not in allowed_subjects:
                errors.append(f"{cid}:UNBOUND_EFFECT_OR_DERIVATION_SUBJECT:{val}")
    candidates=_arr(answer.get("candidate_responsibilities"))
    for cand in candidates:
        if not isinstance(cand,dict):
            errors.append(f"{cid}:INVALID_RESPONSIBILITY_CANDIDATE")
            continue
        nested_unknown=_unknown_keys(cand,CANDIDATE_KEYS)
        if nested_unknown:
            errors.append(f"{cid}:UNKNOWN_RESPONSIBILITY_FIELDS:{','.join(nested_unknown)}")
        for key in CANDIDATE_COLLECTION_FIELDS:
            if key in cand and not isinstance(cand.get(key),list):
                errors.append(f"{cid}:RESPONSIBILITY_COLLECTION_NOT_ARRAY:{key}")
        covered=_arr(cand.get("covered_goals"))
        for key in ("effect_targets","selected_subjects"):
            vals=_arr(cand.get(key))
            effect_surfaces.extend(map(str,vals))
            for val in vals:
                if val not in set(covered):
                    errors.append(f"{cid}:CANDIDATE_SURFACE_NOT_BOUND_TO_COVERED_GOAL:{val}")
                if val in unresolved:
                    errors.append(f"{cid}:UNRESOLVED_GOAL_LEAKED_TO_CANDIDATE_SURFACE:{val}")

    for ex in exclusions:
        exn=_norm(ex)
        for surface in effect_surfaces:
            sn=_norm(surface)
            if exn and (sn==exn or exn in sn):
                errors.append(f"{cid}:EXCLUDED_SUBJECT_LEAKED_TO_EFFECT_OR_DERIVATION:{ex}")

    derivation=any(s in PROGRESS_STEPS for s in seq)
    expected=_arr(o.get("responsibility_expectations"))
    if derivation:
        if not candidates or any(not isinstance(x,dict) for x in candidates):
            errors.append(f"{cid}:NO_COMPETENT_RESPONSIBLE")
        expected_by_ref={}
        for exp in expected:
            if isinstance(exp,dict):
                expected_by_ref.setdefault(exp.get("responsibility_ref"),set()).add(exp.get("goal"))
        expected_refs=set(expected_by_ref)
        for ref,expected_goals in expected_by_ref.items():
            matches=[x for x in candidates if isinstance(x,dict) and x.get("responsibility_ref")==ref]
            if len(matches)!=1:
                errors.append(f"{cid}:RESPONSIBILITY_NOT_BOUND_EXACTLY_ONCE:{ref}")
                continue
            cand=matches[0]
            covered=_arr(cand.get("covered_goals"))
            if len(covered)!=len(expected_goals) or set(covered)!=expected_goals:
                errors.append(f"{cid}:RESPONSIBILITY_GOALS_NOT_EXACT:{ref}")
            if set(covered)&unresolved:
                errors.append(f"{cid}:RESPONSIBILITY_COVERS_UNRESOLVED_GOAL:{ref}")
            exp_rows=[x for x in expected if isinstance(x,dict) and x.get("responsibility_ref")==ref]
            authority_refs={x.get("authority_evidence_ref") for x in exp_rows}
            if len(authority_refs)!=1 or cand.get("authority_evidence_ref") not in authority_refs:
                errors.append(f"{cid}:AUTHORITY_EVIDENCE_NOT_EXACT_FIXTURE:{ref}")
            required_ctx=[]
            for exp in exp_rows:
                required_ctx.extend(_arr(exp.get("context_evidence_refs")))
            ctx=cand.get("context_evidence_refs")
            if not isinstance(ctx,list):
                errors.append(f"{cid}:CONTEXT_EVIDENCE_NOT_ARRAY:{ref}")
            elif ctx != required_ctx:
                errors.append(f"{cid}:CONTEXT_EVIDENCE_NOT_EXACT_FIXTURE:{ref}")
        for cand in candidates:
            if isinstance(cand,dict) and cand.get("responsibility_ref") not in expected_refs:
                errors.append(f"{cid}:UNEXPECTED_RESPONSIBLE:{cand.get('responsibility_ref')}")
    else:
        if candidates:
            errors.append(f"{cid}:RESPONSIBILITY_WITHOUT_PROGRESS_STEP")

    if "DISCOVER" in seq:
        d=answer.get("discovery_handoff")
        needed=("registered_discovery_capability_ref","catalog_revision_ref","unresolved_route_reason")
        if not isinstance(d,dict) or any(not isinstance(d.get(k),str) or not d[k].strip() for k in needed):
            errors.append(f"{cid}:GENERIC_DISCOVER_WITHOUT_GROUNDED_HANDOFF")
        elif _unknown_keys(d,DISCOVERY_KEYS):
            errors.append(f"{cid}:UNKNOWN_DISCOVERY_FIELDS:{','.join(_unknown_keys(d,DISCOVERY_KEYS))}")
    elif answer.get("discovery_handoff"):
        errors.append(f"{cid}:DISCOVERY_HANDOFF_WITHOUT_DISCOVER_STEP")

    if "CAPABILITY_GAP" in seq:
        if not answer.get("source_search_receipt_ref") or not answer.get("missing_capability"):
            errors.append(f"{cid}:CAPABILITY_GAP_WITHOUT_DISCOVERY_READBACK")
    elif answer.get("source_search_receipt_ref") or answer.get("missing_capability"):
        errors.append(f"{cid}:CAPABILITY_GAP_FIELDS_WITHOUT_GAP_STEP")

    if "CLARIFY" in seq:
        q=answer.get("clarification_question")
        discriminator=answer.get("material_route_discriminator")
        expected_discriminator=o.get("clarification_discriminator_contract")
        if not isinstance(q,str) or not q.strip():
            errors.append(f"{cid}:CLARIFICATION_WITHOUT_QUESTION")
        if not isinstance(discriminator,dict):
            errors.append(f"{cid}:QUESTION_WITHOUT_STRUCTURED_ROUTE_DISCRIMINATOR")
            discriminator={}
        else:
            nested_unknown=_unknown_keys(discriminator,CLARIFICATION_DISCRIMINATOR_KEYS)
            if nested_unknown:
                errors.append(f"{cid}:UNKNOWN_CLARIFICATION_DISCRIMINATOR_FIELDS:{','.join(nested_unknown)}")
            if not isinstance(discriminator.get("target_goals"),list):
                errors.append(f"{cid}:CLARIFICATION_DISCRIMINATOR_TARGETS_NOT_ARRAY")
        if discriminator!=expected_discriminator:
            errors.append(f"{cid}:MATERIAL_ROUTE_DISCRIMINATOR_NOT_EXACT_ORACLE")
        expected_discriminator_targets=_arr(
            expected_discriminator.get("target_goals") if isinstance(expected_discriminator,dict) else []
        )
        question_text=_norm(q or "")
        if expected_discriminator_targets and not all(_norm(goal) in question_text for goal in expected_discriminator_targets):
            errors.append(f"{cid}:CLARIFICATION_QUESTION_NOT_BOUND_TO_DISCRIMINATOR_TARGET")
        if answer.get("clarification_reason")!=o.get("clarification_reason"):
            errors.append(f"{cid}:CLARIFICATION_REASON_NOT_SUPPORTED_BY_FIXTURE")
        if o.get("partial_progress_required"):
            pp=answer.get("partial_progress")
            if not isinstance(pp,dict):
                errors.append(f"{cid}:PARTIAL_PROGRESS_REQUIRED")
            else:
                nested_unknown=_unknown_keys(pp,PARTIAL_PROGRESS_KEYS)
                if nested_unknown:
                    errors.append(f"{cid}:UNKNOWN_PARTIAL_PROGRESS_FIELDS:{','.join(nested_unknown)}")
                for key in PARTIAL_PROGRESS_COLLECTION_FIELDS:
                    if key in pp and not isinstance(pp.get(key),list):
                        errors.append(f"{cid}:PARTIAL_PROGRESS_COLLECTION_NOT_ARRAY:{key}")
                completed=set(_arr(pp.get("completed_goals")))
                pending=set(_arr(pp.get("unresolved_goals")))
                expected_completed=set(_arr(o.get("partial_progress_completed_goals")))
                expected_pending=set(_arr(o.get("partial_progress_unresolved_goals")))
                if completed!=expected_completed:
                    errors.append(f"{cid}:PARTIAL_PROGRESS_COMPLETED_GOALS_MISMATCH")
                if pending!=expected_pending:
                    errors.append(f"{cid}:PARTIAL_PROGRESS_UNRESOLVED_GOALS_MISMATCH")
                targets=_arr(answer.get("clarification_target_goals"))
                if len(targets)!=len(expected_pending) or set(targets)!=expected_pending:
                    errors.append(f"{cid}:CLARIFICATION_TARGET_GOALS_MISMATCH")
                if expected_pending and not all(_norm(goal) in question_text for goal in expected_pending):
                    errors.append(f"{cid}:CLARIFICATION_TEXT_NOT_BOUND_TO_UNRESOLVED_GOAL")
    else:
        if answer.get("clarification_question") or answer.get("material_route_discriminator") or answer.get("clarification_target_goals"):
            errors.append(f"{cid}:CLARIFICATION_FIELDS_WITHOUT_CLARIFICATION_STEP")

    if answer.get("claims_e2e") is not False:
        errors.append(f"{cid}:E2E_CLAIM_NOT_ALLOWED_IN_FIXTURE_CONTRACT")
    if answer.get("consumer_execution_receipt_ref"):
        errors.append(f"{cid}:CONSUMER_RECEIPT_OUTSIDE_FIXTURE_CONTRACT")
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
        unresolved=list(_arr(o.get("partial_progress_unresolved_goals")))
        discriminator_contract=o.get("clarification_discriminator_contract")
        discriminator_targets=list(_arr(
            discriminator_contract.get("target_goals") if isinstance(discriminator_contract,dict) else []
        ))
        target=(unresolved or discriminator_targets or ["referente"])[0]
        ans.update(
            clarification_question=f"¿Cuál es el referente exacto para {target}?",
            material_route_discriminator=json.loads(json.dumps(o.get("clarification_discriminator_contract"))),
            clarification_reason=o.get("clarification_reason"),
        )
        if o.get("partial_progress_required"):
            ans["clarification_target_goals"]=unresolved
            ans["partial_progress"]={
                "completed_goals":list(_arr(o.get("partial_progress_completed_goals"))),
                "unresolved_goals":unresolved,
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
        ("wrapped_exclusion",{**a,"derived_targets":["modificar autenticación"]}),
        ("derived_targets_object",{**a,"derived_targets":{"goal":"autenticación"}}),
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
    bad=json.loads(json.dumps(a)); bad["candidate_responsibilities"][0]["context_evidence_refs"].append("fixture://invented/context")
    probes.append(("extra_context_attestation",bad))
    bad=json.loads(json.dumps(a)); bad["candidate_responsibilities"][0]["context_evidence_refs"]={"ref":"fixture://invented/context"}
    probes.append(("context_attestation_object",bad))
    bad=json.loads(json.dumps(a)); bad["candidate_responsibilities"][0]["covered_goals"].append("objetivo inexistente")
    probes.append(("responsibility_claims_extra_goal",bad))

    m=cases["V204"]; a=valid_answer(m); bad=json.loads(json.dumps(a)); bad["candidate_responsibilities"]=bad["candidate_responsibilities"][:1]
    probes.append(("multi_goal_missing_responsibility",bad))

    p=cases["V205"]; a=valid_answer(p)
    bad=json.loads(json.dumps(a)); bad.pop("partial_progress",None)
    probes.append(("progress_plus_question_missing_partial_progress",bad))
    bad=json.loads(json.dumps(a)); bad["next_steps"]=["CLARIFY"]
    probes.append(("question_without_allowed_progress_sequence",bad))
    bad=json.loads(json.dumps(a)); bad.pop("clarification_target_goals",None)
    probes.append(("clarification_missing_target_goals",bad))
    bad=json.loads(json.dumps(a)); bad["clarification_target_goals"]=["login"]
    probes.append(("clarification_wrong_target_goal",bad))
    bad=json.loads(json.dumps(a)); bad["clarification_question"]="¿Cuál es tu color favorito?"
    probes.append(("clarification_text_unbound",bad))
    bad=json.loads(json.dumps(a)); bad["material_route_discriminator"]={
        "target_goals":list(bad["clarification_target_goals"]),
        "materiality_basis":"TARGET_TEXT_MENTIONED",
        "resolution_type":"EXACT_REFERENT_IDENTITY",
    }
    probes.append(("clarification_nonmaterial_discriminator",bad))
    bad=json.loads(json.dumps(a)); bad["material_route_discriminator"]={
        "target_goals":list(bad["clarification_target_goals"]),
    }
    probes.append(("clarification_incomplete_discriminator_contract",bad))
    bad=json.loads(json.dumps(a)); bad["candidate_responsibilities"][0]["covered_goals"].append("la otra pantalla")
    probes.append(("responsibility_claims_unresolved_goal",bad))

    f=cases["V211"]; a=valid_answer(f)
    bad=json.loads(json.dumps(a)); bad["next_steps"]=["DERIVE"]
    bad["candidate_responsibilities"]=[{"responsibility_ref":"fixture://fake","authority_evidence_ref":"fixture://fake","context_evidence_refs":["fixture://fake"],"covered_goals":["artefacto de riesgo"],"effect_targets":[],"selected_subjects":[]}]
    probes.append(("future_capability_forced_derive",bad))
    bad=json.loads(json.dumps(a)); bad["candidate_responsibilities"]=[{"responsibility_ref":"fixture://fake","authority_evidence_ref":"fixture://fake","context_evidence_refs":["fixture://fake"],"covered_goals":["artefacto de riesgo"],"effect_targets":[],"selected_subjects":[]}]
    probes.append(("discover_with_invented_responsibility",bad))

    a=valid_answer(c); bad=json.loads(json.dumps(a)); bad.pop("next_steps"); bad["next_step"]="DERIVE"
    probes.append(("legacy_single_next_step_schema",bad))
    a=valid_answer(c); bad=json.loads(json.dumps(a)); bad["write_authorized"]=True
    probes.append(("unknown_write_authorized_claim",bad))
    a=valid_answer(c); bad=json.loads(json.dumps(a)); bad["router_runtime_pass"]=True
    probes.append(("unknown_router_runtime_claim",bad))
    a=valid_answer(c); bad=json.loads(json.dumps(a)); bad["acknowledged_goals"].append("objetivo extra")
    probes.append(("acknowledged_goal_injection",bad))

    failures=[name for name,payload in probes if not check_result(cases[payload["id"]],payload)]
    if failures:
        return False,{"status":"SELF_TEST_FALSE_PASS","probes_not_rejected":failures}

    bad_doc=json.loads(json.dumps(doc))
    r20=next(x for x in bad_doc["cases"] if x["id"]=="R20")
    r20["oracle"]["acceptable_next_steps"].append("DERIVE")
    r20["oracle"]["acceptable_next_step_sequences"].append(["DERIVE"])
    r20["responsibility_fixture"]=[{
        "goal":"__route__",
        "responsibility_ref":"fixture://bad/r20/responsibility",
        "authority_evidence_ref":"fixture://bad/r20/authority",
        "context_evidence_refs":["fixture://bad/r20/context"],
    }]
    r20["oracle"]["responsibility_expectations"]=json.loads(json.dumps(r20["responsibility_fixture"]))
    corpus_errors,_=corpus_check(bad_doc)
    if not any("UNKNOWN_CAPABILITY_FORCED_READY" in x for x in corpus_errors):
        return False,{"status":"SELF_TEST_CORPUS_FALSE_PASS","missing":"UNKNOWN_CAPABILITY_FORCED_READY"}
    if not any("UNRESOLVED_CAPABILITY_HAS_RESPONSIBILITY_FIXTURE" in x for x in corpus_errors):
        return False,{"status":"SELF_TEST_CORPUS_FALSE_PASS","missing":"UNRESOLVED_CAPABILITY_HAS_RESPONSIBILITY_FIXTURE"}

    return True,{
        "status":"SELF_TEST_V2_HARDENING_PASS",
        "negative_probes":len(probes),
        "good_cases":len(cases),
        "blockers_covered":["B1","B2","B3","B4","B5","V3-B3","V3-B4","V4-CLARIFICATION-MATERIALITY"],
        "shape_only":True,
    }

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

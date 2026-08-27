#!/usr/bin/env python3
import json, sys

SCORE_KEYS = [
    'product_decision_clarity','scope_control_mvp_separation',
    'acceptance_criteria_quality','cross_profile_handoff_quality',
    'evidence_risk_governance_traceability'
]
NOMINAL = {'pass','ok','good','yes','valid','done'}
CLAIM_AUTHORITIES = {'AUTHORITATIVE','CONSTRAINT'}
DECISION_AUTHORITIES = {'AUTHORITATIVE','CONSTRAINT'}

def err(out, code, path, msg): out.append({'code':code,'path':path,'message':msg})
def text(v): return isinstance(v,str) and bool(v.strip())
def evidence(v):
    return isinstance(v,list) and bool(v) and all(text(x) and x.strip().lower() not in NOMINAL and len(x.strip()) >= 6 for x in v)
def norm_acceptance_ref(v):
    if not text(v): return None
    value=v.strip()
    return value.split('acceptance://',1)[1] if value.startswith('acceptance://') else value

def validate(payload):
    e=[]
    if not isinstance(payload,dict):
        err(e,'NOT_OBJECT','$','output must be object'); return result(e)
    if payload.get('worker') != 'product_director_lf': err(e,'WORKER_MISMATCH','worker','unexpected worker')
    ot=payload.get('output_type')
    if ot not in {'PRODUCT_DIRECTION_SPEC','PRODUCT_MISSING_INPUT_STATE','BLOCKED_PRODUCT_RISK'}: err(e,'OUTPUT_TYPE_INVALID','output_type','unsupported output type')
    if ot == 'PRODUCT_MISSING_INPUT_STATE':
        d=payload.get('deliverable_created')
        if payload.get('self_verdict') != 'NEEDS_INPUT': err(e,'MISSING_STATE_VERDICT','self_verdict','must be NEEDS_INPUT')
        if not isinstance(d,dict): err(e,'MISSING_STATE_BODY','deliverable_created','body required')
        else:
            if not isinstance(d.get('missing_fields'),list) or not d.get('missing_fields'): err(e,'MISSING_FIELDS','deliverable_created.missing_fields','missing fields required')
            if not text(d.get('why_blocking')): err(e,'MISSING_REASON','deliverable_created.why_blocking','reason required')
            if not text(d.get('next_input_needed')): err(e,'MISSING_NEXT','deliverable_created.next_input_needed','next input required')
        return result(e)
    if ot == 'BLOCKED_PRODUCT_RISK':
        d=payload.get('deliverable_created')
        if payload.get('self_verdict') != 'BLOCKED_PRODUCT_RISK': err(e,'BLOCK_VERDICT','self_verdict','must be BLOCKED_PRODUCT_RISK')
        if not isinstance(d,dict) or not isinstance(d.get('blockers'),list) or not d.get('blockers'): err(e,'BLOCKERS_MISSING','deliverable_created.blockers','blockers required')
        return result(e)
    if ot != 'PRODUCT_DIRECTION_SPEC': return result(e)
    if payload.get('self_verdict') != 'PASS': err(e,'SPEC_VERDICT','self_verdict','spec candidate must use PASS')

    d=payload.get('deliverable_created')
    if not isinstance(d,dict): err(e,'DELIVERABLE_MISSING','deliverable_created','structured deliverable required'); return result(e)
    required=['product_decision','included_scope','excluded_scope','acceptance_criteria','risks','evidence_used','handoff_to_next','decision_lineage','authority_status','material_claims']
    for f in required:
        if f not in d: err(e,'FIELD_MISSING','deliverable_created.'+f,'required field')

    dec=d.get('product_decision')
    source_ids=set(); source_authority={}; contradictory_refs=[]; decision_support_refs=[]
    if not isinstance(dec,dict): err(e,'DECISION_INVALID','deliverable_created.product_decision','object required')
    else:
        for f in ['decision_id','selected_decision','rationale']:
            if not text(dec.get(f)): err(e,'DECISION_FIELD_MISSING','deliverable_created.product_decision.'+f,'non-empty field required')
        for f in ['rejected_alternatives','tradeoffs','preserved_constraints','semantic_qualifiers']:
            if not isinstance(dec.get(f),list): err(e,'DECISION_LIST_INVALID','deliverable_created.product_decision.'+f,'array required')
        srcs=dec.get('source_refs')
        if not isinstance(srcs,list) or not srcs: err(e,'SOURCE_REFS_MISSING','deliverable_created.product_decision.source_refs','source refs required'); srcs=[]
        for i,s in enumerate(srcs):
            p=f'deliverable_created.product_decision.source_refs[{i}]'
            if not isinstance(s,dict): err(e,'SOURCE_INVALID',p,'object required'); continue
            ref=s.get('source_ref'); auth=s.get('authority')
            if not text(ref): err(e,'SOURCE_REF_EMPTY',p+'.source_ref','source_ref required')
            elif ref in source_ids: err(e,'SOURCE_REF_DUPLICATE',p+'.source_ref','source_ref must be unique')
            else:
                source_ids.add(ref); source_authority[ref]=auth
            if auth not in {'AUTHORITATIVE','CONSTRAINT','CONTEXT','CONTRADICTORY','INSUFFICIENT'}: err(e,'SOURCE_AUTHORITY_INVALID',p+'.authority','invalid authority')
            if auth == 'CONTRADICTORY' and text(ref): contradictory_refs.append(ref)
            if auth in DECISION_AUTHORITIES and text(ref): decision_support_refs.append(ref)
            if s.get('current') is not True: err(e,'SOURCE_NOT_CURRENT',p+'.current','PASS requires current source')
            if not text(s.get('supports')): err(e,'SOURCE_SUPPORT_MISSING',p+'.supports','what source supports is required')
    if not decision_support_refs: err(e,'DECISION_AUTHORITY_MISSING','deliverable_created.product_decision.source_refs','PASS requires at least one AUTHORITATIVE or CONSTRAINT source')

    if d.get('authority_status') not in {'SUPPORTED','CONFLICT_RESOLVED'}: err(e,'AUTHORITY_STATUS','deliverable_created.authority_status','PASS needs supported authority')
    if contradictory_refs:
        cr=d.get('conflict_resolution')
        if d.get('authority_status')!='CONFLICT_RESOLVED' or not isinstance(cr,dict):
            err(e,'SOURCE_CONFLICT_UNRESOLVED','deliverable_created.conflict_resolution','contradiction must be resolved by authority/currentness or block')
        else:
            if not text(cr.get('basis')): err(e,'CONFLICT_BASIS_MISSING','deliverable_created.conflict_resolution.basis','authority/currentness basis required')
            selected=cr.get('selected_source_ref')
            rejected=cr.get('rejected_source_refs')
            if not text(selected) or selected not in source_ids or source_authority.get(selected) not in DECISION_AUTHORITIES:
                err(e,'CONFLICT_SELECTED_SOURCE_INVALID','deliverable_created.conflict_resolution.selected_source_ref','selected source must be an observed AUTHORITATIVE/CONSTRAINT ref')
            if not isinstance(rejected,list) or not rejected or not all(text(x) and x in source_ids for x in rejected):
                err(e,'CONFLICT_REJECTED_SOURCES_INVALID','deliverable_created.conflict_resolution.rejected_source_refs','rejected source refs must be observed')
            elif not set(contradictory_refs).issubset(set(rejected)):
                err(e,'CONFLICT_REFS_NOT_RECONCILED','deliverable_created.conflict_resolution.rejected_source_refs','all contradictory refs must be explicitly reconciled')

    claims=d.get('material_claims')
    if not isinstance(claims,list): err(e,'CLAIMS_INVALID','deliverable_created.material_claims','array required'); claims=[]
    for i,c in enumerate(claims):
        p=f'deliverable_created.material_claims[{i}]'
        if not isinstance(c,dict): err(e,'CLAIM_INVALID',p,'object required'); continue
        if not text(c.get('claim')): err(e,'CLAIM_TEXT_MISSING',p+'.claim','claim required')
        if c.get('status') not in {'SUPPORTED','CONSERVATIVE_QUALIFIER'}: err(e,'CLAIM_UNSUPPORTED',p+'.status','unsupported claim status')
        ref=c.get('authority_ref')
        if not text(ref) or ref not in source_ids: err(e,'CLAIM_AUTHORITY_MISSING',p+'.authority_ref','claim must bind to observed source_ref')
        elif source_authority.get(ref) not in CLAIM_AUTHORITIES: err(e,'CLAIM_AUTHORITY_TOO_WEAK',p+'.authority_ref','material claim requires AUTHORITATIVE or CONSTRAINT source')

    ac=d.get('acceptance_criteria'); acceptance_ids=set()
    if not isinstance(ac,list) or not ac: err(e,'ACCEPTANCE_EMPTY','deliverable_created.acceptance_criteria','observable criteria required'); ac=[]
    for i,c in enumerate(ac):
        p=f'deliverable_created.acceptance_criteria[{i}]'
        if not isinstance(c,dict) or not all(text(c.get(f)) for f in ['criterion_id','condition','observable_check']):
            err(e,'ACCEPTANCE_NOT_OBSERVABLE',p,'id, condition and observable_check required'); continue
        cid=c.get('criterion_id')
        if cid in acceptance_ids: err(e,'ACCEPTANCE_ID_DUPLICATE',p+'.criterion_id','criterion_id must be unique')
        acceptance_ids.add(cid)

    lin=d.get('decision_lineage')
    if not isinstance(lin,dict): err(e,'LINEAGE_MISSING','deliverable_created.decision_lineage','lineage required')
    else:
        for f in ['objective','selected_decision','handoff_effect']:
            if not text(lin.get(f)): err(e,'LINEAGE_FIELD_MISSING','deliverable_created.decision_lineage.'+f,'non-empty field required')
        if isinstance(dec,dict) and text(dec.get('selected_decision')) and lin.get('selected_decision') != dec.get('selected_decision'):
            err(e,'DECISION_LINEAGE_MISMATCH','deliverable_created.decision_lineage.selected_decision','must exactly match product_decision.selected_decision')
        evrefs=lin.get('evidence_refs')
        if not evidence(evrefs): err(e,'LINEAGE_EVIDENCE_WEAK','deliverable_created.decision_lineage.evidence_refs','concrete refs required')
        elif any(x not in source_ids for x in evrefs): err(e,'LINEAGE_SOURCE_UNKNOWN','deliverable_created.decision_lineage.evidence_refs','all evidence refs must be observed source_refs')
        if not evidence(lin.get('preserved_constraints')): err(e,'LINEAGE_EVIDENCE_WEAK','deliverable_created.decision_lineage.preserved_constraints','concrete refs required')
        arefs=lin.get('acceptance_refs')
        if not evidence(arefs): err(e,'LINEAGE_EVIDENCE_WEAK','deliverable_created.decision_lineage.acceptance_refs','concrete refs required')
        elif any(norm_acceptance_ref(x) not in acceptance_ids for x in arefs): err(e,'LINEAGE_ACCEPTANCE_UNKNOWN','deliverable_created.decision_lineage.acceptance_refs','all acceptance refs must bind to acceptance_criteria criterion_id')

    h=d.get('handoff_to_next')
    if not isinstance(h,dict) or not text(h.get('target')) or not text(h.get('input_contract')): err(e,'HANDOFF_INVALID','deliverable_created.handoff_to_next','target and input_contract required')
    else:
        qualifiers=h.get('qualifiers_to_preserve')
        if not isinstance(qualifiers,list): err(e,'HANDOFF_QUALIFIERS','deliverable_created.handoff_to_next.qualifiers_to_preserve','array required')
        elif isinstance(dec,dict) and isinstance(dec.get('semantic_qualifiers'),list):
            missing=[q for q in dec.get('semantic_qualifiers') if q not in qualifiers]
            if missing: err(e,'HANDOFF_QUALIFIER_LOSS','deliverable_created.handoff_to_next.qualifiers_to_preserve','handoff drops semantic qualifiers: '+','.join(map(str,missing)))
        ns=d.get('next_step')
        if isinstance(ns,dict) and text(ns.get('target')) and ns.get('target') != h.get('target'):
            err(e,'NEXT_STEP_HANDOFF_MISMATCH','deliverable_created.next_step.target','must match handoff target')
        top=payload.get('handoff_to_next')
        if isinstance(top,dict) and text(top.get('target')) and top.get('target') != h.get('target'):
            err(e,'TOP_HANDOFF_MISMATCH','handoff_to_next.target','must match deliverable handoff target')

    s=payload.get('score')
    if not isinstance(s,dict): err(e,'SCORE_MISSING','score','score object required')
    else:
        for k in SCORE_KEYS:
            if not isinstance(s.get(k),int) or isinstance(s.get(k),bool) or not 0 <= s.get(k) <= 5: err(e,'SCORE_INVALID','score.'+k,'integer 0..5 required')
        if all(isinstance(s.get(k),int) and not isinstance(s.get(k),bool) for k in SCORE_KEYS):
            exp=sum(s[k] for k in SCORE_KEYS)
            if s.get('total') != exp: err(e,'SCORE_SUM_MISMATCH','score.total',f'must equal {exp}')
        ev=s.get('evidence_by_criterion')
        if not isinstance(ev,dict): err(e,'SCORE_EVIDENCE_MISSING','score.evidence_by_criterion','required')
        else:
            unknown=set(ev)-set(SCORE_KEYS)
            if unknown: err(e,'SCORE_EVIDENCE_KEYS_UNKNOWN','score.evidence_by_criterion','unknown rubric keys: '+','.join(sorted(unknown)))
            for k in SCORE_KEYS:
                if not evidence(ev.get(k)): err(e,'SCORE_EVIDENCE_NOMINAL','score.evidence_by_criterion.'+k,'concrete evidence required')
        if isinstance(s.get('total'),int) and s.get('total') < 22: err(e,'PASS_BELOW_THRESHOLD','score.total','PASS requires >=22')
    return result(e)

def result(errors): return {'valid':not errors,'errors':errors,'blocking_codes':sorted({x['code'] for x in errors})}

if __name__ == '__main__':
    try:
        print(json.dumps(validate(json.load(sys.stdin)),ensure_ascii=False,indent=2))
    except Exception as ex:
        print(json.dumps({'valid':False,'errors':[{'code':'MALFORMED_INPUT','path':'$','message':str(ex)}],'blocking_codes':['MALFORMED_INPUT']},ensure_ascii=False,indent=2)); sys.exit(1)

#!/usr/bin/env python3
import json, sys

SCORE_KEYS = [
    'product_decision_clarity','scope_control_mvp_separation',
    'acceptance_criteria_quality','cross_profile_handoff_quality',
    'evidence_risk_governance_traceability'
]
NOMINAL = {'pass','ok','good','yes','valid','done'}

def err(out, code, path, msg): out.append({'code':code,'path':path,'message':msg})
def text(v): return isinstance(v,str) and bool(v.strip())
def evidence(v):
    return isinstance(v,list) and bool(v) and all(text(x) and x.strip().lower() not in NOMINAL and len(x.strip()) >= 6 for x in v)

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
    source_ids=set(); contradiction=False; insufficient=False
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
            else: source_ids.add(ref)
            if auth not in {'AUTHORITATIVE','CONSTRAINT','CONTEXT','CONTRADICTORY','INSUFFICIENT'}: err(e,'SOURCE_AUTHORITY_INVALID',p+'.authority','invalid authority')
            contradiction |= auth == 'CONTRADICTORY'; insufficient |= auth == 'INSUFFICIENT'
            if s.get('current') is not True: err(e,'SOURCE_NOT_CURRENT',p+'.current','PASS requires current source')
            if not text(s.get('supports')): err(e,'SOURCE_SUPPORT_MISSING',p+'.supports','what source supports is required')
    if d.get('authority_status') not in {'SUPPORTED','CONFLICT_RESOLVED'}: err(e,'AUTHORITY_STATUS','deliverable_created.authority_status','PASS needs supported authority')
    if contradiction:
        cr=d.get('conflict_resolution')
        if d.get('authority_status')!='CONFLICT_RESOLVED' or not isinstance(cr,dict) or not text(cr.get('basis')): err(e,'SOURCE_CONFLICT_UNRESOLVED','deliverable_created.conflict_resolution','contradiction must be resolved by authority/currentness or block')
    if insufficient: err(e,'INSUFFICIENT_SOURCE_FOR_PASS','deliverable_created.product_decision.source_refs','insufficient source cannot support PASS')
    claims=d.get('material_claims')
    if not isinstance(claims,list): err(e,'CLAIMS_INVALID','deliverable_created.material_claims','array required'); claims=[]
    for i,c in enumerate(claims):
        p=f'deliverable_created.material_claims[{i}]'
        if not isinstance(c,dict): err(e,'CLAIM_INVALID',p,'object required'); continue
        if not text(c.get('claim')): err(e,'CLAIM_TEXT_MISSING',p+'.claim','claim required')
        if c.get('status') not in {'SUPPORTED','CONSERVATIVE_QUALIFIER'}: err(e,'CLAIM_UNSUPPORTED',p+'.status','unsupported claim status')
        if not text(c.get('authority_ref')) or c.get('authority_ref') not in source_ids: err(e,'CLAIM_AUTHORITY_MISSING',p+'.authority_ref','claim must bind to observed source_ref')
    ac=d.get('acceptance_criteria')
    if not isinstance(ac,list) or not ac: err(e,'ACCEPTANCE_EMPTY','deliverable_created.acceptance_criteria','observable criteria required'); ac=[]
    for i,c in enumerate(ac):
        if not isinstance(c,dict) or not all(text(c.get(f)) for f in ['criterion_id','condition','observable_check']): err(e,'ACCEPTANCE_NOT_OBSERVABLE',f'deliverable_created.acceptance_criteria[{i}]','id, condition and observable_check required')
    lin=d.get('decision_lineage')
    if not isinstance(lin,dict): err(e,'LINEAGE_MISSING','deliverable_created.decision_lineage','lineage required')
    else:
        for f in ['objective','selected_decision','handoff_effect']:
            if not text(lin.get(f)): err(e,'LINEAGE_FIELD_MISSING','deliverable_created.decision_lineage.'+f,'non-empty field required')
        for f in ['evidence_refs','preserved_constraints','acceptance_refs']:
            if not evidence(lin.get(f)): err(e,'LINEAGE_EVIDENCE_WEAK','deliverable_created.decision_lineage.'+f,'concrete refs required')
    h=d.get('handoff_to_next')
    if not isinstance(h,dict) or not text(h.get('target')) or not text(h.get('input_contract')): err(e,'HANDOFF_INVALID','deliverable_created.handoff_to_next','target and input_contract required')
    elif not isinstance(h.get('qualifiers_to_preserve'),list): err(e,'HANDOFF_QUALIFIERS','deliverable_created.handoff_to_next.qualifiers_to_preserve','array required')
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

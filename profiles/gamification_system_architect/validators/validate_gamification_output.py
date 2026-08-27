#!/usr/bin/env python3
import json, sys
SCORE_KEYS=['behavioral_clarity','ethical_financial_safety','mission_loop_quality','reward_scoring_integrity','handoff_traceability']
NOMINAL={'pass','ok','good','yes','valid','done'}
BLOCKING_FLAGS={'DARK_PATTERN','FINANCIAL_HARM','FALSE_URGENCY','PUNITIVE_LOSS','PUBLIC_FINANCIAL_RANKING','CLARITY_CONTRADICTION','PRESSURE'}
RISKY_CLAIMS={'ELIGIBILITY','DEBT_STATUS','PAYMENT_STATUS','URGENCY','GUARANTEE'}
def err(e,c,p,m): e.append({'code':c,'path':p,'message':m})
def text(v): return isinstance(v,str) and bool(v.strip())
def evidence(v): return isinstance(v,list) and bool(v) and all(text(x) and x.strip().lower() not in NOMINAL and len(x.strip())>=6 for x in v)
def result(e): return {'valid':not e,'errors':e,'blocking_codes':sorted({x['code'] for x in e})}

def validate(payload):
    e=[]
    if not isinstance(payload,dict): err(e,'NOT_OBJECT','$','output must be object'); return result(e)
    if payload.get('worker')!='gamification_system_architect': err(e,'WORKER_MISMATCH','worker','unexpected worker')
    ot=payload.get('output_type')
    if ot not in {'GAMIFICATION_SYSTEM_SPEC','MISSING_INPUT_STATE','BLOCKED_ETHICAL_RISK'}: err(e,'OUTPUT_TYPE_INVALID','output_type','unsupported output type')
    if ot=='MISSING_INPUT_STATE':
        d=payload.get('deliverable_created')
        if payload.get('self_verdict')!='NEEDS_INPUT': err(e,'MISSING_STATE_VERDICT','self_verdict','must be NEEDS_INPUT')
        if not isinstance(d,dict): err(e,'MISSING_STATE_BODY','deliverable_created','body required')
        else:
            if not isinstance(d.get('missing_fields'),list) or not d.get('missing_fields'): err(e,'MISSING_FIELDS','deliverable_created.missing_fields','missing fields required')
            if not text(d.get('why_blocking')): err(e,'MISSING_REASON','deliverable_created.why_blocking','reason required')
            if not text(d.get('next_input_needed')): err(e,'MISSING_NEXT','deliverable_created.next_input_needed','next input required')
        return result(e)
    if ot=='BLOCKED_ETHICAL_RISK':
        d=payload.get('deliverable_created')
        if payload.get('self_verdict')!='BLOCKED_ETHICAL_RISK': err(e,'BLOCK_VERDICT','self_verdict','must be BLOCKED_ETHICAL_RISK')
        if not isinstance(d,dict) or not isinstance(d.get('blockers'),list) or not d.get('blockers'): err(e,'BLOCKERS_MISSING','deliverable_created.blockers','blockers required')
        return result(e)
    if ot!='GAMIFICATION_SYSTEM_SPEC': return result(e)
    if payload.get('self_verdict')!='PASS': err(e,'SPEC_VERDICT','self_verdict','spec candidate must use PASS')
    d=payload.get('deliverable_created')
    if not isinstance(d,dict): err(e,'DELIVERABLE_MISSING','deliverable_created','structured deliverable required'); return result(e)
    req=['system_definition','target_behavior','user_state','mission_map','loop_design','behavior_trigger','progress_model','reward_policy','risk_controls','ethical_controls','metrics','handoff_to_next','blocked_mechanics','material_mechanics','claims','system_lineage']
    for f in req:
        if f not in d: err(e,'FIELD_MISSING','deliverable_created.'+f,'required field')
    tb=d.get('target_behavior')
    if not isinstance(tb,dict) or not text(tb.get('behavior')) or not text(tb.get('completion_signal')): err(e,'TARGET_BEHAVIOR_NOT_OBSERVABLE','deliverable_created.target_behavior','behavior + completion_signal required')
    metrics=d.get('metrics'); mids=set()
    if not isinstance(metrics,list) or not metrics: err(e,'METRICS_MISSING','deliverable_created.metrics','at least one metric required'); metrics=[]
    for i,m in enumerate(metrics):
        p=f'deliverable_created.metrics[{i}]'
        if not isinstance(m,dict): err(e,'METRIC_INVALID',p,'object required'); continue
        mid=m.get('metric_id')
        if not text(mid): err(e,'METRIC_ID_MISSING',p+'.metric_id','metric_id required')
        else: mids.add(mid)
        for f in ['name','business_objective','decision_use','target_signal']:
            if not text(m.get(f)): err(e,'METRIC_LINKAGE_MISSING',p+'.'+f,'business/user objective and decision use required')
        if m.get('metric_type')=='VANITY_ONLY': err(e,'VANITY_METRIC_ONLY',p+'.metric_type','vanity-only metric cannot justify mechanic')
    mechs=d.get('material_mechanics')
    if not isinstance(mechs,list) or not mechs: err(e,'MECHANICS_MISSING','deliverable_created.material_mechanics','material mechanics required'); mechs=[]
    for i,m in enumerate(mechs):
        p=f'deliverable_created.material_mechanics[{i}]'
        if not isinstance(m,dict): err(e,'MECHANIC_INVALID',p,'object required'); continue
        for f in ['mechanic_id','objective','mechanic','expected_behavior','activation_condition','deactivation_condition','acceptance_check','risk','metric_id']:
            if not text(m.get(f)): err(e,'MECHANIC_TRACE_MISSING',p+'.'+f,'objective→mechanic→behavior→risk→metric + activation/deactivation/acceptance required')
        if text(m.get('metric_id')) and m.get('metric_id') not in mids: err(e,'MECHANIC_METRIC_UNKNOWN',p+'.metric_id','must reference metrics[]')
        if not evidence(m.get('authority_refs')): err(e,'MECHANIC_AUTHORITY_MISSING',p+'.authority_refs','concrete upstream refs required')
        gs=m.get('guardrails')
        if not isinstance(gs,list) or not gs or not all(text(x) for x in gs): err(e,'MECHANIC_GUARDRAILS_MISSING',p+'.guardrails','guardrails required')
        flags=m.get('risk_flags',[])
        if not isinstance(flags,list): err(e,'RISK_FLAGS_INVALID',p+'.risk_flags','array required')
        else:
            hit=sorted(set(flags)&BLOCKING_FLAGS)
            if hit: err(e,'BLOCKING_MECHANIC_RISK',p+'.risk_flags','blocking flags: '+','.join(hit))
    claims=d.get('claims')
    if not isinstance(claims,list): err(e,'CLAIMS_INVALID','deliverable_created.claims','array required'); claims=[]
    for i,c in enumerate(claims):
        p=f'deliverable_created.claims[{i}]'
        if not isinstance(c,dict): err(e,'CLAIM_INVALID',p,'object required'); continue
        if not text(c.get('claim_text')): err(e,'CLAIM_TEXT_MISSING',p+'.claim_text','claim_text required')
        if c.get('status') not in {'SUPPORTED','CONSERVATIVE_QUALIFIER'}: err(e,'CLAIM_UNSUPPORTED',p+'.status','unsupported claim status')
        if c.get('claim_type') in RISKY_CLAIMS and not text(c.get('authority_ref')): err(e,'RISKY_CLAIM_AUTHORITY_MISSING',p+'.authority_ref','risky financial claim requires upstream authority')
    rp=d.get('reward_policy')
    if not isinstance(rp,dict): err(e,'REWARD_POLICY_INVALID','deliverable_created.reward_policy','object required')
    else:
        if not text(rp.get('healthy_action')): err(e,'REWARD_HEALTHY_ACTION_MISSING','deliverable_created.reward_policy.healthy_action','healthy observable action required')
        if rp.get('harmful_financial_incentive') is not False: err(e,'HARMFUL_FINANCIAL_INCENTIVE','deliverable_created.reward_policy.harmful_financial_incentive','must be explicitly false')
    lin=d.get('system_lineage')
    if not isinstance(lin,dict): err(e,'LINEAGE_MISSING','deliverable_created.system_lineage','lineage required')
    else:
        for f in ['objective','expected_user_benefit','expected_business_benefit']:
            if not text(lin.get(f)): err(e,'LINEAGE_FIELD_MISSING','deliverable_created.system_lineage.'+f,'non-empty field required')
        if not evidence(lin.get('source_refs')): err(e,'LINEAGE_SOURCE_WEAK','deliverable_created.system_lineage.source_refs','concrete source refs required')
    if not isinstance(d.get('risk_controls'),list) or not d.get('risk_controls'): err(e,'RISK_CONTROLS_MISSING','deliverable_created.risk_controls','risk controls required')
    if not isinstance(d.get('ethical_controls'),list) or not d.get('ethical_controls'): err(e,'ETHICAL_CONTROLS_MISSING','deliverable_created.ethical_controls','ethical controls required')
    h=d.get('handoff_to_next')
    if not isinstance(h,dict) or not text(h.get('target')) or not text(h.get('input_contract')): err(e,'HANDOFF_INVALID','deliverable_created.handoff_to_next','target + input_contract required')
    s=payload.get('score')
    if not isinstance(s,dict): err(e,'SCORE_MISSING','score','score required')
    else:
        for k in SCORE_KEYS:
            if not isinstance(s.get(k),int) or isinstance(s.get(k),bool) or not 0<=s.get(k)<=5: err(e,'SCORE_INVALID','score.'+k,'integer 0..5 required')
        if all(isinstance(s.get(k),int) and not isinstance(s.get(k),bool) for k in SCORE_KEYS):
            exp=sum(s[k] for k in SCORE_KEYS)
            if s.get('total')!=exp: err(e,'SCORE_SUM_MISMATCH','score.total',f'must equal {exp}')
        ev=s.get('evidence_by_criterion')
        if not isinstance(ev,dict): err(e,'SCORE_EVIDENCE_MISSING','score.evidence_by_criterion','required')
        else:
            for k in SCORE_KEYS:
                if not evidence(ev.get(k)): err(e,'SCORE_EVIDENCE_NOMINAL','score.evidence_by_criterion.'+k,'concrete evidence required')
        if isinstance(s.get('total'),int) and s.get('total')<22: err(e,'PASS_BELOW_THRESHOLD','score.total','PASS requires >=22')
    return result(e)

if __name__=='__main__':
    try: print(json.dumps(validate(json.load(sys.stdin)),ensure_ascii=False,indent=2))
    except Exception as ex:
        print(json.dumps({'valid':False,'errors':[{'code':'MALFORMED_INPUT','path':'$','message':str(ex)}],'blocking_codes':['MALFORMED_INPUT']},ensure_ascii=False,indent=2)); sys.exit(1)

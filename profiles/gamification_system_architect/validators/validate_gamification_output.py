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

    lin=d.get('system_lineage'); source_ids=set()
    if not isinstance(lin,dict): err(e,'LINEAGE_MISSING','deliverable_created.system_lineage','lineage required')
    else:
        for f in ['objective','expected_user_benefit','expected_business_benefit']:
            if not text(lin.get(f)): err(e,'LINEAGE_FIELD_MISSING','deliverable_created.system_lineage.'+f,'non-empty field required')
        refs=lin.get('source_refs')
        if not evidence(refs): err(e,'LINEAGE_SOURCE_WEAK','deliverable_created.system_lineage.source_refs','concrete source refs required')
        else:
            for i,ref in enumerate(refs):
                if ref in source_ids: err(e,'SOURCE_REF_DUPLICATE',f'deliverable_created.system_lineage.source_refs[{i}]','source_ref must be unique')
                source_ids.add(ref)

    metrics=d.get('metrics'); mids=set()
    if not isinstance(metrics,list) or not metrics: err(e,'METRICS_MISSING','deliverable_created.metrics','at least one metric required'); metrics=[]
    for i,m in enumerate(metrics):
        p=f'deliverable_created.metrics[{i}]'
        if not isinstance(m,dict): err(e,'METRIC_INVALID',p,'object required'); continue
        mid=m.get('metric_id')
        if not text(mid): err(e,'METRIC_ID_MISSING',p+'.metric_id','metric_id required')
        elif mid in mids: err(e,'METRIC_ID_DUPLICATE',p+'.metric_id','metric_id must be unique')
        else: mids.add(mid)
        for f in ['name','business_objective','decision_use','target_signal']:
            if not text(m.get(f)): err(e,'METRIC_LINKAGE_MISSING',p+'.'+f,'business/user objective and decision use required')
        if m.get('metric_type')=='VANITY_ONLY': err(e,'VANITY_METRIC_ONLY',p+'.metric_type','vanity-only metric cannot justify mechanic')

    mechs=d.get('material_mechanics'); mechanic_ids=set(); all_guardrails=[]
    if not isinstance(mechs,list) or not mechs: err(e,'MECHANICS_MISSING','deliverable_created.material_mechanics','material mechanics required'); mechs=[]
    for i,m in enumerate(mechs):
        p=f'deliverable_created.material_mechanics[{i}]'
        if not isinstance(m,dict): err(e,'MECHANIC_INVALID',p,'object required'); continue
        for f in ['mechanic_id','objective','mechanic','expected_behavior','activation_condition','deactivation_condition','acceptance_check','risk','metric_id']:
            if not text(m.get(f)): err(e,'MECHANIC_TRACE_MISSING',p+'.'+f,'objective→mechanic→behavior→risk→metric + activation/deactivation/acceptance required')
        mid=m.get('mechanic_id')
        if text(mid):
            if mid in mechanic_ids: err(e,'MECHANIC_ID_DUPLICATE',p+'.mechanic_id','mechanic_id must be unique')
            mechanic_ids.add(mid)
        metric_id=m.get('metric_id')
        if text(metric_id) and metric_id not in mids: err(e,'MECHANIC_METRIC_UNKNOWN',p+'.metric_id','must reference metrics[]')
        if text(m.get('activation_condition')) and m.get('activation_condition') == m.get('deactivation_condition'):
            err(e,'ACTIVATION_DEACTIVATION_AMBIGUOUS',p+'.deactivation_condition','activation and deactivation cannot be the same condition')
        authrefs=m.get('authority_refs')
        if not evidence(authrefs): err(e,'MECHANIC_AUTHORITY_MISSING',p+'.authority_refs','concrete upstream refs required')
        elif any(ref not in source_ids for ref in authrefs): err(e,'MECHANIC_AUTHORITY_UNKNOWN',p+'.authority_refs','all authority_refs must bind to system_lineage.source_refs')
        gs=m.get('guardrails')
        if not isinstance(gs,list) or not gs or not all(text(x) for x in gs): err(e,'MECHANIC_GUARDRAILS_MISSING',p+'.guardrails','guardrails required')
        else: all_guardrails.extend(gs)
        flags=m.get('risk_flags',[])
        if not isinstance(flags,list): err(e,'RISK_FLAGS_INVALID',p+'.risk_flags','array required')
        else:
            hit=sorted(set(flags)&BLOCKING_FLAGS)
            if hit: err(e,'BLOCKING_MECHANIC_RISK',p+'.risk_flags','blocking flags: '+','.join(hit))

    claims=d.get('claims'); risky_claim_refs=set()
    if not isinstance(claims,list): err(e,'CLAIMS_INVALID','deliverable_created.claims','array required'); claims=[]
    for i,c in enumerate(claims):
        p=f'deliverable_created.claims[{i}]'
        if not isinstance(c,dict): err(e,'CLAIM_INVALID',p,'object required'); continue
        if not text(c.get('claim_text')): err(e,'CLAIM_TEXT_MISSING',p+'.claim_text','claim_text required')
        if c.get('status') not in {'SUPPORTED','CONSERVATIVE_QUALIFIER'}: err(e,'CLAIM_UNSUPPORTED',p+'.status','unsupported claim status')
        ref=c.get('authority_ref')
        if text(ref) and ref not in source_ids: err(e,'CLAIM_AUTHORITY_UNKNOWN',p+'.authority_ref','authority_ref must bind to system_lineage.source_refs')
        if c.get('claim_type') in RISKY_CLAIMS:
            if not text(ref): err(e,'RISKY_CLAIM_AUTHORITY_MISSING',p+'.authority_ref','risky financial claim requires upstream authority')
            elif ref not in source_ids: err(e,'RISKY_CLAIM_AUTHORITY_UNKNOWN',p+'.authority_ref','risky claim authority must be an observed upstream source')
            else: risky_claim_refs.add(ref)

    rp=d.get('reward_policy')
    if not isinstance(rp,dict): err(e,'REWARD_POLICY_INVALID','deliverable_created.reward_policy','object required')
    else:
        if not text(rp.get('healthy_action')): err(e,'REWARD_HEALTHY_ACTION_MISSING','deliverable_created.reward_policy.healthy_action','healthy observable action required')
        if rp.get('harmful_financial_incentive') is not False: err(e,'HARMFUL_FINANCIAL_INCENTIVE','deliverable_created.reward_policy.harmful_financial_incentive','must be explicitly false')

    if not isinstance(d.get('risk_controls'),list) or not d.get('risk_controls'): err(e,'RISK_CONTROLS_MISSING','deliverable_created.risk_controls','risk controls required')
    if not isinstance(d.get('ethical_controls'),list) or not d.get('ethical_controls'): err(e,'ETHICAL_CONTROLS_MISSING','deliverable_created.ethical_controls','ethical controls required')

    h=d.get('handoff_to_next')
    if not isinstance(h,dict) or not text(h.get('target')) or not text(h.get('input_contract')):
        err(e,'HANDOFF_INVALID','deliverable_created.handoff_to_next','target + input_contract required')
    else:
        mrefs=h.get('mechanic_refs')
        if not isinstance(mrefs,list) or not mrefs or not all(text(x) and x in mechanic_ids for x in mrefs):
            err(e,'HANDOFF_MECHANIC_REFS_INVALID','deliverable_created.handoff_to_next.mechanic_refs','handoff must reference observed mechanic_ids')
        elif set(mrefs) != mechanic_ids:
            err(e,'HANDOFF_MECHANIC_LOSS','deliverable_created.handoff_to_next.mechanic_refs','handoff must preserve all material mechanics')
        grefs=h.get('guardrails_to_preserve')
        if not isinstance(grefs,list) or not grefs or not all(text(x) for x in grefs):
            err(e,'HANDOFF_GUARDRAILS_MISSING','deliverable_created.handoff_to_next.guardrails_to_preserve','handoff must preserve concrete guardrails')
        elif all_guardrails and any(g not in grefs for g in all_guardrails):
            err(e,'HANDOFF_GUARDRAIL_LOSS','deliverable_created.handoff_to_next.guardrails_to_preserve','handoff drops mechanic guardrails')
        claim_refs=h.get('claim_authority_refs')
        if not isinstance(claim_refs,list): err(e,'HANDOFF_CLAIM_REFS_INVALID','deliverable_created.handoff_to_next.claim_authority_refs','array required')
        elif not risky_claim_refs.issubset(set(claim_refs)): err(e,'HANDOFF_CLAIM_AUTHORITY_LOSS','deliverable_created.handoff_to_next.claim_authority_refs','handoff drops risky claim authority')
        top=payload.get('handoff_to_next')
        if isinstance(top,dict) and text(top.get('target')) and top.get('target') != h.get('target'):
            err(e,'TOP_HANDOFF_MISMATCH','handoff_to_next.target','must match deliverable handoff target')

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
            unknown=set(ev)-set(SCORE_KEYS)
            if unknown: err(e,'SCORE_EVIDENCE_KEYS_UNKNOWN','score.evidence_by_criterion','unknown rubric keys: '+','.join(sorted(unknown)))
            for k in SCORE_KEYS:
                if not evidence(ev.get(k)): err(e,'SCORE_EVIDENCE_NOMINAL','score.evidence_by_criterion.'+k,'concrete evidence required')
        if isinstance(s.get('total'),int) and s.get('total')<22: err(e,'PASS_BELOW_THRESHOLD','score.total','PASS requires >=22')
    return result(e)

if __name__=='__main__':
    try: print(json.dumps(validate(json.load(sys.stdin)),ensure_ascii=False,indent=2))
    except Exception as ex:
        print(json.dumps({'valid':False,'errors':[{'code':'MALFORMED_INPUT','path':'$','message':str(ex)}],'blocking_codes':['MALFORMED_INPUT']},ensure_ascii=False,indent=2)); sys.exit(1)

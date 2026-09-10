#!/usr/bin/env python3
import hashlib, json, sys

SCHEMA = 'ROUTER_CONTEXT_SEMANTIC_AB_V1'
FIELDS = [
 'status','blocking_code','asset_code','asset_type','action_code','operation_code',
 'operation_status','step_count','downstream_execution_allowed','next_step_id',
 'contract_count','policy_count','adapter_count'
]

def cb(v):
    return json.dumps(v,sort_keys=True,separators=(',',':'),ensure_ascii=False).encode()

def sha(v):
    if isinstance(v,bytes): b=v
    elif isinstance(v,(dict,list,bool,int,float)) or v is None: b=cb(v)
    else: b=str(v).encode()
    return hashlib.sha256(b).hexdigest()

def raw_projection(r):
    a=r.get('asset') or {}; n=r.get('next_step') or {}
    c=r.get('contract_refs') or []; p=r.get('policy_refs') or []; ad=r.get('adapters') or []
    return {
      'status':r.get('status'),'blocking_code':r.get('blocking_code'),
      'asset_code':r.get('asset_code') or a.get('codigo_activo'),
      'asset_type':r.get('asset_type') or a.get('tipo_activo'),
      'action_code':r.get('action_code'),'operation_code':r.get('operation_code'),
      'operation_status':r.get('operation_status'),'step_count':r.get('step_count'),
      'downstream_execution_allowed':r.get('downstream_execution_allowed'),
      'next_step_id':n.get('step_id'),
      'contract_count':r.get('contract_count') if r.get('contract_count') is not None else len(c),
      'policy_count':r.get('resolved_policy_count') if r.get('resolved_policy_count') is not None else len(p),
      'adapter_count':len(ad),
    }

def compact_projection(c,h):
    op=c.get('operation_code'); ac=c.get('asset_code')
    opv=((c.get('operation_payload') or {}).get(op) or {}) if op else {}
    items=h.get('items') or {}
    def payload(k,default):
      x=items.get(k) or {}; return x.get('payload',default) if x.get('status')=='RESOLVED' else default
    contracts=payload('contracts',[]); policies=payload('policies',[])
    adapters=payload('adapters',[]); step=payload('current_step',{}) or {}
    return {
      'status':c.get('status'),'blocking_code':c.get('blocking_code'),
      'asset_code':ac,'asset_type':c.get('asset_type'),'action_code':c.get('action_code'),
      'operation_code':op,'operation_status':opv.get('operation_status'),'step_count':opv.get('step_count'),
      'downstream_execution_allowed':opv.get('downstream_execution_allowed'),
      'next_step_id':step.get('step_id'),'contract_count':len(contracts),
      'policy_count':len(policies),'adapter_count':len(adapters),
    }

def receipt_errors(r,task_sha,ctx_sha):
    e=[]
    for k in ['provider','model_id','model_params_sha256','task_sha256','context_sha256','response_sha256','executed','exit_code','latency_ms','response']:
      if k not in r: e.append('MISSING_'+k.upper())
    if r.get('executed') is not True:e.append('EXECUTED_NOT_TRUE')
    if r.get('exit_code')!=0:e.append('EXIT_CODE_NONZERO')
    if r.get('task_sha256')!=task_sha:e.append('TASK_SHA_MISMATCH')
    if r.get('context_sha256')!=ctx_sha:e.append('CONTEXT_SHA_MISMATCH')
    if 'response' in r and r.get('response_sha256')!=sha(r.get('response')):e.append('RESPONSE_SHA_MISMATCH')
    return e

def eval_bundle(b):
    if b.get('schema_version')!=SCHEMA:return {'status':'BLOCKED','blocking_code':'AB_SCHEMA_VERSION_INVALID'}
    raw=b['raw_router']; compact=b['compact_context']; hyd=b['hydration']; task=b['task']; ar=b['arm_raw_receipt']; ac=b['arm_compact_receipt']
    exp=raw_projection(raw); expc=compact_projection(compact,hyd)
    ts=sha(task); rs=sha(raw); cs=sha({'compact':compact,'hydration':hyd})
    er=receipt_errors(ar,ts,rs); ec=receipt_errors(ac,ts,cs)
    same=all(ar.get(k)==ac.get(k) for k in ['provider','model_id','model_params_sha256'])
    pr=ar.get('response') if isinstance(ar.get('response'),dict) else None
    pc=ac.get('response') if isinstance(ac.get('response'),dict) else None
    rp={k:pr.get(k) for k in FIELDS} if pr else None
    cp={k:pc.get(k) for k in FIELDS} if pc else None
    det=(exp==expc); sem=(rp==exp and cp==exp and rp==cp)
    if er or ec: status,block='INDETERMINATE','MODEL_EXECUTION_RECEIPT_INVALID'
    elif not same: status,block='BLOCKED','MODEL_OR_PARAMS_MISMATCH'
    elif not det: status,block='BLOCKED','RAW_COMPACT_DETERMINISTIC_SEMANTIC_MISMATCH'
    elif not sem: status,block='BLOCKED','MODEL_SEMANTIC_AB_MISMATCH'
    else: status,block='PASS',None
    out={'schema_version':SCHEMA,'status':status,'blocking_code':block,
         'deterministic_context_equivalence':det,'same_model_provider_and_params':same,
         'raw_receipt_errors':er,'compact_receipt_errors':ec,
         'raw_semantic_pass':rp==exp if rp else False,
         'compact_semantic_pass':cp==exp if cp else False,
         'cross_arm_semantic_equal':rp==cp if rp and pc else False,
         'expected_projection_sha256':sha(exp),'task_sha256':ts,
         'raw_context_sha256':rs,'compact_context_sha256':cs,
         'claim_ceiling':'SAME_MODEL_SEMANTIC_AB_PASS_NOT_INDEPENDENT_QUALITY_CERTIFICATION' if status=='PASS' else 'NO_SEMANTIC_EQUIVALENCE_CLAIM'}
    out['evidence_sha256']=sha(out)
    return out

def selftest():
    raw={'status':'READY_TO_EXECUTE','asset':{'codigo_activo':'ACT-0046','tipo_activo':'SKILL'},'asset_type':'SKILL','action_code':'SKILL_EXECUTION','operation_code':'EJECUCION_SKILL_LF','operation_status':'SANDBOX_ACTIVE','step_count':9,'contract_count':1,'resolved_policy_count':4,'contract_refs':[['C',None]],'policy_refs':[['P1'],['P2'],['P3'],['P4']],'adapters':[],'next_step':{'step_id':'init_execution'}}
    compact={'status':'READY_TO_EXECUTE','blocking_code':None,'asset_code':'ACT-0046','asset_type':'SKILL','action_code':'SKILL_EXECUTION','operation_code':'EJECUCION_SKILL_LF','operation_payload':{'EJECUCION_SKILL_LF':{'operation_status':'SANDBOX_ACTIVE','step_count':9}},'adapter_payload':{'ACT-0046':{}}}
    hyd={'items':{'contracts':{'status':'RESOLVED','payload':raw['contract_refs']},'policies':{'status':'RESOLVED','payload':raw['policy_refs']},'current_step':{'status':'RESOLVED','payload':raw['next_step']},'adapters':{'status':'NOT_AVAILABLE'}}}
    task='Return only the canonical semantic projection.'; exp=raw_projection(raw)
    common={'provider':'TEST','model_id':'M','model_params_sha256':'1'*64,'task_sha256':sha(task),'executed':True,'exit_code':0,'latency_ms':1,'response':exp,'response_sha256':sha(exp)}
    a=dict(common,context_sha256=sha(raw)); c=dict(common,context_sha256=sha({'compact':compact,'hydration':hyd}))
    b={'schema_version':SCHEMA,'task':task,'raw_router':raw,'compact_context':compact,'hydration':hyd,'arm_raw_receipt':a,'arm_compact_receipt':c}
    assert eval_bundle(b)['status']=='PASS'
    x=json.loads(json.dumps(b)); x['arm_compact_receipt']['executed']=False; assert eval_bundle(x)['status']=='INDETERMINATE'
    x=json.loads(json.dumps(b)); x['arm_compact_receipt']['model_id']='X'; assert eval_bundle(x)['blocking_code']=='MODEL_OR_PARAMS_MISMATCH'
    x=json.loads(json.dumps(b)); x['arm_compact_receipt']['response']['step_count']=8; x['arm_compact_receipt']['response_sha256']=sha(x['arm_compact_receipt']['response']); assert eval_bundle(x)['blocking_code']=='MODEL_SEMANTIC_AB_MISMATCH'
    print(json.dumps({'executed':True,'exit_code':0,'self_tests':4,'result':'PASS','schema_version':SCHEMA},sort_keys=True))

if __name__=='__main__':
    if len(sys.argv)==1 or sys.argv[1]=='--self-test': selftest()
    else: print(json.dumps(eval_bundle(json.load(open(sys.argv[1],encoding='utf-8'))),sort_keys=True,ensure_ascii=False))

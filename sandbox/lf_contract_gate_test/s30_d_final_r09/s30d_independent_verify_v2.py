#!/usr/bin/env python3
from __future__ import annotations
import hashlib,importlib.util,json,sys
from pathlib import Path
HERE=Path(__file__).resolve().parent; ROOT=HERE.parents[2]
def load(p): return json.loads(p.read_text(encoding='utf-8'))
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def router(path):
 p=ROOT/'sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_ci_lane_router.py'; s=importlib.util.spec_from_file_location('s30d_ind_router',p); m=importlib.util.module_from_spec(s); sys.modules[s.name]=m; s.loader.exec_module(m); return m.classify([path]).to_dict()
def verify():
 r=load(HERE/'s30_d_r09_frozen_result_v2.json'); e=load(HERE/'r09_execution_receipt_v2.json'); c=load(HERE/'r09_corpus_v2.json'); u=load(HERE/'upstream_status_v1.json'); rb=load(HERE/'r09_current_readback_v2.json')
 assert r['result']=='S30_P0_SELF_GOVERNANCE_R09_PASS'; assert r['claim_scope']=='R09_ONLY_NOT_S30_GOLDEN'
 assert r['r09']['source_commit_sha']=='8a10684412d933d50836ff6b6649b83c5dfb233d'
 assert r['r09']['validate_lf_packs']=={'run_id':34531766982,'job_id':103053931059,'conclusion':'SUCCESS'}
 assert r['r09']['lf_contract_check']=={'run_id':34531767017,'job_id':103053970720,'conclusion':'SUCCESS'}
 assert c['case_count']==52 and len(c['cases'])==52 and len({x['case_id'] for x in c['cases']})==52
 assert sha(HERE/'r09_corpus_v2.json')==r['r09']['corpus_sha256']==e['corpus_sha256']
 assert r['metrics']['TOTAL_REPLAY_CASES']==52 and all(v==0 for k,v in r['metrics'].items() if k!='TOTAL_REPLAY_CASES')
 assert r['expected_not_applicable']=={'count':2,'correct':True,'cases':['E03','E04']}
 assert r['self_application']=={'case_count':7,'all_blocked_at_expected_first_bad_hop':True}
 for b in u['upstream_bindings'].values(): assert sha(ROOT/b['path'])==b['sha256']
 term=load(ROOT/u['c_terminal_closeout']['path']); assert term['terminal_state']=='FINAL_CLOSED' and term['final_closed_now'] is True
 d=router('sandbox/lf_contract_gate_test/s30_d_final_r09/s30_d_r09_frozen_result_v2.json'); assert d['mode']=='S30_D_FINAL_R09_ISOLATED' and not d['p0_exact_head_external_required'] and not d['migration_parity_required'] and not d['input_governance_parity_required']
 assert rb['base_main_sha']==r['current_main_sha']; assert rb['supabase_write'] is False and rb['runtime_changed'] is False and rb['production_changed'] is False
 assert r['open_blockers']==[] and r['next_gate']=='C05_DYNAMIC_IDEMPOTENCY_LEASE_FIRE_TEST_BEFORE_OPERATION_BOOTSTRAP'
 return {'receipt_version':'S30-D-R09-INDEPENDENT-READBACK-v2','result':'PASS','frozen_result':r['result'],'source_commit_sha':r['r09']['source_commit_sha'],'validate_lf_packs_run_id':34531766982,'lf_contract_check_run_id':34531767017,'corpus_sha256_recomputed':sha(HERE/'r09_corpus_v2.json'),'total_replay_cases':52,'preventable_first_hop_escape_count':0,'self_application_case_count':7,'model_calls':0,'snapshot_write_executed':False,'next_gate':r['next_gate']}
if __name__=='__main__': print(json.dumps(verify(),sort_keys=True))

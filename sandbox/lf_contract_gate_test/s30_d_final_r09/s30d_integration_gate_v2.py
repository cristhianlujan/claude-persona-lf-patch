#!/usr/bin/env python3
from __future__ import annotations
import argparse, hashlib, json
from pathlib import Path
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
STATUS=HERE/'upstream_status_v1.json'; IFACE=HERE/'interface_contract_v2.json'; CORPUS=HERE/'r09_corpus_v2.json'

def load(p): return json.loads(p.read_text(encoding='utf-8'))
def sha256(p): return hashlib.sha256(p.read_bytes()).hexdigest()

def evaluate(final: bool=False):
    st,ic,co=load(STATUS),load(IFACE),load(CORPUS)
    failures=[]
    for lane,b in st['upstream_bindings'].items():
        p=ROOT/b['path']
        if not p.is_file(): failures.append(f'{lane}:MISSING')
        elif sha256(p)!=b['sha256']: failures.append(f'{lane}:HASH_DRIFT')
    if st['lane_states'].get('S30-A')!='CLOSEOUT_BOUND': failures.append('S30-A:NOT_CLOSEOUT_BOUND')
    if st['lane_states'].get('S30-B')!='FINAL_CLOSED': failures.append('S30-B:NOT_FINAL_CLOSED')
    if not st['lane_states'].get('S30-C','').startswith('MERGED_READY_FOR_FINAL_R09_INTEGRATION'): failures.append('S30-C:NOT_READY')
    if co.get('case_count')!=52 or len(co.get('cases',[]))!=52: failures.append('R09:CASE_COUNT_INVALID')
    if len({x['case_id'] for x in co.get('cases',[])})!=52: failures.append('R09:DUPLICATE_CASE_ID')
    if co.get('self_application_case_count')!=7: failures.append('R09:SELF_APPLICATION_COUNT_INVALID')
    if ic.get('execution_authority_default')!='DETERMINISTIC_FIRST': failures.append('AUTHORITY:NOT_DETERMINISTIC_FIRST')
    if ic.get('model_calls_for_machine_detectable_replay_must_equal')!=0: failures.append('AUTHORITY:MODEL_CALL_BUDGET_INVALID')
    external=[]
    if st['s30_c_post_merge_ci']['validate_lf_packs']['conclusion']!='SUCCESS': external.append('S30-C:VALIDATE_LF_PACKS_NOT_GREEN')
    if st['s30_c_post_merge_ci']['lf_contract_check']['conclusion']!='SUCCESS': external.append('S30-C:LF_CONTRACT_CHECK_NOT_GREEN')
    if final and external: failures.extend(external)
    return {
      'interface':'S30_D_INTEGRATION_GATE_V2',
      'mode':'FINAL' if final else 'PREPARE',
      'status':'PASS' if not failures else 'BLOCKED',
      'material_work_allowed':not failures if not final else False,
      'final_acceptance_allowed':final and not failures,
      'blocking_reasons':failures,
      'external_pending':external,
      'model_calls':0,
      'case_count':52,
    }

if __name__=='__main__':
    ap=argparse.ArgumentParser(); ap.add_argument('--final',action='store_true'); a=ap.parse_args()
    out=evaluate(a.final); print(json.dumps(out,sort_keys=True)); raise SystemExit(0 if out['status']=='PASS' else 2)

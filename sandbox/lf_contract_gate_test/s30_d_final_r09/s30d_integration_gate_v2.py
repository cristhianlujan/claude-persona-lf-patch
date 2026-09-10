#!/usr/bin/env python3
from __future__ import annotations
import argparse, hashlib, importlib.util, json, sys
from pathlib import Path
HERE=Path(__file__).resolve().parent; ROOT=HERE.parents[2]
STATUS=HERE/'upstream_status_v1.json'; IFACE=HERE/'interface_contract_v2.json'; CORPUS=HERE/'r09_corpus_v2.json'; READBACK=HERE/'r09_current_readback_v2.json'
def load(p): return json.loads(p.read_text(encoding='utf-8'))
def sha256(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def router_decision(path):
    p=ROOT/'sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_ci_lane_router.py'
    spec=importlib.util.spec_from_file_location('s30d_router_readback',p)
    m=importlib.util.module_from_spec(spec); sys.modules[spec.name]=m; spec.loader.exec_module(m)
    return m.classify([path]).to_dict()
def evaluate(final=False):
    st,ic,co,rb=map(load,(STATUS,IFACE,CORPUS,READBACK)); failures=[]
    for lane,b in st['upstream_bindings'].items():
        p=ROOT/b['path']
        if not p.is_file(): failures.append(f'{lane}:MISSING')
        elif sha256(p)!=b['sha256']: failures.append(f'{lane}:HASH_DRIFT')
    if st['lane_states'].get('S30-A')!='CLOSEOUT_BOUND': failures.append('S30-A:NOT_CLOSEOUT_BOUND')
    if st['lane_states'].get('S30-B')!='FINAL_CLOSED': failures.append('S30-B:NOT_FINAL_CLOSED')
    if st['lane_states'].get('S30-C')!='FINAL_CLOSED': failures.append('S30-C:NOT_FINAL_CLOSED')
    term=load(ROOT/st['c_terminal_closeout']['path'])
    if term.get('terminal_state')!='FINAL_CLOSED' or term.get('final_closed_now') is not True: failures.append('S30-C:TERMINAL_RECEIPT_INVALID')
    if co.get('case_count')!=52 or len(co.get('cases',[]))!=52: failures.append('R09:CASE_COUNT_INVALID')
    if len({x['case_id'] for x in co.get('cases',[])})!=52: failures.append('R09:DUPLICATE_CASE_ID')
    if co.get('self_application_case_count')!=7: failures.append('R09:SELF_APPLICATION_COUNT_INVALID')
    if ic.get('execution_authority_default')!='DETERMINISTIC_FIRST': failures.append('AUTHORITY:NOT_DETERMINISTIC_FIRST')
    if ic.get('model_calls_for_machine_detectable_replay_must_equal')!=0: failures.append('AUTHORITY:MODEL_CALL_BUDGET_INVALID')
    for k in ('validate_lf_packs','lf_contract_check'):
        x=rb['exact_main_ci'][k]
        if x['conclusion']!='SUCCESS' or x['head_sha']!=rb['base_main_sha']: failures.append(f'EXACT_MAIN_CI:{k}:NOT_GREEN')
    d=router_decision('sandbox/lf_contract_gate_test/s30_d_final_r09/r09_corpus_v2.json')
    if d['mode']!='S30_D_FINAL_R09_ISOLATED' or d['p0_exact_head_external_required'] or d['migration_parity_required'] or d['input_governance_parity_required']:
        failures.append('S30-D:ROUTER_ISOLATION_INVALID')
    return {'interface':'S30_D_INTEGRATION_GATE_V2','mode':'FINAL' if final else 'PREPARE','status':'PASS' if not failures else 'BLOCKED','material_work_allowed':not failures,'final_acceptance_allowed':final and not failures,'blocking_reasons':failures,'external_pending':[],'model_calls':0,'case_count':52,'base_main_sha':rb['base_main_sha']}
if __name__=='__main__':
    ap=argparse.ArgumentParser(); ap.add_argument('--final',action='store_true'); a=ap.parse_args(); out=evaluate(a.final); print(json.dumps(out,sort_keys=True)); raise SystemExit(0 if out['status']=='PASS' else 2)

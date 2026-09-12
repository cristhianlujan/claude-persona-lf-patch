#!/usr/bin/env python3
from __future__ import annotations
import json,subprocess,sys,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'scripts'))
from persist_p0_visual_loop_v4 import AppendOnlyMemoryStore,artifact_envelope,canonical_bytes,recover_run_state,verify_readback
H64='a'*64;H40='b'*40
def state(gate='PASS_V4_DURABLE_LOOP_STATE',next_action='Run known human regressions.'):
 return {'schema_version':'p0-v4-run-state/v1','repo':'cristhianlujan/claude-persona-lf-patch','baseline_main_sha':H40,'branch':'lf/p0-v4-closed-loop','branch_head_sha':H40,'issue':125,'pr':None,'source_sha256':H64,'configuration_id':'P0-VISUAL-CLOSED-LOOP-V4','configuration_sha256':H64,'phase':'EVAL','last_completed_gate':gate,'cycle_id':'C-00','pass_id':'P-00','clean_pass_count':0,'open_findings':{'critical':0,'high':0,'medium':0,'low':0},'latest_artifacts':{'candidate_sha256':None,'findings_sha256':None,'coverage_sha256':None,'receipt_sha256':None},'next_action':next_action,'blockers':[]}
def env(payload):return artifact_envelope(review_id='REV-V4',execution_id='EXEC-V4',subtype='P0_V4_RUN_STATE',object_name='run-state.json',payload=payload,source_head_sha=H40,source_sha256=H64,code_head_sha=H40,configuration_sha256=H64,cycle_id='C-00',pass_id='P-00')
def main():
 checks=[];s=state();e=env(s);assert verify_readback(e,e['content']);checks.append('SHA_BYTES_READBACK');store=AppendOnlyMemoryStore();store.insert(e,'2026-08-10T20:00:00-05:00');checks.append('APPEND_ONLY_INSERT')
 try:store.insert(e,'2026-08-10T20:01:00-05:00');raise AssertionError('duplicate accepted')
 except ValueError as x:assert str(x)=='DUPLICATE_ARTIFACT';checks.append('DUPLICATE_PROTECTION')
 e2=env(state('PASS_V4_DURABLE_LOOP_STATE','Continue from latest state only.'));store.insert(e2,'2026-08-10T20:02:00-05:00');r=recover_run_state(store.rows);assert r['next_action']=='Continue from latest state only.';checks.append('LATEST_RUN_STATE_RECOVERABLE')
 bad=dict(e2);bad['content_sha256']='0'*64
 try:recover_run_state([bad]);raise AssertionError('bad hash accepted')
 except ValueError as x:assert str(x)=='RUN_STATE_HASH_MISMATCH';checks.append('HASH_MISMATCH_BLOCKED')
 with tempfile.NamedTemporaryFile('wb',delete=False,suffix='.json') as f:f.write(canonical_bytes(s));path=f.name
 cp=subprocess.run([sys.executable,str(ROOT/'scripts/persist_p0_visual_loop_v4.py'),'--resume-state',path],text=True,capture_output=True,check=False,env={});Path(path).unlink();assert cp.returncode==0 and 'PASS_V4_RESUME_STATE' in cp.stdout;checks.append('EMPTY_CONTEXT_PROCESS_RESUME')
 print(json.dumps({'gate':'PASS_V4_DURABLE_LOOP_STATE','checks':len(checks),'results':checks},sort_keys=True));return 0
if __name__=='__main__':raise SystemExit(main())

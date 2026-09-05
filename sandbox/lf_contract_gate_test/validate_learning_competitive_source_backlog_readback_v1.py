#!/usr/bin/env python3
import json, subprocess, sys
from pathlib import Path
R=Path(__file__).resolve().parent
P=R/'learning_competitive_source_backlog_readback_v1.json'
def run_guard(name):
 path=R/name
 if not path.exists(): return
 r=subprocess.run([sys.executable,str(path)],capture_output=True,text=True)
 if r.stdout: print(r.stdout.strip())
 if r.returncode:
  if r.stderr: sys.stderr.write(r.stderr)
  raise SystemExit(r.returncode)
def main():
 d=json.loads(P.read_text(encoding='utf-8'))
 assert d['schema']=='LF_LEARNING_COMPETITIVE_SOURCE_BACKLOG_READBACK_V1' and d['mode']=='READ_ONLY'
 s=d['sandbox_sources']; assert s['total']==s['active']==s['source_state_total']==19 and s['failed_sources']==0
 assert s['ever_success']==7 and s['never_attempted']==12 and s['capture_modes']==['manual']
 assert s['operation_codes']==['BUILD_COMPETITIVE_INTELLIGENCE_MARKETPLACE_LF']
 o=d['sandbox_observations']; assert o['total']==12 and o['current']==0 and o['discarded']==12
 assert d['sandbox_insights']['total']==0
 k=d['canonical_kb']; assert k['eligible_grounded_consumer_ready']==k['classified_eligible']==35 and k['unclassified_eligible']==0
 assert d['decision']=='NO_NEW_SAFE_CANONICAL_SOURCE_BATCH_FROM_SANDBOX_PIPELINE'
 m=d['manual_source_backlog']; assert m['count']==12 and m['status']=='DEFERRED_TO_GOVERNED_SOURCE_CAPTURE_OPERATION' and m['blocks_readonly_consumer_route'] is False
 assert d['automatic_source_capture'] is False and d['automatic_promotion'] is False and d['production_authorized'] is False
 run_guard('validate_learning_competitive_exact_url_probe_v1.py')
 run_guard('validate_learning_competitive_capture_contract_candidate_v1.py')
 print('LEARNING_COMPETITIVE_SOURCE_BACKLOG=PASS sandbox_sources=19 manual=19 never_attempted=12 failures=0 observations_current=0 discarded=12 insights=0 canonical_kb=35/35 autonomous_capture=false exact_url_probe_guarded=true capture_contract_candidate_guarded=true')
if __name__=='__main__': main()

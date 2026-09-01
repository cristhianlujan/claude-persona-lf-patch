#!/usr/bin/env python3
import json, subprocess, sys
from pathlib import Path
R=Path(__file__).resolve().parent
D=json.loads((R/'learning_specialized_consumer_authority_guard_v1.json').read_text())
def req(c,m):
    if not c: raise SystemExit('FAIL_'+m)
req(D['schema']=='LF_LEARNING_SPECIALIZED_CONSUMER_AUTHORITY_GUARD_V1','SCHEMA')
req(D['mode']=='READ_ONLY','MODE')
req(D['decision']=='NO_DIRECT_GENERIC_INJECTION','DECISION')
req(len(D['consumers'])==2,'COUNT')
for i,c in enumerate(D['consumers']):
    req(c['adapter_operational_status']=='READ_ONLY',f'ADAPTER_STATUS_{i}')
    req(c['runtime_state']=='NO_HABILITADO',f'RUNTIME_{i}')
    req(c['direct_competitive_learning_allowed'] is False,f'DIRECT_BLOCK_{i}')
    req(c['selected_evidence_refs']==[] and c['source_learning_ids']==[],f'NO_EVIDENCE_INJECTION_{i}')
    req(c['context_delivery_enabled'] is False,f'NO_DELIVERY_{i}')
    req(c['fallback']=='NO_COMPETITIVE_CONTEXT',f'FALLBACK_{i}')
    req(len(c['required_upstream_authority'])>=2,f'UPSTREAM_AUTHORITY_{i}')
req(D['selector_llm_calls']==0 and D['selector_round_trips']==0 and D['reader_writes']==0,'DETERMINISTIC_READONLY')
req(D['automatic_binding'] is False and D['automatic_impact'] is False and D['production_authorized'] is False,'NO_PROMOTION')
print('LEARNING_SPECIALIZED_CONSUMER_AUTHORITY_GUARD=PASS consumers=2/2 direct_injection=false delivery=false')
for script in (
    'validate_learning_specialized_consumer_activation_guard_v1.py',
    'validate_learning_specialized_consumer_activation_negative_v1.py',
    'validate_learning_specialized_consumer_failclosed_benchmark_50_v1.py',
):
    r=subprocess.run([sys.executable,str(R/script)],capture_output=True,text=True)
    if r.stdout: print(r.stdout.strip())
    if r.returncode:
        if r.stderr: sys.stderr.write(r.stderr)
        raise SystemExit(r.returncode)
print('LEARNING_SPECIALIZED_CONSUMER_AUTHORITY_EXTENSION=PASS activation_guard=1 negative=12/12 benchmark=50/50')

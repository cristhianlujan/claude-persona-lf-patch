#!/usr/bin/env python3
from __future__ import annotations
import json,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
FIX=ROOT/'sandbox/lf_contract_gate_test/learning_read_only_context_rows_fixture_v1.json'
CLI=ROOT/'sandbox/lf_contract_gate_test/learning_read_only_context_reader_cli_v1.py'

def main() -> int:
    data=FIX.read_text(encoding='utf-8')
    cmd=[sys.executable,str(CLI),'--binding-id','BIND-LF-PD-NEGOCIACION-DEUDA-v2']
    run=subprocess.run(cmd,input=data,text=True,capture_output=True,cwd=ROOT)
    if run.returncode!=0: raise SystemExit(run.stderr or run.stdout)
    out=json.loads(run.stdout)
    assert out['binding_id']=='BIND-LF-PD-NEGOCIACION-DEUDA-v2'
    assert out['consumer_id']=='PERFIL-PRODUCT-DIRECTOR-LF'
    assert out['capability_id']=='NEGOCIACION_DEUDA'
    assert out['selected_count']==2
    assert [x['kb_id'] for x in out['selected']]==['19461cc1-dc9c-4261-8b36-2bc8401160a1','07fec06f-51fd-4b3f-a322-114878881f5c']
    assert out['llm_calls']==0 and out['round_trips']==0 and out['tool_calls']==0
    assert out['context_bytes']<=out['max_context_bytes']<=6000
    assert all(x['kb_id']!='not-bound' for x in out['selected'])
    bad=subprocess.run([sys.executable,str(CLI),'--binding-id','UNKNOWN'],input=data,text=True,capture_output=True,cwd=ROOT)
    assert bad.returncode!=0 and 'EXACT_BINDING_NOT_FOUND' in (bad.stderr+bad.stdout)
    print('LEARNING_READ_ONLY_CONTEXT_READER_CLI=PASS selected=2 unbound=blocked stale=blocked not_ready=blocked unknown_binding=blocked')
    return 0
if __name__=='__main__': raise SystemExit(main())

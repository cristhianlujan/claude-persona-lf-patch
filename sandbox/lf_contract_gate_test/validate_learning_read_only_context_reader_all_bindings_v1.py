#!/usr/bin/env python3
from __future__ import annotations
import json,subprocess,sys
from pathlib import Path
import yaml

ROOT=Path(__file__).resolve().parents[2]
BINDINGS=ROOT/'sandbox/lf_contract_gate_test/learning_consumer_bindings_v1.yaml'
CLI=ROOT/'sandbox/lf_contract_gate_test/learning_read_only_context_reader_cli_v1.py'

def main() -> int:
    doc=yaml.safe_load(BINDINGS.read_text(encoding='utf-8'))
    bindings=doc.get('bindings') or []
    assert len(bindings)==3
    results=[]
    for binding in bindings:
        ids=binding.get('source_learning_ids') or []
        assert ids
        good_id=ids[0]
        second_id=ids[1] if len(ids)>1 else ids[0]
        payload={'rows':[
            {'kb_id':good_id,'grounding_status':'GROUNDED','consumer_ready':True,'topic':'good','summary':'grounded exact binding','source_url':'https://example.test/good','competitor':'fixture','quality_score':0.9},
            {'kb_id':second_id,'grounding_status':'STALE','consumer_ready':True,'topic':'stale','summary':'blocked','source_url':'https://example.test/stale','competitor':'fixture','quality_score':0.9},
            {'kb_id':'not-bound-'+binding['capability_id'],'grounding_status':'GROUNDED','consumer_ready':True,'topic':'unbound','summary':'blocked','source_url':'https://example.test/unbound','competitor':'fixture','quality_score':1.0}
        ]}
        run=subprocess.run([sys.executable,str(CLI),'--binding-id',binding['binding_id']],input=json.dumps(payload),text=True,capture_output=True,cwd=ROOT)
        if run.returncode!=0: raise SystemExit(run.stderr or run.stdout)
        out=json.loads(run.stdout)
        assert out['binding_id']==binding['binding_id']
        assert out['consumer_id']==binding['consumer_id']
        assert out['capability_id']==binding['capability_id']
        assert out['selected_count']==1
        assert out['selected'][0]['kb_id']==good_id
        assert out['context_bytes']<=out['max_context_bytes']<=6000
        assert out['llm_calls']==0 and out['round_trips']==0 and out['tool_calls']==0
        results.append(binding['capability_id'])
    print('LEARNING_READ_ONLY_CONTEXT_READER_ALL_BINDINGS=PASS bindings=3 capabilities='+','.join(results))
    return 0

if __name__=='__main__': raise SystemExit(main())

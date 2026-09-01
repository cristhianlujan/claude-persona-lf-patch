#!/usr/bin/env python3
from __future__ import annotations
import argparse,json,sys
from pathlib import Path
import yaml
from learning_read_only_context_selector_v2 import BindingSpec, select_read_only_context

ROOT=Path(__file__).resolve().parents[2]
BINDINGS=ROOT/'sandbox/lf_contract_gate_test/learning_consumer_bindings_v1.yaml'

def load_binding(binding_id: str) -> BindingSpec:
    doc=yaml.safe_load(BINDINGS.read_text(encoding='utf-8'))
    for item in doc.get('bindings',[]):
        if item.get('binding_id')==binding_id:
            budget=(item.get('context_budget') or {}).get('max_bytes',6000)
            return BindingSpec(
                consumer_id=item['consumer_id'],
                capability_id=item['capability_id'],
                source_learning_ids=tuple(item.get('source_learning_ids') or ()),
                max_evidence_refs=min(5,len(item.get('selected_evidence_refs') or ()) or 5),
                max_context_bytes=min(6000,int(budget)),
            )
    raise SystemExit('EXACT_BINDING_NOT_FOUND')

def main() -> int:
    ap=argparse.ArgumentParser()
    ap.add_argument('--binding-id',required=True)
    args=ap.parse_args()
    payload=json.load(sys.stdin)
    rows=payload if isinstance(payload,list) else payload.get('rows',[])
    if not isinstance(rows,list): raise SystemExit('ROWS_ARRAY_REQUIRED')
    binding=load_binding(args.binding_id)
    out=select_read_only_context(rows,binding=binding)
    out['binding_id']=args.binding_id
    out['source']='STDIN_READ_ONLY_ROWS'
    print(json.dumps(out,ensure_ascii=False,sort_keys=True,separators=(',',':')))
    return 0

if __name__=='__main__': raise SystemExit(main())

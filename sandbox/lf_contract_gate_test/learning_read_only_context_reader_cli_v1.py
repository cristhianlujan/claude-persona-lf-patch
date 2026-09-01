#!/usr/bin/env python3
from __future__ import annotations
import argparse,json,sys
from pathlib import Path
import yaml
from learning_read_only_context_selector_v2 import BindingSpec, select_read_only_context

ROOT=Path(__file__).resolve().parents[2]
DEFAULT_BINDINGS=ROOT/'sandbox/lf_contract_gate_test/learning_consumer_bindings_v1.yaml'
ALLOWED_BINDING_DIR=(ROOT/'sandbox/lf_contract_gate_test').resolve()


def _resolve_bindings_path(value: str | None) -> Path:
    path=(Path(value) if value else DEFAULT_BINDINGS).resolve()
    if path.parent != ALLOWED_BINDING_DIR:
        raise SystemExit('BINDINGS_FILE_OUTSIDE_GOVERNED_SANDBOX')
    if not path.name.startswith('learning_') or path.suffix not in {'.yaml','.yml'}:
        raise SystemExit('BINDINGS_FILE_NOT_GOVERNED_LEARNING_CONTRACT')
    if not path.is_file():
        raise SystemExit('BINDINGS_FILE_NOT_FOUND')
    return path


def load_binding(binding_id: str, *, bindings_path: Path=DEFAULT_BINDINGS) -> BindingSpec:
    doc=yaml.safe_load(bindings_path.read_text(encoding='utf-8'))
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
    ap.add_argument('--bindings-file')
    args=ap.parse_args()
    payload=json.load(sys.stdin)
    rows=payload if isinstance(payload,list) else payload.get('rows',[])
    if not isinstance(rows,list): raise SystemExit('ROWS_ARRAY_REQUIRED')
    bindings_path=_resolve_bindings_path(args.bindings_file)
    binding=load_binding(args.binding_id,bindings_path=bindings_path)
    out=select_read_only_context(rows,binding=binding)
    out['binding_id']=args.binding_id
    out['bindings_file']=bindings_path.name
    out['source']='STDIN_READ_ONLY_ROWS'
    print(json.dumps(out,ensure_ascii=False,sort_keys=True,separators=(',',':')))
    return 0

if __name__=='__main__': raise SystemExit(main())

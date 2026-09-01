#!/usr/bin/env python3
import json
from pathlib import Path
R=Path(__file__).resolve().parent
PACK=json.loads((R/'ui_architect_learning_context_pack_v1.json').read_text())
READBACK=json.loads((R/'ui_architect_learning_kb_eligibility_readback_v1.json').read_text())

def main():
    rows={r['kb_id']:r for r in READBACK['rows']}
    selected=[]
    for spec in PACK['capabilities'].values():
        for kid in spec['source_learning_ids']:
            selected.append(rows[kid])
    selected={x['kb_id']:x for x in selected}.values()
    payload=json.dumps(list(selected),sort_keys=True,separators=(',',':')).encode()
    challenger=len(payload)
    budget=PACK['selection']['max_context_bytes']
    assert challenger<=budget
    assert len(list(selected))<=PACK['selection']['max_evidence_refs']
    print(f'UI_ARCHITECT_CONTEXT_MEASUREMENT=PASS challenger_bytes={challenger} budget_bytes={budget} selected_unique={len(list(selected))} selector_llm_calls=0 selector_round_trips=0')
if __name__=='__main__': main()

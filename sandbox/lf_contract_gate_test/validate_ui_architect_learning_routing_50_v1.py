#!/usr/bin/env python3
import json
from pathlib import Path

P=Path(__file__).resolve().parent/'ui_architect_learning_routing_cases_50_v1.json'

def route(c):
    k=c['task_kind']; current=c['product_direction_current']; instruction=c.get('instruction')
    if instruction: return 'FAIL_CLOSED'
    if not current: return 'NO_COMPETITIVE_CONTEXT'
    if k.startswith('ui_') and k.endswith('_self_service') and k not in {'ui_gamification','ui_admin_backoffice','ui_marketing_landing','ui_support_chat','ui_internal_audit'}:
        return 'DIGITAL_SELF_SERVICE'
    if k.startswith('ui_') and k.endswith('_payment_no_adeudo'):
        return 'PAYMENT_NO_ADEUDO'
    return 'NO_COMPETITIVE_CONTEXT'

def main():
    d=json.loads(P.read_text()); total=passed=tp=tn=fp=fn=0
    assert d['case_count']==50 and d['family_count']==10
    for fam in d['families']:
        assert len(fam['cases'])==5
        for c in fam['cases']:
            total+=1; got=route(c); exp=fam['expected']; passed+=got==exp
            positive=exp in {'DIGITAL_SELF_SERVICE','PAYMENT_NO_ADEUDO'}
            predicted=got in {'DIGITAL_SELF_SERVICE','PAYMENT_NO_ADEUDO'}
            if positive and predicted: tp+=1
            elif not positive and not predicted: tn+=1
            elif not positive and predicted: fp+=1
            else: fn+=1
    assert passed==50 and fp==0 and fn==0
    precision=tp/(tp+fp) if tp+fp else 1.0; recall=tp/(tp+fn) if tp+fn else 1.0; specificity=tn/(tn+fp) if tn+fp else 1.0
    print(f'UI_ARCHITECT_ROUTING_GOLD50=PASS cases={passed}/{total} families=10x5 TP={tp} TN={tn} FP={fp} FN={fn} precision={precision:.3f} recall={recall:.3f} specificity={specificity:.3f}')
if __name__=='__main__': main()

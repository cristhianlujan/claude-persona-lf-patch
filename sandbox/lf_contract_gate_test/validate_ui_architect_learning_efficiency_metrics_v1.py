#!/usr/bin/env python3
import json
from pathlib import Path
P=Path(__file__).resolve().parent/'ui_architect_learning_efficiency_metrics_v1.json'
def main():
 d=json.loads(P.read_text(encoding='utf-8'))
 assert d['schema']=='LEARNING_EFFICIENCY_METRICS_V1'
 assert d['consumer_id']=='PERFIL-UI-ARCHITECT'
 assert d['evidence_mode']=='DETERMINISTIC_CONTRACT_AND_ROUTING_ONLY'
 r=d['routing']; assert r=={'cases':50,'families':10,'tp':10,'tn':40,'fp':0,'fn':0,'precision':1.0,'recall':1.0,'specificity':1.0}
 c=d['context']; assert c['challenger_bytes']==1047 and c['challenger_bytes']<=c['max_challenger_bytes'] and c['requirement_retention']=='5/5'
 assert c['context_reduction_pct']=='INSUFFICIENT_EVIDENCE_BEHAVIORAL_CHAMPION_NOT_EXECUTED'
 e=d['efficiency']; assert e['selector_llm_calls']==0 and e['selector_round_trips']==0 and e['reader_writes']==0 and e['semantic_search'] is False and e['deterministic_share']==1.0
 assert d['quality']['critical_must_not_invoke_fp']==0
 assert d['performance']['runtime_case_p95_ms']=='NOT_OBSERVED'
 s=d['stability']; assert s['selector_permutations']=='60/60' and s['selector_ordering']=='QUALITY_DESC_RECEIPT_DESC_KB_ID_ASC' and s['selector_repeatability']=='PASS_DETERMINISTIC' and s['runtime_repeatability']=='NOT_OBSERVED_RUNTIME_NOT_EXECUTED'
 assert d['outcome']=='INSUFFICIENT_EVIDENCE' and d['production_authorized'] is False
 print('UI_ARCHITECT_LEARNING_EFFICIENCY=PASS routing=50/50 stability=60/60 challenger_bytes=1047/5000 retention=5/5 llm=0 rt=0 writes=0 runtime=NOT_OBSERVED outcome=INSUFFICIENT_EVIDENCE')
if __name__=='__main__': main()

#!/usr/bin/env python3
import json
from pathlib import Path
P=Path(__file__).resolve().parent/'product_director_learning_efficiency_metrics_v1.json'
REQ=["eligible_count","retrieved_count","relevant_retrieved","applied_count","retrieval_precision","retrieval_recall","application_rate","repeat_error_rate","context_bytes_or_tokens","supabase_queries","learning_lookup_latency"]
def main():
 d=json.loads(P.read_text(encoding='utf-8'))
 assert d['schema']=='LEARNING_EFFICIENCY_METRICS_V1' and d['consumer_id']=='PERFIL-PRODUCT-DIRECTOR-LF'
 assert d['evidence_mode']=='DETERMINISTIC_CONTRACT_AND_ROUTING_ONLY'
 m=d['canonical_metric_contract']
 assert m['contract_ref']=='programacion.contratos#43' and m['contract_code']=='LEARNING_EFFICIENCY_METRICS_V1' and m['contract_state']=='draft'
 assert m['fail_closed'] is True and m['activation_authorized'] is False and m['unknown_semantics']=='must_be_null_or_explicit_not_observed'
 assert m['required_metrics']==REQ and set(m['values'])==set(REQ) and len(m['values'])==11
 assert m['values']['eligible_count']==35
 for k,v in m['values'].items():
  if k!='eligible_count': assert v is None or (isinstance(v,str) and 'NOT_OBSERVED' in v)
 r=d['routing']; assert r=={'cases':50,'families':10,'tp':25,'tn':25,'fp':0,'fn':0,'precision':1.0,'recall':1.0,'specificity':1.0}
 c=d['context']; assert c['selected_learning_ids_total']==13 and c['max_active_capabilities_per_request']==1 and c['max_evidence_refs_per_capability']==5 and c['max_challenger_bytes_per_request']==6000
 assert c['requirement_retention']=='5/5_CONTRACT_SECTIONS' and c['context_reduction_pct']=='INSUFFICIENT_EVIDENCE_BEHAVIORAL_CHAMPION_NOT_EXECUTED'
 e=d['efficiency']; assert e['selector_llm_calls']==0 and e['selector_round_trips']==0 and e['reader_writes']==0 and e['semantic_search'] is False and e['deterministic_share']==1.0
 assert d['quality']['critical_must_not_invoke_fp']==0 and d['performance']['runtime_case_p95_ms']=='NOT_OBSERVED'
 s=d['stability']; assert s['selector_permutations']=='60/60' and s['selector_ordering']=='QUALITY_DESC_RECEIPT_DESC_KB_ID_ASC' and s['selector_repeatability']=='PASS_DETERMINISTIC' and s['runtime_repeatability']=='NOT_OBSERVED_RUNTIME_NOT_EXECUTED'
 assert d['outcome']=='INSUFFICIENT_EVIDENCE' and d['production_authorized'] is False
 print('PRODUCT_DIRECTOR_LEARNING_EFFICIENCY=PASS routing=50/50 stability=60/60 canonical_metrics=11/11 observed=1 unknown_explicit=10 activation_authorized=false outcome=INSUFFICIENT_EVIDENCE')
if __name__=='__main__': main()

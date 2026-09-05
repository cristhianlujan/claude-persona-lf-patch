#!/usr/bin/env python3
import json,subprocess,sys
from pathlib import Path
R=Path(__file__).resolve().parent
C=json.loads((R/'learning_cluster_consumer_coverage_readback_v1.json').read_text())
D=json.loads((R/'learning_consumer_dynamic_cluster_bindings_v1.json').read_text())
def main():
 bound={c for b in D['bindings'] for c in b['cluster_codes']}
 assert C['source_contract']=='gobernanza/contratos/contrato_learning_bridge_kb_card_lf.yaml'
 assert C['taxonomy_version']==D['taxonomy_version']=='LF_LEARNING_CLUSTER_V1'
 assert bound==set(C['bound_cluster_codes'])
 assert C['eligible_total']==C['classified_total']==35 and C['unclassified_total']==0
 assert set(C['unbound_cluster_codes']).isdisjoint(bound)
 assert C['unbound_policy']=='READY_FOR_BINDING_ONLY_NO_AUTOMATIC_CONSUMER'
 assert C['existing_card_check_required_before_binding'] is True
 assert C['automatic_binding'] is False
 assert {'REINSERCION_FINANCIERA','CAMPANAS_Y_OFERTAS','BENCHMARK_PERIFERICO'}==set(C['unbound_cluster_codes'])
 assert D['fallback']=='NO_COMPETITIVE_CONTEXT' and D['automatic_impact'] is False
 assert D['boundedness']['llm_calls_for_selection']==0 and D['boundedness']['round_trips_for_selection']==0 and D['boundedness']['reader_writes']==0 and D['boundedness']['semantic_search'] is False
 assert {x['consumer_id'] for x in D['explicit_nonbindings']}=={'PERFIL-GAMIFICATION-SYSTEM-ARCHITECT','ACT-0051','PERFIL-CX-TRUST-EXPERIENCE-ARCHITECT-LF-20260531','PERFIL-UX-PRODUCT-EXPERIENCE-ARCHITECT-LF-20260531'}
 p=subprocess.run([sys.executable,str(R/'validate_learning_competitive_source_backlog_readback_v1.py')],capture_output=True,text=True)
 if p.returncode!=0: raise SystemExit(p.stdout+p.stderr)
 print(p.stdout.strip())
 print('LEARNING_CLUSTER_CONSUMER_COVERAGE=PASS eligible_classified=35/35 bound_clusters=5 unbound_clusters=3 explicit_nonbindings=4 source_backlog_checked=true card_check_required=true')
if __name__=='__main__': main()

#!/usr/bin/env python3
import json
from pathlib import Path
R=Path(__file__).resolve().parent
C=json.loads((R/'learning_cluster_consumer_coverage_readback_v1.json').read_text())
D=json.loads((R/'learning_consumer_dynamic_cluster_bindings_v1.json').read_text())
def main():
 bound={c for b in D['bindings'] for c in b['cluster_codes']}
 assert bound==set(C['bound_cluster_codes'])
 assert C['eligible_total']==C['classified_total']==35 and C['unclassified_total']==0
 assert set(C['unbound_cluster_codes']).isdisjoint(bound)
 assert C['unbound_policy']=='READY_FOR_BINDING_ONLY_NO_AUTOMATIC_CONSUMER'
 assert {'REINSERCION_FINANCIERA','CAMPANAS_Y_OFERTAS','BENCHMARK_PERIFERICO'}==set(C['unbound_cluster_codes'])
 assert D['fallback']=='NO_COMPETITIVE_CONTEXT' and D['automatic_impact'] is False
 print('LEARNING_CLUSTER_CONSUMER_COVERAGE=PASS eligible_classified=35/35 bound_clusters=5 unbound_clusters=3 unbound_fail_closed=3/3')
if __name__=='__main__': main()

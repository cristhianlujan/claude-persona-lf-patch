#!/usr/bin/env python3
from pathlib import Path
import json
from learning_read_only_context_service_v1 import build_context,LearningContextBlocked
ROOT=Path(__file__).resolve().parents[2]
FIXTURE=json.loads((ROOT/'sandbox/lf_contract_gate_test/learning_read_only_context_rows_fixture_v1.json').read_text())
ROWS=FIXTURE['rows']
def blocked(**kw):
 try: build_context(rows=ROWS,**kw)
 except (LearningContextBlocked,ValueError): return True
 return False
def main():
 pd=build_context(consumer_id='PERFIL-PRODUCT-DIRECTOR-LF',binding_id='BIND-LF-PD-NEGOCIACION-DEUDA-v2',rows=ROWS)
 assert pd['router_asset']=='ACT-0001' and pd['selected_count']==2 and pd['llm_calls']==0 and pd['round_trips']==0 and pd['writes']==0
 ui=build_context(consumer_id='PERFIL-UI-ARCHITECT',binding_id='BIND-LF-UI-NEGOCIACION-PRESENTATION-v1',rows=ROWS,upstream_current=True,upstream_artifact_ref='product-direction://fixture/current')
 assert ui['selected_count']==2 and ui['max_context_bytes']<=5000 and ui['upstream_artifact_ref']
 assert blocked(consumer_id='PERFIL-UI-ARCHITECT',binding_id='BIND-LF-UI-NEGOCIACION-PRESENTATION-v1',upstream_current=False,upstream_artifact_ref='x')
 assert blocked(consumer_id='PERFIL-UI-ARCHITECT',binding_id='BIND-LF-UI-NEGOCIACION-PRESENTATION-v1',upstream_current=True,upstream_artifact_ref=None)
 assert blocked(consumer_id='FRONTEND_IMPLEMENTATION',binding_id='X')
 print('LEARNING_CONTEXT_SERVICE=PASS router_first=1 consumers=2 selected_pd=2 selected_ui=2 llm=0 roundtrips=0 writes=0 production=0')
 return 0
if __name__=='__main__': raise SystemExit(main())

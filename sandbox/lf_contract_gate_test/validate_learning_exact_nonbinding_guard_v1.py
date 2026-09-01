#!/usr/bin/env python3
import json, subprocess, sys
from pathlib import Path
R=Path(__file__).resolve().parent
D=json.loads((R/'learning_exact_nonbinding_guard_v1.json').read_text())
def req(c,m):
    if not c: raise SystemExit('FAIL_'+m)
req(D['schema']=='LF_LEARNING_EXACT_NONBINDING_GUARD_V1','SCHEMA')
req(D['mode']=='READ_ONLY','MODE')
req(D['fallback']=='NO_COMPETITIVE_CONTEXT','FALLBACK')
req(D['selection_rule']=='NO_EXACT_BINDING_MEANS_NO_CONTEXT','SELECTION_RULE')
req({'public.lf_eventos/9872','public.lf_error_knowledge/LEARNING-DIRECT-CONSUMER-AUTHORITY-001','gobernanza/contratos/contrato_learning_bridge_kb_card_lf.yaml'} <= set(D['authority_refs']),'AUTHORITY_REFS')
rows={x['consumer_id']:x for x in D['explicit_nonbindings']}
req(len(rows)==4,'NONBINDINGS_COUNT')
for c in ('PERFIL-CX-TRUST-EXPERIENCE-ARCHITECT-LF-20260531','PERFIL-UX-PRODUCT-EXPERIENCE-ARCHITECT-LF-20260531'):
    req(rows[c]['reason']=='NO_DIRECT_GENERIC_INJECTION_RUNTIME_DISABLED','SPECIALIZED_AUTHORITY')
clusters={x['cluster_code']:x for x in D['unbound_clusters']}
req(set(clusters)=={'REINSERCION_FINANCIERA','CAMPANAS_Y_OFERTAS','BENCHMARK_PERIFERICO'},'CLUSTERS')
required={'novelty_assessed','risk_assessed','research_to_rules_matrix_present','decision_matrix_present','card_factory_contract_read'}
for code in ('REINSERCION_FINANCIERA','CAMPANAS_Y_OFERTAS'):
    req(clusters[code]['next_state']=='READY_FOR_BINDING_ONLY','READY_'+code)
    req(set(clusters[code]['required_before_card'])==required,'CARD_PRECONDITIONS_'+code)
    req(clusters[code]['automatic_card_creation'] is False,'NO_AUTO_CARD_'+code)
req(clusters['BENCHMARK_PERIFERICO']['next_state']=='NO_CARD','BENCH_NO_CARD')
for k in ('semantic_search','automatic_binding','automatic_card_creation','automatic_impact','production_authorized'):
    req(D[k] is False,'AUTH_'+k.upper())
print('LEARNING_EXACT_NONBINDING_GUARD=PASS authority_refs=3 explicit_nonbindings=4 unbound_clusters=3 no_direct_specialized=2 no_auto_card=3')
r=subprocess.run([sys.executable,str(R/'validate_learning_specialized_selector_nonbinding_v1.py')],capture_output=True,text=True)
if r.stdout: print(r.stdout.strip())
if r.returncode:
    if r.stderr: sys.stderr.write(r.stderr)
    raise SystemExit(r.returncode)

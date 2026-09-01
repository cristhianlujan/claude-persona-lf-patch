#!/usr/bin/env python3
from pathlib import Path
import yaml
ROOT=Path(__file__).resolve().parents[2]
P=ROOT/'sandbox/lf_contract_gate_test/learning_read_only_consumer_registry_v1.yaml'
def fail(x): raise SystemExit('FAIL learning-consumer-registry: '+x)
def main():
 d=yaml.safe_load(P.read_text()); c=d.get('consumers') or []; b=d.get('blocked_consumers') or []
 if d.get('status')!='CANDIDATO_READ_ONLY' or d.get('router_asset')!='ACT-0001' or d.get('selection')!='DETERMINISTIC_EXACT_BINDING': fail('root')
 ids={x['consumer_id'] for x in c};
 if ids!={'PERFIL-PRODUCT-DIRECTOR-LF','PERFIL-UI-ARCHITECT'}: fail(str(ids))
 ui=next(x for x in c if x['consumer_id']=='PERFIL-UI-ARCHITECT')
 if ui.get('upstream_consumer_id')!='PERFIL-PRODUCT-DIRECTOR-LF' or ui.get('upstream_current_required') is not True: fail('UI upstream')
 for x in c:
  if x.get('read_only_enabled_candidate') is not True or x.get('production_impact') is not False: fail('enabled/impact')
  for f in ('binding_file','context_pack_file'):
   p=(P.parent/x[f]).resolve()
   if p.parent!=P.parent.resolve() or not p.is_file(): fail('missing contract '+x[f])
 blocked={x['consumer_id']:x['state'] for x in b}
 if blocked.get('FRONTEND_IMPLEMENTATION')!='BLOCKED_NO_EXACT_BINDING' or blocked.get('GAMIFICATION')!='BLOCKED_NO_EXACT_BINDING' or blocked.get('GENERIC_PROFILE')!='BLOCKED_NO_EXACT_BINDING': fail('blocked consumers')
 prohib=set(d.get('prohibitions') or [])
 if not {'implicit_consumer_selection','direct_learning_to_frontend','direct_learning_to_gamification','automatic_promotion'}<=prohib: fail('prohibitions')
 if d.get('production_impact') is not False: fail('production')
 print('LEARNING_READ_ONLY_CONSUMER_REGISTRY=PASS enabled_candidates=2 blocked_implicit=3 production=0')
 return 0
if __name__=='__main__': raise SystemExit(main())

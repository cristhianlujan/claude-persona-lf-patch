#!/usr/bin/env python3
from learning_read_only_consumer_resolver_v1 import resolve_consumer,ConsumerRouteBlocked

def main():
 pd=resolve_consumer('PERFIL-PRODUCT-DIRECTOR-LF'); ui=resolve_consumer('PERFIL-UI-ARCHITECT')
 assert pd['router_asset']=='ACT-0001' and pd['router_action']=='EJECUCION_PERFIL_LF' and pd['upstream_required'] is False
 assert ui['upstream_required'] is True and ui['upstream_consumer_id']=='PERFIL-PRODUCT-DIRECTOR-LF' and ui['upstream_artifact']=='product_direction_ref' and ui['upstream_current_required'] is True
 for blocked in ('FRONTEND_IMPLEMENTATION','GAMIFICATION','GENERIC_PROFILE','UNKNOWN'):
  try: resolve_consumer(blocked)
  except ConsumerRouteBlocked: pass
  else: raise SystemExit('FAIL resolver allowed '+blocked)
 print('LEARNING_CONSUMER_RESOLVER=PASS enabled=2 blocked=4 router=ACT-0001 production=0')
 return 0
if __name__=='__main__': raise SystemExit(main())

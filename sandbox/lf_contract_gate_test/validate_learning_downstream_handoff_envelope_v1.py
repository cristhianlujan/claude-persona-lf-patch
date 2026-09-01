#!/usr/bin/env python3
from learning_downstream_handoff_envelope_v1 import build_frontend_handoff,build_gamification_handoff,DownstreamHandoffBlocked

def must_block(fn,**kw):
 try: fn(**kw)
 except DownstreamHandoffBlocked: return
 raise SystemExit('FAIL downstream handoff did not block')
def main():
 f=build_frontend_handoff(product_direction_ref='product://current',ui_spec_ref='ui://current',approved_constraints={'cta':'preserve','states':['idle','error']},current=True)
 assert f['consumer_id']=='ACT-0051' and f['direct_learning_context'] is False and f['learning_llm_calls']==0 and f['production_impact'] is False
 g=build_gamification_handoff(objective_ref='objective://current',authorized_objective={'healthy_behavior':'clarity_completion','guardrails':['no_pressure']},current=True)
 assert g['consumer_id']=='PERFIL-GAMIFICATION-SYSTEM-ARCHITECT' and g['direct_learning_context'] is False and g['learning_llm_calls']==0
 must_block(build_frontend_handoff,product_direction_ref='p',ui_spec_ref='u',approved_constraints={'source_learning_ids':['x']},current=True)
 must_block(build_gamification_handoff,objective_ref='o',authorized_objective={'competitive_kb_rows':[]},current=True)
 must_block(build_frontend_handoff,product_direction_ref='p',ui_spec_ref='u',approved_constraints={},current=False)
 print('LEARNING_DOWNSTREAM_HANDOFF=PASS frontend=1 gamification=1 raw_learning=blocked extra_learning_llm=0 production=0')
 return 0
if __name__=='__main__': raise SystemExit(main())

#!/usr/bin/env python3
from __future__ import annotations
import json,re
from collections import Counter
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
CONTRACT=ROOT/'sandbox/lf_contract_gate_test/learning_downstream_consumer_handoff_v1.json'
CASES=ROOT/'sandbox/lf_contract_gate_test/learning_downstream_no_bypass_cases_v1.yaml'

def fail(msg): raise SystemExit('FAIL learning-downstream-no-bypass: '+msg)

def decide_frontend(direct_kb,product_direction,ui_spec):
 if direct_kb: return 'BLOCK_DIRECT_KB'
 if not product_direction: return 'RETURN_PRODUCT_DIRECTION'
 if not ui_spec: return 'RETURN_UI_ARCHITECT'
 return 'ALLOW_UPSTREAM_CONTEXT'

def decide_gamification(direct_kb,objective,guardrails,harmful):
 if direct_kb: return 'BLOCK_DIRECT_KB'
 if harmful: return 'BLOCK_HARMFUL_MECHANIC'
 if not objective or not guardrails: return 'RETURN_PRODUCT_DIRECTION'
 return 'ALLOW_UPSTREAM_CONTEXT'

def b(x): return x=='true'

def main():
 c=json.loads(CONTRACT.read_text())
 if c.get('direct_kb_injection') is not False or c.get('production_impact') is not False: fail('unsafe contract flags')
 consumers={x['consumer_id']:x for x in c.get('consumers',[])}
 if set(consumers)!={'ACT-0051','PERFIL-GAMIFICATION-SYSTEM-ARCHITECT'}: fail('consumer set mismatch')
 for cid,x in consumers.items():
  if not x.get('required_upstream') or not x.get('must_not_receive') or x.get('automatic_promotion') is not False: fail(f'{cid} incomplete')
 lines=[x.strip() for x in CASES.read_text().splitlines() if x.strip().startswith('- {id:')]
 if len(lines)!=40: fail(f'cases={len(lines)}')
 counts=Counter(); passed=0
 for line in lines:
  if 'consumer: ACT-0051' in line:
   m=re.search(r'direct_kb: (true|false), product_direction: (true|false), ui_spec: (true|false), expect: ([A-Z_]+)',line)
   if not m: fail('frontend malformed')
   got=decide_frontend(b(m.group(1)),b(m.group(2)),b(m.group(3))); exp=m.group(4); counts['ACT-0051']+=1
  else:
   m=re.search(r'direct_kb: (true|false), objective: (true|false), guardrails: (true|false), harmful_mechanic: (true|false), expect: ([A-Z_]+)',line)
   if not m: fail('gamification malformed')
   got=decide_gamification(b(m.group(1)),b(m.group(2)),b(m.group(3)),b(m.group(4))); exp=m.group(5); counts['PERFIL-GAMIFICATION-SYSTEM-ARCHITECT']+=1
  if got!=exp: fail(f'{line} got={got}')
  passed+=1
 if counts['ACT-0051']!=20 or counts['PERFIL-GAMIFICATION-SYSTEM-ARCHITECT']!=20: fail(str(counts))
 print(f'LEARNING_DOWNSTREAM_NO_BYPASS=PASS cases={passed}/40 frontend=20/20 gamification=20/20 direct_kb_injection=0')
 return 0
if __name__=='__main__': raise SystemExit(main())

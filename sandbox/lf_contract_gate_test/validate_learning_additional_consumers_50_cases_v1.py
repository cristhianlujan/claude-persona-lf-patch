#!/usr/bin/env python3
from __future__ import annotations
import json,subprocess,sys
from collections import Counter
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
S=ROOT/'sandbox/lf_contract_gate_test'
CASES=S/'learning_additional_consumers_50_cases_v1.json'
RUNNER=S/'run_learning_additional_consumers_routing_benchmark_v1.py'
EXPECTED_FAMILIES={'HAPPY_PATH','OUT_OF_SCOPE_NO_INVOKE','MISSING_AUTHORITY','CLAIM_BOUNDARY_NEGATIVE','TEMPORAL_CURRENTNESS','STATES_RECOVERY','CONFLICT_PRECEDENCE','CARDINALITY_EXACT','MULTI_DOMAIN_COMPLEX','REGRESSION_HISTORICAL'}

def fail(msg): raise SystemExit('FAIL learning-additional-consumers-50-cases: '+msg)

def main():
 d=json.loads(CASES.read_text()); cases=d.get('cases',[])
 if len(cases)!=50: fail(f'cases={len(cases)}')
 ids=[x.get('id') for x in cases]
 if len(set(ids))!=50: fail('duplicate ids')
 fam=Counter(x.get('family') for x in cases)
 if set(fam)!=EXPECTED_FAMILIES or any(v!=5 for v in fam.values()): fail('family shape')
 if not any(x.get('expected_route')=='MUST_NOT_INVOKE' for x in cases): fail('must-not-invoke missing')
 if not any(x.get('expected_route')=='BLOCK_DIRECT_LEARNING' for x in cases): fail('direct-learning negatives missing')
 if not any(x.get('expected_route')=='BLOCK_CLAIM_BOUNDARY' for x in cases): fail('claim-boundary negatives missing')
 p=subprocess.run([sys.executable,str(RUNNER)],cwd=ROOT,text=True,capture_output=True)
 if p.returncode!=0: fail('runner failed '+p.stdout+' '+p.stderr)
 out=json.loads(p.stdout)
 if out.get('cases')!=50 or out.get('families')!=10 or out.get('passed')!=50: fail('benchmark counts')
 r=out.get('routing',{})
 if r.get('fp')!=0 or r.get('fn')!=0 or r.get('precision')!=1.0 or r.get('recall')!=1.0 or r.get('specificity')!=1.0: fail('routing metrics')
 if out.get('llm_calls')!=0 or out.get('round_trips')!=0 or out.get('tool_calls')!=0 or out.get('production_impact') is not False: fail('efficiency/impact')
 print('LEARNING_ADDITIONAL_CONSUMERS_50_CASES=PASS cases=50 families=10 fp=0 fn=0 precision=1 recall=1 specificity=1 llm_calls=0')
if __name__=='__main__': main()

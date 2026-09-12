#!/usr/bin/env python3
from __future__ import annotations
import json, sys
from pathlib import Path
from evaluate_s26_profile_baseline import evaluate

def main() -> int:
    if len(sys.argv) not in (2,3):
        print('usage: plan_s26_profile_update.py <profile_slug> [repo_root]',file=sys.stderr); return 2
    slug=sys.argv[1]; repo=Path(sys.argv[2]).resolve() if len(sys.argv)==3 else Path(__file__).resolve().parents[3]
    evaluation=evaluate(repo,slug)
    plan={
      'schema':'S26_PROFILE_UPDATE_PLAN_V1','operation_code':'ACTUALIZACION_PERFIL_LF','profile_slug':slug,
      'baseline_evaluation':evaluation,
      'decision':evaluation['decision'],
      'ordered_actions':evaluation['repair_actions'],
      'write_allowed':evaluation['decision']=='UPDATE_REQUIRED' and not evaluation['blocking_codes'],
      'authority_resolution_required':evaluation['decision']=='BLOCKED_AUTHORITY_REQUIRED',
      'closure_requirement':'POST_WRITE_BASELINE_10_OF_10_PLUS_EXISTING_OPERATION_GATES',
      'automatic_runtime_activation':False,'automatic_production_activation':False,
    }
    print(json.dumps(plan,indent=2,sort_keys=True))
    return 0 if plan['decision'] in {'NO_UPDATE_REQUIRED','UPDATE_REQUIRED'} else 3
if __name__=='__main__': raise SystemExit(main())

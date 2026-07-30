#!/usr/bin/env python3
from __future__ import annotations
import argparse, hashlib, json
from pathlib import Path
import yaml
ROOT=Path(__file__).resolve().parents[2]
SKILL=ROOT/'skills'/'creating-integral-user-stories'
PATH=SKILL/'manifest.yaml'
REQUIRED_TOP={'skill_code','version','status','operation_code','execution_id','canonical_store','source_authority','validator_dependencies','github_contract','package_contract','quality_policy','files','auxiliary_files','workflow','chain_policy','limits','current_state'}

def canonical_paths(data):
    rows=[]
    for values in data.get('files',{}).values():
        if isinstance(values,list): rows.extend(str(x) for x in values)
    return rows

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('--report-dir',type=Path,required=True); a=ap.parse_args()
    raw=PATH.read_bytes(); data=yaml.safe_load(raw.decode())
    paths=canonical_paths(data) if isinstance(data,dict) else []
    checks={
      'yaml_object':isinstance(data,dict),
      'required_top_level':isinstance(data,dict) and REQUIRED_TOP<=set(data),
      'candidate_read_only':data.get('status')=='CANDIDATO_READ_ONLY',
      'execution_current':data.get('execution_id')=='EXEC-BISC-005-DEEP-AUDIT',
      'github_repo_exact':data.get('github_contract',{}).get('repository')=='cristhianlujan/claude-persona-lf-patch',
      'github_base_exact':data.get('github_contract',{}).get('base_branch')=='feat/integral-story-creator-r8-forward',
      'github_target_exact':data.get('github_contract',{}).get('target_branch')=='fix/deep-audit-a01-a62',
      'draft_pr_57':data.get('github_contract',{}).get('draft_pr_number')==57,
      'no_direct_main':data.get('github_contract',{}).get('direct_main_write')=='BLOCKED',
      'merge_false':data.get('github_contract',{}).get('merge_allowed') is False,
      'canonical_count_declared':data.get('package_contract',{}).get('canonical_file_count')==62,
      'canonical_paths_62_unique':len(paths)==62 and len(set(paths))==62,
      'canonical_paths_exist':all((SKILL/x).is_file() for x in paths),
      'auxiliary_disjoint':not(set(paths)&set(data.get('auxiliary_files',[]))),
      'workflow_13_ordered':[(x.get('order'),x.get('judge')) for x in data.get('workflow',{}).get('steps',[])]==[(i, f'J{i:02d}_'+['SOURCE_INTEGRITY','SCREEN_DECOMPOSITION','STORY_CORE','FIELD_CONTRACTS','OBSERVATIONS_ERRORS','SECURITY_PRIVACY','AUDIT_TRACEABILITY','TOKENS_MESSAGES','ANALYTICS_OBSERVABILITY','TEST_COVERAGE','SKILL_PACKAGE','GITHUB_INTEGRITY','INTEGRATION_CLOSE'][i-1]) for i in range(1,14)],
      'dual_gate':data.get('quality_policy',{}).get('benchmark_gate')=='DUAL_REQUIRED',
      'score_formula_min':data.get('quality_policy',{}).get('score_formula')=='MIN(CLAUDE,GITHUB,TECHNICAL)',
      'minimum_exclusive_9_5':float(data.get('quality_policy',{}).get('minimum_score_exclusive',0))==9.5,
      'no_temporal_star_counts':all('stars_verified' not in x for x in data.get('quality_policy',{}).get('github_references',[])),
      'limits_preserved':all(data.get('limits',{}).get(k) is True for k in ('no_validated','no_production','no_runtime_enable','no_merge','no_direct_main_write','no_force_push','no_release','no_tag')),
      'deep_reaudit_in_progress':data.get('current_state',{}).get('global_close')=='DEEP_REAUDIT_IN_PROGRESS',
      'confirmed_count_22':data.get('current_state',{}).get('confirmed_artifact_count')==22,
    }
    score=10.0 if all(checks.values()) else round(8+2*sum(checks.values())/len(checks),2)
    out={'artifact_code':'A23','relative_path':'manifest.yaml','sha256':hashlib.sha256(raw).hexdigest(),'checks':checks,'claude_score':score,'github_score':score,'technical_score':score,'final_score':score,'result':'PASS_WITH_EVIDENCE' if score>9.5 and all(checks.values()) else 'RETURN_TO_WORKER','findings':[k for k,v in checks.items() if not v]}
    a.report_dir.mkdir(parents=True,exist_ok=True); (a.report_dir/'A23.json').write_text(json.dumps(out,ensure_ascii=False,indent=2)+'\n'); print(json.dumps(out,ensure_ascii=False,sort_keys=True)); return 0 if out['result']=='PASS_WITH_EVIDENCE' else 1
if __name__=='__main__': raise SystemExit(main())

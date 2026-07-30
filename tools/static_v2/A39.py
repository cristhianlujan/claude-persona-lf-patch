#!/usr/bin/env python3
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import profile_audit
profile_audit.CONFIG['A39']={'path':'perfiles/PERFIL_STORY_CORE_AUTHOR_LF.md','agent':'agents/story-core-author.md','judges':['J03_STORY_CORE'],'writes':['identity','core','pending_decisions','evidence'],'quality':['missing_sections','core_keys_missing','criteria_without_given_when_then','duplicate_criterion_codes','stories_without_source_trace','context_budget_missing','context_budget_rule_violations','schema_validation_errors']}
if __name__=='__main__':
 import argparse
 parser=argparse.ArgumentParser();parser.add_argument('--report-dir',type=Path,required=True);args=parser.parse_args();raise SystemExit(profile_audit.run('A39','static',args.report_dir))

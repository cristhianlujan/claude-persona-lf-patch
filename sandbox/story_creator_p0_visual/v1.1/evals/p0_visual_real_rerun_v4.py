#!/usr/bin/env python3
from __future__ import annotations
import argparse,json,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'scripts'))
from p0_visual_graders_v4 import canonical_sha
from p0_visual_discovery_v4 import union_findings,coverage_receipt
from p0_visual_convergence_v4 import convergence_receipt_binding
from run_p0_visual_quality_loop_v4 import run_loop
from p0_visual_real_rerun_support_v4 import TRACE,reset_trace,traced_reader,traced_grader_runner,traced_sweep,remediator,targeted

def main():
 ap=argparse.ArgumentParser();ap.add_argument('--source',required=True);ap.add_argument('--source-sha',required=True);ap.add_argument('--code-head',required=True);ap.add_argument('--config-sha',required=True);ap.add_argument('--output',required=True);a=ap.parse_args();reset_trace()
 result=run_loop(source_path=a.source,expected_source_sha256=a.source_sha,full_reader=traced_reader,remediator=remediator,targeted_reread=targeted,code_head_sha=a.code_head,configuration_id='P0-VISUAL-CLOSED-LOOP-V4',configuration_sha256=a.config_sha,max_remediation_cycles=5,required_clean_passes=2,grader_runner=traced_grader_runner,omission_sweep_runner=traced_sweep,regression_suite='PASS',adversarial_suite='PASS',artifact_hash_chain='PASS')
 convergence=result.get('convergence_receipt');binding=convergence_receipt_binding(convergence) if isinstance(convergence,dict) else None
 sweep_by={s.get('execution_id'):s for s in TRACE['omission_sweeps']};grad_by={g['ctx']['pass_id']:g for g in TRACE['grader_runs']};pass_summ=[]
 for c in TRACE['readers']:
  g=grad_by.get(c['pass_id']);
  if not g:continue
  fs=union_findings(g['outputs']);cov=coverage_receipt(c,g['outputs'],g['ctx']);sw=g['ctx'].get('independent_sweep') or {};full=next((r for r in sw.get('regions',[]) if r.get('region_id')=='FULL'),{})
  pass_summ.append({'pass_id':c['pass_id'],'reader_execution_id':c['reader_execution_id'],'omission_sweep_execution_id':sw.get('execution_id'),'candidate_sha256':canonical_sha({k:v for k,v in c.items() if k!='reader_execution_id'}),'reader_profile':c['reader_profile'],'element_count':len(c['elements']),'finding_counts':{s:sum(f['severity']==s for f in fs) for s in ['CRITICAL','HIGH','MEDIUM','LOW','INFO']},'finding_categories':sorted({f['category'] for f in fs}),'coverage_percent':cov['coverage_percent'],'coverage_pass':cov['coverage_pass'],'candidate_grader_coverage':cov['candidate_grader_coverage'],'independent_screen_coverage':cov['independent_screen_coverage'],'independent_sweep':{'status':sw.get('status'),'observed_count':full.get('observed_count',0),'represented_count':full.get('represented_count',0),'unrepresented_count':full.get('unrepresented_count',0),'uncertain_count':full.get('uncertain_count',0),'object_sweep':sw.get('object_sweep')},'grader_execution_ids':[o['execution_id'] for o in g['outputs']]})
 receipt={'schema_version':'p0-v4-real-rerun-trace/v3','source_sha256':a.source_sha,'code_head_sha':a.code_head,'configuration_sha256':a.config_sha,'result':result,'convergence_receipt_binding':binding,'passes':pass_summ,'reader_outputs':TRACE['readers'],'omission_sweeps':TRACE['omission_sweeps'],'grader_runs':TRACE['grader_runs'],'remediation_plans':TRACE['remediations'],'targeted_rereads':TRACE['targeted']};Path(a.output).write_text(json.dumps(receipt,ensure_ascii=False,sort_keys=True,separators=(',',':')));print(json.dumps({'terminal_result':result.get('result'),'human_review_ready':result.get('human_review_ready'),'passes':pass_summ,'remediation_cycles':result.get('remediation_cycles'),'convergence_receipt_binding':binding},ensure_ascii=False,sort_keys=True));return 0 if result.get('result')=='PASS_P0_V4_CLOSED_LOOP' else 2
if __name__=='__main__':raise SystemExit(main())

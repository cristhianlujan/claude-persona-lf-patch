#!/usr/bin/env python3
from __future__ import annotations
import argparse,hashlib,json,os,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'scripts'))
from p0_visual_graders_v4 import canonical_sha
from p0_visual_discovery_v4 import union_findings,coverage_receipt
from p0_visual_convergence_v4 import convergence_receipt_binding,make_gate_proof
from run_p0_visual_quality_loop_v4 import run_loop
from p0_visual_real_rerun_support_v4 import TRACE,reset_trace,traced_reader,traced_grader_runner,traced_sweep,remediator,targeted

def file_sha(path:Path)->str:return hashlib.sha256(path.read_bytes()).hexdigest()
def last_json(text:str):
 for line in reversed([x.strip() for x in text.splitlines() if x.strip()]):
  try:
   value=json.loads(line)
   if isinstance(value,dict):return value
  except json.JSONDecodeError:pass
 return None
def execute_gate(rel:str,validator)->dict:
 path=ROOT/rel;p=subprocess.run([sys.executable,str(path)],cwd=ROOT.parent.parent,text=True,capture_output=True,check=False,env=os.environ.copy());parsed=last_json(p.stdout);ok=p.returncode==0 and isinstance(parsed,dict) and validator(parsed)
 return {'path':rel,'exit_code':p.returncode,'stdout_sha256':hashlib.sha256(p.stdout.encode()).hexdigest(),'stderr_sha256':hashlib.sha256(p.stderr.encode()).hexdigest(),'parsed':parsed,'passed':ok}
def build_gate_proofs(*,source_sha:str,head:str,config_sha:str)->tuple[dict,dict,dict,dict]:
 if os.environ.get('P0_CI_ENGINEERING_REGRESSION') is not None:raise RuntimeError('ENGINEERING_REGRESSION_OVERRIDE_FORBIDDEN')
 repo_root=ROOT.parents[2];observed_head=subprocess.run(['git','rev-parse','HEAD'],cwd=repo_root,text=True,capture_output=True,check=True).stdout.strip()
 if observed_head!=head:raise RuntimeError('CODE_HEAD_SHA_MISMATCH')
 config_path=ROOT/'evals/p0-closed-loop-runtime-config-v4.json'
 if file_sha(config_path)!=config_sha:raise RuntimeError('CONFIGURATION_SHA_MISMATCH')
 runtime=execute_gate('evals/p0_visual_quality_runtime_regression_suite.py',lambda x:x.get('result')=='PASS_WITH_EVIDENCE' and x.get('required')==15 and x.get('passed')==15)
 negative=execute_gate('evals/p0_machine_visual_quality_negative_suite_v2.py',lambda x:x.get('result')=='PASS_WITH_EVIDENCE' and x.get('required')==28 and x.get('passed')==28 and x.get('positive_restore_count')==28)
 forward=execute_gate('evals/p0_visual_forward_adversarial_v4.py',lambda x:x.get('gate')=='PASS_V4_FORWARD_ADVERSARIAL' and x.get('critical_false_passes')==0)
 atomic=execute_gate('evals/p0_visual_known_failure_regression_v4.py',lambda x:x.get('gate')=='PASS_V4_HUMAN_FINDINGS_AS_REGRESSIONS' and x.get('atomic_segmentation_defended') is True)
 if not runtime['passed']:raise RuntimeError('RUNTIME_REGRESSION_NOT_PROVEN')
 if not negative['passed'] or not forward['passed']:raise RuntimeError('ADVERSARIAL_SUITE_NOT_PROVEN')
 if not atomic['passed']:raise RuntimeError('ATOMIC_SEGMENTATION_REGRESSION_NOT_PROVEN')
 regression=make_gate_proof(gate='regression_suite',source_sha256=source_sha,code_head_sha=head,configuration_sha256=config_sha,details={'runtime_regression':runtime,'atomic_segmentation_regression':atomic})
 adversarial=make_gate_proof(gate='adversarial_suite',source_sha256=source_sha,code_head_sha=head,configuration_sha256=config_sha,details={'required_negative':negative,'forward_adversarial':forward})
 artifact_rel=['scripts/p0_full_reader_v4.py','scripts/p0_visual_grader_structure_v4.py','scripts/p0_visual_convergence_v4.py','scripts/run_p0_visual_quality_loop_v4.py','evals/p0_visual_real_rerun_v4.py','evals/p0_visual_quality_runtime_regression_suite.py','evals/p0_visual_known_failure_regression_v4.py','evals/p0_machine_visual_quality_negative_suite_v2.py','evals/p0_visual_forward_adversarial_v4.py','evals/p0-closed-loop-runtime-config-v4.json','requirements-p0-visual-quality.txt']
 hashes={rel:file_sha(ROOT/rel) for rel in artifact_rel};chain=hashlib.sha256(json.dumps(hashes,sort_keys=True,separators=(',',':')).encode()).hexdigest()
 artifact=make_gate_proof(gate='artifact_hash_chain',source_sha256=source_sha,code_head_sha=head,configuration_sha256=config_sha,details={'files':hashes,'chain_sha256':chain,'file_count':len(hashes)})
 return regression,adversarial,artifact,{'runtime_regression':runtime,'atomic_segmentation_regression':atomic,'required_negative':negative,'forward_adversarial':forward,'artifact_chain_sha256':chain}
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--source',required=True);ap.add_argument('--source-sha',required=True);ap.add_argument('--code-head',required=True);ap.add_argument('--config-sha',required=True);ap.add_argument('--output',required=True);a=ap.parse_args();reset_trace()
 try:regression,adversarial,artifact,preflight=build_gate_proofs(source_sha=a.source_sha,head=a.code_head,config_sha=a.config_sha)
 except Exception as exc:
  blocked={'schema_version':'p0-v4-real-rerun-trace/v5','source_sha256':a.source_sha,'code_head_sha':a.code_head,'configuration_sha256':a.config_sha,'result':{'result':'BLOCKED_GATE_PROOF','human_review_ready':False,'reason':str(exc)},'human_review_packet':{'human_adjudication':'NOT_PERFORMED','p0_5_state':'UNASSESSED_SEPARATE','production_authorized':False}};Path(a.output).write_text(json.dumps(blocked,ensure_ascii=False,sort_keys=True,separators=(',',':')));print(json.dumps({'terminal_result':'BLOCKED_GATE_PROOF','reason':str(exc)},sort_keys=True));return 2
 result=run_loop(source_path=a.source,expected_source_sha256=a.source_sha,full_reader=traced_reader,remediator=remediator,targeted_reread=targeted,code_head_sha=a.code_head,configuration_id='P0-VISUAL-CLOSED-LOOP-V4',configuration_sha256=a.config_sha,max_remediation_cycles=5,required_clean_passes=2,grader_runner=traced_grader_runner,omission_sweep_runner=traced_sweep,regression_proof=regression,adversarial_proof=adversarial,artifact_hash_proof=artifact)
 convergence=result.get('convergence_receipt');binding=convergence_receipt_binding(convergence) if isinstance(convergence,dict) else None
 grad_by={g['ctx']['pass_id']:g for g in TRACE['grader_runs']};pass_summ=[]
 for c in TRACE['readers']:
  g=grad_by.get(c['pass_id']);
  if not g:continue
  fs=union_findings(g['outputs']);cov=coverage_receipt(c,g['outputs'],g['ctx']);sw=g['ctx'].get('independent_sweep') or {};full=next((r for r in sw.get('regions',[]) if r.get('region_id')=='FULL'),{})
  pass_summ.append({'pass_id':c['pass_id'],'reader_execution_id':c['reader_execution_id'],'omission_sweep_execution_id':sw.get('execution_id'),'candidate_sha256':canonical_sha({k:v for k,v in c.items() if k!='reader_execution_id'}),'reader_profile':c['reader_profile'],'element_count':len(c['elements']),'finding_counts':{s:sum(f['severity']==s for f in fs) for s in ['CRITICAL','HIGH','MEDIUM','LOW','INFO']},'finding_categories':sorted({f['category'] for f in fs}),'coverage_percent':cov['coverage_percent'],'coverage_pass':cov['coverage_pass'],'candidate_grader_coverage':cov['candidate_grader_coverage'],'independent_screen_coverage':cov['independent_screen_coverage'],'independent_sweep':{'status':sw.get('status'),'observed_count':full.get('observed_count',0),'represented_count':full.get('represented_count',0),'unrepresented_count':full.get('unrepresented_count',0),'uncertain_count':full.get('uncertain_count',0),'object_sweep':sw.get('object_sweep'),'materiality_policy':sw.get('materiality_policy')},'grader_execution_ids':[o['execution_id'] for o in g['outputs']]})
 human_packet={'schema_version':'p0-v4-human-review-packet-technical/v1','technical_gate_result':result.get('result'),'human_adjudication':'NOT_PERFORMED','p0_5_state':'UNASSESSED_SEPARATE','production_authorized':False,'limitations':[],'convergence_receipt_binding':binding}
 if isinstance(binding,dict):human_packet['limitations'].append({'code':'OCR_ENGINE_FAMILY_SINGLE','severity':'MEDIUM','status':'DISCLOSED','detail':binding.get('detector_diversity')})
 receipt={'schema_version':'p0-v4-real-rerun-trace/v5','source_sha256':a.source_sha,'code_head_sha':a.code_head,'configuration_sha256':a.config_sha,'gate_preflight':preflight,'result':result,'convergence_receipt_binding':binding,'human_review_packet':human_packet,'passes':pass_summ,'reader_outputs':TRACE['readers'],'omission_sweeps':TRACE['omission_sweeps'],'grader_runs':TRACE['grader_runs'],'remediation_plans':TRACE['remediations'],'targeted_rereads':TRACE['targeted']};Path(a.output).write_text(json.dumps(receipt,ensure_ascii=False,sort_keys=True,separators=(',',':')));print(json.dumps({'terminal_result':result.get('result'),'human_review_ready':result.get('human_review_ready'),'passes':pass_summ,'remediation_cycles':result.get('remediation_cycles'),'gate_preflight':preflight,'convergence_receipt_binding':binding,'human_review_packet':human_packet},ensure_ascii=False,sort_keys=True));return 0 if result.get('result')=='PASS_P0_V4_CLOSED_LOOP' else 2
if __name__=='__main__':raise SystemExit(main())

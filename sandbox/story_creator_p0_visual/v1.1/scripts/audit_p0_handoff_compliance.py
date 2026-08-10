#!/usr/bin/env python3
"""Strict final gate for p0-handoff-compliance-report/v1."""
from __future__ import annotations
import argparse,json,re
from pathlib import Path

def validate(r:dict)->dict:
    failures=[]
    if r.get('schema_version')!='p0-handoff-compliance-report/v1':failures.append('schema_version')
    if not re.fullmatch(r'[0-9a-f]{64}',str(r.get('handoff_sha256',''))):failures.append('handoff_sha256')
    if not re.fullmatch(r'[0-9a-f]{40}',str(r.get('audited_sha',''))):failures.append('audited_sha')
    total=r.get('total_sections'); applicable=r.get('applicable_sections')
    if not isinstance(total,int) or total<53:failures.append('all_handoff_sections_not_inventoried')
    if not isinstance(applicable,int) or applicable<1:failures.append('applicable_sections_invalid')
    if r.get('sections_partial')!=0:failures.append('section_partials_nonzero')
    if r.get('sections_fail')!=0:failures.append('section_failures_nonzero')
    if r.get('sections_pass')!=applicable:failures.append('applicable_sections_not_all_pass')
    if r.get('positive_coverage_rows_total')!=60 or r.get('positive_coverage_rows_pass')!=60:failures.append('positive_coverage_not_60_of_60')
    if r.get('negative_tests_required')!=28 or r.get('negative_tests_executed')!=28 or r.get('negative_tests_passed')!=28:failures.append('negative_suite_not_28_of_28')
    dod_total=r.get('definition_of_done_total');dod_passed=r.get('definition_of_done_passed')
    if not isinstance(dod_total,int) or dod_total<1 or dod_passed!=dod_total:failures.append('definition_of_done_incomplete')
    if r.get('unresolved_gaps')!=[]:failures.append('unresolved_internal_gaps')
    ft=r.get('forward_test') if isinstance(r.get('forward_test'),dict) else {}
    if ft.get('result')!='PASS' or ft.get('false_passes')!=[]:failures.append('forward_test_false_pass')
    expected='PASS_HANDOFF_COMPLIANCE' if not failures else 'BLOCKED_HANDOFF_COMPLIANCE'
    if r.get('final_result')!=expected:failures.append('final_result_not_derived')
    return {'result':'PASS_HANDOFF_COMPLIANCE' if not failures else 'BLOCKED_HANDOFF_COMPLIANCE','blocking_assertions':sorted(set(failures))}

def self_test()->int:
    base={'schema_version':'p0-handoff-compliance-report/v1','handoff_identifier':'H','handoff_sha256':'a'*64,'audited_sha':'b'*40,'audit_execution_id':'A','auditor_identity':'FRESH_P0_HANDOFF_AUDITOR','total_sections':53,'applicable_sections':53,'sections_pass':53,'sections_partial':0,'sections_fail':0,'sections_blocked':0,'positive_coverage_rows_total':60,'positive_coverage_rows_pass':60,'negative_tests_required':28,'negative_tests_executed':28,'negative_tests_passed':28,'definition_of_done_total':30,'definition_of_done_passed':30,'unresolved_gaps':[],'remediation_cycles':1,'regressions_added':['N01-N28','R01-R15'],'forward_test':{'result':'PASS','false_passes':[]},'final_result':'PASS_HANDOFF_COMPLIANCE','created_at':'2026-08-10T00:00:00Z'}
    positive=validate(base)['result']=='PASS_HANDOFF_COMPLIANCE'; negatives=[]
    for key,value in [('sections_partial',1),('positive_coverage_rows_pass',59),('negative_tests_passed',27),('definition_of_done_passed',29),('unresolved_gaps',[{'x':1}])]:
        x=json.loads(json.dumps(base));x[key]=value;x['final_result']='BLOCKED_HANDOFF_COMPLIANCE';negatives.append(validate(x)['result']=='BLOCKED_HANDOFF_COMPLIANCE')
    x=json.loads(json.dumps(base));x['forward_test']={'result':'BLOCKED','false_passes':['bypass']};x['final_result']='BLOCKED_HANDOFF_COMPLIANCE';negatives.append(validate(x)['result']=='BLOCKED_HANDOFF_COMPLIANCE')
    ok=positive and all(negatives);print(json.dumps({'schema_version':'p0-handoff-compliance-selftest/v1','result':'PASS_WITH_EVIDENCE' if ok else 'BLOCKED','positive':positive,'negatives_passed':sum(negatives),'negatives_total':len(negatives)},sort_keys=True));return 0 if ok else 2

def main()->int:
    ap=argparse.ArgumentParser();ap.add_argument('--report',type=Path);ap.add_argument('--self-test',action='store_true');a=ap.parse_args()
    if a.self_test:return self_test()
    if not a.report:ap.error('--report required')
    out=validate(json.loads(a.report.read_text()));print(json.dumps(out,sort_keys=True));return 0 if out['result']=='PASS_HANDOFF_COMPLIANCE' else 2
if __name__=='__main__':raise SystemExit(main())

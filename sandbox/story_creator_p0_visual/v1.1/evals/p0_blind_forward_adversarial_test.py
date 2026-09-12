#!/usr/bin/env python3
"""Fresh adversarial forward-test: source + candidate + contract only; find false PASS."""
from __future__ import annotations
import copy,os,json,sys,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts'));sys.path.insert(0,str(ROOT/'evals'))
from consolidate_p0_visual_reading import Box,canonical_sha
from run_p0_visual_judge import audit_candidate
from validate_p0_machine_visual_quality import derive
from p0_machine_visual_quality_negative_suite_v2 import make_image,baseline,remove_id,add_fake_element

def main()->int:
    config=json.loads((ROOT/'evals/p0-visual-quality-runtime-config.json').read_text())
    if os.environ.get('P0_CI_ENGINEERING_REGRESSION')=='1':
        from consolidate_p0_visual_reading import runtime_versions
        config['dependencies']=runtime_versions();config['configuration_id']='P0-CI-ENGINEERING-REGRESSION-v1';config['calibration']['calibration_reference']='ci://engineering-regression/not-operational-quality'
    false_passes=[]; attempts=[]
    with tempfile.TemporaryDirectory(prefix='p0-forward-') as td:
        image=Path(td)/'source.png';make_image(image);candidate,judge,report,_=baseline(image,config)
        def live(name,c):
            j=audit_candidate(image,c,execution_id='FRESH-J00-'+name,identity='FRESH_P0_VISUAL_JUDGE',reader_execution_id=c['execution_id'],config=config)
            passed=j.get('judgment')=='PASS';attempts.append({'name':name,'surface':'J00','passed':passed,'finding_count':len(j.get('findings',[]))})
            if passed:false_passes.append(name)
        c=copy.deepcopy(candidate);remove_id(c,next(e['element_id'] for e in c['elements'] if e['element_type']=='BUTTON'));live('missing_material_action',c)
        c=copy.deepcopy(candidate);root=next(e['element_id'] for e in c['elements'] if e['parent_id'] is None);add_fake_element(c,'ICON',Box(760,20,18,18),root);live('unsupported_visible_claim',c)
        c=copy.deepcopy(candidate);b=next(e for e in c['elements'] if e['element_type']=='BUTTON');b['element_type']='INPUT';b['semantic_role']='form_control';live('semantic_type_swap',c)
        c=copy.deepcopy(candidate);root=next(e['element_id'] for e in c['elements'] if e['parent_id'] is None)
        for e in c['elements']:
            if e['element_id']!=root:e['parent_id']=root
        c['ui_structure']['visual_containment_tree']['edges']=[{'parent':root,'child':e['element_id']} for e in c['elements'] if e['element_id']!=root];live('flattened_structure',c)
        j=audit_candidate(image,candidate,execution_id=candidate['execution_id'],identity='P0_VISUAL_READER',reader_execution_id=candidate['execution_id'],config=config);passed=j.get('judgment')=='PASS';attempts.append({'name':'judge_identity_reuse','surface':'J00','passed':passed});false_passes += ['judge_identity_reuse'] if passed else []
        for name,mut in [('edited_ready_flag',lambda r:r.update(human_review_ready=False)),('stale_calibration',lambda r:r['checks'].update(calibration_policy_current=False)),('critical_omission_counter',lambda r:r['counts'].update(critical_omissions=1))]:
            r=copy.deepcopy(report);mut(r);g=derive(r,candidate,judge);passed=g.get('human_review_ready') is True;attempts.append({'name':name,'surface':'P0H','passed':passed,'blocking':g.get('blocking_assertions',[])});false_passes += [name] if passed else []
    result='PASS' if not false_passes else 'BLOCKED';out={'schema_version':'p0-blind-forward-test/v1','auditor_identity':'FRESH_P0_FORWARD_ADVERSARY','input_scope':['source','candidate','contracts'],'attempted_bypasses':len(attempts),'attempts':attempts,'false_passes':false_passes,'result':result};print(json.dumps(out,sort_keys=True));return 0 if result=='PASS' else 2
if __name__=='__main__':raise SystemExit(main())

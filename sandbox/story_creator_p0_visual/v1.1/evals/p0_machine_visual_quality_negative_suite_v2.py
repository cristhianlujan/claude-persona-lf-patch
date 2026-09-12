#!/usr/bin/env python3
"""Required P0 N01-N28 fail-closed suite with positive restore after every case."""
from __future__ import annotations
import copy,os,hashlib,json,struct,sys,tempfile
from pathlib import Path
from typing import Any,Callable
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'scripts'))
import cv2
import numpy as np
from PIL import Image,ImageOps
from consolidate_p0_visual_reading import build_consolidated,canonical_bytes,canonical_sha,evidence_ref,Box,sha256_bytes
from run_p0_visual_judge import audit_candidate
from run_p0_visual_quality_loop import run_loop,validate_admission,empirical_p0_5_eligible
from validate_p0_machine_visual_quality import derive,LEGACY_BAD_SHA
from validate_p0_human_review_packet_v3 import validate as validate_packet
from validate_p0_visual_quality_receipt import validate as validate_receipt
def make_image(path:Path)->None:
    img=np.full((600,800,3),255,np.uint8);cv2.rectangle(img,(300,70),(770,570),(210,210,210),2);cv2.putText(img,'Libertad Financiera',(30,40),cv2.FONT_HERSHEY_SIMPLEX,.7,(0,80,0),2,cv2.LINE_AA)
    for x in (350,475,600):cv2.rectangle(img,(x,105),(x+105,111),(120,120,120),-1)
    cv2.putText(img,'Paso 1 de 3',(350,145),cv2.FONT_HERSHEY_SIMPLEX,.45,(30,30,30),1,cv2.LINE_AA)
    for y,label,text in [(180,'Nombre','Tu nombre'),(250,'Tipo','DNI'),(320,'Email','correo@ejemplo.com')]:
        cv2.putText(img,label,(350,y-8),cv2.FONT_HERSHEY_SIMPLEX,.4,(30,30,30),1,cv2.LINE_AA);cv2.rectangle(img,(345,y),(725,y+50),(100,100,100),2);cv2.circle(img,(370,y+25),8,(80,80,80),2);cv2.putText(img,text,(390,y+31),cv2.FONT_HERSHEY_SIMPLEX,.45,(70,70,70),1,cv2.LINE_AA)
    for i,y in enumerate((390,430,470),1):cv2.rectangle(img,(350,y),(372,y+22),(80,80,80),2);cv2.putText(img,f'Acepto condicion {i}',(385,y+17),cv2.FONT_HERSHEY_SIMPLEX,.4,(40,40,40),1,cv2.LINE_AA)
    cv2.rectangle(img,(345,515),(725,565),(0,155,40),-1);cv2.putText(img,'Continuar',(470,548),cv2.FONT_HERSHEY_SIMPLEX,.6,(255,255,255),2,cv2.LINE_AA)
    if not cv2.imwrite(str(path),img):raise RuntimeError('fixture_write_failed')
def make_admission(image_path:Path,path:Path)->dict[str,Any]:
    raw=image_path.read_bytes();im=ImageOps.exif_transpose(Image.open(image_path)).convert('RGBA');normalized=hashlib.sha256(struct.pack('>II',im.width,im.height)+im.tobytes()).hexdigest();adm={'schema_version':'p0-image-admission/v1','source_ref':'image://SYNTH-P0-NEGATIVE','raw_bytes_sha256':sha256_bytes(raw),'normalized_pixel_sha256':normalized,'width':im.width,'height':im.height,'decoder_name':'Pillow','decoder_version':'12.3.0','input_format':'PNG','normalized_mode':'RGBA','processing_manifest_sha256':'0'*64};path.write_text(json.dumps(adm));return adm
def sanitize_fixture(candidate:dict[str,Any])->dict[str,Any]:
    c=copy.deepcopy(candidate);drop=set()
    for e in c['elements']:
        r=e['region']
        if e.get('machine_resolution_status')=='REMEDIATION_REQUIRED':drop.add(e['element_id'])
        if e['element_type']=='ICON' and r['width']>100:drop.add(e['element_id'])
        if e['element_type']=='CHECKBOX' and r['y']<370:drop.add(e['element_id'])
    c['elements']=[e for e in c['elements'] if e['element_id'] not in drop];tree=c['ui_structure']['visual_containment_tree'];tree['edges']=[e for e in tree['edges'] if e['child'] not in drop and e['parent'] not in drop];c['ui_structure']['candidate_reading_orders']=[[eid for eid in order if eid not in drop] for order in c['ui_structure']['candidate_reading_orders']];c['execution_id']='SYNTH-READER-CANONICAL';return c
def baseline(image:Path,config:dict[str,Any])->tuple[dict[str,Any],dict[str,Any],dict[str,Any],dict[str,Any]]:
    raw,_=build_consolidated(image,source_image_ref='SYNTH-P0-NEGATIVE',execution_id='SYNTH-READER-RAW',config=config,created_at='2026-08-10T00:00:00Z');c=sanitize_fixture(raw);j=audit_candidate(image,c,execution_id='SYNTH-J00-CANONICAL',identity='P0_VISUAL_JUDGE',reader_execution_id=c['execution_id'],config=config,created_at='2026-08-10T00:00:00Z')
    if j['judgment']!='PASS':raise AssertionError('canonical synthetic J00 must PASS: '+json.dumps(j,sort_keys=True))
    counts={'consolidated_elements':len(c['elements']),'confirmed':sum(e['classification']=='CONFIRMED' for e in c['elements']),'inferred':sum(e['classification']=='INFERRED' for e in c['elements']),'not_observable':sum(e['classification']=='NOT_OBSERVABLE' for e in c['elements']),'audit_only':0,'reader_only':0,'contradictions':0,'unsupported_claims':0,'critical_omissions':0,'noncritical_omissions':0,'unresolved_critical_uncertainties':0,'pending_remediations':0};checks={k:True for k in ('evidence_integrity_pass','visual_structure_pass','visual_semantic_pass','visual_completeness_pass','source_admission_binding_pass','j00_independence_pass','security_pass','privacy_pass','model_configuration_registered','calibration_policy_current','packet_hashes_reconcilable')};r={'schema_version':'p0-machine-visual-quality-report/v1','execution_id':'SYNTH-QUALITY','source_image_refs':['SYNTH-P0-NEGATIVE'],'source_sha256':c['source_sha256'],'raw_visual_output_sha256':'1'*64,'consolidated_visual_reading_sha256':canonical_sha(c),'p0h_execution_id':'SYNTH-P0H','j00_execution_id':j['execution_id'],'j00_identity':j['identity'],'remediation_cycles':0,'max_remediation_cycles':3,'counts':counts,'checks':checks,'result':'PASS_VISUAL_QUALITY','human_review_ready':True,'blocking_assertions':[],'created_at':'2026-08-10T00:00:00Z','model_configuration_id':config['configuration_id'],'calibration_reference':config['calibration']['calibration_reference']};p={'schema_version':'p0-human-review-packet-v3/v1','review_id':'REV-SYNTH','execution_id':'EXEC-SYNTH','source_refs':['SYNTH-P0-NEGATIVE'],'raw_visual_output_ref':'artifact://raw','consolidated_visual_reading_ref':'artifact://consolidated','machine_quality_report_ref':'artifact://quality','machine_quality_report_sha256':hashlib.sha256(canonical_bytes(r)).hexdigest(),'j00_judgment_ref':'artifact://j00','human_review_ready':True,'reviewer_role':'P0_VISUAL_ADJUDICATOR','expires_at':'2026-08-11T00:00:00Z','data_classification':'INTERNAL','summary':{},'region_rows':[]};assert derive(r,c,j)['human_review_ready'] is True;assert validate_packet(p,r,c,j)['human_review_ready'] is True;return c,j,r,p
def add_fake_element(c:dict[str,Any],etype:str,box:Box,parent:str)->str:
    eid='EL-FAKE-'+etype;e={'element_id':eid,'source_image_ref':'SYNTH-P0-NEGATIVE','parent_id':parent,'region':box.as_region(),'element_type':etype,'visible_text':None,'semantic_role':'synthetic_negative','visual_state':'STATIC_VISIBLE','classification':'CONFIRMED','confidence':.99,'evidence_refs':[evidence_ref(c['source_sha256'],box)],'source_observation_refs':[],'uncertainty_codes':[],'machine_resolution_status':'RESOLVED'};c['elements'].append(e);c['ui_structure']['visual_containment_tree']['edges'].append({'parent':parent,'child':eid});return eid
def remove_id(c:dict[str,Any],eid:str)->None:
    c['elements']=[e for e in c['elements'] if e['element_id']!=eid];c['ui_structure']['visual_containment_tree']['edges']=[x for x in c['ui_structure']['visual_containment_tree']['edges'] if x.get('child')!=eid and x.get('parent')!=eid];c['ui_structure']['candidate_reading_orders']=[[x for x in order if x!=eid] for order in c['ui_structure']['candidate_reading_orders']]
def main()->int:
    config=json.loads((ROOT/'evals/p0-visual-quality-runtime-config.json').read_text())
    if os.environ.get('P0_CI_ENGINEERING_REGRESSION')=='1':
        from consolidate_p0_visual_reading import runtime_versions
        config['dependencies']=runtime_versions();config['configuration_id']='P0-CI-ENGINEERING-REGRESSION-v1';config['calibration']['calibration_reference']='ci://engineering-regression/not-operational-quality'
    results={};restore_count=0
    with tempfile.TemporaryDirectory(prefix='p0-neg-v2-') as td:
        td=Path(td);image=td/'fixture.png';make_image(image);adm_path=td/'admission.json';adm=make_admission(image,adm_path);c0,j0,r0,p0=baseline(image,config);immutable_fingerprint=canonical_sha({'c':c0,'j':j0,'r':r0,'p':p0})
        def positive_restore()->None:
            nonlocal restore_count
            assert derive(copy.deepcopy(r0),copy.deepcopy(c0),copy.deepcopy(j0))['human_review_ready'] is True;assert validate_packet(copy.deepcopy(p0),copy.deepcopy(r0),copy.deepcopy(c0),copy.deepcopy(j0))['human_review_ready'] is True;assert canonical_sha({'c':c0,'j':j0,'r':r0,'p':p0})==immutable_fingerprint;restore_count+=1
        def case(name:str,fn:Callable[[],bool])->None:
            try:ok=bool(fn())
            except Exception as exc:print(f'{name} exception: {exc}',file=sys.stderr);ok=False
            results[name]=ok;positive_restore()
        case('N01_raw_ocr_attempts_human_ready',lambda:(lambda r:not derive(r,c0,j0)['human_review_ready'])((lambda r:(r.update(raw_visual_output_sha256=LEGACY_BAD_SHA) or r))(copy.deepcopy(r0))));case('N02_missing_p0h_report',lambda:not validate_packet(copy.deepcopy(p0),None,copy.deepcopy(c0),copy.deepcopy(j0))['human_review_ready']);case('N03_missing_j00',lambda:not validate_packet(copy.deepcopy(p0),copy.deepcopy(r0),copy.deepcopy(c0),None)['human_review_ready']);case('N04_quality_report_sha_tampered',lambda:(lambda p:not validate_packet(p,copy.deepcopy(r0),copy.deepcopy(c0),copy.deepcopy(j0))['human_review_ready'])((lambda p:(p.update(machine_quality_report_sha256='f'*64) or p))(copy.deepcopy(p0))));case('N05_consolidated_sha_tampered',lambda:(lambda c:not validate_packet(copy.deepcopy(p0),copy.deepcopy(r0),c,copy.deepcopy(j0))['human_review_ready'])((lambda c:(c['elements'][0].update(semantic_role='tampered') or c))(copy.deepcopy(c0))));case('N06_reader_judge_execution_reuse',lambda:(lambda r:not derive(r,c0,j0)['human_review_ready'])((lambda r:(r.update(execution_id=j0['execution_id']) or r))(copy.deepcopy(r0))));case('N07_reader_judge_identity_reuse',lambda:(lambda r:not derive(r,c0,j0)['human_review_ready'])((lambda r:(r.update(j00_identity='P0_VISUAL_READER') or r))(copy.deepcopy(r0))));case('N08_critical_omission_gt_zero',lambda:(lambda r:not derive(r,c0,j0)['human_review_ready'])((lambda r:(r['counts'].update(critical_omissions=1) or r))(copy.deepcopy(r0))));case('N09_contradiction_gt_zero',lambda:(lambda r:not derive(r,c0,j0)['human_review_ready'])((lambda r:(r['counts'].update(contradictions=1) or r))(copy.deepcopy(r0))));case('N10_pending_remediation_gt_zero',lambda:(lambda r:not derive(r,c0,j0)['human_review_ready'])((lambda r:(r['counts'].update(pending_remediations=1) or r))(copy.deepcopy(r0))));case('N11_unresolved_critical_uncertainty',lambda:(lambda r:not derive(r,c0,j0)['human_review_ready'])((lambda r:(r['counts'].update(unresolved_critical_uncertainties=1) or r))(copy.deepcopy(r0))))
        def n12():
            c=copy.deepcopy(c0);root=next(e['element_id'] for e in c['elements'] if e['parent_id'] is None)
            for e in c['elements']:
                if e['element_id']!=root:e['parent_id']=root
            c['ui_structure']['visual_containment_tree']['edges']=[{'parent':root,'child':e['element_id']} for e in c['elements'] if e['element_id']!=root];r=copy.deepcopy(r0);j=copy.deepcopy(j0);r['consolidated_visual_reading_sha256']=canonical_sha(c);j['candidate_sha256']=canonical_sha(c);return not derive(r,c,j)['human_review_ready']
        case('N12_flat_hierarchy',n12)
        def n13():
            c=copy.deepcopy(c0);parent=next(e['element_id'] for e in c['elements'] if e['element_type']=='REGION' and e['semantic_role']=='header');add_fake_element(c,'ICON',Box(740,15,20,20),parent);j=audit_candidate(image,c,execution_id='N13-J00',identity='P0_VISUAL_JUDGE',reader_execution_id=c['execution_id'],config=config);return j['judgment']=='BLOCKED' and any(x.get('reason')=='ICON_CROP_GEOMETRY_NOT_REDETECTED_BY_J00' for x in j['unsupported_claims'])
        case('N13_icon_claim_incompatible_crop',n13)
        def n14():
            c=copy.deepcopy(c0);form=next(e['element_id'] for e in c['elements'] if e['element_type']=='CONTAINER');add_fake_element(c,'CHECKBOX',Box(700,480,22,22),form);j=audit_candidate(image,c,execution_id='N14-J00',identity='P0_VISUAL_JUDGE',reader_execution_id=c['execution_id'],config=config);return j['judgment']=='BLOCKED' and any(x.get('reason')=='CHECKBOX_NOT_REDETECTED_BY_J00' for x in j['unsupported_claims'])
        case('N14_checkbox_claim_incompatible_crop',n14)
        def n15():
            c=copy.deepcopy(c0);btn=next(e for e in c['elements'] if e['element_type']=='BUTTON');btn['element_type']='INPUT';btn['semantic_role']='form_control';j=audit_candidate(image,c,execution_id='N15-J00',identity='P0_VISUAL_JUDGE',reader_execution_id=c['execution_id'],config=config);return j['judgment']=='BLOCKED' and any(x.get('reason')=='CONTROL_SEMANTIC_TYPE_MISMATCH' for x in j['contradictions'])
        case('N15_semantic_claim_tampered_crop_hash_intact',n15)
        def n16():
            c=copy.deepcopy(c0);target=next(e['element_id'] for e in c['elements'] if e['element_type']=='BUTTON');remove_id(c,target);j=audit_candidate(image,c,execution_id='N16-J00',identity='P0_VISUAL_JUDGE',reader_execution_id=c['execution_id'],config=config);return j['judgment']=='BLOCKED' and any(x.get('material') for x in j['audit_only'])
        case('N16_audit_only_material_removed',n16)
        def n17():
            bad=copy.deepcopy(adm);bad['raw_bytes_sha256']='0'*64;badp=td/'bad-admission.json';badp.write_text(json.dumps(bad));return validate_admission(image,badp,None)['pass'] is False
        case('N17_source_admission_mismatch',n17);case('N18_pass_flag_edited',lambda:(lambda r:not derive(r,c0,j0)['human_review_ready'])((lambda r:(r.update(human_review_ready=False) or r))(copy.deepcopy(r0))))
        def n19():
            r=copy.deepcopy(r0);r['result']='BLOCKED_VISUAL_QUALITY';r['human_review_ready']=True;p=copy.deepcopy(p0);p['machine_quality_report_sha256']=hashlib.sha256(canonical_bytes(r)).hexdigest();return not validate_packet(p,r,copy.deepcopy(c0),copy.deepcopy(j0))['human_review_ready']
        case('N19_human_ready_true_with_blocked',n19)
        def n20():return not validate_packet({'schema_version':'p0-human-review-packet-v2/v1','human_review_ready':True},copy.deepcopy(r0),copy.deepcopy(c0),copy.deepcopy(j0))['human_review_ready']
        case('N20_legacy_packet_attempts_new_gate',n20)
        def n21():
            import run_p0_visual_quality_loop as loop
            original=loop.remediate_once
            try:
                loop.remediate_once=lambda image_path,candidate,audit,config,cycle:(copy.deepcopy(candidate),[{'cycle':cycle,'action':'NO_STATE_CHANGE'}]);res=run_loop(image_path=image,admission_path=adm_path,processing_manifest_path=None,source_image_ref='SYNTH-P0-NEGATIVE',config=config,output_dir=td/'loop-no-progress',execution_id='N21-LOOP',judge_identity='P0_VISUAL_JUDGE');return res['result']=='BLOCKED_MAX_REMEDIATION' and res['human_review_ready'] is False
            finally:loop.remediate_once=original
        case('N21_max_remediation_no_progress_loop',n21)
        def n22():
            tiny=np.full((120,120,3),255,np.uint8);tp=td/'tiny.png';cv2.imwrite(str(tp),tiny);ta=td/'tiny-adm.json';make_admission(tp,ta);res=run_loop(image_path=tp,admission_path=ta,processing_manifest_path=None,source_image_ref='SYNTH-TINY',config=config,output_dir=td/'tiny-out',execution_id='N22',judge_identity='P0_VISUAL_JUDGE');return res['result']=='BLOCKED_SOURCE_QUALITY'
        case('N22_source_quality_insufficient_confirms',n22);case('N23_synthetic_fixture_empirical_denominator',lambda:empirical_p0_5_eligible(config,'SYNTHETIC_ADVERSARIAL') is False)
        def n24():
            cfg=copy.deepcopy(config);cfg['dependencies']['tesseract']='0.0.0';res=run_loop(image_path=image,admission_path=adm_path,processing_manifest_path=None,source_image_ref='SYNTH-P0-NEGATIVE',config=cfg,output_dir=td/'n24',execution_id='N24',judge_identity='P0_VISUAL_JUDGE');return res['result']=='BLOCKED_MODEL_CONFIGURATION'
        case('N24_unregistered_model_config',n24)
        def n25():
            cfg=copy.deepcopy(config);cfg['calibration']['status']='STALE';res=run_loop(image_path=image,admission_path=adm_path,processing_manifest_path=None,source_image_ref='SYNTH-P0-NEGATIVE',config=cfg,output_dir=td/'n25',execution_id='N25',judge_identity='P0_VISUAL_JUDGE');return res['result']=='BLOCKED_CALIBRATION'
        case('N25_stale_calibration',n25)
        def n26():
            receipt={'schema_version':'p0-visual-quality-loop-receipt/v1','p0_5_denominator_eligible':False,'final_candidate_sha256':canonical_sha(c0),'source_sha256':c0['source_sha256'],'human_review_ready':True,'cycles':[{'cycle':1,'before_candidate_sha256':'a','after_candidate_sha256':'b','state_changed':True,'actions':[{'targeted_reread':{'transform':{'source_region':{'x':20,'y':20,'width':30,'height':10},'expanded_source_crop':{'x':25,'y':25,'width':5,'height':5},'scale':3.0}}}]}]};return validate_receipt(receipt,c0,j0)['result']=='BLOCKED'
        case('N26_remediation_loses_coordinate_mapping',n26);case('N27_negative_test_contaminates_positive_fixture',lambda:canonical_sha({'c':c0,'j':j0,'r':r0,'p':p0})==immutable_fingerprint)
        def n28():
            c=copy.deepcopy(c0);text=next(e for e in c['elements'] if e.get('visible_text'));text['visible_text']=(text['visible_text'] or '')+' MUTATED';return not derive(copy.deepcopy(r0),c,copy.deepcopy(j0))['human_review_ready']
        case('N28_output_locked_mutated_after_j00',n28)
    failed=[k for k,v in results.items() if not v];out={'schema_version':'p0-required-negative-suite/v2','result':'PASS_WITH_EVIDENCE' if not failed and restore_count==28 else 'BLOCKED','required':28,'executed':len(results),'passed':sum(results.values()),'positive_restore_count':restore_count,'tests':results,'failed':failed};print(json.dumps(out,sort_keys=True));return 0 if out['result']=='PASS_WITH_EVIDENCE' else 2
if __name__=='__main__':raise SystemExit(main())

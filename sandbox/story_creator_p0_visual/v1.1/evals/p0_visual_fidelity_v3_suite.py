#!/usr/bin/env python3
"""P0 V3 mandatory R16-R40 + N29-N50 with positive restore after every negative."""
from __future__ import annotations
import copy,json,sys,tempfile,hashlib
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
import cv2,numpy as np
from p0_visual_fidelity_v3 import (enrich_candidate,validate_visual_fidelity,reconcile_auxiliary,
    remediate_visual_fidelity,human_review_packet,build_human_html,validate_packet_v4,validate_html_v4,
    validate_observed_style_against_bitmap,canonical_sha,compare_viewports,build_text_groups)
ROOT=Path(__file__).resolve().parents[1]
CFG=json.loads((ROOT/'evals/p0-visual-fidelity-runtime-config-v3.json').read_text())

def E(i,t,box,p=None,text=None,role='material'):
 return {'element_id':i,'source_image_ref':'SYNTH-P0-V3','parent_id':p,'region':dict(zip(['x','y','width','height'],box)),'element_type':t,'visible_text':text,'semantic_role':role,'visual_state':'STATIC_VISIBLE','classification':'CONFIRMED','confidence':.99,'evidence_refs':[f'crop://{i}:sha256:'+hashlib.sha256(i.encode()).hexdigest()],'source_observation_refs':[f'word://{i}'] if text else [],'uncertainty_codes':[],'machine_resolution_status':'RESOLVED'}

def fixture(path:Path,small=False):
 w,h=(520,600) if small else (900,600);img=np.full((h,w,3),255,np.uint8)
 px=180 if small else 330;pw=300 if small else 500
 cv2.rectangle(img,(px,40),(px+pw,560),(220,220,220),2)
 cv2.putText(img,'Confirma',(px+25,100),cv2.FONT_HERSHEY_SIMPLEX,.75,(0,120,65),2,cv2.LINE_AA)
 cv2.putText(img,'tus datos',(px+145,100),cv2.FONT_HERSHEY_SIMPLEX,.75,(0,120,65),2,cv2.LINE_AA)
 cv2.putText(img,'Nombre',(px+25,150),cv2.FONT_HERSHEY_SIMPLEX,.48,(35,35,35),1,cv2.LINE_AA)
 cv2.putText(img,'Correo',(px+150,150),cv2.FONT_HERSHEY_SIMPLEX,.48,(35,35,35),1,cv2.LINE_AA)
 cv2.rectangle(img,(px+25,170),(px+pw-25,220),(120,120,120),2)
 cv2.putText(img,'texto verde',(px+25,260),cv2.FONT_HERSHEY_SIMPLEX,.55,(0,145,45),1,cv2.LINE_AA)
 cv2.putText(img,'regular',(px+25,300),cv2.FONT_HERSHEY_SIMPLEX,.55,(30,30,30),1,cv2.LINE_AA)
 cv2.putText(img,'bold',(px+145,300),cv2.FONT_HERSHEY_SIMPLEX,.55,(30,30,30),3,cv2.LINE_AA)
 cv2.putText(img,'link',(px+25,340),cv2.FONT_HERSHEY_SIMPLEX,.55,(40,70,180),1,cv2.LINE_AA);cv2.line(img,(px+25,345),(px+70,345),(40,70,180),1)
 cv2.rectangle(img,(px+25,390),(px+pw-25,445),(0,150,40),-1);cv2.putText(img,'Continuar',(px+pw//2-45,425),cv2.FONT_HERSHEY_SIMPLEX,.55,(255,255,255),2,cv2.LINE_AA)
 cv2.rectangle(img,(px+25,470),(px+145,525),(245,245,245),-1)
 cv2.imwrite(str(path),img);return w,h,px,pw

def legacy_for(path:Path,small=False):
 w,h,px,pw=fixture(path,small);els=[E('SCR','SCREEN',(0,0,w,h)),E('PANEL','CONTAINER',(px,40,pw,520),'SCR',role='form_panel'),
 E('T1','TEXT',(px+25,75,110,32),'PANEL','Confirma','heading_part'),E('T2','TEXT',(px+140,75,115,32),'PANEL','tus datos','heading_part'),
 E('L1','LABEL',(px+25,130,90,28),'PANEL','Nombre','field_label'),E('L2','LABEL',(px+150,130,85,28),'PANEL','Correo','field_label'),
 E('INPUT','INPUT',(px+25,170,pw-50,50),'PANEL',role='form_control'),E('GREEN','TEXT',(px+25,240,140,28),'PANEL','texto verde','supporting_copy'),
 E('REG','TEXT',(px+25,280,95,28),'PANEL','regular','body_copy'),E('BOLD','TEXT',(px+145,280,70,28),'PANEL','bold','body_copy'),
 E('LINK','LINK',(px+25,320,55,30),'PANEL','link','link'),E('BTN','BUTTON',(px+25,390,pw-50,55),'PANEL','Continuar','primary_action'),
 E('PLAIN','CONTAINER',(px+25,470,120,55),'PANEL',role='plain_panel')]
 return {'schema_version':'p0-consolidated-visual-reading/v1','execution_id':'SYNTH-V2','source_image_ref':'SYNTH-P0-V3','source_sha256':'a'*64,'elements':els,'ui_structure':{'candidate_reading_orders':[[e['element_id'] for e in els]]}}

def baseline(path:Path,small=False):
 legacy=legacy_for(path,small);c=enrich_candidate(legacy,path,CFG);rep=validate_visual_fidelity(c,None,CFG)
 if rep['result']!='PASS_VISUAL_FIDELITY':raise AssertionError(rep)
 return legacy,c,rep

def aux(c,claims,sha='b'*64,mapping='SYNTH-P0-V3'):
 return {'source_type':'COMPUTED_STYLE_SNAPSHOT','source_version':'1','source_sha256':sha,'captured_at':'2026-08-10T00:00:00Z','screen_mapping':{'source_image_ref':mapping},'provenance':'synthetic fixture','trust_level':'TEST','authorization':'TEST_ONLY','claims':claims}

def main()->int:
 results={};restore_count=0
 with tempfile.TemporaryDirectory(prefix='p0v3-') as td:
  td=Path(td);image=td/'fixture.png';legacy,c0,r0=baseline(image);fingerprint=canonical_sha(c0)
  def restore():
   nonlocal restore_count
   c=enrich_candidate(copy.deepcopy(legacy),image,CFG);r=validate_visual_fidelity(c,None,CFG);assert r['result']=='PASS_VISUAL_FIDELITY';assert canonical_sha(c)==fingerprint;restore_count+=1
  def neg(name,fn):
   ok=False
   try:ok=bool(fn())
   except Exception as ex:print(name,'EXCEPTION',repr(ex),file=sys.stderr)
   results[name]=ok;restore()
  def reg(name,fn):
   try:results[name]=bool(fn())
   except Exception as ex:print(name,'EXCEPTION',repr(ex),file=sys.stderr);results[name]=False

  def n29():
   c=copy.deepcopy(c0);t=next(e for e in c['elements'] if e['element_id']=='T1')['visual_style']['typography'];t['font_family']='Inter';t['font_family_kind']='ESTIMATED_VISUAL_STYLE';return any('UNSUPPORTED_EXACT_FONT_FAMILY' in x for x in validate_visual_fidelity(c,None,CFG)['errors'])
  neg('N29_exact_font_family_from_screenshot',n29)
  def n30():
   c=copy.deepcopy(c0);next(e for e in c['elements'] if e['element_id']=='T1')['visual_style']['typography']['font_size_kind']='OBSERVED_PIXEL_STYLE';return any('UNSUPPORTED_EXACT_CSS_FONT_SIZE' in x for x in validate_visual_fidelity(c,None,CFG)['errors'])
  neg('N30_exact_css_font_size_from_bitmap',n30)
  def n31():
   c=copy.deepcopy(c0);g=next(g for g in c['text_groups'] if 'T1' in g['member_element_ids']);g['member_element_ids'].remove('T1');return any('SPLIT_OR_UNGROUPED_TEXT:T1' in x for x in validate_visual_fidelity(c,None,CFG)['errors'])
  neg('N31_split_visual_text_unit_false_pass',n31)
  def n32():
   c=copy.deepcopy(c0);g=next(g for g in c['text_groups'] if 'BTN' in g['member_element_ids']);g['member_element_ids'].append('INPUT');g['group_text']+=' input';return any('TEXT_GROUP_CONTROL_OVERMERGE' in x for x in validate_visual_fidelity(c,None,CFG)['errors'])
  neg('N32_merge_independent_controls_false_pass',n32)
  def n33():
   c=copy.deepcopy(c0);g=next(e for e in c['elements'] if e['element_id']=='PANEL')['geometry'];g['viewport_box_px']['width']=0;return any('IMPOSSIBLE_GEOMETRY:PANEL' in x for x in validate_visual_fidelity(c,None,CFG)['errors'])
  neg('N33_material_panel_without_width_height',n33)
  def n34():
   c=copy.deepcopy(c0);g=next(e for e in c['elements'] if e['element_id']=='L1')['geometry'];g['viewport_box_px']['x']=-5;g['clipping']='NOT_CLIPPED';return any('OUT_OF_VIEWPORT_WITHOUT_CLIPPING:L1' in x for x in validate_visual_fidelity(c,None,CFG)['errors'])
  neg('N34_negative_out_of_bounds_geometry',n34)
  def n35():
   c=copy.deepcopy(c0);e=next(e for e in c['elements'] if e['element_id']=='L1');e['region']['x']=10;e['geometry']['clipping']='NOT_CLIPPED';return any('PARENT_CHILD_GEOMETRY_CONFLICT:L1' in x for x in validate_visual_fidelity(c,None,CFG)['errors'])
  neg('N35_child_geometry_parent_conflict',n35)
  def n36():
   c=copy.deepcopy(c0);p=next(e for e in c['elements'] if e['element_id']=='GREEN')['visual_style']['foreground'];p['hex']='#FF00FF';return any('COLOR_HEX_RGB_INCONSISTENT:GREEN:foreground' in x for x in validate_visual_fidelity(c,None,CFG)['errors'])
  neg('N36_tampered_hex_same_crop_hash',n36)
  def n37():
   c=copy.deepcopy(c0);s=next(e for e in c['elements'] if e['element_id']=='GREEN')['visual_style'];s['foreground'],s['background']=s['background'],s['foreground'];return any('PIXEL_COLOR_MISMATCH:GREEN' in x for x in validate_observed_style_against_bitmap(c,image,CFG)['errors'])
  neg('N37_foreground_background_swapped',n37)
  def n38():
   c=copy.deepcopy(c0);t=next(e for e in c['elements'] if e['element_id']=='LINK')['visual_style']['typography'];t['text_decoration']=['NONE'];t['text_decoration_kind']='ESTIMATED_VISUAL_STYLE';return any('TEXT_DECORATION_PIXEL_MISMATCH:LINK' in x for x in validate_observed_style_against_bitmap(c,image,CFG)['errors'])
  neg('N38_underline_tampered',n38)
  def n39():
   c=copy.deepcopy(c0);e=next(e for e in c['elements'] if e['element_id']=='INPUT');e['visual_style']['border']['present']=not bool(e['visual_style']['border']['present']);e['visual_style']['radius']['estimated_radius_px']=99;errs=validate_observed_style_against_bitmap(c,image,CFG)['errors'];return any(x.startswith(('BORDER_PIXEL_MISMATCH:INPUT','RADIUS_PIXEL_MISMATCH:INPUT')) for x in errs)
  neg('N39_border_radius_incompatible_crop',n39)
  def n40():
   c=copy.deepcopy(c0);next(e for e in c['elements'] if e['element_id']=='T1')['fidelity_property_status'].pop('weight',None);return any('SILENT_STYLE_PROPERTY_MISSING:T1' in x for x in validate_visual_fidelity(c,None,CFG)['errors'])
  neg('N40_required_style_property_silent',n40)
  def n41():
   before=canonical_sha(c0);rc=reconcile_auxiliary(c0,aux(c0,[{'element_id':'T1','property':'visual_style.typography.estimated_font_size_px','value':31,'kind':'DECLARED_DOM_COMPUTED_STYLE'}]),CFG);return canonical_sha(c0)==before and rc['blind_output_sha256']==before and not rc['blind_output_mutated']
  neg('N41_aux_overwrite_blind_observed_value',n41)
  def n42():
   rc={'blind_output_sha256':canonical_sha(c0),'blind_output_mutated':False,'summary':{'mismatches_critical':0},'reconciliations':[{'critical':True,'observed':{'value':24},'declared':{'value':40},'reconciliation':{'status':'MATCH'}}]};return 'HIDDEN_CRITICAL_AUXILIARY_MISMATCH' in validate_visual_fidelity(c0,rc,CFG)['errors']
  neg('N42_hidden_critical_aux_mismatch',n42)
  def n43():
   rc={'blind_output_sha256':canonical_sha(c0),'blind_output_mutated':True,'summary':{'mismatches_critical':0},'reconciliations':[]};return 'AUXILIARY_MUTATED_BLIND_OUTPUT' in validate_visual_fidelity(c0,rc,CFG)['errors']
  neg('N43_p0x_mutates_blind_sha',n43)
  def n44():
   rc=reconcile_auxiliary(c0,aux(c0,[],sha=''),CFG);return rc['result']=='BLOCKED_AUXILIARY_CONFLICT' and any('SOURCE_SHA256' in x for x in rc['summary']['source_errors'])
  neg('N44_design_token_without_source_sha',n44)
  def n45():
   rc=reconcile_auxiliary(c0,aux(c0,[],mapping='OTHER-SCREEN'),CFG);return rc['result']=='BLOCKED_AUXILIARY_CONFLICT' and 'STALE_OR_WRONG_SCREEN_MAPPING' in rc['summary']['source_errors']
  neg('N45_stale_aux_wrong_screen',n45)
  def n46():
   p=human_review_packet(c0,r0);p['human_attention_required']=[{'element_id':e['element_id'],'reason':'FORCED'} for e in c0['elements']];p['automatically_resolved_count']=0;return 'MASS_MANUAL_REVIEW_OF_RESOLVED_ELEMENTS' in validate_packet_v4(p,r0,c0)['errors']
  neg('N46_review_forces_all_resolved_manual',n46)
  def n47():
   p=human_review_packet(c0,r0);doc=build_human_html(p,c0,image).replace('Layout principal','Layout');return 'Layout principal' in validate_html_v4(doc)['missing']
  neg('N47_html_missing_geometry',n47)
  def n48():
   p=human_review_packet(c0,r0);doc=build_human_html(p,c0,image).replace('Jerarquía tipográfica','Tipografía').replace('Paleta observada','Paleta');m=validate_html_v4(doc)['missing'];return 'Jerarquía tipográfica' in m and 'Paleta observada' in m
  neg('N48_html_missing_typography_color',n48)
  def n49():
   c=copy.deepcopy(c0);c['text_groups']=[];c2,h=remediate_visual_fidelity(c,image,CFG,3);r=validate_visual_fidelity(c2,None,CFG);p=human_review_packet(c2,r,None,h);return r['result']=='PASS_VISUAL_FIDELITY' and any('TEXT_GROUP_REBUILD' in x['strategies'] for x in h) and not any(x.get('reason')=='GROUPING_MACHINE_FIXABLE' for x in p['human_attention_required'])
  neg('N49_machine_fixable_grouping_sent_human',n49)
  def n50():
   c=copy.deepcopy(c0);semantic=canonical_sha([{k:e.get(k) for k in ('element_id','element_type','visible_text','semantic_role','classification')} for e in c['elements']]);c2,_=remediate_visual_fidelity(c,image,CFG,3);semantic2=canonical_sha([{k:e.get(k) for k in ('element_id','element_type','visible_text','semantic_role','classification')} for e in c2['elements']]);return semantic==semantic2
  neg('N50_style_remediation_breaks_v2_semantics',n50)

  reg('R16_split_words_consolidated',lambda:any(g['member_element_ids']==['T1','T2'] and g['group_text']=='Confirma tus datos' for g in c0['text_groups']))
  reg('R17_close_independent_labels_separate',lambda:not any('L1' in g['member_element_ids'] and 'L2' in g['member_element_ids'] for g in c0['text_groups']))
  reg('R18_panel_geometry_fixture_tolerance',lambda:(lambda b:abs(b['x']-330)<=1 and abs(b['y']-40)<=1 and abs(b['width']-500)<=1 and abs(b['height']-520)<=1)(next(e for e in c0['elements'] if e['element_id']=='PANEL')['geometry']['viewport_box_px']))
  def r19():
   c=copy.deepcopy(c0);e=next(e for e in c['elements'] if e['element_id']=='INPUT');e['region']['x']=0;return any('PARENT_CHILD_GEOMETRY_CONFLICT' in x for x in validate_visual_fidelity(c,None,CFG)['errors'])
  reg('R19_child_outside_parent_detected',r19)
  reg('R20_regular_vs_bold_weight',lambda:next(e for e in c0['elements'] if e['element_id']=='REG')['visual_style']['typography']['font_weight_class']!=next(e for e in c0['elements'] if e['element_id']=='BOLD')['visual_style']['typography']['font_weight_class'])
  reg('R21_underline_present',lambda:'UNDERLINE' in next(e for e in c0['elements'] if e['element_id']=='LINK')['visual_style']['typography']['text_decoration'])
  reg('R22_underline_absent',lambda:'UNDERLINE' not in next(e for e in c0['elements'] if e['element_id']=='REG')['visual_style']['typography']['text_decoration'])
  def r23():
   rgb=next(e for e in c0['elements'] if e['element_id']=='GREEN')['visual_style']['foreground']['rgb'];return rgb and rgb[1]>rgb[0]+30 and rgb[1]>rgb[2]+30
  reg('R23_green_foreground_approximates_fixture',r23)
  def r24():
   s=next(e for e in c0['elements'] if e['element_id']=='GREEN')['visual_style'];return s['foreground'].get('hex')!=s['background'].get('hex')
  reg('R24_foreground_background_not_confused',r24)
  reg('R25_control_radius_profile_present',lambda:next(e for e in c0['elements'] if e['element_id']=='INPUT')['visual_style']['radius'].get('estimated_radius_px') is not None)
  reg('R26_panel_border_detected',lambda:next(e for e in c0['elements'] if e['element_id']=='PANEL')['visual_style']['border'].get('present') is True)
  reg('R27_panel_without_border_not_invented',lambda:next(e for e in c0['elements'] if e['element_id']=='PLAIN')['visual_style']['border'].get('present') is False)
  reg('R28_repeated_style_clusters',lambda:len(c0['observed_style_clusters'])>=1)
  reg('R29_screenshot_no_exact_font_family',lambda:all(e.get('visual_style',{}).get('typography',{}).get('font_family') is None for e in c0['elements']))
  reg('R30_screenshot_font_size_qualified',lambda:all(e.get('visual_style',{}).get('typography',{}).get('font_size_kind')!='OBSERVED_PIXEL_STYLE' for e in c0['elements']))
  def r31():
   val=next(e for e in c0['elements'] if e['element_id']=='T1')['visual_style']['typography']['estimated_font_size_px'];rc=reconcile_auxiliary(c0,aux(c0,[{'element_id':'T1','property':'visual_style.typography.estimated_font_size_px','value':val,'kind':'DECLARED_DOM_COMPUTED_STYLE'}]),CFG);return rc['reconciliations'][0]['reconciliation']['status']=='MATCH'
  reg('R31_aux_css_visual_match',r31)
  def r32():
   rc=reconcile_auxiliary(c0,aux(c0,[{'element_id':'T1','property':'visual_style.typography.estimated_font_size_px','value':99,'kind':'DECLARED_DESIGN_TOKEN','critical':False}]),CFG);return rc['reconciliations'][0]['reconciliation']['status']=='MISMATCH' and rc['reconciliations'][0]['observed']['value']!=rc['reconciliations'][0]['declared']['value']
  reg('R32_aux_token_mismatch_visible_no_overwrite',r32)
  reg('R33_observed_and_declared_spacing_coexist',lambda:(lambda rc:rc['reconciliations'][0]['observed']['value'] is not None and rc['reconciliations'][0]['declared']['value']==12)(reconcile_auxiliary(c0,aux(c0,[{'element_id':'PANEL','property':'geometry.viewport_box_px.x','value':12,'kind':'DECLARED_DOM_COMPUTED_STYLE'}]),CFG)))
  reg('R34_single_viewport_no_breakpoint',lambda:compare_viewports([c0],CFG)['status']=='NOT_OBSERVABLE_SINGLE_VIEWPORT' and not compare_viewports([c0],CFG)['breakpoints'])
  def r35():
   im2=td/'small.png';_,c2,_=baseline(im2,True);return len(compare_viewports([c0,c2],CFG)['responsive_claims'])>0
  reg('R35_multi_viewport_detects_reflow',r35)
  p0=human_review_packet(c0,r0);doc=build_human_html(p0,c0,image)
  reg('R36_html_panel_geometry',lambda:'Layout principal' in doc and 'viewport_box_px' in doc)
  reg('R37_html_typography_summary',lambda:'Jerarquía tipográfica' in doc and 'estimated_font_size_px' in doc)
  reg('R38_html_color_swatches',lambda:'Paleta observada' in doc and "class='sw'" in doc)
  reg('R39_html_exception_first',lambda:doc.index('Excepciones que requieren humano')<doc.index('Anexo técnico'))
  def r40():
   before=canonical_sha(c0);reconcile_auxiliary(c0,aux(c0,[]),CFG);return canonical_sha(c0)==before
  reg('R40_blind_sha_immutable_after_p0x',r40)

 failed=[k for k,v in results.items() if not v];out={'suite':'P0_VISUAL_FIDELITY_V3','negatives':sum(k.startswith('N') for k in results),'regressions':sum(k.startswith('R') for k in results),'positive_restores':restore_count,'passed':sum(results.values()),'failed':failed,'results':results}
 print(json.dumps(out,indent=2,sort_keys=True));return 1 if failed or restore_count!=22 or out['negatives']!=22 or out['regressions']!=25 else 0
if __name__=='__main__':raise SystemExit(main())

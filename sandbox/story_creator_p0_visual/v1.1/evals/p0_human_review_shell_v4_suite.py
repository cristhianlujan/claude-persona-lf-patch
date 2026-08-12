#!/usr/bin/env python3
"""Contract/regression checks for the responsive P0HR shell V4."""
from __future__ import annotations
import json,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
from p0_human_review_shell_v4 import build_human_review_shell_v4,validate_human_review_shell_v4,ALLOWED_ACTIONS


def fixture():
    candidate={
      'schema_version':'p0-consolidated-visual-reading/v2','execution_id':'SHELL-V4-TEST','source_image_ref':'IMG-TEST','source_sha256':'a'*64,
      'elements':[
        {'element_id':'E1','element_type':'LABEL','visible_text':'Nombre completo','semantic_role':'field_label','classification':'CONFIRMED','confidence':.987,'parent_id':'FORM','region':{'x':20,'y':20,'width':120,'height':24},'geometry':{'viewport_box_normalized':{'x':.1,'y':.1,'width':.3,'height':.08},'viewport_box_px':{'x':20,'y':20,'width':120,'height':24}},'visual_style':{},'fidelity_property_status':{'geometry':'RESOLVED_OBSERVED'},'evidence_refs':['crop://E1:sha256:'+'b'*64]},
        {'element_id':'E2','element_type':'BUTTON','visible_text':'Continuar','semantic_role':'primary_action','classification':'INFERRED','confidence':.88,'parent_id':'FORM','region':{'x':20,'y':70,'width':160,'height':40},'geometry':{'viewport_box_normalized':{'x':.1,'y':.35,'width':.4,'height':.15},'viewport_box_px':{'x':20,'y':70,'width':160,'height':40}},'visual_style':{},'fidelity_property_status':{'geometry':'RESOLVED_ESTIMATED'},'evidence_refs':[]},
      ]}
    packet={'schema_version':'p0-human-review-packet-v4/v1','candidate_sha256':'c'*64,'fidelity_report_sha256':'d'*64,'human_review_ready':True,'screen_summary':{'visual_fidelity_result':'PASS_VISUAL_FIDELITY'},'layout_regions':[],'typography_summary':[],'color_summary':[],'text_groups':[],'human_attention_required':[{'element_id':'E2','reason':'INFERRED_OR_REMEDIATION'}],'automatically_resolved_count':1,'remediation_history':[],'reconciliation':None,'technical_appendix':{}}
    challenge={'challenge_id':'CH-P0-TEST-V4-01','review_id':'REV-P0-TEST-V4-01','required_reviewer_role':'P0_VISUAL_ADJUDICATOR','source_head_sha':'1'*40,'source_sha256':'a'*64,'visual_output_sha256':'e'*64,'packet_manifest_sha256':'f'*64,'issue_number':125,'expires_at':'2099-01-01T00:00:00Z','binding_valid':True}
    return packet,candidate,challenge


def main()->int:
    p,c,ch=fixture();doc=build_human_review_shell_v4(p,c,None,ch);v=validate_human_review_shell_v4(doc);results={}
    results['R01_contract_markers']=v['pass']
    results['R02_all_actions_present']=all(f'data-action="{a}"' in doc or a in doc for a in ALLOWED_ACTIONS)
    results['R03_mobile_swipe_and_scroll']=('@media (max-width: 767px)' in doc and 'scroll-snap-type:x mandatory' in doc and 'touch-action:pan-y' in doc)
    results['R04_evidence_read_only_notice']='La web no publica ni autentica esta decisión' in doc
    results['R05_challenge_bound_command']='challenge_id=${M.challenge_id} action=${action}' in doc
    results['R06_no_auth_secrets']=not v['forbidden']
    expired=dict(ch,expires_at='2000-01-01T00:00:00Z');doc2=build_human_review_shell_v4(p,c,None,expired)
    results['N01_expired_challenge_disables']='CHALLENGE EXPIRADO' in doc2 and 'decisionDisabled=M.expired' in doc2
    broken=dict(ch,binding_valid=False);doc3=build_human_review_shell_v4(p,c,None,broken)
    results['N02_binding_mismatch_disables']='EVIDENCE BINDING ERROR' in doc3
    not_ready=dict(p,human_review_ready=False);doc4=build_human_review_shell_v4(not_ready,c,None,ch)
    results['N03_not_human_ready_disables']='HUMAN_REVIEW_READY=false' in doc4
    no_ch=build_human_review_shell_v4(p,c,None,None)
    results['N04_missing_challenge_disables']='No hay challenge activo ligado a esta vista' in no_ch
    failed=[k for k,v in results.items() if not v];print(json.dumps({'suite':'P0_HUMAN_REVIEW_SHELL_V4','passed':len(results)-len(failed),'total':len(results),'failed':failed,'results':results},indent=2,sort_keys=True));return 1 if failed else 0
if __name__=='__main__':raise SystemExit(main())

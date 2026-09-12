#!/usr/bin/env python3
"""Fresh V3 adversary. It receives only source fixture, candidate and V3 contracts."""
from __future__ import annotations
import copy,json,sys,tempfile
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'));sys.path.insert(0,str(Path(__file__).resolve().parent))
from p0_visual_fidelity_v3 import validate_visual_fidelity,reconcile_auxiliary,canonical_sha,validate_packet_v4,human_review_packet,build_human_html,validate_html_v4
from p0_visual_fidelity_v3_suite import baseline,CFG,aux

def main()->int:
 false=[];attempts=[]
 with tempfile.TemporaryDirectory(prefix='p0v3-forward-') as td:
  image=Path(td)/'source.png';_,c0,r0=baseline(image)
  def attack(name,mut,checker=None):
   c=copy.deepcopy(c0);extra=mut(c)
   if checker:blocked=checker(c,extra)
   else:blocked=validate_visual_fidelity(c,None,CFG)['result']!='PASS_VISUAL_FIDELITY'
   attempts.append({'name':name,'blocked':blocked});
   if not blocked:false.append(name)
  attack('false_pass_geometry',lambda c:next(e for e in c['elements'] if e['element_id']=='PANEL')['geometry']['viewport_box_px'].update(width=0))
  attack('false_pass_style',lambda c:next(e for e in c['elements'] if e['element_id']=='T1')['visual_style']['typography'].update(font_family='Inter',font_family_kind='ESTIMATED_VISUAL_STYLE'))
  attack('wrong_text_grouping',lambda c:c.update(text_groups=[]))
  attack('unsupported_exact_design_claim',lambda c:next(e for e in c['elements'] if e['element_id']=='T1')['visual_style']['typography'].update(font_size_kind='OBSERVED_PIXEL_STYLE'))
  def hidden(c):return {'blind_output_sha256':canonical_sha(c),'blind_output_mutated':False,'summary':{'mismatches_critical':0},'reconciliations':[{'critical':True,'observed':{'value':10},'declared':{'value':20},'reconciliation':{'status':'MATCH'}}]}
  attack('hidden_aux_mismatch',hidden,lambda c,r:validate_visual_fidelity(c,r,CFG)['result']!='PASS_VISUAL_FIDELITY')
  attack('layout_omission',lambda c:next(e for e in c['elements'] if e['element_id']=='INPUT').pop('geometry'))
  def overload(c):
   p=human_review_packet(c,r0);p['human_attention_required']=[{'element_id':e['element_id']} for e in c['elements']];p['automatically_resolved_count']=0;return p
  attack('human_review_overload',overload,lambda c,p:not validate_packet_v4(p,r0,c)['pass'])
  def contamination(c):
   rc=reconcile_auxiliary(c,aux(c,[{'element_id':'T1','property':'visual_style.typography.font_family','value':'Inter','kind':'DECLARED_DOM_COMPUTED_STYLE'}]),CFG);rc['blind_output_mutated']=True;return rc
  attack('provenance_contamination',contamination,lambda c,r:validate_visual_fidelity(c,r,CFG)['result']!='PASS_VISUAL_FIDELITY')
  def html_over(c):return build_human_html(human_review_packet(c,r0),c,image).replace('Excepciones que requieren humano','All elements')
  attack('review_exception_queue_removed',html_over,lambda c,d:not validate_html_v4(d)['pass'])
  before=canonical_sha(c0);reconcile_auxiliary(c0,aux(c0,[]),CFG);blocked=(canonical_sha(c0)==before);attempts.append({'name':'blind_output_mutation_probe','blocked':blocked});false += [] if blocked else ['blind_output_mutation_probe']
 out={'schema_version':'p0-v3-forward-adversarial/v1','auditor_identity':'FRESH_P0_V3_ADVERSARY','attempted_bypasses':len(attempts),'false_passes':false,'attempts':attempts,'result':'PASS' if not false else 'BLOCKED'};print(json.dumps(out,indent=2));return 0 if not false else 2
if __name__=='__main__':raise SystemExit(main())

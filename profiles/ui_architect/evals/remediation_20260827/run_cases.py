#!/usr/bin/env python3
import copy, importlib.util, json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
VP=ROOT/'validators'/'validate_ui_architect_output.py'
spec=importlib.util.spec_from_file_location('v',VP); v=importlib.util.module_from_spec(spec); spec.loader.exec_module(v)

def comp(cid, zone='main', role='ui component', content=None, state=None):
    return {'zone_id':zone,'component_id':cid,'component_type':'BLOCK','role':role,'content':content or {'text':cid},'visual_priority':1,'color_tokens':{'surface':'neutral_surface'},'typography':{'body':'14px/400'},'spacing':{'gap':'12px'},'state':state or {'default':'visible'},'allowed_variants':['default'],'blocked_variants':['pressure_variant']}

def score():
    refs={'layout_precision':['layout_grid','spacing_typography'],'visual_hierarchy':['visual_hierarchy'],'lf_system_fidelity':['token_map','risk_controls'],'state_mapping':['state_map'],'handoff_quality':['handoff_to_next']}
    return {**{k:5 for k in v.SCORE_KEYS},'total':25,'evidence_by_criterion':{k:{'refs':r,'summary':f'{k} is supported by explicit named deliverable structures and implementation-ready evidence.'} for k,r in refs.items()}}

def base(case, mode, components, actions=None):
    d={'screen_definition':{'task_mode':mode,'screen':case,'primary_action':'continue'},'component_tree':components,'layout_grid':{'desktop':'12 columns','gap':'24px'},'visual_hierarchy':[{'rank':i+1,'component_id':c['component_id']} for i,c in enumerate(components)],'state_map':{'default':'observable states defined'},'token_map':{'neutral_surface':{'use':[c['component_id'] for c in components]}},'spacing_typography':{'gap':'24px','body':'14px/400'},'density_rules':['one dominant action'],'risk_controls':['no fake urgency','no unsupported guarantee'],'prompt_constraints':['preserve hierarchy and user-visible constraints']}
    if actions is not None: d['remediation_actions']=actions
    return {'worker':'ui_architect','case_id':case,'output_type':'PRODUCTION_UI_SPEC','deliverable_created':d,'score':score(),'handoff_to_next':{'worker':'quality_pack','instruction':'Validate exact candidate.'},'self_verdict':'PASS_TO_QUALITY_PACK_CANDIDATE'}

def action(i,cat,ev,target,op,prop,val,check,decision,impl,ac,authority=None):
    x={'issue_id':i,'priority':'P0','category':cat,'evidence_anchor':ev,'evidence_component_ids':[target],'decision':decision,'implementation_change':impl,'acceptance_criteria':ac,'execution':{'operation':op,'target_component_id':target,'property':prop,'desired_value':val},'acceptance_check':{'check_type':check,'target_component_id':target,'expected':val}}
    if authority: x['semantic_authority']=authority
    return x

ruta=base('home_ruta_claridad_001','CREATE',[comp('ruta_intro',content={'title':'Tu Ruta de Claridad'}),comp('clarity_path',role='show four orientation milestones',content={'milestones':4}),comp('simulation_disclaimer',role='preserve referential validation constraint',content={'text':'Simulación referencial sujeta a validación.'}),comp('simulator_cta',role='route to simulator',content={'label':'Ver si tengo una oferta','href':'/simulador'},state={'default':'enabled'})])
ruta['deliverable_created']['prompt_constraints'] += ['preserve one CTA to /simulador','preserve visible copy: Simulación referencial sujeta a validación.']
ruta['handoff_to_next']['instruction']='Validate visible referential/validation qualifier before render.'

checkout_components=[comp('top_amount_strip',role='duplicate payable amount source',content={'amount':'S/2,097'}),comp('payment_methods',role='choose payment method',state={'selection':'none|selected'}),comp('payment_summary',role='single payable amount source',content={'label':'Hoy pagas','amount':'S/2,097'}),comp('payment_cta',role='continue with selected method',state={'enabled':'false until method selected'})]
checkout_actions=[
 action('CHK-01','HIERARCHY','top_amount_strip duplicates the payable total already shown in payment_summary.','top_amount_strip','REMOVE','visibility','absent','ABSENT','Remove top_amount_strip so payment_summary is the sole payable-total source.','Remove top_amount_strip from checkout and keep the payable total in payment_summary only.','Visual QA confirms top_amount_strip is absent and payment_summary remains the single total source.'),
 action('CHK-02','LAYOUT','payment_summary starts lower than payment_methods, breaking top-edge alignment.','payment_summary','ALIGN','top_edge','aligned with payment_methods at sticky 24px','ALIGNED','Align payment_summary with payment_methods and keep the summary sticky at 24px.','Align payment_summary top edge with payment_methods and apply sticky top spacing of 24px.','Visual QA confirms payment_summary is aligned with payment_methods and remains sticky at 24px.'),
 action('CHK-03','INTERACTION','payment_cta is detached from the current method state and can appear actionable without a selection.','payment_cta','SET_STATE','enabled','false until a payment method is selected','STATE','Set payment_cta disabled until payment_methods has one selected method.','Set payment_cta state to disabled until payment_methods selection exists, then enable it.','Visual QA confirms payment_cta stays disabled until a method is selected and enables after selection.',{'source_refs':['raw_input.payment_methods','raw_input.payment_cta'],'claim_scope':'PRESENTATION_ONLY'})]
checkout_direct=base('checkout_direct_001','EVALUATE_EXISTING',checkout_components,checkout_actions)
checkout_router=copy.deepcopy(checkout_direct); checkout_router['case_id']='checkout_router_001'

hold_components=[comp('offer_label',content={'text':'Oferta hoy'}),comp('alternative_selector',role='choose one alternative',state={'selection':'none'}),comp('payment_status',role='confirm payment event',content={'text':'Pago registrado'}),comp('receipt_status',role='confirm receipt availability',content={'text':'Tu constancia ya está disponible'})]
hold_actions=[
 action('HLD-01','RISK','offer_label says Oferta hoy although no authoritative expiry is present.','offer_label','REPLACE_COPY','text','Oferta disponible','COPY_EQUALS','Replace offer_label with Oferta disponible to remove unsupported same-day urgency.','Replace offer_label text with Oferta disponible without adding an expiry or countdown.','Visual QA confirms offer_label equals Oferta disponible and no deadline is introduced.',{'source_refs':['raw_input.offer_label','raw_input.no_expiry_authority'],'claim_scope':'CONSERVATIVE_REDUCTION'}),
 action('HLD-02','INTERACTION','alternative_selector presents mutually exclusive alternatives without an explicit initial selection state.','alternative_selector','SET_STATE','selection','none initially; exactly one selected before continue','STATE','Set alternative_selector to single-select with no preselection.','Set alternative_selector state to none initially and permit exactly one selected option.','Visual QA confirms alternative_selector starts with none selected and permits one selection.',{'source_refs':['raw_input.alternatives'],'claim_scope':'INPUT_SUPPORTED'}),
 action('HLD-03','COPY','payment_status says Pago registrado while receipt_status separately confirms receipt availability; neither states debt closure.','payment_status','REPLACE_COPY','text','Pago registrado','COPY_EQUALS','Keep payment_status as Pago registrado and do not introduce debt-cancellation language.','Replace any closure wording in payment_status with Pago registrado while receipt_status remains separate.','Visual QA confirms payment_status equals Pago registrado and no debt-cancellation claim appears.',{'source_refs':['raw_input.payment_status','raw_input.receipt_status'],'claim_scope':'INPUT_SUPPORTED'})]
hold=base('marketplace_holdout_001','EVALUATE_EXISTING',hold_components,hold_actions)
positives={'ruta_after':ruta,'checkout_direct_after':checkout_direct,'checkout_router_after':checkout_router,'marketplace_holdout_after':hold}

def codes(e): return [x.get('code') for x in e]
results=[]; failures=[]
for n,p in positives.items():
    e=v.validate(p); ok=not e; results.append((n,'POSITIVE',ok,codes(e))); failures += [] if ok else [n]
struct={}
x=copy.deepcopy(ruta); x['output_type']='UI_SECTION_SPEC'; struct['historical_stale_output_mode']=x
x=copy.deepcopy(ruta); [x['score'].__setitem__(k,0) for k in v.SCORE_KEYS]; x['score']['total']=0; struct['pass_zero_score']=x
x=copy.deepcopy(ruta); x['score']['evidence_by_criterion']={k:'PASS' for k in v.SCORE_KEYS}; struct['nominal_score_evidence']=x
x=copy.deepcopy(checkout_direct); a=x['deliverable_created']['remediation_actions'][0]; a['decision']='Adjust colors, spaces and general distribution across the checkout to improve the interface overall.'; a['implementation_change']='Adjust the general interface presentation with broad visual refinements across the page.'; a['acceptance_criteria']='The overall interface should look cleaner and generally more polished after the change.'; struct['generic_long_action']=x
x=copy.deepcopy(checkout_direct); x['deliverable_created']['remediation_actions'][0]['evidence_component_ids']=['unknown_component']; struct['unknown_component_ref']=x
x=copy.deepcopy(checkout_direct); x['deliverable_created']['remediation_actions'][1]['category']='COPY'; struct['category_operation_mismatch']=x
x=copy.deepcopy(ruta); x['score']['product_alignment']=5; struct['stale_score_key']=x
for n,p in struct.items():
    e=v.validate(p); ok=bool(e); results.append((n,'STRUCTURAL_NEGATIVE',ok,codes(e))); failures += [] if ok else [n]
mal={'root_none':None,'root_list':[],'deliverable_string':{'output_type':'PRODUCTION_UI_SPEC','deliverable_created':'oops'}}
x=copy.deepcopy(ruta); x['deliverable_created']['component_tree']='oops'; mal['component_tree_string']=x
for n,p in mal.items():
    try: e=v.validate(p); ok=bool(e); ec=codes(e)
    except Exception as exc: ok=False; ec=[f'CRASH:{type(exc).__name__}']
    results.append((n,'MALFORMED_NEGATIVE',ok,ec)); failures += [] if ok else [n]
sem={}
x=copy.deepcopy(checkout_direct); a=x['deliverable_created']['remediation_actions'][0]; a.update({'decision':'Remove payment_summary and keep top_amount_strip as the remaining payable-total source.','implementation_change':'Remove payment_summary from checkout and retain top_amount_strip above payment_methods.','acceptance_criteria':'Visual QA confirms payment_summary is absent while top_amount_strip remains visible above payment_methods.','evidence_component_ids':['top_amount_strip','payment_summary'],'execution':{'operation':'REMOVE','target_component_id':'payment_summary','property':'visibility','desired_value':'absent'},'acceptance_check':{'check_type':'ABSENT','target_component_id':'payment_summary','expected':'absent'}}); sem['wrong_duplicate_resolution']=x
x=copy.deepcopy(hold); a=x['deliverable_created']['remediation_actions'][2]; a.update({'decision':'Replace payment_status with Deuda cancelada after the registered payment.','implementation_change':'Replace payment_status text with Deuda cancelada and keep receipt_status secondary.','acceptance_criteria':'Visual QA finds payment_status equal to Deuda cancelada and receipt_status remains visible.','execution':{'operation':'REPLACE_COPY','target_component_id':'payment_status','property':'text','desired_value':'Deuda cancelada'},'acceptance_check':{'check_type':'COPY_EQUALS','target_component_id':'payment_status','expected':'Deuda cancelada'}}); sem['unsupported_debt_closure']=x
x=copy.deepcopy(checkout_direct); a=x['deliverable_created']['remediation_actions'][2]; a.update({'category':'LAYOUT','decision':'Move payment_cta into a page footer below both checkout columns.','implementation_change':'Move payment_cta from payment_summary into a footer after payment_methods and payment_summary.','acceptance_criteria':'Visual QA confirms payment_cta appears below payment_methods and payment_summary in the footer.','execution':{'operation':'MOVE','target_component_id':'payment_cta','property':'position','desired_value':'page footer below checkout columns'},'acceptance_check':{'check_type':'RELATIONSHIP','target_component_id':'payment_cta','expected':'page footer below checkout columns'}}); a.pop('semantic_authority',None); sem['cta_farther_from_selection']=x
x=copy.deepcopy(hold); a=x['deliverable_created']['remediation_actions'][0]; a.update({'decision':'Replace offer_label copy with Liquidación garantizada al pagar as primary reassurance.','implementation_change':'Replace offer_label text with Liquidación garantizada al pagar and keep the offer card unchanged.','acceptance_criteria':'Visual QA finds offer_label equal to Liquidación garantizada al pagar in the offer card.','execution':{'operation':'REPLACE_COPY','target_component_id':'offer_label','property':'text','desired_value':'Liquidación garantizada al pagar'},'acceptance_check':{'check_type':'COPY_EQUALS','target_component_id':'offer_label','expected':'Liquidación garantizada al pagar'},'semantic_authority':{'source_refs':['raw_input.offer_label'],'claim_scope':'INPUT_SUPPORTED'}}); sem['guaranteed_settlement_claim']=x
for n,p in sem.items():
    e=v.validate(p); ok=not e; results.append((n,'SEMANTIC_NEGATIVE_EXPECT_STRUCTURAL_PASS',ok,codes(e))); failures += [] if ok else [n]
consistent=checkout_direct['deliverable_created']['remediation_actions']==checkout_router['deliverable_created']['remediation_actions']; results.append(('router_direct_positive_consistency','CONSISTENCY',consistent,[])); failures += [] if consistent else ['router_direct_positive_consistency']
for r in results: print(json.dumps({'case':r[0],'kind':r[1],'expected_met':r[2],'errors':r[3]},ensure_ascii=False))
summary={'positive_pass':sum(1 for r in results if r[1]=='POSITIVE' and r[2]),'structural_negative_reject':sum(1 for r in results if r[1]=='STRUCTURAL_NEGATIVE' and r[2]),'malformed_negative_reject_without_crash':sum(1 for r in results if r[1]=='MALFORMED_NEGATIVE' and r[2]),'semantic_negative_structural_pass':sum(1 for r in results if r[1]=='SEMANTIC_NEGATIVE_EXPECT_STRUCTURAL_PASS' and r[2]),'router_direct_consistent':consistent,'failures':failures}
print(json.dumps({'summary':summary},ensure_ascii=False,indent=2)); raise SystemExit(1 if failures else 0)

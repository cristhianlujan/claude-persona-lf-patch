#!/usr/bin/env python3
import copy, json, sys
from pathlib import Path

HERE=Path(__file__).resolve().parent
PROFILE=HERE.parents[1]
sys.path.insert(0,str(PROFILE/'validators'))
from validate_product_director_output import validate
from jsonschema import Draft202012Validator

SCHEMA=json.loads((PROFILE/'schemas/product_direction_spec.schema.json').read_text())
SCHEMA_VALIDATOR=Draft202012Validator(SCHEMA)

def good_output():
    score_keys=['product_decision_clarity','scope_control_mvp_separation','acceptance_criteria_quality','cross_profile_handoff_quality','evidence_risk_governance_traceability']
    evidence={k:[f'deliverable_created.decision_lineage::{k}'] for k in score_keys}
    return {
      'worker':'product_director_lf','output_type':'PRODUCT_DIRECTION_SPEC','self_verdict':'PASS',
      'deliverable_created':{
        'product_decision':{
          'decision_id':'PD-LF-001','selected_decision':'Mantener la oferta como referencial hasta validación upstream',
          'rationale':'La fuente vigente autoriza mostrar alternativa, no garantiza elegibilidad ni cierre.',
          'source_refs':[{'source_ref':'upstream://offer-policy/v3','authority':'AUTHORITATIVE','supports':'Oferta referencial y sujeta a validación','current':True}],
          'rejected_alternatives':['Presentarla como oferta garantizada'],
          'tradeoffs':['Menor fuerza comercial a cambio de preservar verdad de producto'],
          'preserved_constraints':['No garantizar elegibilidad','No afirmar deuda cancelada'],
          'semantic_qualifiers':['referencial','sujeta a validación']
        },
        'included_scope':['Mostrar alternativa referencial'],'excluded_scope':['Garantía de elegibilidad'],'priority':{'level':'P1','reason':'verdad de producto'},
        'acceptance_criteria':[{'criterion_id':'AC-1','condition':'Toda salida downstream conserva el qualifier','observable_check':'El texto visible contiene una condición referencial o equivalente semánticamente conservadora'}],
        'dependencies':['upstream offer policy'],'risks':['sobrepromesa'],'profiles_to_activate':['ui_architect'],'blockers':[],
        'next_step':{'target':'ui_architect'},'final_verdict':'PROCEED_WITH_QUALIFIER','evidence_used':['upstream://offer-policy/v3'],'open_assumptions':[],
        'success_metric_or_proxy':{'metric':'qualifier_preservation_rate','target':'100%'},
        'handoff_to_next':{'target':'ui_architect','input_contract':'Preservar decisión y qualifiers','qualifiers_to_preserve':['referencial','sujeta a validación']},
        'authority_status':'SUPPORTED','material_claims':[{'claim':'La alternativa es referencial','authority_ref':'upstream://offer-policy/v3','status':'SUPPORTED'}],
        'decision_lineage':{'objective':'Presentar alternativa sin sobreprometer','selected_decision':'Mantener la oferta como referencial hasta validación upstream','evidence_refs':['upstream://offer-policy/v3'],'preserved_constraints':['constraint://no-guarantee'],'acceptance_refs':['acceptance://AC-1'],'handoff_effect':'UI debe preservar qualifiers y no fortalecer la claim'}
      },
      'score':{**{k:5 for k in score_keys},'total':25,'evidence_by_criterion':evidence},
      'handoff_to_next':{'target':'ui_architect'},'traceability':{'case':'after_supported_decision'}
    }

def schema_ok(payload): return not list(SCHEMA_VALIDATOR.iter_errors(payload))

def run():
    cases=[]
    g=good_output()
    cases.append(('positive_supported', validate(g)['valid'] and schema_ok(g), 'PASS'))

    ui=copy.deepcopy(g); ui['traceability']['case']='positive_ui_qualifier'
    cases.append(('positive_ui_qualifier', validate(ui)['valid'] and 'referencial' in ui['deliverable_created']['handoff_to_next']['qualifiers_to_preserve'], 'PASS'))

    resolved=copy.deepcopy(g)
    resolved['deliverable_created']['product_decision']['source_refs'].append({'source_ref':'upstream://legacy/v1','authority':'CONTRADICTORY','supports':'Legacy copy described offer as guaranteed','current':True})
    resolved['deliverable_created']['authority_status']='CONFLICT_RESOLVED'
    resolved['deliverable_created']['conflict_resolution']={'basis':'Current authoritative v3 supersedes conflicting legacy description','selected_source_ref':'upstream://offer-policy/v3','rejected_source_refs':['upstream://legacy/v1']}
    cases.append(('positive_conflict_resolved', validate(resolved)['valid'] and schema_ok(resolved), 'PASS'))

    missing={'worker':'product_director_lf','output_type':'PRODUCT_MISSING_INPUT_STATE','self_verdict':'NEEDS_INPUT','deliverable_created':{'missing_fields':['business eligibility rule'],'why_blocking':'Eligibility cannot be inferred safely','next_input_needed':'Current authoritative eligibility source'}}
    cases.append(('insufficient_input_blocks_decision', validate(missing)['valid'], 'NEEDS_INPUT_VALID'))

    conflict=copy.deepcopy(g); conflict['deliverable_created']['product_decision']['source_refs'].append({'source_ref':'upstream://legacy/v1','authority':'CONTRADICTORY','supports':'Oferta garantizada','current':True})
    cases.append(('contradictory_source_unresolved', not validate(conflict)['valid'] and 'SOURCE_CONFLICT_UNRESOLVED' in validate(conflict)['blocking_codes'], 'REJECT'))

    violated=copy.deepcopy(g); violated['deliverable_created']['material_claims'][0]={'claim':'Elegibilidad garantizada','authority_ref':'missing://none','status':'SUPPORTED'}
    cases.append(('attractive_but_upstream_violation', not validate(violated)['valid'] and 'CLAIM_AUTHORITY_MISSING' in validate(violated)['blocking_codes'], 'REJECT'))

    weak=copy.deepcopy(g)
    weak['deliverable_created']['product_decision']['source_refs'].append({'source_ref':'context://marketing-note','authority':'CONTEXT','supports':'Marketing preference only','current':True})
    weak['deliverable_created']['material_claims'][0]={'claim':'Elegibilidad garantizada','authority_ref':'context://marketing-note','status':'SUPPORTED'}
    cases.append(('claim_bound_to_context_is_not_authority', not validate(weak)['valid'] and 'CLAIM_AUTHORITY_TOO_WEAK' in validate(weak)['blocking_codes'], 'REJECT'))

    generic=copy.deepcopy(g); generic['deliverable_created']['acceptance_criteria']=[{'criterion_id':'AC-X','condition':'Mejorar experiencia','observable_check':''}]
    cases.append(('generic_non_actionable', not validate(generic)['valid'] and 'ACCEPTANCE_NOT_OBSERVABLE' in validate(generic)['blocking_codes'], 'REJECT'))

    nominal=copy.deepcopy(g); nominal['score']['evidence_by_criterion']={k:['PASS'] for k in nominal['score']['evidence_by_criterion']}
    cases.append(('score_without_evidence', not validate(nominal)['valid'] and 'SCORE_EVIDENCE_NOMINAL' in validate(nominal)['blocking_codes'], 'REJECT'))

    twin=copy.deepcopy(g); twin['deliverable_created']['material_claims'][0]={'claim':'La oferta es garantizada','authority_ref':'none://unsupported','status':'SUPPORTED'}; twin['deliverable_created']['product_decision']['selected_decision']=g['deliverable_created']['product_decision']['selected_decision']
    cases.append(('counterfactual_twin_wrong_trajectory', not validate(twin)['valid'], 'REJECT'))

    lineage=copy.deepcopy(g); lineage['deliverable_created']['decision_lineage']['selected_decision']='Decisión divergente no autorizada'
    cases.append(('cross_artifact_decision_mismatch', not validate(lineage)['valid'] and 'DECISION_LINEAGE_MISMATCH' in validate(lineage)['blocking_codes'], 'REJECT'))

    qualifier=copy.deepcopy(g); qualifier['deliverable_created']['handoff_to_next']['qualifiers_to_preserve']=['referencial']
    cases.append(('handoff_drops_required_qualifier', not validate(qualifier)['valid'] and 'HANDOFF_QUALIFIER_LOSS' in validate(qualifier)['blocking_codes'], 'REJECT'))

    holdout=copy.deepcopy(g); holdout['traceability']['case']='holdout_fresh'; holdout['deliverable_created']['product_decision']['selected_decision']='Permitir actualizar solo una carga ya existente, no toda la cartera'; holdout['deliverable_created']['decision_lineage']['selected_decision']=holdout['deliverable_created']['product_decision']['selected_decision']; holdout['deliverable_created']['product_decision']['source_refs'][0]={'source_ref':'product://portfolio-safety/holdout','authority':'CONSTRAINT','supports':'La cartera total mezcla cargas con métodos distintos y aumenta riesgo','current':True}; holdout['deliverable_created']['material_claims'][0]={'claim':'La actualización se limita a una carga existente','authority_ref':'product://portfolio-safety/holdout','status':'SUPPORTED'}; holdout['deliverable_created']['decision_lineage']['evidence_refs']=['product://portfolio-safety/holdout']; holdout['deliverable_created']['evidence_used']=['product://portfolio-safety/holdout']
    cases.append(('holdout_fresh', validate(holdout)['valid'] and schema_ok(holdout), 'PASS'))

    malformed_inputs=[None,[],{'worker':'product_director_lf'},{'worker':'product_director_lf','output_type':'PRODUCT_DIRECTION_SPEC','deliverable_created':[]}]
    malformed_ok=all(isinstance(validate(x),dict) and validate(x)['valid'] is False for x in malformed_inputs)
    cases.append(('malformed_fail_closed_no_crash', malformed_ok, 'REJECT_NO_CRASH'))

    passed=sum(1 for _,ok,_ in cases if ok)
    print(json.dumps({'suite':'PRODUCT_DIRECTOR_LF_STRUCTURAL_REMEDIATION_20260827','evidence_class':'STRUCTURAL_VALIDATOR_ONLY_NOT_PROFILE_EXECUTION','passed':passed,'total':len(cases),'cases':[{'case':n,'ok':ok,'expected':exp} for n,ok,exp in cases]},ensure_ascii=False,indent=2))
    return 0 if passed==len(cases) else 1

if __name__=='__main__': raise SystemExit(run())

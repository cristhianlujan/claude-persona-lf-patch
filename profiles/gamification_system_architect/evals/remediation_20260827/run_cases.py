#!/usr/bin/env python3
import copy, json, sys
from pathlib import Path
HERE=Path(__file__).resolve().parent
PROFILE=HERE.parents[1]
sys.path.insert(0,str(PROFILE/'validators'))
from validate_gamification_output import validate
from jsonschema import Draft202012Validator
SCHEMA=json.loads((PROFILE/'schemas/gamification_system.schema.json').read_text())
SV=Draft202012Validator(SCHEMA)
def schema_ok(p): return not list(SV.iter_errors(p))

def good_output():
    keys=['behavioral_clarity','ethical_financial_safety','mission_loop_quality','reward_scoring_integrity','handoff_traceability']
    return {
      'worker':'gamification_system_architect','output_type':'GAMIFICATION_SYSTEM_SPEC','self_verdict':'PASS',
      'deliverable_created':{
        'system_definition':{'name':'Ruta de claridad educativa'},
        'target_behavior':{'behavior':'Completar un paso educativo voluntario','completion_signal':'Paso educativo marcado completo por evento explícito'},
        'user_state':{'state':'Explorando opciones sin obligación de pago'},
        'mission_map':[],'loop_design':{},'behavior_trigger':{},'progress_model':{},
        'reward_policy':{'healthy_action':'Completar contenido educativo sin realizar pago','harmful_financial_incentive':False,'reward':'insignia simbólica'},
        'risk_controls':['Sin urgencia','Sin penalización por abandono'],'ethical_controls':['Autonomía','Claridad','Salida libre'],
        'metrics':[{'metric_id':'M1','name':'completion_with_clarity','business_objective':'Aumentar comprensión de opciones sin presionar conversión','decision_use':'Decidir si mantener o retirar la misión','target_signal':'Mejora comprensión sin aumento de abandono por presión','metric_type':'DECISIONAL'}],
        'handoff_to_next':{'target':'ui_architect','input_contract':'Mostrar progreso voluntario, no urgente'},'blocked_mechanics':['countdown','punitive streak'],
        'material_mechanics':[{'mechanic_id':'GM-1','objective':'Aumentar comprensión de opciones','mechanic':'Micro-misión educativa con progreso privado','expected_behavior':'Leer y completar un paso educativo','activation_condition':'Usuario entra voluntariamente a la ruta educativa','deactivation_condition':'Se completa, abandona o el usuario cierra la ruta','acceptance_check':'No aparece urgencia ni pérdida; completion event solo tras acción educativa','risk':'Convertir progreso en presión','metric_id':'M1','guardrails':['sin countdown','sin pérdida por abandonar','sin premio por pagar'],'authority_refs':['product://clarity-route/v2'],'risk_flags':[]}],
        'claims':[{'claim_type':'OTHER','claim_text':'El progreso representa pasos educativos completados','status':'SUPPORTED','authority_ref':'product://clarity-route/v2'}],
        'system_lineage':{'objective':'Aumentar comprensión sin presión','expected_user_benefit':'Entender opciones y próximos pasos','expected_business_benefit':'Mejorar calidad de interacción, no conversion forzada','source_refs':['product://clarity-route/v2']}
      },
      'score':{**{k:5 for k in keys},'total':25,'evidence_by_criterion':{k:[f'deliverable_created.material_mechanics[0]::{k}'] for k in keys}},
      'handoff_to_next':{'target':'ui_architect'},'traceability':{'case':'healthy'}
    }

def run():
    cases=[]; g=good_output()
    cases.append(('positive_healthy_mechanic',validate(g)['valid'] and schema_ok(g),'PASS'))
    recovery=copy.deepcopy(g); recovery['deliverable_created']['material_mechanics'][0]['deactivation_condition']='Usuario abandona, completa o desactiva la misión sin pérdida'; cases.append(('positive_recovery_safe',validate(recovery)['valid'] and schema_ok(recovery),'PASS'))

    missing={'worker':'gamification_system_architect','output_type':'MISSING_INPUT_STATE','self_verdict':'NEEDS_INPUT','deliverable_created':{'missing_fields':['target behavior authority'],'why_blocking':'No se puede definir conducta financiera sin objetivo autorizado','next_input_needed':'Fuente upstream vigente del objetivo'}}
    cases.append(('missing_input',validate(missing)['valid'],'NEEDS_INPUT_VALID'))

    dark=copy.deepcopy(g); dark['deliverable_created']['material_mechanics'][0]['risk_flags']=['FALSE_URGENCY']; cases.append(('dark_pattern_pressure',not validate(dark)['valid'] and 'BLOCKING_MECHANIC_RISK' in validate(dark)['blocking_codes'],'REJECT'))
    harmful=copy.deepcopy(g); harmful['deliverable_created']['reward_policy']['harmful_financial_incentive']=True; harmful['deliverable_created']['reward_policy']['healthy_action']='Pagar antes de perder puntos'; cases.append(('harmful_financial_reward',not validate(harmful)['valid'] and 'HARMFUL_FINANCIAL_INCENTIVE' in validate(harmful)['blocking_codes'],'REJECT'))
    claim=copy.deepcopy(g); claim['deliverable_created']['claims']=[{'claim_type':'PAYMENT_STATUS','claim_text':'Pago exitoso garantiza deuda cancelada','status':'SUPPORTED','authority_ref':''}]; cases.append(('unsupported_payment_claim',not validate(claim)['valid'] and 'RISKY_CLAIM_AUTHORITY_MISSING' in validate(claim)['blocking_codes'],'REJECT'))
    ambiguous=copy.deepcopy(g); ambiguous['deliverable_created']['material_mechanics'][0]['deactivation_condition']=''; cases.append(('ambiguous_no_off_condition',not validate(ambiguous)['valid'] and 'MECHANIC_TRACE_MISSING' in validate(ambiguous)['blocking_codes'],'REJECT'))
    vanity=copy.deepcopy(g); vanity['deliverable_created']['metrics'][0]['metric_type']='VANITY_ONLY'; cases.append(('vanity_metric',not validate(vanity)['valid'] and 'VANITY_METRIC_ONLY' in validate(vanity)['blocking_codes'],'REJECT'))
    contradiction=copy.deepcopy(g); contradiction['deliverable_created']['material_mechanics'][0]['risk_flags']=['CLARITY_CONTRADICTION']; cases.append(('lf_clarity_contradiction',not validate(contradiction)['valid'],'REJECT'))
    twin=copy.deepcopy(g); twin['deliverable_created']['metrics'][0]['target_signal']=g['deliverable_created']['metrics'][0]['target_signal']; twin['deliverable_created']['material_mechanics'][0]['risk_flags']=['PRESSURE']; twin['traceability']['case']='same_metric_wrong_trajectory'; cases.append(('counterfactual_twin_same_metric_pressure',not validate(twin)['valid'],'REJECT'))
    hold=copy.deepcopy(g); hold['traceability']['case']='fresh_holdout'; hold['deliverable_created']['material_mechanics'][0].update({'mechanic_id':'GM-HOLD','objective':'Ayudar a revisar requisitos antes de simular','mechanic':'Checklist educativo opcional','expected_behavior':'Revisar requisitos y elegir continuar o salir','activation_condition':'Usuario abre información previa a simulación','deactivation_condition':'Usuario continúa, cierra o marca no continuar','acceptance_check':'Checklist no altera elegibilidad ni ofrece premio por solicitar','risk':'Confundir checklist con elegibilidad','guardrails':['sin claim de elegibilidad','salida visible','sin recompensa financiera'],'authority_refs':['product://simulation-precheck/holdout'],'risk_flags':[]}); hold['deliverable_created']['system_lineage']['source_refs']=['product://simulation-precheck/holdout']; cases.append(('holdout_fresh',validate(hold)['valid'] and schema_ok(hold),'PASS'))
    malformed=[None,[],{'worker':'gamification_system_architect'},{'worker':'gamification_system_architect','output_type':'GAMIFICATION_SYSTEM_SPEC','deliverable_created':[]}]
    cases.append(('malformed_fail_closed_no_crash',all(isinstance(validate(x),dict) and not validate(x)['valid'] for x in malformed),'REJECT_NO_CRASH'))

    passed=sum(ok for _,ok,_ in cases)
    print(json.dumps({'suite':'GAMIFICATION_SYSTEM_ARCHITECT_REMEDIATION_20260827','passed':passed,'total':len(cases),'cases':[{'case':n,'ok':ok,'expected':ex} for n,ok,ex in cases]},ensure_ascii=False,indent=2))
    return 0 if passed==len(cases) else 1
if __name__=='__main__': raise SystemExit(run())

#!/usr/bin/env python3
"""PE10 C6: deterministic real-source selector execution, no live methods.

Reads ACTUAL repo selector, profile assessment and method candidate catalog.
The catalog of capabilities & method evidence refs are deliberate TEST DOUBLES,
not qualified catalog authority or provider attestation.
Does not write, merge, promote methods or activate v0.2.
"""
from __future__ import annotations
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
CAP = ROOT / 'sandbox/lf_contract_gate_test/transversal_assets/capability_selector'
ASSESS = ROOT / 'sandbox/lf_contract_gate_test/transversal_assets/profile_assessment'
REGISTRY = ROOT / 'sandbox/lf_contract_gate_test/transversal_assets/method_pack_registry/method_pack_registry_v1.json'
sys.path[:0] = [str(CAP), str(ASSESS)]
from capability_selector_v2 import compose_capabilities  # noqa: E402
from profile_assessment_v1 import assess_profile  # noqa: E402

CAPABILITIES = [
    ('INDEPENDENT_ASSURANCE', 'risk', ['HIGH', 'CRITICAL'], 20),
    ('PACK_VALIDATION_HARNESS', 'complexity', ['MEDIUM', 'HIGH'], 5),
    ('CAUSAL_EFFECT_LINEAGE', 'causal_requirement', ['REQUIRED', 'HIGH'], 15),
    ('TARGETED_EVIDENCE_ACQUISITION', 'evidence_sufficiency', ['INSUFFICIENT'], 30),
    ('CURRENTNESS_AUTHORITY', 'novelty', ['HIGH'], 11),
    ('PERFORMANCE_EXACT_SOURCE_BENCHMARK', 'optimization_need', ['REQUIRED', 'ADVANCED'], 18),
    ('REVERSIBLE_CANDIDATE_VERIFICATION', 'optimization_need', ['REQUIRED', 'ADVANCED'], 9),
]
CATALOG = [dict(capability_code=a, signal_type=b, accepted_values=c, rank=d,
                state='AVAILABLE') for a, b, c, d in CAPABILITIES]
POLICY = {'fallback_capabilities': ['PACK_VALIDATION_HARNESS']}
P = ['evidence_sufficiency!=NONE', 'candidate_exists',
     'decision_can_change_with_external_evidence', 'grader_available',
     'benchmark_exists', 'uplift_target_defined', 'deterministic_verifier_exists',
     'no_shared_mutable_state', 'holdout_exists', 'search_budget_approved']
E = ['causal_claim_refs', 'candidate_ref', 'challenge_criteria',
     'pre_research_baseline', 'grader_contract', 'baseline_benchmark',
     'holdout', 'verifier_ref', 'search_plan', 'budget']
# Each case is (id, description, typed signals, status override, present
# preconditions, present evidence, budget, expected mode, expected method ids,
# expected distinct cost). Other evidence dimensions default to PASS; the
# optimization opportunity defaults to FAIL except if explicitly overridden.
CASES = [
 ('C01', 'Corregir regla puntual', dict(complexity='LOW',risk='LOW',novelty='LOW'),
  {'structural_compatibility':'FAIL'}, [],[],0,'PATCH',[],0),
 ('C02', 'Diagnosticar causas y refinar', dict(complexity='MEDIUM',risk='LOW',causal_requirement='REQUIRED',evidence_sufficiency='SUFFICIENT'),
  {'strategy_routing':'FAIL'}, ['evidence_sufficiency!=NONE','candidate_exists','grader_available'], ['causal_claim_refs','candidate_ref','grader_contract'],4,'ADAPT',['CAUSAL_ANALYSIS','SELF_REFINE'],4),
 ('C03', 'Investigar nueva materia con fuentes independientes',dict(complexity='LOW',risk='LOW',novelty='HIGH',evidence_sufficiency='INSUFFICIENT',evidence_paths='MULTIPLE_INDEPENDENT'),
  {'domain_task_uplift':'FAIL'}, ['decision_can_change_with_external_evidence','no_shared_mutable_state'], ['pre_research_baseline','search_plan'],7,'SPECIALIZE',['DEEP_RESEARCH','PARALLEL_EVIDENCE_SEARCH'],7),
 ('C04', 'Optimizar con benchmark y verificador',dict(complexity='HIGH',risk='LOW',optimization_need='REQUIRED'),
  {'optimization_opportunity':'PASS'},['candidate_exists','grader_available','benchmark_exists','uplift_target_defined','deterministic_verifier_exists'],['candidate_ref','grader_contract','baseline_benchmark','holdout','verifier_ref'],10,'OPTIMIZE',['SELF_REFINE','EVALUATOR_OPTIMIZER','VERIFIER_GUIDED_SEARCH'],10),
 ('C05', 'Cambio crítico',dict(complexity='HIGH',risk='HIGH'),
  {'structural_compatibility':'FAIL'},['candidate_exists','deterministic_verifier_exists'],['candidate_ref','challenge_criteria','verifier_ref'],6,'PATCH',['HOSTILE_CHALLENGE','VERIFIER_GUIDED_SEARCH'],6),
 ('C06', 'FULL multifactor crítico y avanzado',dict(complexity='HIGH',risk='CRITICAL',uncertainty='HIGH',novelty='HIGH',causal_requirement='REQUIRED',evidence_sufficiency='INSUFFICIENT',evidence_paths='MULTIPLE_INDEPENDENT',optimization_need='ADVANCED'),
  {'architecture_fit':'FAIL'},P,E,30,'REARCHITECT',['CAUSAL_ANALYSIS','HOSTILE_CHALLENGE','DEEP_RESEARCH','SELF_REFINE','VERIFIER_GUIDED_SEARCH','PARALLEL_EVIDENCE_SEARCH','PROMPT_OPTIMIZATION'],25),
 ('C07', 'No hay datos suficientes',dict(complexity='LOW',risk='LOW',novelty='HIGH',evidence_sufficiency='INSUFFICIENT',evidence_paths='MULTIPLE_INDEPENDENT'),
  {'domain_task_uplift':'UNKNOWN'},[],[],30,None,[],0),
 ('C08', 'Perfil ya cumple',dict(complexity='LOW',risk='LOW',novelty='LOW'),
  {},[],[],0,'NO_CHANGE',[],0),
 ('C09', 'Optimización con presupuesto acotado',dict(complexity='HIGH',risk='LOW',optimization_need='REQUIRED'),
  {'optimization_opportunity':'PASS'},['candidate_exists','grader_available','benchmark_exists','uplift_target_defined','deterministic_verifier_exists'],['candidate_ref','grader_contract','baseline_benchmark','holdout','verifier_ref'],3,'OPTIMIZE',['SELF_REFINE'],2),
 ('C10', 'Optimización sin benchmark',dict(complexity='HIGH',risk='LOW',optimization_need='REQUIRED'),
  {'optimization_opportunity':'PASS'},['candidate_exists','grader_available','deterministic_verifier_exists'],['candidate_ref','grader_contract','verifier_ref'],10,'OPTIMIZE',['SELF_REFINE','VERIFIER_GUIDED_SEARCH'],5),
]

BASE_EVIDENCE = ['structural_compatibility','architecture_fit','domain_task_uplift',
                 'strategy_routing','expert_holdout','repeated_optimization',
                 'optimization_opportunity']


def main() -> None:
    registry = json.loads(REGISTRY.read_text(encoding='utf-8'))
    assert registry['schema_version'] == 'METHOD_PACK_REGISTRY_V1'
    assert registry['execution_permission'] is False
    assert len(registry['methods']) == 8
    results=[]
    for cid,desc,signals,changes,preconditions,refs,budget,exp_mode,exp_methods,exp_cost in CASES:
        ev={k:{'status':changes.get(k,'FAIL' if k=='optimization_opportunity' else 'PASS'),
               'refs':['test-evidence://'+cid+'/'+k]} for k in BASE_EVIDENCE}
        context = dict(signals, precondition_evidence={k:'fixture://'+cid+'/'+k for k in preconditions},
                       method_evidence={k:'fixture://'+cid+'/'+k for k in refs},
                       budget={'max_method_cost_points':budget})
        assessed=assess_profile({'signals':signals, 'evidence':ev})
        context['profile_gaps']=assessed['profile_gaps']
        chosen=compose_capabilities(context,CATALOG,POLICY,registry)
        selected=[m['method_id'] for m in chosen['method_requirements'] if m['eligible_for_composition']]
        assert assessed['evolution_mode']==exp_mode, (cid,'MODE',assessed['evolution_mode'])
        assert assessed['assessment_status']==('NEEDS_MORE_EVIDENCE' if exp_mode is None else 'EVIDENCE_SUFFICIENT'),(cid,'STATUS')
        assert set(selected)==set(exp_methods), (cid,'METHODS',selected)
        assert chosen['estimated_cost']['method_cost_points']==exp_cost, (cid,'COST')
        assert exp_cost<=budget, (cid,'OVER_BUDGET')
        assert chosen['execution_authorized'] is False, (cid,'FALSE_AUTHORITY')
        assert chosen['selection_evidence_authority']=='CALLER_DECLARED_UNVERIFIED', (cid,'FALSE_RECEIPT')
        results.append(dict(case=cid,status='PASS',mode=exp_mode or 'NEEDS_MORE_EVIDENCE',
                            methods=selected,cost=exp_cost,budget=budget))
    # Full capability mix: two distinct subtasks, NOT contradictory scalar signals.
    _,_,signals,_,preconditions,refs,budget,_,_,_=CASES[5]
    context=dict(signals, profile_gaps=[],
                 precondition_evidence={k:'fixture://full/'+k for k in preconditions},
                 method_evidence={k:'fixture://full/'+k for k in refs},
                 budget={'max_method_cost_points':budget})
    all_selected={}
    for need in ('REQUIRED','ADVANCED'):
        phase=compose_capabilities(dict(context,optimization_need=need),CATALOG,POLICY,registry)
        assert phase['execution_authorized'] is False
        for m in phase['method_requirements']:
            if m['eligible_for_composition']:
                all_selected[m['method_id']]=m
    assert set(all_selected)=={m['method_id'] for m in registry['methods']}
    assert sum(m['cost_points'] for m in all_selected.values())==30
    # Negative guards: no supplied evidence, registry claims unauthorized exec, budget.
    noev=compose_capabilities(dict(context,precondition_evidence={},method_evidence={}),CATALOG,POLICY,registry)
    assert not any(m['eligible_for_composition'] for m in noev['method_requirements'])
    malformed={**registry,'execution_permission':True}
    denied=compose_capabilities(context,CATALOG,POLICY,malformed)
    assert denied['fallback_state']=='CAPABILITY_FAILURE'
    small=compose_capabilities(dict(context,budget={'max_method_cost_points':2}),CATALOG,POLICY,registry)
    assert small['estimated_cost']['method_cost_points']<=2
    for r in results:
        print('PASS',r['case'],'mode='+r['mode'],'methods='+','.join(r['methods']),'cost='+str(r['cost']))
    print('PASS FULL_EIGHT_METHODS_IN_TWO_SUBTASKS cost=30 budget=30')
    print('PASS NEGATIVE_GATES missing_evidence/unauthorized_registry/budget')
    print('PASS PE10_C6_SOURCE_SELECTION_MATRIX cases=10 qualified_method_execution=NOT_CLAIMED runtime_activation=NONE')

if __name__=='__main__': main()
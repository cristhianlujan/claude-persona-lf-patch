"""Consumer regression test with synthetic registry; no governed catalog writes."""
from __future__ import annotations
import json
from pathlib import Path
from skills.profile_creator.evals.profile_method_composition_v1 import compose_profile_methods

# Tests have no filesystem side effects. Synthetic case assessment, not live Profile Updater.


def make_registry(methods):
    return {'registry_id': 'METHOD_PACK_REGISTRY', 'provider_verified': True,
            'source_ref': 'exercise://synthetic-candidate-catalog', 'methods': methods}


def method(mid, scopes, triggers):
    return {'method_id': mid, 'profile_scopes': scopes,
            'applicability': [{'type': 'need.'+t, 'accepted_values': ['YES'], 'rank': 10} for t in triggers],
            'availability_state': 'EXPERIMENTAL_NOT_ADMITTED',
            'selection_lane': 'SHADOW_ONLY', 'auto_select': False,
            'execution_permission': False}


def assessment(profile, names):
    return {'profile_slug': profile, 'signals': [{'type': 'need.'+n, 'value': 'YES',
            'evidence_ref': 'exercise://case-prompt', 'evidence_state': 'EXERCISE_SUPPLIED'} for n in names]}


METHODS = [
    method('EVIDENCE_GATE', ['quality_pack'], ['evidence']),
    method('RELATIONAL_TRACE', ['quality_pack'], ['relational']),
    method('FALSE_POSITIVE_CONTROL', ['quality_pack'], ['relational']),
    method('ASYNC_AUTH', ['quality_pack'], ['revoke']),
    method('IDEMPOTENT_EFFECTS', ['quality_pack'], ['retry']),
    method('UI_COMPONENT', ['ui_architect'], ['existing_ui']),
    method('UI_RACE', ['ui_architect'], ['race']),
    method('UI_TIMEOUT', ['ui_architect'], ['reject']),
    method('UI_RETRY', ['ui_architect'], ['reject']),
    method('UI_CONFIG', ['ui_architect'], ['config']),
    method('UI_REVISION', ['ui_architect'], ['config']),
    method('UI_PRINT', ['ui_architect'], ['print']),
    method('SEGMENT_ANALYSIS', ['product_director_lf'], ['segments']),
    method('COMMON_MIX_SENSITIVITY', ['product_director_lf'], ['segments']),
    method('WILSON', ['product_director_lf'], ['complaints']),
    method('BETA_RISK', ['product_director_lf'], ['complaints']),
    method('EXPECTED_NET', ['product_director_lf'], ['net']),
    method('MANDATE_SCOPE', ['product_director_lf'], ['mandate']),
    method('EXACT_TERMS', ['product_director_lf'], ['mandate']),
]
CASES = {
    '201': ('quality_pack', ['relational']),
    '202': ('quality_pack', ['revoke']),
    '203': ('quality_pack', ['retry']),
    '204': ('quality_pack', []),
    '205': ('ui_architect', ['existing_ui','race']),
    '206': ('ui_architect', ['existing_ui','reject']),
    '207': ('ui_architect', ['existing_ui','config']),
    '208': ('ui_architect', ['existing_ui','print']),
    '209': ('product_director_lf', ['segments']),
    '210': ('product_director_lf', ['complaints']),
    '211': ('product_director_lf', ['net']),
    '212': ('product_director_lf', ['mandate']),
}


def run():
    registry = make_registry(METHODS)
    policy = {'fallback_capabilities': []}
    selections = {}
    for case, (profile, needs) in CASES.items():
        inp = assessment(profile, needs)
        if not needs:
            inp.update({'decision': 'NO_ADDITIONAL_CAPABILITY_NEEDED',
                        'decision_evidence_ref': 'exercise://bundle-verification',
                        'decision_evidence_state': 'EXERCISE_SUPPLIED'})
        out = compose_profile_methods(inp, registry, policy)
        assert out['status'] in {'NO_ADDITIONAL_CAPABILITY_NEEDED', 'CANDIDATE_COMPOSITION_SELECTED'}, (case,out)
        assert not out['method_execution_authorized'] and not out['profile_write_authorized'] and not out['runtime_activation_authorized']
        selections[case] = out
    assert len(selections) == 12
    assert selections['204']['selected_methods'] == []
    assert set(selections['206']['selected_methods']) == {'UI_COMPONENT','UI_TIMEOUT','UI_RETRY'}
    assert set(selections['207']['selected_methods']) == {'UI_COMPONENT','UI_CONFIG','UI_REVISION'}
    assert set(selections['210']['selected_methods']) == {'BETA_RISK','WILSON'}
    assert 'EXACT_TERMS' in selections['212']['selected_methods']
    assert 'UI_COMPONENT' not in selections['209']['selected_methods']
    negatives = 0
    def denied(inp, reg=registry, pol=policy, reason=None):
        nonlocal negatives
        out = compose_profile_methods(inp, reg, pol)
        assert out['status'] == 'BLOCKED_CANDIDATE_SELECTION',out
        if reason: assert out['reason'] == reason,(out,reason)
        negatives += 1
    denied({'profile_slug': 'quality_pack'}, reason='ASSESSMENT_SIGNALS_MISSING')
    denied({'profile_slug': 'quality_pack', 'signals': []}, reason='EMPTY_SIGNAL_NEEDS_POSITIVE_AUTHORITY')
    denied(assessment('quality_pack', ['relational']), make_registry(METHODS+METHODS[:1]), reason='METHOD_RECORD_OR_ID_INVALID')
    denied(assessment('quality_pack', ['relational']), {'registry_id':'METHOD_PACK_REGISTRY','provider_verified':False,'source_ref':'x','methods':METHODS}, reason='REGISTRY_NOT_RESOLVED_BY_PROVIDER')
    denied(assessment('quality_pack', ['relational']), make_registry([dict(METHODS[0], auto_select=True)]), reason='SHADOW_SAFETY_INVARIANT_FAILED')
    bad=assessment('quality_pack',['relational']);bad['signals'][0]['evidence_state']='UNVERIFIED'
    denied(bad, reason='SIGNAL_PROVENANCE_NOT_RESOLVED')
    denied(assessment('quality_pack',['relational']),pol={'fallback_capabilities':['NOT_REGISTERED']},reason='FALLBACK_NOT_IN_REGISTRY')
    clash=assessment('quality_pack',['relational']);clash['signals'].append({'type':'need.relational','value':'NO','evidence_ref':'exercise://conflict','evidence_state':'EXERCISE_SUPPLIED'})
    denied(clash, reason='PROVIDER_CONTRADICTORY')
    denied(assessment('product_director_lf',['relational']), reason='PROVIDER_NO_SIGNAL')
    assert negatives == 9
    evidence = {'case_count': 12, 'negative_tests': negatives,
                'selector_reused': 'CAPABILITY_SELECTOR_V1',
                'registry_fixture': 'SYNTHETIC_NOT_CANONICAL',
                'signal_extraction': 'UPSTREAM_MANUALLY_SUPPLIED_NOT_AUTOMATIC',
                'execution_authorized': False,
                'selections': selections}
    print(json.dumps({'cases':evidence['case_count'],'negatives':evidence['negative_tests'],'selection_only':True,'provider':'CAPABILITY_SELECTOR_V1'}))
    print('PASS_PROFILE_METHOD_COMPOSITION cases=12 negatives=9 selection_only=true')


if __name__ == '__main__':run()

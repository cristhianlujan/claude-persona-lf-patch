"""Profile Updater candidate consumer for the governed CAPABILITY_SELECTOR v1.

It does not select by profile/case ID, register methods, authorize execution,
change authoritative assets or add a parallel selector. The caller supplies
its current externally-resolved method catalog and a PROFILE_ASSESSMENT result.
"""
from __future__ import annotations

from typing import Any
from sandbox.lf_contract_gate_test.transversal_assets.capability_selector.capability_selector_v1 import select_capabilities


ELIGIBLE_SOURCE_STATES = frozenset({'VERIFIED', 'EXERCISE_SUPPLIED'})


def _block(reason: str, **detail: Any) -> dict[str, Any]:
    return {
        'status': 'BLOCKED_CANDIDATE_SELECTION', 'reason': reason,
        'selected_methods': [], 'selection_reasons': [],
        'method_execution_authorized': False,
        'profile_write_authorized': False,
        'runtime_activation_authorized': False,
        'candidate_only': True,
        **detail,
    }


def compose_profile_methods(assessment: dict[str, Any],
                            method_registry: dict[str, Any],
                            policy: dict[str, Any]) -> dict[str, Any]:
    """Return advisory method composition. Nothing here is an execution grant.

    Evidence and catalog authenticity are delegated to the trusted caller;
    do not infer provenance from caller-declared flags. In experimental mode
    allow exercise-supplied evidence, distinctly marked in the output.
    """
    if not isinstance(assessment, dict) or not isinstance(method_registry, dict) or not isinstance(policy, dict):
        return _block('INPUT_INVALID')
    profile = assessment.get('profile_slug')
    if not isinstance(profile, str) or not profile.strip():
        return _block('PROFILE_MISSING')
    if method_registry.get('registry_id') != 'METHOD_PACK_REGISTRY':
        return _block('REGISTRY_AUTHORITY_UNRESOLVED')
    if method_registry.get('provider_verified') is not True:
        return _block('REGISTRY_NOT_RESOLVED_BY_PROVIDER')
    registry_ref = method_registry.get('source_ref')
    if not isinstance(registry_ref, str) or not registry_ref:
        return _block('REGISTRY_SOURCE_MISSING')
    methods = method_registry.get('methods')
    if not isinstance(methods, list):
        return _block('METHODS_INVALID')
    seen: set[str] = set()
    catalog: list[dict[str, Any]] = []
    for method in methods:
        if not isinstance(method, dict):
            return _block('METHOD_INVALID')
        mid = method.get('method_id')
        scopes = method.get('profile_scopes')
        triggers = method.get('applicability')
        if (not isinstance(mid, str) or not mid or mid in seen
            or not isinstance(scopes, list) or not scopes
            or any(not isinstance(s, str) or not s for s in scopes)
            or not isinstance(triggers, list) or not triggers):
            return _block('METHOD_RECORD_OR_ID_INVALID')
        seen.add(mid)
        if method.get('availability_state') != 'EXPERIMENTAL_NOT_ADMITTED':
            # These are candidate methods only; do not mix in released runtime methods.
            continue
        if (method.get('selection_lane') != 'SHADOW_ONLY'
            or method.get('auto_select') is not False
            or method.get('execution_permission') is not False):
            return _block('SHADOW_SAFETY_INVARIANT_FAILED', method_id=mid)
        if profile not in scopes and '*' not in scopes:
            continue
        for trigger in triggers:
            if not isinstance(trigger, dict):
                return _block('TRIGGER_INVALID', method_id=mid)
            typ = trigger.get('type')
            vals = trigger.get('accepted_values')
            rank = trigger.get('rank', 0)
            if (not isinstance(typ, str) or not typ
                or not isinstance(vals, list) or not vals
                or any(not isinstance(v, str) or not v for v in vals)
                or type(rank) not in (int, float)):
                return _block('TRIGGER_INVALID', method_id=mid)
            catalog.append({'capability_code': mid,
                            'signal_type': typ,
                            'accepted_values': vals,
                            'rank': rank,
                            'state': 'AVAILABLE'})
    if not isinstance(assessment.get('signals'), list):
        return _block('ASSESSMENT_SIGNALS_MISSING')
    signals = assessment['signals']
    for signal in signals:
        if not isinstance(signal, dict):
            return _block('SIGNAL_INVALID')
        if (not isinstance(signal.get('type'), str)
            or not isinstance(signal.get('value'), str)
            or not isinstance(signal.get('evidence_ref'), str)
            or not signal['evidence_ref']
            or signal.get('evidence_state') not in ELIGIBLE_SOURCE_STATES):
            return _block('SIGNAL_PROVENANCE_NOT_RESOLVED')
    if 'fallback_capabilities' not in policy:
        return _block('FALLBACK_NOT_DECLARED')
    fb = policy['fallback_capabilities']
    if not isinstance(fb, list) or any(not isinstance(x, str) or not x for x in fb):
        return _block('FALLBACK_INVALID')
    # For this consumer, only candidates from the registry may appear as fallback.
    if any(x not in seen for x in fb):
        return _block('FALLBACK_NOT_IN_REGISTRY')
    if not signals:
        if (assessment.get('decision') != 'NO_ADDITIONAL_CAPABILITY_NEEDED'
            or assessment.get('decision_evidence_state') not in ELIGIBLE_SOURCE_STATES
            or not isinstance(assessment.get('decision_evidence_ref'), str)
            or not assessment['decision_evidence_ref']):
            return _block('EMPTY_SIGNAL_NEEDS_POSITIVE_AUTHORITY')
        return {
            'status': 'NO_ADDITIONAL_CAPABILITY_NEEDED',
            'selected_methods': [], 'selection_reasons': ['EXPLICIT_POSITIVE_EMPTY_SELECTION'],
            'source_ref': registry_ref,
            'selection_source': 'CAPABILITY_SELECTOR_V1_CONSUMER',
            'candidate_only': True, 'method_execution_authorized': False,
            'profile_write_authorized': False, 'runtime_activation_authorized': False,
            'evidence_scope': assessment['decision_evidence_state'],
        }
    provider_signals = [{'type': s['type'], 'value': s['value']} for s in signals]
    result = select_capabilities(provider_signals, catalog, {'fallback_capabilities': fb})
    if result['fallback_state'] in {'CONTRADICTORY', 'CAPABILITY_FAILURE', 'NO_SIGNAL'}:
        return _block('PROVIDER_'+result['fallback_state'], provider_result=result)
    return {
        'status': 'CANDIDATE_COMPOSITION_SELECTED',
        'selected_methods': result['selected_capabilities'],
        'selection_reasons': result['reasons'],
        'provider_state': result['fallback_state'],
        'selection_source': 'CAPABILITY_SELECTOR_V1_CONSUMER',
        'source_ref': registry_ref,
        'evidence_scope': 'EXERCISE_SUPPLIED' if any(s['evidence_state'] == 'EXERCISE_SUPPLIED' for s in signals) else 'VERIFIED',
        'candidate_only': True,
        'method_execution_authorized': False,
        'profile_write_authorized': False,
        'runtime_activation_authorized': False,
    }

"""D1/D2 candidate discovery, PURE AND EPHEMERAL.

All policy values and authoritative metadata must be resolved from Supabase by a
trusted adapter. This module neither reads databases nor grants data access.
It is not a business-rule repository or canonical evidence store.
"""
from __future__ import annotations

import re
import unicodedata
from typing import Any


class ContractError(ValueError):
    pass


def _normalized(text: str) -> str:
    folded = unicodedata.normalize('NFKD', text).casefold()
    folded = ''.join(c for c in folded if not unicodedata.combining(c))
    return ' '.join(re.findall(r'[a-z0-9]+', folded))


def _terms(text: str, stop_terms: list[str]) -> list[str]:
    excluded = set(_normalized(s) for s in stop_terms)
    return list(dict.fromkeys(t for t in _normalized(text).split() if t not in excluded))


def _policy(policy: dict[str, Any]) -> tuple[int, dict[str, int], list[str]]:
    if not isinstance(policy, dict) or policy.get('authority') != 'SUPABASE' or not policy.get('snapshot_verified'):
        raise ContractError('SUPABASE_POLICY_SNAPSHOT_REQUIRED')
    max_candidates = policy.get('max_candidates')
    weights = policy.get('ranking_weights')
    stop_terms = policy.get('stop_terms')
    if (not isinstance(max_candidates, int) or isinstance(max_candidates, bool) or max_candidates not in range(1, 51)
        or not isinstance(weights, dict) or set(weights) != {'label', 'columns', 'description'}
        or any(not isinstance(v, int) or isinstance(v, bool) or v < 0 for v in weights.values())
        or not isinstance(stop_terms, list) or any(not isinstance(v, str) for v in stop_terms)):
        raise ContractError('DISCOVERY_POLICY_INVALID')
    return max_candidates, weights, stop_terms


def discover_sources(request: dict[str, Any], metadata: dict[str, Any], policy: dict[str, Any]) -> dict[str, Any]:
    """Rank candidates; metadata provenance/permission is NOT inferred by rank."""
    try:
        max_candidates, weights, stop_terms = _policy(policy)
        if not isinstance(metadata, dict) or metadata.get('origin') != 'SUPABASE' or not metadata.get('snapshot_ref'):
            raise ContractError('TRUSTED_METADATA_SNAPSHOT_REQUIRED')
        entries = metadata.get('sources')
        if not isinstance(entries, list):
            raise ContractError('SOURCE_CATALOG_INVALID')
        if not isinstance(request, dict) or not isinstance(request.get('objective'), str) or not request['objective'].strip():
            raise ContractError('OBJECTIVE_INVALID')
        query_terms = request.get('query_terms', [])
        if not isinstance(query_terms, list) or any(not isinstance(t, str) for t in query_terms):
            raise ContractError('QUERY_TERMS_INVALID')
        terms = _terms(request['objective'] + ' ' + ' '.join(query_terms), stop_terms)
        if not terms:
            raise ContractError('NO_SEARCH_TERMS')
        candidates = []
        for source in entries:
            if not isinstance(source, dict):
                raise ContractError('SOURCE_INVALID')
            ref, label = source.get('source_ref'), source.get('label')
            columns = source.get('columns', [])
            if (not isinstance(ref, str) or not ref or not isinstance(label, str)
                or not isinstance(columns, list) or any(not isinstance(c, str) for c in columns)):
                raise ContractError('SOURCE_SHAPE_INVALID')
            # The source's presence in metadata DOES NOT establish access to its rows.
            fields = {'label': _normalized(label), 'columns': _normalized(' '.join(columns)),
                      'description': _normalized(source.get('description') or '')}
            matched = [t for t in terms if any(t in field.split() or (len(t) >= 4 and any(word.startswith(t) for word in field.split()))
                                                   for field in fields.values())]
            score = sum(weights[field] for t in matched for field, value in fields.items()
                        if t in value.split() or (len(t) >= 4 and any(word.startswith(t) for word in value.split())))
            if score > 0:
                candidates.append({
                    'source_ref': ref, 'source_kind': source.get('source_kind', 'UNKNOWN'),
                    'relevance_score': score, 'matched_terms': matched,
                    'relation_refs': source.get('relation_refs', []),
                    'authority_check': 'NOT_VERIFIED', 'authorization_check': 'NOT_VERIFIED',
                    'provenance': {'metadata_snapshot_ref': metadata['snapshot_ref']},
                })
        candidates.sort(key=lambda x: (-x['relevance_score'], x['source_ref']))
        return {'schema_version': 'LF_SOURCE_DISCOVERY_RESULT_V1',
                'discovery_state': 'CANDIDATES_FOUND' if candidates else 'NO_MATCH_IN_SCOPE',
                'discovery_exhausted': False,
                'candidate_sources': candidates[:max_candidates],
                'scope_ref': metadata['snapshot_ref'],
                'scope_remaining_unknown': True,
                'data_access_granted': False}
    except ContractError as e:
        return {'schema_version': 'LF_SOURCE_DISCOVERY_RESULT_V1',
                'discovery_state': 'ERROR_FAIL_CLOSED', 'code': str(e),
                'candidate_sources': [], 'discovery_exhausted': False, 'data_access_granted': False}


def adapt_for_targeted_evidence(
    discovery: dict[str, Any], unresolved_reasons: list[str],
    consumer_ref: str, admitted: dict[str, dict[str, Any]]
) -> dict[str, Any]:
    """D2: emits an existing planner payload, not an acquisition/execution permission.

    'admitted' MUST be obtained from an independent, trusted Supabase authority
    adapter after verifying actor, tenant, source, reason and currentness. It
    must never be the raw GPT prediction or an Excel/Sheets record.
    """
    if (not isinstance(discovery, dict) or not isinstance(unresolved_reasons, list)
        or any(not isinstance(r, str) or not r for r in unresolved_reasons)
        or not isinstance(admitted, dict) or not isinstance(consumer_ref, str)):
        return {'state': 'BLOCK', 'code': 'D2_CONTRACT_INVALID'}
    if discovery.get('discovery_state') not in ('CANDIDATES_FOUND', 'DISCOVERY_EXHAUSTED'):
        return {'state': 'DISCOVER_MORE', 'code': 'DISCOVERY_NOT_EXHAUSTED'}
    candidates = []
    for c in discovery.get('candidate_sources', []):
        ref = c.get('source_ref')
        proof = admitted.get(ref)
        if not isinstance(proof, dict):
            continue
        if (proof.get('authority') != 'SUPABASE' or proof.get('authorization_verified') is not True
            or proof.get('currentness_verified') is not True or not proof.get('admission_receipt_ref')):
            continue
        reasons = proof.get('covers_reasons', [])
        cost = proof.get('acquisition_cost_rank')
        if (not isinstance(reasons, list) or not all(isinstance(x, str) and x in unresolved_reasons for x in reasons)
            or not reasons or not isinstance(cost, int) or isinstance(cost, bool) or cost < 0):
            continue
        candidates.append({'candidate_ref': proof['admission_receipt_ref'], 'source_ref': ref,
                           'covers_reasons': reasons, 'acquisition_cost_rank': cost,
                           'available': True, 'material': proof.get('material_verified') is True})
    if discovery.get('discovery_state') != 'DISCOVERY_EXHAUSTED' and not candidates:
        return {'state': 'DISCOVER_MORE', 'code': 'CANDIDATES_NOT_ADMITTED'}
    return {'state': 'PLANNER_INPUT_READY',
            'payload': {'consumer_ref': consumer_ref, 'unresolved_reasons': unresolved_reasons,
                        'current_evidence': [], 'candidates': candidates},
            'planner_capability_code': 'TARGETED_EVIDENCE_ACQUISITION',
            'data_access_granted': False}

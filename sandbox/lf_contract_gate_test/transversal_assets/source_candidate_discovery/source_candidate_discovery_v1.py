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


def _policy(policy: dict[str, Any]) -> tuple[int, dict[str, int], list[str], int, int]:
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
    relation_hops = policy.get('relation_hops', 0)
    max_related = policy.get('max_related_candidates', 0)
    if (not isinstance(relation_hops, int) or isinstance(relation_hops, bool)
        or relation_hops not in range(0, 3)
        or not isinstance(max_related, int) or isinstance(max_related, bool)
        or max_related not in range(0, 51)):
        raise ContractError('RELATION_DISCOVERY_POLICY_INVALID')
    return max_candidates, weights, stop_terms, relation_hops, max_related


def discover_sources(request: dict[str, Any], metadata: dict[str, Any], policy: dict[str, Any]) -> dict[str, Any]:
    """Rank candidates; metadata provenance/permission is NOT inferred by rank."""
    try:
        max_candidates, weights, stop_terms, relation_hops, max_related = _policy(policy)
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
        source_index = {}
        for source in entries:
            if not isinstance(source, dict):
                raise ContractError('SOURCE_INVALID')
            ref, label = source.get('source_ref'), source.get('label')
            columns = source.get('columns', [])
            if (not isinstance(ref, str) or not ref or not isinstance(label, str)
                or not isinstance(columns, list) or any(not isinstance(c, str) for c in columns)):
                raise ContractError('SOURCE_SHAPE_INVALID')
            relation_refs = source.get('relation_refs', [])
            aliases = source.get('aliases', [])
            if (not isinstance(relation_refs, list) or any(not isinstance(r, str) or not r for r in relation_refs)
                or not isinstance(aliases, list) or any(not isinstance(a, str) for a in aliases)
                or ref in source_index):
                raise ContractError('SOURCE_RELATION_OR_ALIAS_INVALID')
            source_index[ref] = source
            # Aliases are metadata supplied from the trusted catalog, not case-specific code.
            fields = {'label': _normalized(label + ' ' + ' '.join(aliases)),
                      'columns': _normalized(' '.join(columns)),
                      'description': _normalized(source.get('description') or '')}
            matched = [t for t in terms if any(t in field.split() or (len(t) >= 4 and any(word.startswith(t) for word in field.split()))
                                                   for field in fields.values())]
            score = sum(weights[field] for t in matched for field, value in fields.items()
                        if t in value.split() or (len(t) >= 4 and any(word.startswith(t) for word in value.split())))
            if score > 0:
                candidates.append({
                    'source_ref': ref, 'source_kind': source.get('source_kind', 'UNKNOWN'),
                    'relevance_score': score, 'matched_terms': matched,
                    'relation_refs': relation_refs, 'selection_basis': 'DIRECT_METADATA_MATCH',
                    'authority_check': 'NOT_VERIFIED', 'authorization_check': 'NOT_VERIFIED',
                    'provenance': {'metadata_snapshot_ref': metadata['snapshot_ref']},
                })
        candidates.sort(key=lambda x: (-x['relevance_score'], x['source_ref']))
        selected = candidates[:max_candidates]
        related = []
        # Bounded breadth-first metadata-only expansion, no data hydration.
        if relation_hops and max_related and selected:
            direct_refs = {c['source_ref'] for c in selected}
            seen = set(direct_refs)
            frontier = [(c['source_ref'], [c['source_ref']]) for c in selected]
            for _ in range(relation_hops):
                next_frontier = []
                for node_ref, path in frontier:
                    for linked_ref in sorted(source_index[node_ref].get('relation_refs', [])):
                        # Foreign sources cannot be added outside the current catalog scope.
                        if linked_ref not in source_index or linked_ref in seen:
                            continue
                        seen.add(linked_ref)
                        new_path = path + [linked_ref]
                        related.append({
                            'source_ref': linked_ref,
                            'source_kind': source_index[linked_ref].get('source_kind', 'UNKNOWN'),
                            'relevance_score': 0, 'matched_terms': [],
                            'relation_refs': source_index[linked_ref].get('relation_refs', []),
                            'selection_basis': 'STRUCTURAL_NEIGHBOR_UNVERIFIED',
                            'relation_path': new_path,
                            'authority_check': 'NOT_VERIFIED',
                            'authorization_check': 'NOT_VERIFIED',
                            'provenance': {'metadata_snapshot_ref': metadata['snapshot_ref']},
                        })
                        next_frontier.append((linked_ref, new_path))
                        if len(related) >= max_related:
                            break
                    if len(related) >= max_related:
                        break
                if len(related) >= max_related or not next_frontier:
                    break
                frontier = next_frontier
        return {'schema_version': 'LF_SOURCE_DISCOVERY_RESULT_V1',
                'discovery_state': 'CANDIDATES_FOUND' if candidates else 'NO_MATCH_IN_SCOPE',
                'discovery_exhausted': False,
                'candidate_sources': selected + related,
                'direct_count': len(selected), 'related_count': len(related),
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
    if discovery.get('discovery_state') == 'DISCOVERY_EXHAUSTED':
        # This adapter NEVER asserts exhaustion. Canonical exhaustion must be
        # adjudicated by a separate Supabase trust boundary, not input flags.
        return {'state': 'BLOCK', 'code': 'CANONICAL_EXHAUSTION_PROOF_REQUIRED'}
    if discovery.get('discovery_state') != 'CANDIDATES_FOUND':
        return {'state': 'DISCOVER_MORE', 'code': 'DISCOVERY_NOT_COMPLETE'}
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
    if not candidates:
        return {'state': 'DISCOVER_MORE', 'code': 'CANDIDATES_NOT_ADMITTED'}
    return {'state': 'PLANNER_INPUT_READY',
            'payload': {'consumer_ref': consumer_ref, 'unresolved_reasons': unresolved_reasons,
                        'current_evidence': [], 'candidates': candidates},
            'planner_capability_code': 'TARGETED_EVIDENCE_ACQUISITION',
            'data_access_granted': False}

"""A9 snapshot assembler. Pure Python; no I/O, storage or model calls."""
from __future__ import annotations

import copy
import hashlib
import json
import re
from typing import Any

from validate_wave1_boundary_contracts_v1 import (
    ContractError, assemble_scope_front_matrix_v1,
    validate_programming_snapshot_payload_v1,
)

DIGEST = 'd2e347efe07a9971790f1a605f0b6ab93fa48a1608744330d1e49e59930d7fb8'
SHA40 = re.compile(r'^[0-9a-f]{40}$')
SHA64 = re.compile(r'^[0-9a-f]{64}$')
VERSIONS = dict(A3='TARGETED_EVIDENCE_SET_V1', A4='SHARED_CHANGE_IMPACT_MAP_V1',
                A5='ANALYSIS_DECISION_CONTEXT_V1', A6='IMPLEMENTABILITY_SCHEMA_V1',
                A7='MATERIAL_FRONT_COVERAGE_V1', A8='ANALYSIS_STOP_RULE_V1')
CANDIDATE_FIELDS = ('schema_version', 'candidate_only', 'request_context', 'classification',
                    'stage_trace', 'material_unknowns', 'decisions_pending', 'requirements',
                    'material_fronts', 'scope_proposals', 'research_stop',
                    'package_readiness_candidate')
SNAPSHOT_FIELDS = ('objective', 'target', 'target_granularity', 'authority_state',
                   'implementation_state', 'requirements', 'authority_bindings',
                   'applicable_rules', 'applicable_invariants', 'preserve',
                   'material_front_coverage', 'implementability_schema', 'decision_context',
                   'analysis_stop_rule', 'scope_front_matrix', 'scope_readiness',
                   'package_readiness', 'unresolved_material_items', 'source_refs',
                   'currentness_refs', 'snapshot_schema_digest_sha256',
                   'authority_fingerprint_sha256', 'source_snapshot_sha256')
FORBIDDEN = {'chosen_component_structure', 'chosen_framework_pattern',
             'chosen_endpoint_design', 'chosen_internal_algorithm'}


class A9AssemblyError(ValueError):
    def __init__(self, code: str):
        self.code = code
        super().__init__(code)


def require(obj: dict, key: str, code: str) -> Any:
    if not isinstance(obj, dict) or key not in obj or obj[key] is None:
        raise A9AssemblyError(code)
    return obj[key]


def nonempty_str(value: Any, code: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise A9AssemblyError(code)
    return value


def list_field(obj: dict, key: str, code: str) -> list:
    value = require(obj, key, code)
    if not isinstance(value, list):
        raise A9AssemblyError(code)
    return value


def json_clone(value):
    return copy.deepcopy(value)


def fingerprint(value: Any) -> str:
    """PROPOSED A9_FINGERPRINT_RULE_V1, NOT postgres jsonb::text."""
    data = json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=False,
                      allow_nan=False).encode('utf-8')
    return hashlib.sha256(data).hexdigest()


def walk_no_strategy(value):
    if isinstance(value, dict):
        if FORBIDDEN.intersection(value):
            raise A9AssemblyError('A9_TECHNICAL_STRATEGY_FORBIDDEN')
        for item in value.values():
            walk_no_strategy(item)
    elif isinstance(value, list):
        for item in value:
            walk_no_strategy(item)


def refs_from(value, field, code):
    result = list_field(value, field, code)
    if any(not isinstance(x, str) or not x.strip() for x in result):
        raise A9AssemblyError(code)
    return result


def typed_artifacts(artifacts):
    for stage, version in VERSIONS.items():
        item = require(artifacts, stage, f'A9_STAGE_ARTIFACT_MISSING:{stage}')
        if not isinstance(item, dict) or item.get('schema_version') != version:
            raise A9AssemblyError(f'A9_STAGE_ARTIFACT_VERSION:{stage}')
    return artifacts


def collect_refs(artifacts, canonical):
    """Only explicitly present source/currentness references, retaining source provenance."""
    result = []
    for stage in VERSIONS:
        item = artifacts[stage]
        if 'source_refs' in item:
            result.extend(refs_from(item, 'source_refs', f'A9_STAGE_SOURCE_INVALID:{stage}'))
    return sorted(set(result + canonical))


def unresolved_items(candidate, stages):
    sources = (
        ('A3', 'unresolved_material_gaps'),
        ('A4', 'unresolved_material_impacts'),
        ('A5', 'unresolved_questions'),
        ('A6', 'unresolved_material_items'),
        ('A7', 'unmapped_material_signals'),
        ('A8', 'unresolved_decision_changing_questions'),
        ('A8', 'additional_available_evidence_capable_of_changing_material_decision'),
    )
    items = []
    for stage, field in sources:
        artifact = stages[stage]
        if field in artifact:
            for index, value in enumerate(list_field(artifact, field, f'A9_UNRESOLVED_INVALID:{stage}.{field}')):
                items.append({'origin': f'{stage}.{field}', 'index': index,
                              'scope_id': value.get('scope_id') if isinstance(value, dict) else None,
                              'value': json_clone(value)})
    for index, x in enumerate(candidate['material_unknowns']):
        items.append({'origin': 'candidate.material_unknowns', 'index': index,
                      'scope_id': x.get('scope_id'), 'value': json_clone(x)})
    for index, x in enumerate(candidate['decisions_pending']):
        items.append({'origin': 'candidate.decisions_pending', 'index': index,
                      'scope_id': x.get('scope_id'), 'value': json_clone(x)})
    for front in stages['A7']['material_fronts']:
        if front['closure'] == 'BLOCKED':
            items.append({'origin': 'A7.material_fronts', 'scope_id': json_clone(front['scope_refs']),
                          'value': json_clone(front)})
    return items


def decisions_for_scope(a5, sid):
    decisions = list_field(a5, 'decisions', 'A9_STAGE_FIELD_MISSING:A5.decisions')
    return [d for d in decisions if sid in d.get('scope_refs', [])]


def derive_scope_readiness(candidate, a5, a6, a7, unresolved):
    proposals = list_field(candidate, 'scope_proposals', 'A9_CANDIDATE_INVALID')
    scope_index = {}
    for p in proposals:
        sid = nonempty_str(p.get('scope_id'), 'A9_SCOPE_ID_INVALID')
        if sid in scope_index:
            raise A9AssemblyError('A9_SCOPE_DUPLICATE')
        scope_index[sid] = p
    if not scope_index:
        raise A9AssemblyError('A9_SCOPE_EMPTY')
    # Scope metadata must come from A6, not fabricated from the proposal.
    definitions = list_field(a6, 'scope_definitions', 'A9_STAGE_FIELD_MISSING:A6.scope_definitions')
    definitions = {nonempty_str(s.get('scope_id'), 'A9_SCOPE_ID_INVALID'): s for s in definitions}
    if set(definitions) != set(scope_index):
        raise A9AssemblyError('A9_SCOPE_DEFINITION_PARITY')
    fronts = list_field(a7, 'material_fronts', 'A9_STAGE_FIELD_MISSING:A7.material_fronts')
    by_id = {f['front_id']: f for f in fronts}
    if len(by_id) != len(fronts):
        raise A9AssemblyError('A9_FRONT_DUPLICATE')
    result = []
    for sid in sorted(scope_index):
        definition = definitions[sid]
        refs = refs_from(definition, 'material_front_refs', f'A9_SCOPE_FIELD_MISSING:{sid}.material_front_refs')
        dependencies = refs_from(definition, 'depends_on_scope_ids', f'A9_SCOPE_FIELD_MISSING:{sid}.depends_on_scope_ids')
        authorities = refs_from(definition, 'authority_refs', f'A9_SCOPE_FIELD_MISSING:{sid}.authority_refs')
        blockers = refs_from(definition, 'blockers', f'A9_SCOPE_FIELD_MISSING:{sid}.blockers')
        kind = nonempty_str(definition.get('scope_kind'), f'A9_SCOPE_FIELD_MISSING:{sid}.scope_kind')
        if not refs or any(ref not in by_id or sid not in by_id[ref]['scope_refs'] for ref in refs):
            raise A9AssemblyError(f'A9_SCOPE_FRONT_INVALID:{sid}')
        if any(d not in scope_index or d == sid for d in dependencies):
            raise A9AssemblyError(f'A9_SCOPE_DEPENDENCY_INVALID:{sid}')
        decisions = decisions_for_scope(a5, sid)
        bad = [d for d in decisions if d.get('status') != 'STABLE']
        blocked_fronts = [by_id[r] for r in refs if by_id[r]['closure'] == 'BLOCKED' and by_id[r]['status'] != 'NOT_APPLICABLE']
        # Fail closed: an unresolved item without scope (e.g. an A8 decision-changing
        # question or an A7 unmapped material signal) affects every scope.
        blocking_items = [u for u in unresolved if u.get('scope_id') is None or u.get('scope_id') == sid or (isinstance(u.get('scope_id'), list) and sid in u['scope_id'])]
        status = 'READY'
        reason = 'All material fronts closed, decisions stable, no unresolved material items'
        if bad:
            status = 'REQUIRES_DECISION' if any(d.get('status') == 'REQUIRES_DECISION' for d in bad) else 'BLOCKED' if any(d.get('status') == 'BLOCKED' for d in bad) else 'NEED_MORE_EVIDENCE'
            reason = 'Material A5 decisions unresolved'
        elif blocked_fronts or blockers:
            status = 'BLOCKED'
            reason = 'Material front blocked or authoritative scope blocker'
        elif blocking_items:
            status = 'NEED_MORE_EVIDENCE'
            reason = 'Unresolved material items'
        elif all(by_id[r]['status'] == 'NOT_APPLICABLE' for r in refs):
            status = 'NOT_APPLICABLE'
            reason = 'All linked material fronts explicitly not applicable'
        result.append({'scope_id': sid, 'scope_kind': kind, 'status': status,
                       'depends_on_scope_ids': sorted(set(dependencies)),
                       'material_front_refs': sorted(set(refs)), 'authority_refs': json_clone(authorities),
                       'blockers': sorted(set(blockers + [b for f in blocked_fronts for b in f['blockers']])),
                       'reason': reason})
    # Fixpoint: dependencies cannot promote or retain READY when their prerequisites are not READY.
    by_scope = {s['scope_id']: s for s in result}
    changed = True
    while changed:
        changed = False
        for item in result:
            if item['status'] == 'READY' and any(by_scope[d]['status'] != 'READY' for d in item['depends_on_scope_ids']):
                item['status'] = 'BLOCKED'
                item['reason'] = 'Dependent scope is not READY'
                changed = True
    return result


def package_state(scopes, a8, a7, authority_inputs):
    statuses = [s['status'] for s in scopes]
    ready = sum(s == 'READY' for s in statuses)
    open_a8 = a8.get('unresolved_decision_changing_questions') or a8.get('additional_available_evidence_capable_of_changing_material_decision')
    if a8.get('decision') != 'STOP' or a8.get('decision_stable') is not True or a8.get('all_material_fronts_accounted') is not True or a7.get('all_material_fronts_accounted') is not True or open_a8:
        return 'NEED_MORE_EVIDENCE'
    if ready == len(statuses):
        return 'READY'
    if ready:
        # No silent assumption that partially ready scopes can be independently executed.
        if authority_inputs.get('independent_execution_boundary_verified') is True and authority_inputs.get('transversal_blockers_affect_ready') is False:
            return 'PARTIAL_READY'
        return 'BLOCKED'
    if 'BLOCKED' in statuses:
        return 'BLOCKED'
    if 'REQUIRES_DECISION' in statuses:
        return 'REQUIRES_DECISION'
    return 'NEED_MORE_EVIDENCE'


def assemble_a9_snapshot(candidate, artifacts, authority_inputs, *, entry_contract_digest):
    if entry_contract_digest != DIGEST:
        raise A9AssemblyError('A9_ENTRY_CONTRACT_DIGEST_MISMATCH')
    if not isinstance(candidate, dict) or candidate.get('schema_version') != 'ANALYSIS_IMPLEMENTATION_PACKAGE_V1' or candidate.get('candidate_only') is not True or any(k not in candidate for k in CANDIDATE_FIELDS):
        raise A9AssemblyError('A9_CANDIDATE_INVALID')
    walk_no_strategy(candidate)
    stages = typed_artifacts(artifacts)
    walk_no_strategy(stages)
    if not isinstance(authority_inputs, dict):
        raise A9AssemblyError('A9_AUTHORITY_INPUT_MISSING:authority_inputs')
    for k in ('target_identity', 'product_rules', 'currentness_receipts', 'applicable_invariants', 'preserve', 'source_refs'):
        require(authority_inputs, k, f'A9_AUTHORITY_INPUT_MISSING:{k}')
    walk_no_strategy(authority_inputs)
    identity = authority_inputs['target_identity']
    repo = nonempty_str(require(identity, 'repo_full_name', 'A9_AUTHORITY_INPUT_MISSING:repo_full_name'), 'A9_AUTHORITY_INPUT_MISSING:repo_full_name')
    head = require(identity, 'base_head_sha', 'A9_AUTHORITY_INPUT_MISSING:base_head_sha')
    if not isinstance(head, str) or not SHA40.fullmatch(head):
        raise A9AssemblyError('A9_AUTHORITY_INPUT_INVALID:base_head_sha')
    for k in ('product_rules', 'currentness_receipts', 'applicable_invariants', 'preserve', 'source_refs'):
        if not isinstance(authority_inputs[k], list):
            raise A9AssemblyError(f'A9_AUTHORITY_INPUT_INVALID:{k}')
    for stage, field in (('A3', 'target_resolution'), ('A3', 'authority_binding_refs'), ('A6', 'canonical_implementation_bindings'), ('A5', 'decisions'), ('A7', 'material_fronts')):
        require(stages[stage], field, f'A9_STAGE_FIELD_MISSING:{stage}.{field}')
    a3, a4, a5, a6, a7, a8 = [stages[s] for s in VERSIONS]
    bindings = list_field(a6, 'canonical_implementation_bindings', 'A9_STAGE_FIELD_MISSING:A6.canonical_implementation_bindings')
    # Source reconciliation cannot turn model claims into authority.
    binding_refs = refs_from(a3, 'authority_binding_refs', 'A9_STAGE_FIELD_MISSING:A3.authority_binding_refs')
    for b in bindings:
        if b.get('canonical_ref') not in binding_refs:
            raise A9AssemblyError('A9_AUTHORITY_BINDING_NOT_ANCHORED')
        for field in ('binding_id', 'canonical_ref', 'currentness_ref'):
            nonempty_str(b.get(field), f'A9_AUTHORITY_BINDING_FIELD_MISSING:{field}')
    invariants = json_clone(authority_inputs['applicable_invariants'])
    # [] is valid only when it was supplied explicitly by the authoritative caller.
    source_refs = collect_refs(stages, authority_inputs['source_refs'])
    currentness = sorted(set(authority_inputs['currentness_receipts'] + [r for s in VERSIONS for r in stages[s].get('currentness_refs', [])]))
    rules = json_clone(authority_inputs['product_rules'])
    rule_refs = sorted([(r['code'], r['status'], r['canonical_ref']) for r in rules])
    invariant_refs = sorted([(r['code'], r['canonical_ref']) for r in invariants])
    authority_hash = fingerprint({'bindings': sorted([(b['binding_id'], b['canonical_ref'], b['currentness_ref']) for b in bindings]), 'rules': rule_refs, 'invariants': invariant_refs})
    source_hash = fingerprint({'repo_full_name': repo, 'base_head_sha': head, 'source_refs': source_refs})
    target = json_clone(a3['target_resolution'])
    if not isinstance(target, dict):
        raise A9AssemblyError('A9_STAGE_FIELD_INVALID:A3.target_resolution')
    target.update(repo_full_name=repo, base_head_sha=head, source_snapshot_sha256=source_hash)
    unresolved = unresolved_items(candidate, stages)
    scopes = derive_scope_readiness(candidate, a5, a6, a7, unresolved)
    snapshot = {
        'schema_version': 'PROGRAMMING_CONTEXT_SNAPSHOT_V1',
        'objective': require(candidate['request_context'], 'intent', 'A9_CANDIDATE_INVALID'),
        'target': target,
        'target_granularity': require(candidate['classification'], 'target_granularity', 'A9_CANDIDATE_INVALID'),
        'authority_state': require(a3, 'authority_state', 'A9_STAGE_FIELD_MISSING:A3.authority_state'),
        'implementation_state': require(a3, 'implementation_state', 'A9_STAGE_FIELD_MISSING:A3.implementation_state'),
        'requirements': json_clone(list_field(a6, 'requirements', 'A9_STAGE_FIELD_MISSING:A6.requirements')),
        'authority_bindings': json_clone(bindings),
        'applicable_rules': rules,
        'applicable_invariants': invariants,
        'preserve': json_clone(authority_inputs['preserve']),
        'material_front_coverage': json_clone(a7),
        'implementability_schema': json_clone(a6),
        'decision_context': json_clone(a5),
        'analysis_stop_rule': json_clone(a8),
        'scope_readiness': scopes,
        'package_readiness': package_state(scopes, a8, a7, authority_inputs),
        'unresolved_material_items': unresolved,
        'source_refs': source_refs,
        'currentness_refs': currentness,
        'snapshot_schema_digest_sha256': entry_contract_digest,
        'authority_fingerprint_sha256': authority_hash,
        'source_snapshot_sha256': source_hash,
    }
    try:
        snapshot['scope_front_matrix'] = assemble_scope_front_matrix_v1(snapshot)
        walk_no_strategy(snapshot)
        validate_programming_snapshot_payload_v1(snapshot)
    except ContractError as exc:
        # Same code as the existing validator, under the assembler's error type.
        raise A9AssemblyError(str(exc)) from exc
    provenance = {k: 'A3/A4/A5/A6/A7/A8 and canonical authority inputs' for k in SNAPSHOT_FIELDS}
    provenance.update(objective='candidate.request_context.intent', target='A3.target_resolution + authority_inputs.target_identity',
                      target_granularity='candidate.classification.target_granularity',
                      scope_readiness='A6.scope_definitions + A5 + A7 + unresolved provenance',
                      scope_front_matrix='assemble_scope_front_matrix_v1',
                      authority_bindings='A6.canonical_implementation_bindings anchored to A3',
                      applicable_rules='authority_inputs.product_rules',
                      applicable_invariants='authority_inputs.applicable_invariants',
                      preserve='authority_inputs.preserve',
                      snapshot_schema_digest_sha256='caller-supplied verified contract digest')
    report = {'schema_version': 'A9_ASSEMBLY_REPORT_V1', 'field_sources': provenance,
              'candidate_fields_used': ['request_context.intent', 'classification.target_granularity', 'scope_proposals.scope_id', 'material_unknowns', 'decisions_pending'],
              'candidate_fields_not_authoritative': ['classification.authority_state', 'classification.implementation_state', 'requirements', 'material_fronts', 'scope_proposals.readiness_candidate', 'package_readiness_candidate', 'research_stop'],
              'warnings': ['A9_FINGERPRINT_RULE_V1 is PROPOSED, not approved', 'Pure assembly does not persist or approve snapshot']}
    return snapshot, report


def build_asof_record_input(snapshot, *, decision_ref, consumer_code, subject_ref,
                            subject_version, actor_authority, governing, decided_at,
                            effective_at, authority_refs):
    if not isinstance(snapshot, dict) or snapshot.get('schema_version') != 'PROGRAMMING_CONTEXT_SNAPSHOT_V1':
        raise A9AssemblyError('A9_ASOF_INPUT_INVALID:snapshot')
    validate_programming_snapshot_payload_v1(snapshot)
    for name, val in (('decision_ref', decision_ref), ('consumer_code', consumer_code),
                      ('subject_ref', subject_ref), ('subject_version', subject_version),
                      ('decided_at', decided_at), ('effective_at', effective_at)):
        nonempty_str(val, f'A9_ASOF_INPUT_INVALID:{name}')
    from datetime import datetime
    for name, value in (('decided_at', decided_at), ('effective_at', effective_at)):
        try:
            parsed = datetime.fromisoformat(value.replace('Z', '+00:00'))
            if parsed.tzinfo is None:
                raise ValueError('timezone needed')
        except (ValueError, TypeError):
            raise A9AssemblyError(f'A9_ASOF_INPUT_INVALID:{name}') from None
    for name, obj, fields, prohibited in (
        ('actor_authority', actor_authority, ('actor_ref', 'authority_ref', 'authority_version', 'authority_sha256'), ('payload','content','snapshot','document','body')),
        ('governing', governing, ('policy_ref','policy_version','policy_sha256','terms_ref','terms_version','terms_sha256'), ('policy_payload','terms_payload','payload','content','snapshot','document','body'))):
        if not isinstance(obj, dict) or set(obj).intersection(prohibited):
            raise A9AssemblyError(f'A9_ASOF_INPUT_INVALID:{name}')
        for field in fields:
            nonempty_str(obj.get(field), f'A9_ASOF_INPUT_INVALID:{name}.{field}')
        for field in ('authority_sha256',) if name == 'actor_authority' else ('policy_sha256', 'terms_sha256'):
            if not SHA64.fullmatch(obj[field]):
                raise A9AssemblyError(f'A9_ASOF_INPUT_INVALID:{name}.{field}')
    if not isinstance(authority_refs, list) or len(authority_refs) < 3:
        raise A9AssemblyError('A9_ASOF_INPUT_INVALID:authority_refs')
    expected = {'CURRENTNESS_AUTHORITY', 'CAPABILITY_VERSION_COMPATIBILITY', 'TYPED_EVIDENCE_REGISTRY'}
    actual = [r.get('capability_code') for r in authority_refs if isinstance(r, dict)]
    if any(actual.count(k) != 1 for k in expected):
        raise A9AssemblyError('A9_ASOF_INPUT_INVALID:authority_refs.capabilities')
    for ref in authority_refs:
        if not isinstance(ref, dict):
            raise A9AssemblyError('A9_ASOF_INPUT_INVALID:authority_refs')
        for k in ('capability_code', 'version', 'authority_ref', 'manifest_sha256'):
            nonempty_str(ref.get(k), f'A9_ASOF_INPUT_INVALID:authority_refs.{k}')
        if not SHA64.fullmatch(ref['manifest_sha256']):
            raise A9AssemblyError('A9_ASOF_INPUT_INVALID:authority_refs.manifest_sha256')
    return {'schema_version': 'LF_DECISION_CONTEXT_ASOF_INPUT_V1', 'decision_ref': decision_ref,
            'consumer_code': consumer_code, 'subject': {'ref': subject_ref, 'version': subject_version},
            'actor_authority': json_clone(actor_authority), 'governing': json_clone(governing),
            'times': {'decided_at': decided_at, 'effective_at': effective_at},
            'authority_refs': json_clone(authority_refs),
            'extensions': {'programming_context_snapshot': json_clone(snapshot)}}

"""Skill-only structural gate for the existing LOCK/GUIDED/FREE blueprint.
Returns an art-direction supplement, never a canonical or sent handoff.
Caller supplies discovered evidence; its provenance is not authenticated here.
"""
import hashlib
import json
import re


class ArtBlocked(ValueError):
    pass


def require(ok, code):
    if not ok:
        raise ArtBlocked(code)


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def nonempty(x):
    return isinstance(x, str) and bool(x.strip())


def exact_keys(obj, keys, code):
    require(type(obj) is dict and set(obj) == set(keys.split()), code)


def preflight(plan):
    """Validate authored proposal against explicit evidence and blueprint hierarchy."""
    exact_keys(plan, 'business_code literal_request blueprint presentation direction components sources requirements', 'PLAN_FIELDS')
    business = plan['business_code']
    literal = plan['literal_request']
    require(nonempty(business) and nonempty(literal), 'PLAN_SCOPE')
    bp = plan['blueprint']
    require(type(bp) is dict and bp.get('schema_version') == 'CREATIVE_VISUAL_BLUEPRINT_V1'
            and bp.get('mode') == 'PLAN_ONLY' and bp.get('brand') == business, 'BLUEPRINT_SCOPE')
    lock = bp.get('design_lock', {})
    exact_keys(lock, 'LOCK GUIDED FREE', 'BLUEPRINT_LOCK')
    require(type(lock['LOCK']) is dict and type(lock['GUIDED']) is list and type(lock['FREE']) is list,
            'BLUEPRINT_LOCK')
    require(all(bp.get(k) == v for k, v in lock['LOCK'].items()) and bp.get('guided') == lock['GUIDED']
            and bp.get('free') == lock['FREE'], 'BLUEPRINT_LOCK_DRIFT')
    hierarchy = lock['LOCK'].get('hierarchy')
    require(type(hierarchy) is list and hierarchy and all(nonempty(h) for h in hierarchy)
            and len(hierarchy) == len(set(hierarchy)), 'HIERARCHY_INVALID')
    for k in ('intent', 'art'):
        require(nonempty(bp.get(k)), 'BLUEPRINT_MISSING_' + k.upper())
    presentation = plan['presentation']
    exact_keys(presentation, 'mode destination', 'PRESENTATION_FIELDS')
    require(presentation['mode'] in ('FULL_SCENE', 'BODY_ONLY', 'OTHER_ASSET') and nonempty(presentation['destination']),
            'PRESENTATION_INVALID')
    # Source adapter owns discovery; this layer only verifies supplied snapshots, not authority.
    evidence = {'REQUEST': literal}
    sources = {}
    require(type(plan['sources']) is list, 'SOURCE_LIST')
    for s in plan['sources']:
        exact_keys(s, 'id business_code ref version status text sha256', 'SOURCE_FIELDS')
        require(all(nonempty(s[k]) for k in ('id','ref','version','text')) and s['id'] not in evidence,
                'SOURCE_ID')
        require(s['business_code'] == business, 'SOURCE_CROSS_BUSINESS')
        require(s['status'] in ('APPROVED', 'CANDIDATE'), 'SOURCE_STATUS')
        require(sha(s['text'].encode('utf-8')) == s['sha256'], 'SOURCE_BYTES_DRIFT')
        evidence[s['id']] = s['text']
        sources[s['id']] = s
    requirements = {}
    require(type(plan['requirements']) is list and plan['requirements'], 'REQUIREMENTS_MISSING')
    for r in plan['requirements']:
        exact_keys(r, 'id source quote', 'REQUIREMENT_FIELDS')
        require(nonempty(r['id']) and r['id'] not in requirements and type(r['source']) is str
                and r['source'] in evidence and nonempty(r['quote'])
                and r['quote'] in evidence[r['source']], 'REQUIREMENT_UNGROUNDED')
        requirements[r['id']] = r
    require(any(r['source'] == 'REQUEST' for r in requirements.values()), 'REQUEST_COVERAGE_MISSING')
    covered = set()
    def cover(ids):
        require(type(ids) is list and ids and all(type(k) is str and k in requirements for k in ids),
                'REQUIREMENT_LINK_INVALID')
        covered.update(ids)
    direction = plan['direction']
    exact_keys(direction, 'scene style background typography hierarchy visual_impact', 'ART_DIRECTION_INCOMPLETE')
    art = ['Presentación: ' + presentation['destination'], bp['art']]
    for k, d in direction.items():
        exact_keys(d, 'instruction rationale requirements', 'DIRECTION_FIELDS')
        require(nonempty(d['instruction']) and nonempty(d['rationale']), 'DIRECTION_EMPTY')
        cover(d['requirements'])
        art.append(k + ': ' + d['instruction'])
    require(type(plan['components']) is list and all(type(c) is dict for c in plan['components']), 'COMPONENT_LIST')
    require([c.get('name') for c in plan['components']] == hierarchy, 'COMPONENT_COVERAGE_DRIFT')
    for c in plan['components']:
        exact_keys(c, 'name owner freedom instruction copy source_ids requirements', 'COMPONENT_FIELDS')
        require(c['owner'] in ('NATIVE', 'COMPOSITOR', 'REFERENCE_ONLY'), 'COMPONENT_OWNER')
        require(c['freedom'] in ('LOCK','GUIDED','FREE') and nonempty(c['instruction']), 'COMPONENT_DIRECTION_MISSING')
        require(type(c['source_ids']) is list and c['source_ids']
                and all(type(k) is str and k in evidence for k in c['source_ids']), 'COMPONENT_SOURCE_MISSING')
        require(type(c['copy']) is list and all(nonempty(t) and any(t in evidence[k] for k in c['source_ids'])
                for t in c['copy']), 'COPY_UNGROUNDED')
        if c['copy']:
            require(c['freedom'] == 'LOCK', 'COPY_NOT_LOCKED')
        if c['owner'] == 'COMPOSITOR':
            require(c['freedom'] == 'LOCK' and any(k in sources for k in c['source_ids']), 'FIXED_COMPONENT_UNPINNED')
        cover(c['requirements'])
        # Fixed components supply scene context to the planner, not new Native-owned pixels.
        art.append(c['name'] + ' | ' + c['owner'] + ' | ' + c['freedom'] + ': ' + c['instruction'])
        if c['copy']:
            art.append('Textos exactos: ' + json.dumps(c['copy'], ensure_ascii=False))
    require(covered == set(requirements), 'REQUIREMENT_COVERAGE_GAP')
    return {'status': 'STRUCTURAL_PASS_SEMANTIC_PENDING', 'business_code': business,
            'literal_request_sha256': sha(literal.encode('utf-8')),
            'proposal_sha256': sha(json.dumps(plan, ensure_ascii=False, sort_keys=True, separators=(',', ':'), allow_nan=False).encode('utf-8')),
            'art_direction_supplement': '\n'.join(art), 'requirement_count': len(requirements),
            'component_count': len(hierarchy), 'source_authenticity': 'NOT_ATTESTED_BY_LOCAL_GATE',
            'semantic_qa': 'NOT_EVALUATED', 'native_payload': None, 'native_transmitted': False,
            'image_generation_allowed': False, 'production_approved': False}

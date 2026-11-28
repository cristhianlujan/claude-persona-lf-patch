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


# --- F4: deterministic prompt-quality checks (diagnostic, no new contract fields) ---
# Python only blocks explicit, verifiable defects; ambiguity and intent stay with
# the independent semantic review. Findings are plain tuples (level, code, evidence).
_GENERIC_WORDS = {
    'premium', 'moderno', 'moderna', 'elegante', 'wow', 'bonito', 'bonita', 'creativo',
    'creativa', 'limpio', 'limpia', 'profesional', 'atractivo', 'atractiva', 'mas', 'más',
    'muy', 'y', 'e', 'o', 'un', 'una', 'el', 'la', 'de', 'con', 'estilo', 'diseño',
    'aspecto', 'look', 'sensacion', 'sensación', 'agradable', 'bien', 'mejor',
}
_CLAUSE = re.compile(r'[;.\n]')
_NEG = re.compile(r'\b(?:no|nunca|sin|evita|evitar|prohibido|prohibir)\b', re.I)
_DRAW = re.compile(r'\b(?:dibuj\w*|inventa\w*|cre[ae]\w*|genera\w*|dise[ñn]a\w*|inclu[iy]\w*|'
                   r'agrega\w*|a[ñn]ade\w*|coloca\w*|usa\w*|muestra\w*)\b', re.I)
_LOGO = re.compile(r'\blogo(?:tipos?|s)?\b', re.I)
_TEXT_ONLY = re.compile(r'\b(?:como\s+texto|solo\s+texto|en\s+texto|texto\s+plano)\b', re.I)
_DIMS = re.compile(r'(\d{2,5})\s*(?:x|×|por)\s*(\d{2,5})', re.I)
_ATTRS = ('sólido', 'solido', 'completo', 'completa', 'exacto', 'exactos', 'exacta', 'exactas')


def _words(text):
    return re.findall(r"[a-záéíóúüñ]+", text.casefold())


def inspect_instruction_conflicts(texts):
    """PF-01: one text demands drawing logos while another forbids third-party logos."""
    demands, forbids = [], []
    for t in texts:
        for clause in _CLAUSE.split(t):
            if not _LOGO.search(clause):
                continue
            if _NEG.search(clause):
                forbids.append(clause.strip())
            elif _DRAW.search(clause) and not _TEXT_ONLY.search(clause):
                demands.append(clause.strip())
    if demands and forbids:
        return [('BLOCK', 'INSTRUCTION_CONFLICT_LOGO', {'demands': demands[0], 'forbids': forbids[0]})]
    return []


def inspect_component_specificity(components):
    """PF-07: an instruction made only of generic words is not materializable."""
    out = []
    for c in components:
        words = _words(c['instruction'])
        if not words or all(w in _GENERIC_WORDS for w in words):
            out.append(('BLOCK', 'INSTRUCTION_ONLY_GENERIC', {'component': c['name'], 'instruction': c['instruction']}))
    return out


def inspect_dimension_requirements(literal, prompt):
    """PF-05/PF-06: requested WxH must reach the handoff unchanged; actual size is only measurable on bytes."""
    wanted = {(int(a), int(b)) for a, b in _DIMS.findall(literal)}
    if not wanted:
        return []
    found = {(int(a), int(b)) for a, b in _DIMS.findall(prompt)}
    out = []
    if not wanted <= found:
        code = 'DIMENSIONS_ALTERED' if found else 'DIMENSIONS_OMITTED'
        out.append(('BLOCK', code, {'requested': sorted(wanted), 'handoff': sorted(found)}))
    out.append(('WARNING', 'DIMENSIONS_NOT_VERIFIABLE_BEFORE_RENDER', {'requested': sorted(wanted)}))
    return out


def verify_compiled_coverage(requirements, prompt):
    """PF-03/PF-04: explicit attributes in a requirement quote must survive into the prompt."""
    low = prompt.casefold()
    out = []
    for r in requirements:
        for a in _ATTRS:
            if a in r['quote'].casefold() and a not in low:
                out.append(('BLOCK', 'REQUIREMENT_ATTRIBUTE_DROPPED', {'requirement': r['id'], 'attribute': a}))
    return out


def verify_prompt_integrity(prompt, expected_sha256):
    """PF-10: the text about to be sealed must match the reviewed hash."""
    ok = sha(prompt.encode('utf-8')) == expected_sha256
    return [] if ok else [('BLOCK', 'PROMPT_HASH_MISMATCH', {})]


def blocking(findings):
    return [f for f in findings if f[0] == 'BLOCK']


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
    # F4: explicit, verifiable defects only; semantic review stays independent.
    for finding in blocking(inspect_component_specificity(plan['components'])
                            + inspect_instruction_conflicts(art)):
        raise ArtBlocked(finding[1])
    return {'status': 'STRUCTURAL_PASS_SEMANTIC_PENDING', 'business_code': business,
            'literal_request_sha256': sha(literal.encode('utf-8')),
            'proposal_sha256': sha(json.dumps(plan, ensure_ascii=False, sort_keys=True, separators=(',', ':'), allow_nan=False).encode('utf-8')),
            'art_direction_supplement': '\n'.join(art), 'requirement_count': len(requirements),
            'component_count': len(hierarchy), 'source_authenticity': 'NOT_ATTESTED_BY_LOCAL_GATE',
            'semantic_qa': 'NOT_EVALUATED', 'native_payload': None, 'native_transmitted': False,
            'image_generation_allowed': False, 'production_approved': False}

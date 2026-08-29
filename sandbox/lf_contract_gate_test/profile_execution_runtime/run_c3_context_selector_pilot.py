#!/usr/bin/env python3
from __future__ import annotations
import json, re, time
from pathlib import Path
from github_actions_local_runtime import GitHubHostedLlamaCppAdapter, GitHubHostedLlamaCppVerifier
from profile_runtime_runner import execute_profile_runtime

ROOT = Path(__file__).resolve().parents[3]
SKILL = ROOT / 'profiles/ui_architect/SKILL.md'
RUNTIME_SCHEMA = ROOT / 'profiles/ui_architect/schemas/runtime_output.schema.json'
INPUT = '''Define una nueva pantalla de oferta de deuda.

Datos autorizados:
- Deuda original: S/ 8,000
- Oferta: S/ 3,200
- Ahorro: S/ 4,800
- Formas de pago: contado o cuotas
- Debe existir un CTA principal.

Modo operativo: PILOT.
Especialidades activas: financial UX y trust clarity.

Conserva todos los requisitos suministrados.
No inventes información financiera, legal o de elegibilidad no proporcionada.'''

OUTPUT_GUARD = '''
RUNTIME OUTPUT GUARD — deterministic materialization
Return one compact JSON object only; no Markdown fences or prose.
Root keys exactly: worker, output_type, deliverable_created, score, handoff_to_next, self_verdict.
deliverable_created sibling keys exactly: screen_definition, component_tree, layout_grid, visual_hierarchy, state_map, token_map, spacing_typography, density_rules, risk_controls, prompt_constraints.
component_tree is a flat array. content is terminal text; relationships use IDs only.
visual_hierarchy is a flat array of {parent_id:string, child_ids:[string,...]}; child_ids NEVER contains objects.
Keep every section minimal and bounded. Do not repeat the same financial facts across sections unless required for meaning.
self_verdict must be a string. Preserve every supplied case requirement exactly; do not invent financial truth.
'''.strip()

# C3-only generation boundary. Deliberately narrower than the canonical production
# schema that previously produced empty output: it constrains the proven recursion
# vector and root shape without changing the canonical profile or domain authority.
C3_RUNTIME_SCHEMA = {
    'type': 'object',
    'required': ['worker','output_type','deliverable_created','score','handoff_to_next','self_verdict'],
    'additionalProperties': False,
    'properties': {
        'worker': {'type':'string'},
        'output_type': {'type':'string'},
        'deliverable_created': {
            'type':'object',
            'required': ['screen_definition','component_tree','layout_grid','visual_hierarchy','state_map','token_map','spacing_typography','density_rules','risk_controls','prompt_constraints'],
            'additionalProperties': False,
            'properties': {
                'screen_definition': {'type':'object','maxProperties':12},
                'component_tree': {
                    'type':'array','maxItems':20,
                    'items': {
                        'type':'object',
                        'required':['zone_id','component_id','component_type','role','content','visual_priority','color_tokens','typography','spacing','state','allowed_variants','blocked_variants'],
                        'additionalProperties': False,
                        'properties': {
                            'zone_id': {'type':'string'},
                            'component_id': {'type':'string'},
                            'component_type': {'type':'string'},
                            'role': {'type':'string'},
                            'content': {'type':'string'},
                            'visual_priority': {'type':['integer','number','string']},
                            'color_tokens': {'type':'array','maxItems':8,'items':{'type':'string'}},
                            'typography': {'type':'object','maxProperties':8},
                            'spacing': {'type':'object','maxProperties':8},
                            'state': {'type':'string'},
                            'allowed_variants': {'type':'array','maxItems':8,'items':{'type':'string'}},
                            'blocked_variants': {'type':'array','maxItems':8,'items':{'type':'string'}},
                        },
                    },
                },
                'layout_grid': {'type':'object','maxProperties':12},
                'visual_hierarchy': {
                    'type':'array','maxItems':20,
                    'items': {
                        'type':'object',
                        'required':['parent_id','child_ids'],
                        'additionalProperties': False,
                        'properties': {
                            'parent_id': {'type':'string'},
                            'child_ids': {'type':'array','maxItems':20,'items':{'type':'string'}},
                        },
                    },
                },
                'state_map': {'type':'object','maxProperties':30},
                'token_map': {'type':'object','maxProperties':30},
                'spacing_typography': {'type':'object','maxProperties':30},
                'density_rules': {'type':'array','maxItems':20,'items':{'type':'string'}},
                'risk_controls': {'type':'array','maxItems':20,'items':{'type':'string'}},
                'prompt_constraints': {'type':'array','maxItems':20,'items':{'type':'string'}},
            },
        },
        'score': {'type':'object','maxProperties':12},
        'handoff_to_next': {'type':'object','maxProperties':12},
        'self_verdict': {'type':'string'},
    },
}

REQUIRED_ROOT = {'worker','output_type','deliverable_created','score','handoff_to_next','self_verdict'}
REQUIRED_DELIVERABLE = {'screen_definition','component_tree','layout_grid','visual_hierarchy','state_map','token_map','spacing_typography','density_rules','risk_controls','prompt_constraints'}
PLACEHOLDER_VALUES = {'needs_input','need_input','tbd','todo','placeholder','unknown_required'}
ALLOWED_CURRENCY_AMOUNTS = {'8000','3200','4800'}


def sections(md: str) -> list[tuple[str, str]]:
    hits = list(re.finditer(r'(?m)^(#{2,3})\s+(.+?)\s*$', md))
    out=[]
    pre=md[:hits[0].start()].strip() if hits else md.strip()
    if pre: out.append(('__PREAMBLE__', pre))
    for i,h in enumerate(hits):
        end=hits[i+1].start() if i+1 < len(hits) else len(md)
        out.append((h.group(2).strip(), md[h.start():end].strip()))
    return out


def select_c3(md: str) -> str:
    keep_exact = {
        '__PREAMBLE__','Purpose','Routing semantics','RUNTIME CRITICAL GATE — EXECUTE FIRST',
        'TASK CLASSIFICATION — HARD BINARY DISCRIMINATOR','BOUNDED SERIALIZATION — HARD STRUCTURAL GATE',
        'New-screen invariants','Production UI Spec contract','Scoring'
    }
    parts=[]
    for title,body in sections(md):
        if title in keep_exact or title.startswith('CREATE_NEW'):
            parts.append(body)
    selected='\n\n'.join(parts).strip()+"\n"
    forbidden=['RESOLVED EXISTING DUPLICATE','UNRESOLVED AUTHORITY SHORT-CIRCUIT','Existing-screen invariants','top_amount_strip','payment_summary']
    for term in forbidden:
        if term in selected:
            raise SystemExit('C3_SELECTOR_LEAK:'+term)
    required=['CREATE_NEW','component_tree','Root shape','Supplied requirements are not defects','PRODUCTION_UI_SPEC']
    for term in required:
        if term.casefold() not in selected.casefold():
            raise SystemExit('C3_SELECTOR_MISSING:'+term)
    return selected


def materialize(source: str) -> str:
    return source.rstrip() + '\n\n' + OUTPUT_GUARD + '\n'


def assistant_text(raw: object) -> str:
    text=raw if isinstance(raw,str) else json.dumps(raw,ensure_ascii=False)
    return text.rsplit('Assistant:',1)[-1].strip() if 'Assistant:' in text else text.strip()


def extract_json_text(text: str) -> str:
    stripped=text.strip()
    fenced=re.fullmatch(r'```(?:json)?\s*(.*?)\s*```', stripped, flags=re.I|re.S)
    return fenced.group(1).strip() if fenced else stripped


def canonicalize(text: str) -> tuple[str, bool, str | None]:
    candidate=extract_json_text(text)
    try:
        obj=json.loads(candidate)
    except Exception as exc:
        return candidate, False, f'{type(exc).__name__}:{exc}'
    if not isinstance(obj,dict):
        return candidate, False, 'TypeError:root_not_object'
    deliverable=obj.get('deliverable_created')
    if isinstance(deliverable,dict):
        screen=deliverable.get('screen_definition')
        if isinstance(screen,dict):
            for key in REQUIRED_DELIVERABLE-{'screen_definition'}:
                if key not in deliverable and key in screen:
                    deliverable[key]=screen.pop(key)
        for key in ('score','handoff_to_next','self_verdict'):
            if key not in obj and key in deliverable:
                obj[key]=deliverable.pop(key)
    return json.dumps(obj,ensure_ascii=False,separators=(',',':')), True, None


def max_depth(value: object, depth: int = 0) -> int:
    if isinstance(value,dict):
        return max([depth] + [max_depth(v, depth+1) for v in value.values()])
    if isinstance(value,list):
        return max([depth] + [max_depth(v, depth+1) for v in value])
    return depth


def placeholder_values(value: object) -> list[str]:
    found=[]
    if isinstance(value,dict):
        for v in value.values(): found.extend(placeholder_values(v))
    elif isinstance(value,list):
        for v in value: found.extend(placeholder_values(v))
    elif isinstance(value,str) and value.strip().casefold() in PLACEHOLDER_VALUES:
        found.append(value)
    return found


def inspect(raw: object) -> dict:
    raw_text=assistant_text(raw).strip()
    raw_fence='```' in raw_text
    governed, json_ok, json_error=canonicalize(raw_text)
    obj=json.loads(governed) if json_ok else None
    low=governed.casefold()
    reqs={
        'debt': ('8000' in low or '8,000' in low),
        'offer': ('3200' in low or '3,200' in low),
        'savings': ('4800' in low or '4,800' in low),
        'cash': ('contado' in low or 'cash' in low or 'single' in low or 'one-time' in low),
        'installments': ('cuota' in low or 'installment' in low),
        'cta': ('cta' in low or 'button' in low or 'pagar' in low or 'continuar' in low),
    }
    root_keys=set(obj.keys()) if isinstance(obj,dict) else set()
    deliverable=obj.get('deliverable_created') if isinstance(obj,dict) else None
    screen=deliverable.get('screen_definition') if isinstance(deliverable,dict) else None
    component_tree=deliverable.get('component_tree') if isinstance(deliverable,dict) else None
    hierarchy=deliverable.get('visual_hierarchy') if isinstance(deliverable,dict) else None
    hierarchy_ids_only=bool(isinstance(hierarchy,list) and all(
        isinstance(rel,dict) and isinstance(rel.get('parent_id'),str) and
        isinstance(rel.get('child_ids'),list) and all(isinstance(x,str) for x in rel['child_ids'])
        for rel in hierarchy
    ))
    components_flat=bool(isinstance(component_tree,list) and all(
        isinstance(c,dict) and isinstance(c.get('component_id'),str) and isinstance(c.get('content'),str)
        for c in component_tree
    ))
    prohibited_in_screen=REQUIRED_DELIVERABLE-{'screen_definition'}
    structural_pass=bool(
        isinstance(obj,dict) and root_keys == REQUIRED_ROOT and
        isinstance(deliverable,dict) and set(deliverable.keys()) == REQUIRED_DELIVERABLE and
        isinstance(screen,dict) and not (prohibited_in_screen & set(screen.keys())) and
        isinstance(obj.get('self_verdict'),str) and components_flat and hierarchy_ids_only
    )
    depth=max_depth(obj) if isinstance(obj,dict) else None
    placeholders=placeholder_values(obj) if isinstance(obj,dict) else []
    currency_values=[]
    if json_ok:
        for match in re.findall(r'S/\s*([0-9][0-9.,]*)', governed, flags=re.I):
            currency_values.append(re.sub(r'[^0-9]','',match))
    invented_currency=sorted({v for v in currency_values if v and v not in ALLOWED_CURRENCY_AMOUNTS})
    bounded_pass=bool(json_ok and len(governed) <= 25000 and depth is not None and depth <= 8 and hierarchy_ids_only)
    authority_pass=not invented_currency
    placeholder_pass=not placeholders
    return {
        'output_chars': len(governed), 'output_bytes': len(governed.encode('utf-8')),
        'raw_output_chars': len(raw_text), 'raw_output_bytes': len(raw_text.encode('utf-8')),
        'json_ok': json_ok, 'json_error': json_error,
        'fence': ('```' in governed), 'raw_fence': raw_fence,
        'grid_content_count': governed.count('grid_content'),
        'requirements': reqs, 'requirements_pass': all(reqs.values()),
        'root_keys': sorted(root_keys), 'structural_pass': structural_pass,
        'hierarchy_ids_only': hierarchy_ids_only, 'components_flat': components_flat,
        'max_depth': depth, 'bounded_pass': bounded_pass,
        'placeholder_values': placeholders, 'placeholder_pass': placeholder_pass,
        'invented_currency': invented_currency, 'authority_pass': authority_pass,
        'raw_output': raw_text, 'governed_output': governed,
    }


def run(label: str, source: str, *, constrained: bool = False) -> dict:
    adapter=GitHubHostedLlamaCppAdapter(
        work_dir=ROOT,
        max_output_tokens=2048 if constrained else 4096,
        context_tokens=16384,
    )
    verifier=GitHubHostedLlamaCppVerifier()
    if constrained:
        if RUNTIME_SCHEMA.exists():
            raise SystemExit('C3_RUNTIME_SCHEMA_PREEXISTS')
        RUNTIME_SCHEMA.write_text(json.dumps(C3_RUNTIME_SCHEMA,ensure_ascii=False,separators=(',',':')),encoding='utf-8')
    t=time.monotonic()
    try:
        package=execute_profile_runtime(
            execution_id='C3_PILOT_'+label, profile_code='PERFIL-UI-ARCHITECT', profile_slug='ui_architect',
            profile_sources=[{'ref':'profiles/ui_architect/SKILL.md','content':materialize(source)}],
            input_literal=INPUT, adapter=adapter, attestation_verifier=verifier, allow_test_doubles=False,
            lf_adapter_sources=None,
        )
    finally:
        if constrained:
            RUNTIME_SCHEMA.unlink(missing_ok=True)
    elapsed=round(time.monotonic()-t,3)
    result=inspect(package['raw_output'])
    result.update({
        'variant':label,'runtime_seconds':elapsed,
        'profile_context_chars':len(materialize(source)),
        'profile_context_bytes':len(materialize(source).encode('utf-8')),
        'input_chars':len(INPUT),'input_bytes':len(INPUT.encode('utf-8')),
        'llm_calls':1,'round_trips':1,
        'context_window_tokens':adapter.context_tokens,
        'max_output_tokens':adapter.max_output_tokens,
        'structured_schema':constrained,
    })
    return result


def main() -> int:
    full=SKILL.read_text(encoding='utf-8')
    c3=select_c3(full)
    full_m=materialize(full); c3_m=materialize(c3)
    print('C3_SELECTOR_FULL_CHARS='+str(len(full_m)))
    print('C3_SELECTOR_SELECTED_CHARS='+str(len(c3_m)))
    print('C3_SELECTOR_REDUCTION_PCT='+str(round((1-len(c3_m)/len(full_m))*100,2)))
    a=run('A_FULL', full, constrained=False)
    c=run('C3_SELECTED', c3, constrained=True)
    excluded={'raw_output','governed_output'}
    summary={'A':{k:v for k,v in a.items() if k not in excluded},'C3':{k:v for k,v in c.items() if k not in excluded}}
    summary['comparison']={
        'context_reduction_pct': round((1-c['profile_context_bytes']/a['profile_context_bytes'])*100,2),
        'runtime_change_pct': round((c['runtime_seconds']/a['runtime_seconds']-1)*100,2) if a['runtime_seconds'] else None,
        'output_change_pct': round((c['output_bytes']/a['output_bytes']-1)*100,2) if a['output_bytes'] else None,
        'llm_calls_change': c['llm_calls']-a['llm_calls'],
        'round_trips_change': c['round_trips']-a['round_trips'],
        'quality_c3_not_worse': bool(
            c['json_ok'] and c['structural_pass'] and c['bounded_pass'] and
            not c['fence'] and not c['raw_fence'] and c['requirements_pass'] and
            c['placeholder_pass'] and c['authority_pass'] and
            c['grid_content_count'] <= a['grid_content_count']
        ),
    }
    print('C3_PILOT_SUMMARY='+json.dumps(summary,ensure_ascii=False,sort_keys=True))
    print('C3_RAW_BEGIN')
    print(c['raw_output'])
    print('C3_RAW_END')
    print('C3_GOVERNED_BEGIN')
    print(c['governed_output'])
    print('C3_GOVERNED_END')
    return 0 if summary['comparison']['quality_c3_not_worse'] else 2

if __name__=='__main__':
    raise SystemExit(main())

#!/usr/bin/env python3
from __future__ import annotations
import json, re, shutil, time
from pathlib import Path
from github_actions_local_runtime import GitHubHostedLlamaCppAdapter, GitHubHostedLlamaCppVerifier
from profile_runtime_runner import execute_profile_runtime

ROOT = Path(__file__).resolve().parents[3]
SKILL = ROOT / 'profiles/ui_architect/SKILL.md'
CANONICAL_SCHEMA = ROOT / 'profiles/ui_architect/schemas/ui_production_spec.schema.json'
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
        if title in keep_exact:
            parts.append(body)
        elif title.startswith('CREATE_NEW'):
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


def assistant_text(raw: object) -> str:
    text=raw if isinstance(raw,str) else json.dumps(raw,ensure_ascii=False)
    return text.rsplit('Assistant:',1)[-1].strip() if 'Assistant:' in text else text.strip()


def inspect(raw: object) -> dict:
    text=assistant_text(raw)
    stripped=text.strip()
    fence='```' in stripped
    json_error=None
    try:
        obj=json.loads(stripped)
        json_ok=isinstance(obj,dict)
    except Exception as exc:
        obj=None; json_ok=False; json_error=f'{type(exc).__name__}:{exc}'
    low=stripped.casefold()
    reqs={
        'debt': ('8000' in low or '8,000' in low),
        'offer': ('3200' in low or '3,200' in low),
        'savings': ('4800' in low or '4,800' in low),
        'cash': ('contado' in low or 'cash' in low or 'single' in low or 'one-time' in low),
        'installments': ('cuota' in low or 'installment' in low),
        'cta': ('cta' in low or 'button' in low or 'pagar' in low or 'continuar' in low),
    }
    required_root={'worker','output_type','deliverable_created','score','handoff_to_next','self_verdict'}
    root_keys=set(obj.keys()) if isinstance(obj,dict) else set()
    deliverable=obj.get('deliverable_created') if isinstance(obj,dict) else None
    screen=deliverable.get('screen_definition') if isinstance(deliverable,dict) else None
    prohibited_in_screen={'component_tree','layout_grid','visual_hierarchy','state_map','token_map','spacing_typography','density_rules','risk_controls','prompt_constraints','remediation_actions'}
    structural_pass=bool(
        isinstance(obj,dict) and required_root.issubset(root_keys) and
        isinstance(deliverable,dict) and isinstance(screen,dict) and
        not (prohibited_in_screen & set(screen.keys()))
    )
    return {
        'output_chars': len(stripped), 'json_ok': json_ok, 'json_error': json_error, 'fence': fence,
        'grid_content_count': stripped.count('grid_content'),
        'requirements': reqs, 'requirements_pass': all(reqs.values()),
        'root_keys': sorted(root_keys), 'structural_pass': structural_pass,
        'raw_output': stripped,
    }


def run(label: str, source: str) -> dict:
    adapter=GitHubHostedLlamaCppAdapter(work_dir=ROOT, max_output_tokens=2048, context_tokens=16384)
    verifier=GitHubHostedLlamaCppVerifier()
    t=time.monotonic()
    package=execute_profile_runtime(
        execution_id='C3_PILOT_'+label, profile_code='PERFIL-UI-ARCHITECT', profile_slug='ui_architect',
        profile_sources=[{'ref':'profiles/ui_architect/SKILL.md','content':source}],
        input_literal=INPUT, adapter=adapter, attestation_verifier=verifier, allow_test_doubles=False,
        lf_adapter_sources=None,
    )
    elapsed=round(time.monotonic()-t,3)
    result=inspect(package['raw_output'])
    result.update({'variant':label,'runtime_seconds':elapsed,'profile_context_chars':len(source),'input_chars':len(INPUT)})
    return result


def main() -> int:
    full=SKILL.read_text(encoding='utf-8')
    c3=select_c3(full)
    print('C3_SELECTOR_FULL_CHARS='+str(len(full)))
    print('C3_SELECTOR_SELECTED_CHARS='+str(len(c3)))
    print('C3_SELECTOR_REDUCTION_PCT='+str(round((1-len(c3)/len(full))*100,2)))
    shutil.copyfile(CANONICAL_SCHEMA, RUNTIME_SCHEMA)
    try:
        a=run('A_FULL', full)
        c=run('C3_SELECTED', c3)
    finally:
        RUNTIME_SCHEMA.unlink(missing_ok=True)
    summary={'A':{k:v for k,v in a.items() if k!='raw_output'},'C3':{k:v for k,v in c.items() if k!='raw_output'}}
    summary['comparison']={
        'context_reduction_pct': round((1-c['profile_context_chars']/a['profile_context_chars'])*100,2),
        'runtime_change_pct': round((c['runtime_seconds']/a['runtime_seconds']-1)*100,2) if a['runtime_seconds'] else None,
        'output_change_pct': round((c['output_chars']/a['output_chars']-1)*100,2) if a['output_chars'] else None,
        'quality_c3_not_worse': bool(c['json_ok'] and c['structural_pass'] and not c['fence'] and c['requirements_pass'] and c['grid_content_count'] <= a['grid_content_count']),
    }
    print('C3_PILOT_SUMMARY='+json.dumps(summary,ensure_ascii=False,sort_keys=True))
    print('C3_RAW_BEGIN')
    print(c['raw_output'])
    print('C3_RAW_END')
    return 0 if summary['comparison']['quality_c3_not_worse'] else 2

if __name__=='__main__':
    raise SystemExit(main())

"""Review-only projection of the existing blueprint into a graphical prompt.
No provider invocation, canonical seal, semantic approval or authority grant.
"""
import hashlib
import json
import re
from pathlib import Path
from art_direction_preflight_v1 import preflight, ArtBlocked

DIRECTION = ('scene','style','background','typography','hierarchy','visual_impact')


def require(ok, code):
    if not ok:
        raise ArtBlocked(code)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def instruction(s):
    require(type(s) is str and bool(s.strip()), 'GRAPHICAL_INSTRUCTION_MISSING')
    # Basic lexical guard, not semantic leakage detection or prompt-injection defense.
    require(not re.search(r'\b(?:[a-f0-9]{64}|SHA-?256|READY_TO_MERGE|SEMANTIC_QA_PENDING|PLAN_ONLY|REVIEW_ONLY|PROVIDER_RECEIPT|HANDOFF_NOT_SENT|SUPABASE|MERGE TRAIN)\b',s,re.I), 'GRAPHICAL_OPERATIONAL_METADATA')
    return s.strip()


def build_candidate(plan, projection, files):
    p=preflight(plan)
    require(type(projection) is dict and set(projection)=={'direction','components','references'}, 'GRAPHICAL_PROJECTION_FIELDS')
    require(type(projection['direction']) is dict and set(projection['direction'])==set(DIRECTION), 'GRAPHICAL_DIRECTION_COVERAGE')
    comps=plan['components']; authored=projection['components']
    require(type(authored) is dict and set(authored)=={c['name'] for c in comps if c['owner']=='NATIVE'}, 'GRAPHICAL_COMPONENT_COVERAGE')
    lock=plan['blueprint']['design_lock']['LOCK']; layout=lock.get('composition_layout')
    require(type(layout) is dict and set(layout)=={'canvas','backdrop','regions'}, 'GRAPHICAL_LAYOUT_MISSING')
    canvas=layout['canvas']; require(type(canvas) is list and len(canvas)==2 and all(type(n) is int and n>0 for n in canvas), 'GRAPHICAL_CANVAS')
    w,h=canvas; regions=layout['regions']
    require(type(regions) is list and all(type(r) is dict for r in regions) and [(r.get('name'),r.get('owner')) for r in regions]==[(c['name'],c['owner']) for c in comps], 'GRAPHICAL_LAYOUT_COVERAGE')
    sources={s['id']:s for s in plan['sources']}; refs=projection['references']
    require(type(refs) is list and type(files) is dict and all(type(r) is dict and set(r)=={'source_id','guidance'} for r in refs), 'GRAPHICAL_REFERENCE_FIELDS')
    ids=[r['source_id'] for r in refs]
    require(all(type(sid) is str for sid in ids) and len(ids)==len(set(ids)) and set(ids)==set(files), 'GRAPHICAL_ATTACHMENT_SET')
    allowed={sid for c in comps if c['owner']!='COMPOSITOR' for sid in c['source_ids']}
    attachments=[]; lines=[]
    for k in DIRECTION:
        t=instruction(projection['direction'][k]);
        if t not in lines:lines.append(t)
    lines.append(f'Lienzo de {w} × {h}. Una sola pieza en el encuadre solicitado.')
    for n,r in enumerate(refs,1):
        sid=r['source_id'];require(sid in sources and sid in allowed,'GRAPHICAL_REFERENCE_UNBOUND')
        meta=json.loads(sources[sid]['text']);require(meta.get('role')=='previous_generated_visual_reference_only','GRAPHICAL_REFERENCE_ROLE')
        path=Path(files[sid]);require(path.is_file() and not path.is_symlink() and path.stat().st_size<=20_000_000,'GRAPHICAL_ATTACHMENT_FILE')
        raw=path.read_bytes();require(sha(raw)==meta.get('file_sha256'),'GRAPHICAL_ATTACHMENT_HASH_DRIFT')
        require(raw.startswith(b'\x89PNG\r\n\x1a\n'),'GRAPHICAL_ATTACHMENT_FORMAT')
        attachments.append({'filename':f'reference_{n}.png','sha256':sha(raw),'mime_type':'image/png','role':'visual_reference'})
        lines.append(f'Referencia visual adjunta {n}: '+instruction(r['guidance']))
    for c,r in zip(comps,regions):
        if c['owner']=='REFERENCE_ONLY':continue
        instruction(c['name'])
        for text in c['copy']:instruction(text)
        if c['owner']=='NATIVE':
            lines.append(c['name']+': '+instruction(authored[c['name']]))
            if c['copy']:lines.append('Textos o símbolos exactos de esta sección: '+json.dumps(c['copy'],ensure_ascii=False)+'.')
        else:
            require(r.get('coverage')=='BOX','GRAPHICAL_RESERVED_MASK_UNSUPPORTED')
            b=r.get('box');require(type(b) is list and len(b)==4 and all(type(n) is int for n in b),'GRAPHICAL_RESERVED_BOX')
            x,y,a,d=b;require(min(x,y)>=0 and min(a,d)>0 and x+a<=w and y+d<=h,'GRAPHICAL_RESERVED_BOX')
            lines.append(f'{c["name"]}: reserva el rectángulo [{x}, {y}, {a}, {d}] con fondo limpio y continuo, sin textos ni dibujos en él. Se completará después. Conserva el diseño circundante.')
    lines.append('No dibujes marcas, botones ni textos en las zonas reservadas; no dupliques componentes. No muestres coordenadas, medidas, códigos de color, notas técnicas ni etiquetas de instrucción. Renderiza exclusivamente los textos y símbolos indicados para cada sección.')
    prompt='\n\n'.join(lines)
    payload={'prompt':prompt,'attachments':attachments}
    wire=json.dumps(payload,ensure_ascii=False,sort_keys=True,separators=(',',':')).encode('utf-8')
    return {'status':'GRAPHICAL_CANDIDATE_SEMANTIC_PENDING','payload':payload,'candidate_wire_sha256':sha(wire),'candidate_wire_bytes':len(wire),'proposal_sha256':p['proposal_sha256'],'semantic_qa':'NOT_EVALUATED','canonical_wire':False,'native_transmitted':False,'provider_receipt':None,'image_generation_allowed':False,'production_approved':False}

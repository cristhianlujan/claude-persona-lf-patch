"""SALY-specific L2C review adapter. Engine remains brand-neutral.

Offline: accepts a genuine L2C packet, frozen logo bytes and registered font refs.
Never dispatches GPT Native, approves QA, or authorizes rendering.
"""
import hashlib
import json
from pathlib import Path

class ReviewPacketError(ValueError):
    pass

def check(cond, code):
    if not cond:raise ReviewPacketError(code)

def sha(data):return hashlib.sha256(data).hexdigest()

def _trace(traces, consumer, component, prop):
    vals=[v for v in traces if v.get('consumer')==consumer and v.get('component')==component and v.get('property')==prop]
    check(len(vals)==1,'TRACE_UNIQUE_REQUIRED:'+component+':'+prop)
    t=vals[0]
    check(t.get('status') in ('APPROVED','CANDIDATE') and isinstance(t.get('chain'),list) and t['chain'], 'TRACE_SOURCE_INVALID')
    return t['value']

def from_packet(pkt,logo_file,font_registry,assets_dir):
    check(pkt.get('schema_version')=='SALY_WORK_PACKET_L2C_V1','PACKET_VERSION')
    check(pkt.get('readiness_code')=='READY_FOR_REVIEW_ONLY' and pkt.get('native_execution_authorized') is False and pkt.get('image_generation_allowed') is False,'PACKET_AUTHORITY')
    r=pkt.get('review_contract') or {}
    check(r.get('state')=='REVIEW_CONTRACT_PREPARED','REVIEW_CONTRACT_STATE')
    c=r.get('contract') or {};h=c.get('handoff') or {};comp=h.get('composition') or {}
    check(c.get('qa_verdict')=='NOT_EVALUATED' and c.get('render_ready') is not True,'REVIEW_QA_STATE')
    check(comp.get('render_ready') is False and comp.get('asset_state')=='CANDIDATE_REVIEW_ONLY' and comp.get('pending_assets')==[],'REVIEW_ASSET_AUTHORITY')
    tr=pkt.get('native_transport') or {};payload=tr.get('payload') or {}
    check(set(tr)=={'schema_version','item_id','contract_sha256','prompt_sha256','payload'} and tr.get('schema_version')=='SALY_NATIVE_TRANSPORT_V2','TRANSPORT_ENVELOPE')
    check(set(payload)=={'prompt','attachments'} and isinstance(payload['prompt'],str) and isinstance(payload['attachments'],list),'TRANSPORT_PAYLOAD')
    check(pkt.get('item_id')==h.get('item_id')==tr.get('item_id'),'ITEM_BINDING_DRIFT')
    check(tr.get('contract_sha256')==r.get('contract_sha256'),'CONTRACT_BINDING_DRIFT')
    check(payload['attachments']==h.get('attachments') and payload['prompt']==h.get('native_prompt'),'TRANSPORT_REWRITE')
    check(sha(payload['prompt'].encode('utf-8'))==tr.get('prompt_sha256')==h.get('prompt_sha256'),'TRANSPORT_HASH_DRIFT')
    check(h.get('mode')=='REVIEW_ONLY','HANDOFF_MODE')
    refs=comp.get('asset_refs') or {};raw=pkt.get('composition_svg_assets') or {}
    check(set(refs)==set(raw),'SVG_SET_DRIFT')
    nav=comp.get('navigation_labels') or []
    check(set(refs)==set(['frame',*nav]),'NAV_ASSET_BINDING')
    check(isinstance(comp.get('geometry'),dict),'GEOMETRY_MISSING')
    check(isinstance(font_registry,dict) and font_registry.get('family') and isinstance(font_registry.get('files'),dict),'FONT_REGISTRY_MISSING')
    trace=h.get('trace') or []
    families=[_trace(trace,'composition',component,'fuente base') for component in ('cta','navegacion')]
    check(len(set(families))==1 and families[0].split(',')[0].strip()==font_registry['family'],'FONT_FAMILY_DRIFT')
    files=font_registry['files']
    logo=comp.get('logo_ref') or {};logo_file=Path(logo_file)
    check(logo_file.is_file() and sha(logo_file.read_bytes())==logo.get('sha256'),'LOGO_BYTES_DRIFT')
    staged={}
    for name,src in sorted(raw.items()):
        ref=refs[name]
        check(src.get('ref')==ref and ref.get('provider')=='SUPABASE_INLINE_SVG','SVG_REFERENCE_DRIFT')
        svg=src.get('svg_utf8');check(isinstance(svg,str),'SVG_BYTES_MISSING')
        binary=svg.encode('utf-8');check(sha(binary)==ref.get('sha256'),'SVG_BYTES_DRIFT')
        staged[name]=binary
    fsize=_trace(trace,'composition','cta','tipografía botón')
    nsize=_trace(trace,'composition','navegacion','tipografía etiqueta')
    check(isinstance(fsize,dict) and isinstance(nsize,dict),'FONT_TOKEN_STRUCTURE')
    tokens={
      'cta_bg':_trace(trace,'composition','cta','fondo'),
      'cta_text':_trace(trace,'composition','cta','texto'),
      'nav_bg':_trace(trace,'composition','navegacion','fondo'),
      'nav_active':_trace(trace,'composition','navegacion','activa'),
      'nav_inactive':_trace(trace,'composition','navegacion','inactiva')}
    layout=comp.get('navigation_layout') or {}
    check(layout.get('columns')==len(nav) and layout.get('color_mode')=='RESOLVED_TOKEN_CURRENT_COLOR','NAV_LAYOUT_DRIFT')
    for weight in (str(fsize['weight']),str(nsize['weight'])):
        pin=files.get(weight)
        check(isinstance(pin,dict) and Path(pin.get('path','')).is_file(),'FONT_FILE_MISSING')
        check(sha(Path(pin['path']).read_bytes())==pin.get('sha256'),'FONT_FILE_HASH_DRIFT')
    out=Path(assets_dir);out.mkdir(parents=True,exist_ok=True)
    sources={'logo':{'path':str(logo_file),'sha256':logo['sha256']}}
    for i,(name,binary) in enumerate(sorted(staged.items())):
        path=out/f'asset_{i}.svg'
        path.write_bytes(binary)
        sources[name]={'path':str(path),'sha256':refs[name]['sha256']}
    return {
      'schema_version':'CREATIVE_COMPOSITION_REVIEW_V1','review_only':True,'render_authorized':False,
      'contract_sha256':r['contract_sha256'],'prompt_sha256':h['prompt_sha256'],
      'geometry':comp['geometry'],'frame_outer':comp['frame_outer'],'frame_app_opening':comp['frame_app_opening'],
      'navigation_labels':nav,'navigation_active':h['navigation_active'],
      'icon_size':layout['icon_size_px'],'icon_top_offset':layout['icon_top_offset_px'],
      'label_top_offset':layout['label_top_offset_px'],'cta_copy':h['cta_copy'],
      'cta_radius':_trace(trace,'composition','cta','radio botón (px)'),
      'cta_font_size':fsize['size_px'],'cta_font_weight':fsize['weight'],
      'nav_font_size':nsize['size_px'],'nav_font_weight':nsize['weight'],
      'tokens':tokens,'assets':sources,'font_files':files}

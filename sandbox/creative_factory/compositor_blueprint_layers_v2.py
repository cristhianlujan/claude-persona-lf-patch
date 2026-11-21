"""Layer extension of the existing compositor; candidate review only, not a new renderer.
Uses the existing art-direction preflight and shared raster/font/asset primitives.
"""
import io
import json
import re
from pathlib import Path
from PIL import Image, ImageDraw, ImageChops
from art_direction_preflight_v1 import ArtBlocked, preflight
from compositor_core_v1 import CompositionError, box, digest, font, svg_image

SCHEMA = 'CREATIVE_COMPOSITION_BLUEPRINT_REVIEW_V2'


def need(ok, code):
    if not ok:
        raise CompositionError(code)


def fields(obj, keys):
    need(type(obj) is dict and set(obj) == set(keys.split()), 'LAYER_FIELDS')


def canonical(obj):
    return json.dumps(obj, sort_keys=True, ensure_ascii=False, separators=(',', ':'), allow_nan=False).encode('utf-8')


def rect(b):
    x,y,w,h = b
    return (x,y,x+w-1,y+h-1)


def compose_blueprint(m, body):
    fields(m, 'schema_version review_only render_authorized body_origin plan proposal_sha256 canvas backdrop regions files')
    need(m['schema_version'] == SCHEMA and m['review_only'] is True and m['render_authorized'] is False
         and m['body_origin'] in ('SYNTHETIC_REVIEW','RGB_REFERENCE_REVIEW'), 'LAYER_REVIEW_ONLY')
    rgb_review = m['body_origin']=='RGB_REFERENCE_REVIEW'
    try:
        p = preflight(m['plan'])
    except ArtBlocked as exc:
        raise CompositionError('LAYER_PLAN_BLOCKED:'+str(exc)) from exc
    need(p['proposal_sha256'] == m['proposal_sha256'], 'LAYER_PLAN_HASH_DRIFT')
    dims=m['canvas']
    need(type(dims) is list and len(dims)==2 and all(type(x) is int and 0<x<=4096 for x in dims)
         and dims[0]*dims[1]<=8_000_000, 'LAYER_CANVAS')
    w,h = dims
    need(isinstance(body,Image.Image) and body.mode==('RGB' if rgb_review else 'RGBA') and body.size==(w,h), 'BODY_FORMAT')
    plan=m['plan']; sources={s['id']:s for s in plan['sources']}
    layout={key:m[key] for key in ('canvas','backdrop','regions')}
    need(plan['blueprint']['design_lock']['LOCK'].get('composition_layout')==layout, 'LAYER_BLUEPRINT_LAYOUT_DRIFT')
    parsed={}; used={}; files=m['files']
    need(type(files) is dict, 'LAYER_FILE_REGISTRY')
    if rgb_review:
        binding=plan['blueprint']['design_lock']['LOCK'].get('rgb_reference_binding')
        fields(binding,'source_id pixel_sha256 alignment')
        need(plan['presentation']['mode']=='FULL_SCENE' and binding['alignment']=='CANDIDATE_MANUAL_REVIEW', 'RGB_REFERENCE_ALIGNMENT_PENDING')
        need(binding['source_id'] in sources, 'RGB_REFERENCE_SOURCE_MISSING')
        ref=json.loads(sources[binding['source_id']]['text'])
        need(ref.get('role')=='previous_generated_visual_reference_only' and ref.get('mode')=='RGB'
             and ref.get('dimensions')==dims and digest(body.tobytes())==binding['pixel_sha256'], 'RGB_REFERENCE_BINDING_DRIFT')
    def source(sid, allowed):
        need(type(sid) is str and sid in allowed and sid in sources, 'LAYER_SOURCE_UNBOUND')
        if sid not in parsed:
            try: parsed[sid]=json.loads(sources[sid]['text'])
            except ValueError as exc: raise CompositionError('LAYER_SOURCE_FORMAT') from exc
        need(type(parsed[sid]) is dict, 'LAYER_SOURCE_FORMAT')
        return parsed[sid]
    def color(sid, allowed):
        v=source(sid,allowed).get('value')
        need(type(v) is str and re.fullmatch(r'#[0-9A-Fa-f]{6}',v) is not None, 'LAYER_COLOR_TOKEN')
        return v
    def file(sid, allowed):
        meta=source(sid,allowed); pin=meta.get('file_sha256'); path=files.get(sid)
        need(type(pin) is str and re.fullmatch('[0-9a-f]{64}',pin) is not None and type(path) is str, 'LAYER_FILE_UNPINNED')
        fp=Path(path)
        need(fp.is_file() and not fp.is_symlink() and fp.stat().st_size<=20_000_000, 'LAYER_FILE_MISSING')
        raw=fp.read_bytes(); need(digest(raw)==pin, 'LAYER_FILE_HASH_DRIFT')
        used[sid]=pin
        return fp,raw,meta
    def asset(sid, allowed, size):
        fp,raw,meta=file(sid,allowed)
        if meta.get('mime_type')=='image/svg+xml':
            # SVGs are untrusted input: no external resources/DTD/CSS imports.
            low=raw.lower()
            need(not any(x in low for x in (b'<!doctype',b'<!entity',b'href',b'url(',b'@import',b'<style')), 'LAYER_SVG_EXTERNAL')
            image=svg_image(raw)
        else:
            need(meta.get('mime_type','image/png')=='image/png', 'LAYER_ASSET_FORMAT')
            with Image.open(io.BytesIO(raw)) as im:
                need(im.format=='PNG' and im.width*im.height<=8_000_000, 'LAYER_ASSET_FORMAT')
                image=im.convert('RGBA')
        image.thumbnail(size,Image.Resampling.LANCZOS)
        return image
    def text_layer(target,b,op,c):
        x,y,a,d=b
        need(type(op['size']) is int and 1<=op['size']<=d and type(op['weight']) is int, 'LAYER_TEXT_SIZE')
        need(op['copy'] in c['copy'], 'LAYER_TEXT_UNBOUND')
        fp,_,meta=file(op['font_source'],c['source_ids'])
        need(meta.get('weight')==op['weight'], 'LAYER_FONT_WEIGHT')
        ft=font(op['size'],op['weight'],{str(op['weight']):{'path':str(fp),'sha256':meta['file_sha256']}})
        draw=ImageDraw.Draw(target); bb=draw.textbbox((0,0),op['copy'],font=ft)
        tw,th=bb[2]-bb[0],bb[3]-bb[1]
        need(tw<=a and th<=d, 'LAYER_TEXT_OVERFLOW')
        draw.text((x+(a-tw)//2-bb[0],y+(d-th)//2-bb[1]),op['copy'],font=ft,fill=color(op['color_source'],c['source_ids']))
    regions=m['regions']; comps=plan['components']
    need(type(regions) is list and len(regions)==len(comps), 'LAYER_COMPONENT_COVERAGE')
    native=Image.new('L',(w,h)); fixed=Image.new('L',(w,h)); rendered=[]; occupied=[]
    for c,r in zip(comps,regions):
        fields(r,'name owner box ops coverage')
        need(r['name']==c['name'] and r['owner']==c['owner'], 'LAYER_COMPONENT_BINDING')
        need(type(r['ops']) is list, 'LAYER_OPS')
        if c['owner']=='REFERENCE_ONLY':
            need(r['box'] is None and not r['ops'] and r['coverage']=='NONE', 'LAYER_REFERENCE_DRAW'); continue
        b=box(r['box'],c['name'],w,h)
        if c['owner']=='NATIVE':
            need(not r['ops'] and r['coverage']=='BOX', 'LAYER_NATIVE_FIXED_OP')
            ImageDraw.Draw(native).rectangle(rect(b),fill=255); continue
        need(bool(r['ops']), 'LAYER_FIXED_EMPTY')
        need(r['coverage'] in ('BOX','ALPHA'), 'LAYER_COVERAGE_MODE')
        if rgb_review: need(r['coverage']=='BOX','RGB_REFERENCE_ALPHA_OVERLAY_UNSAFE')
        occupied.append((c,r,b))
    prepared=[]
    for c,r,b in occupied:
        x,y,a,d=b; allowed=c['source_ids']; copies=[]; has_asset=False
        # Render into a clipped local component surface, then place it in its box.
        layer=Image.new('RGBA',(a,d))
        for op in r['ops']:
            need(type(op) is dict,'LAYER_OPS'); kind=op.get('kind')
            if kind=='FILL':
                fields(op,'kind box color_source radius')
                bb=box(op['box'],'fill',a,d); rad=op['radius']
                need(type(rad) is int and 0<=rad<=min(bb[2:])//2, 'LAYER_RADIUS')
                ImageDraw.Draw(layer).rounded_rectangle(rect(bb),radius=rad,fill=color(op['color_source'],allowed))
            elif kind=='ASSET':
                fields(op,'kind box source_id')
                xx,yy,aw,ah=box(op['box'],'asset',a,d)
                im=asset(op['source_id'],allowed,(aw,ah)); has_asset=True
                layer.alpha_composite(im,(xx+(aw-im.width)//2,yy+(ah-im.height)//2))
            elif kind=='TEXT':
                fields(op,'kind box copy size weight font_source color_source')
                bb=box(op['box'],'text',a,d); text_layer(layer,bb,op,c); copies.append(op['copy'])
            else:
                raise CompositionError('LAYER_OPERATION_UNSUPPORTED')
        need(copies==c['copy'] or (has_asset and not copies), 'LAYER_COPY_COVERAGE')
        need(bool(layer.getchannel('A').getbbox()),'LAYER_FIXED_EMPTY')
        current=Image.new('L',(w,h))
        if r['coverage']=='ALPHA':
            # Only a pinned transparent asset may reserve a non-rectangular silhouette.
            need(len(r['ops'])==1 and r['ops'][0]['kind']=='ASSET', 'LAYER_ALPHA_ASSET_ONLY')
            mask=layer.getchannel('A').point(lambda a:255 if a else 0)
            need(mask.getextrema()==(0,255),'LAYER_ALPHA_NOT_TRANSPARENT')
            current.paste(mask,(x,y))
        else:
            ImageDraw.Draw(current).rectangle(rect(b),fill=255)
        need(not ImageChops.multiply(fixed,current).getbbox(),'LAYER_FIXED_OVERLAP')
        fixed=ImageChops.lighter(fixed,current)
        prepared.append((layer,x,y,c['name']))
    permitted=ImageChops.subtract(native,fixed)
    rgb_evidence=None
    if rgb_review:
        # Do not resize, crop, infer geometry or inpaint. The approved-for-review
        # plan owns every reserved box. Everything outside is byte-identical RGB.
        need(ImageChops.lighter(native,fixed).getextrema()==(255,255),'RGB_REFERENCE_INCOMPLETE_CANVAS')
        need(bool(fixed.getbbox()),'RGB_REFERENCE_NO_FIXED_REGIONS')
        original_rgb=body
        body=body.convert('RGBA'); body.putalpha(permitted)
        need(m['backdrop']['kind'] in ('COLOR','ASSET'),'RGB_REFERENCE_CLEAN_PLATE_REQUIRED')
    alpha=body.getchannel('A')
    need(not ImageChops.multiply(alpha,ImageChops.invert(permitted)).getbbox(),'BODY_OVERWRITES_FIXED')
    need(not native.getbbox() or alpha.getbbox(),'BODY_EMPTY')
    # Base layer may be a pinned background asset or a resolved color.
    back=m['backdrop']; fields(back,'kind source_id')
    if back['kind']=='TRANSPARENT':
        need(back['source_id'] is None,'LAYER_BACKDROP_SOURCE'); out=Image.new('RGBA',(w,h))
    elif back['kind']=='COLOR':
        out=Image.new('RGBA',(w,h),color(back['source_id'],list(sources)))
    else:
        need(back['kind']=='ASSET','LAYER_BACKDROP_KIND')
        out=asset(back['source_id'],list(sources),(w,h))
        need(out.size==(w,h), 'LAYER_BACKDROP_DIMENSIONS')
    if rgb_review: need(out.getchannel('A').getextrema()==(255,255),'RGB_REFERENCE_CLEAN_PLATE_NOT_OPAQUE')
    out.alpha_composite(body)
    for layer,x,y,name in prepared:
        out.alpha_composite(layer,(x,y)); rendered.append(name)
    need(set(files)==set(used),'LAYER_UNUSED_FILE')
    if rgb_review:
        # Compare actual output against input, including all original scene pixels.
        diff=ImageChops.difference(original_rgb,out.convert('RGB'))
        r,g,b=diff.split(); changed=ImageChops.lighter(ImageChops.lighter(r,g),b).point(lambda v:255 if v else 0)
        need(not ImageChops.multiply(changed,ImageChops.invert(fixed)).getbbox(),'RGB_REFERENCE_OUTSIDE_PIXELS_CHANGED')
        rgb_evidence={'alignment':'CANDIDATE_MANUAL_REVIEW','reference_pixel_sha256':digest(original_rgb.tobytes()),
                      'mask_sha256':digest(fixed.tobytes()),'fixed_pixel_count':fixed.histogram()[255],
                      'preserved_pixel_count':w*h-fixed.histogram()[255],
                      'changed_pixel_count':changed.histogram()[255],'outside_changed_pixels':0,
                      'resize_or_inpaint':False,'clean_plate_visual_qa':'PENDING','provider_provenance':'UNVERIFIED_REFERENCE'}
    return out,{'status':'LOCAL_BLUEPRINT_COMPOSITOR_PASS','schema_version':SCHEMA,
                'business_code':plan['business_code'],'proposal_sha256':p['proposal_sha256'],
                'manifest_sha256':digest(canonical(m)),'source_sha256':used,'fixed_components':rendered,
                'dimensions':[w,h],'body_origin':m['body_origin'],'body_sha256':digest(body.tobytes()),
                'rgb_reference_review':rgb_evidence,
                'image_sha256':digest(out.tobytes()),'source_authenticity':'NOT_ATTESTED_BY_LOCAL_GATE',
                'qa_verdict':'NOT_EVALUATED','native_transmitted':False,'provider_receipt':None,
                'image_generation_allowed':False,'production_approved':False}

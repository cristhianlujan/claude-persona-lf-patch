"""Brand-neutral, offline compositor for frozen review contracts. Does not authorize rendering."""
import argparse
import hashlib
import io
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import cairosvg

class CompositionError(ValueError):
    pass

def digest(raw):
    return hashlib.sha256(raw).hexdigest()

def box(values, name, w, h):
    if not isinstance(values,list) or len(values)!=4 or any(type(v)!=int for v in values):
        raise CompositionError('BOX_INVALID:'+name)
    x,y,a,b=values
    if min(x,y)<0 or min(a,b)<1 or x+a>w or y+b>h:
        raise CompositionError('BOX_BOUNDS:'+name)
    return x,y,a,b

def font(size,weight):
    mapping={400:'Regular',600:'SemiBold',700:'Bold'}
    if weight not in mapping:raise CompositionError('FONT_WEIGHT_INVALID')
    fn=Path('/usr/share/fonts/opentype/inter')/('Inter-'+mapping[weight]+'.otf')
    if not fn.exists():raise CompositionError('FONT_NOT_FOUND')
    return ImageFont.truetype(str(fn),size)

def svg_image(data,color=None):
    text=data.decode('utf-8')
    for unsafe in ('<script','foreignObject','href=','url(http','url(file','<image'):
        if unsafe.lower() in text.lower():raise CompositionError('SVG_UNSAFE')
    if color:
        if 'currentColor' not in text:raise CompositionError('SVG_COLOR_MODE')
        text=text.replace('currentColor',color)
    return Image.open(io.BytesIO(cairosvg.svg2png(bytestring=text.encode('utf-8')))).convert('RGBA')

def compose(m,body):
    if m.get('schema_version')!='CREATIVE_COMPOSITION_REVIEW_V1':raise CompositionError('MANIFEST_VERSION')
    if m.get('review_only') is not True or m.get('render_authorized') is not False:
        raise CompositionError('REVIEW_AUTHORITY')
    for h in ('contract_sha256','prompt_sha256'):
        v=m.get(h)
        if not isinstance(v,str) or len(v)!=64 or any(c not in '0123456789abcdef' for c in v):
            raise CompositionError('INVALID_HASH:'+h)
    g=m['geometry'];w,h=g['viewport'];fw,fh=m['frame_outer'];ox,oy,ow,oh=box(m['frame_app_opening'],'opening',fw,fh)
    if (ow,oh)!=(w,h) or g['origin']!='top_left' or g['units']!='logical_px':
        raise CompositionError('COORDINATES')
    b={k:box(g[k],k,w,h) for k in ('primary','details','header','cta','footer','logo')}
    labels=m['navigation_labels'];active=m['navigation_active']
    if len(labels)!=g['footer_columns'] or active not in labels:raise CompositionError('NAV_CONTRACT')
    if set(m['assets'])!=set(('logo','frame',*labels)):raise CompositionError('ASSET_SET')
    assets={}
    for k,ref in m['assets'].items():
        path=Path(ref['path'])
        if not path.is_file():raise CompositionError('ASSET_MISSING:'+k)
        data=path.read_bytes()
        if digest(data)!=ref['sha256']:raise CompositionError('ASSET_SHA256:'+k)
        assets[k]=data
    if not isinstance(body,Image.Image) or body.mode!='RGBA' or body.size!=(w,h):
        raise CompositionError('BODY_FORMAT')
    # BODY may supply pixels only in its exact native-owned slots.
    mask=Image.new('L',(w,h));md=ImageDraw.Draw(mask)
    for k in ('primary','details'):
        x,y,a,bb=b[k];md.rectangle((x,y,x+a-1,y+bb-1),fill=255)
    alpha=body.getchannel('A')
    if not alpha.getbbox():raise CompositionError('BODY_EMPTY')
    if Image.composite(alpha,Image.new('L',(w,h)),Image.eval(mask,lambda v:255-v)).getbbox():
        raise CompositionError('BODY_OVERWRITES_FIXED')
    for a in ('primary','details'):
        x,y,aw,ah=b[a]
        for k in ('header','cta','footer'):
            xx,yy,kw,kh=b[k]
            if max(x,xx)<min(x+aw,xx+kw) and max(y,yy)<min(y+ah,yy+kh):
                raise CompositionError('OVERLAPPING_SLOTS')
    colors=m['tokens']
    for k in ('cta_bg','cta_text','nav_bg','nav_active','nav_inactive'):
        v=colors[k]
        if not isinstance(v,str) or len(v)!=7 or v[0]!='#' or any(z not in '0123456789abcdefABCDEF' for z in v[1:]):
            raise CompositionError('COLOR_TOKEN:'+k)
    if m['cta_font_weight']!=600 or m['nav_font_weight']!=400:
        raise CompositionError('WEIGHT_DRIFT')
    native=Image.new('RGBA',(w,h),'white');native.alpha_composite(body)
    d=ImageDraw.Draw(native)
    x,y,a,bb=b['header'];d.rectangle((x,y,x+a-1,y+bb-1),fill='white')
    logo=Image.open(io.BytesIO(assets['logo'])).convert('RGBA')
    x,y,a,bb=b['logo'];logo.thumbnail((a,bb),Image.Resampling.LANCZOS)
    native.alpha_composite(logo,(x,y+(bb-logo.height)//2))
    x,y,a,bb=b['cta']
    d.rounded_rectangle((x,y,x+a-1,y+bb-1),radius=m['cta_radius'],fill=colors['cta_bg'])
    cf=font(m['cta_font_size'],m['cta_font_weight']);txt=m['cta_copy'];bounds=d.textbbox((0,0),txt,font=cf)
    ww,hh=bounds[2]-bounds[0],bounds[3]-bounds[1]
    if ww>a-16 or hh>bb-12:raise CompositionError('CTA_OVERFLOW')
    d.text((x+(a-ww)/2,y+(bb-hh)/2-bounds[1]),txt,font=cf,fill=colors['cta_text'])
    x,y,a,bb=b['footer'];d.rectangle((x,y,x+a-1,y+bb-1),fill=colors['nav_bg'])
    d.line((x,y,x+a,y),fill='#D9DDE4')
    nf=font(m['nav_font_size'],m['nav_font_weight']);sz=m['icon_size']
    for j,label in enumerate(labels):
        color=colors['nav_active' if label==active else 'nav_inactive']
        icon=svg_image(assets[label],color).resize((sz,sz),Image.Resampling.LANCZOS)
        center=x+(j+.5)*a/len(labels)
        native.alpha_composite(icon,(int(center-sz/2),y+m['icon_top_offset']))
        bbox=d.textbbox((0,0),label,font=nf)
        d.text((center-(bbox[2]-bbox[0])/2,y+m['label_top_offset']),label,font=nf,fill=color)
    frame=svg_image(assets['frame'])
    if frame.size!=(fw,fh):raise CompositionError('FRAME_DIMENSIONS')
    result=Image.new('RGBA',(fw,fh));result.alpha_composite(native,(ox,oy));result.alpha_composite(frame)
    return result,{'status':'LOCAL_COMPOSITOR_PASS','provider_receipt':None,'native_transmitted':False,
        'production_approved':False,'qa_verdict':'NOT_EVALUATED','contract_sha256':m['contract_sha256'],
        'prompt_sha256':m['prompt_sha256'],'source_sha256':{k:digest(v) for k,v in assets.items()},
        'body_sha256':digest(body.tobytes()),'image_sha256':digest(result.tobytes()),'dimensions':[fw,fh]}

def main():
    ap=argparse.ArgumentParser()
    for key in ('manifest','body','output'):ap.add_argument(key)
    ap.add_argument('--receipt')
    args=ap.parse_args()
    m=json.loads(Path(args.manifest).read_text())
    result,receipt=compose(m,Image.open(args.body))
    result.save(args.output)
    receipt['file_sha256']=digest(Path(args.output).read_bytes())
    if args.receipt:Path(args.receipt).write_text(json.dumps(receipt,indent=2,ensure_ascii=False)+'\n')
    print(json.dumps(receipt,ensure_ascii=False))
if __name__=='__main__':main()

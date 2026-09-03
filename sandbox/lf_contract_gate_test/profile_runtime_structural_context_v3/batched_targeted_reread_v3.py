#!/usr/bin/env python3
"""Batch-first targeted OCR reread for Structural Context Resolver V3.

Consumes only V3 residual regions. Multiple residual crops are stacked into one
montage and OCR'd once per configured PSM. OCR words are mapped back to their
source region using strict vertical containment, then the existing non-destructive
reconciler decides whether visible reread text is safer than original OCR.
"""
from __future__ import annotations
import argparse, json, time
from pathlib import Path

DEFAULT_PSMS=(6,7,11,13)

def assign_words_to_spans(words, spans):
    """Assign OCR word dicts to exactly one source span; reject cross-span boxes."""
    out=[[] for _ in spans]
    for word in words:
        top=float(word['top']); h=float(word['height']); bottom=top+h
        for i,(start,end) in enumerate(spans):
            if top >= start and bottom <= end:
                out[i].append(word); break
    return out

def reconstruct_region_text(words):
    """Adaptive line grouping, then left-to-right ordering within each line."""
    if not words: return ''
    lines=[]
    for w in sorted(words,key=lambda z:(float(z['top'])+float(z['height'])/2,float(z['left']))):
        cy=float(w['top'])+float(w['height'])/2; hh=float(w['height'])
        target=None
        for ln in lines:
            if abs(cy-ln['cy']) <= max(5.0,0.45*max(hh,ln['h'])):
                target=ln; break
        if target is None:
            lines.append({'cy':cy,'h':hh,'items':[(float(w['left']),str(w['text']))]})
        else:
            target['items'].append((float(w['left']),str(w['text'])))
    lines.sort(key=lambda z:z['cy']); parts=[]
    for ln in lines:
        ln['items'].sort(key=lambda z:z[0]); parts.extend(t for _,t in ln['items'] if t.strip())
    return ' '.join(parts).strip()

def select_best_candidate(original, role, candidates, reconcile_fn):
    """Evaluate each visible OCR candidate and keep best safe adopted decision."""
    evaluated=[]
    for psm,text in candidates.items():
        decision=reconcile_fn(original,text,role)
        evaluated.append((float(decision.get('reread_role_fit',0)),int(psm),text,decision))
    adopted=[x for x in evaluated if x[3].get('adopted')]
    if adopted:
        best=max(adopted,key=lambda x:(x[0],-x[1]))
        return best[3] | {'psm':best[1]}
    best=max(evaluated,key=lambda x:x[0],default=(0,None,'',{'text':original,'source':'ORIGINAL_OCR','adopted':False}))
    decision=dict(best[3]); decision['text']=original; decision['source']='ORIGINAL_OCR'; decision['adopted']=False; decision['psm']=best[1]
    return decision

def run(image_path, residuals, psms=DEFAULT_PSMS, separator_px=36, pad_x=24, pad_y=14):
    from PIL import Image
    import pytesseract
    from pytesseract import Output
    from targeted_reread_reconciler_v3 import reconcile

    image=Image.open(image_path).convert('RGB'); W,H=image.size
    crops=[]
    for r in residuals:
        x,y,w,h=[int(round(float(v))) for v in r['bbox']]
        x0=max(0,x-pad_x); y0=max(0,y-pad_y); x1=min(W,x+w+pad_x); y1=min(H,y+h+pad_y)
        crops.append((r,image.crop((x0,y0,x1,y1))))
    if not crops:
        return {'regions':[],'ocr_invocations':0,'ocr_ms':0.0,'psms':list(psms)}
    maxw=max(c.width for _,c in crops); total_h=sum(c.height for _,c in crops)+separator_px*(len(crops)-1)
    montage=Image.new('RGB',(maxw,total_h),'white'); spans=[]; yy=0
    for _,crop in crops:
        montage.paste(crop,(0,yy)); spans.append((yy,yy+crop.height)); yy += crop.height+separator_px

    candidates=[{} for _ in crops]; stage=[]; total_start=time.perf_counter()
    for psm in psms:
        t0=time.perf_counter()
        data=pytesseract.image_to_data(montage,lang='eng+spa',config=f'--psm {int(psm)}',output_type=Output.DICT)
        elapsed=(time.perf_counter()-t0)*1000
        words=[]
        for i,text in enumerate(data['text']):
            text=(text or '').strip()
            if not text: continue
            words.append({'text':text,'left':data['left'][i],'top':data['top'][i],'width':data['width'][i],'height':data['height'][i]})
        assigned=assign_words_to_spans(words,spans)
        for i,region_words in enumerate(assigned): candidates[i][int(psm)]=reconstruct_region_text(region_words)
        stage.append({'psm':int(psm),'duration_ms':round(elapsed,3),'word_count':len(words)})
    total_ms=(time.perf_counter()-total_start)*1000

    results=[]
    for (r,_),cand in zip(crops,candidates):
        decision=select_best_candidate(str(r.get('text','')),str(r.get('role','UNKNOWN')),cand,reconcile)
        results.append({'id':r.get('id'),'role':r.get('role'),'bbox':r.get('bbox'),'original_text':r.get('text',''),'candidates':cand,'decision':decision})
    return {'regions':results,'ocr_invocations':len(psms),'ocr_ms':round(total_ms,3),'psms':[int(x) for x in psms],
            'montage_size':[maxw,total_h],'stage_metrics':stage}

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('image'); ap.add_argument('resolver_json'); ap.add_argument('--output',required=True)
    a=ap.parse_args(); src=json.loads(Path(a.resolver_json).read_text()); residuals=src.get('residual',src)
    result=run(a.image,residuals); Path(a.output).write_text(json.dumps(result,ensure_ascii=False,indent=2)); print(json.dumps({k:result[k] for k in ('ocr_invocations','ocr_ms','psms','montage_size')}))
if __name__=='__main__':main()

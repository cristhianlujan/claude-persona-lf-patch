#!/usr/bin/env python3
"""Non-destructive adjudication for Structural Context Resolver V3 targeted rereads.

It chooses only between visible OCR readings. Canonical role candidates are used as
scoring context and are never emitted as replacement text, so context cannot
manufacture visual evidence.
"""
from difflib import SequenceMatcher
import re, unicodedata

ROLE_CANDIDATES = {
    'FILTER_BAR': ('buscar','estado','tipo de carga','cargado por','aprobacion','desde','hasta','ordenar por','direccion','todos','todas','mas recientes','limpiar filtros'),
    'TABLE_HEADER': ('lote','nombre','archivo','tipo','cargado por','fecha','total','validos','estado','acciones'),
    'STATE_BADGE': ('procesado','procesado con observaciones','pendiente de aprobacion','validando','rechazado','cancelado','aprobado','autoaprobado'),
    'ROW_ACTION': ('ver detalle','original','observados','rechazados'),
    'TABLE_SUMMARY': ('desplazate horizontalmente para ver todos los campos','cargas'),
}

def norm(s):
    s=unicodedata.normalize('NFKD', str(s)).encode('ascii','ignore').decode().lower()
    return re.sub(r'[^a-z0-9]+',' ',s).strip()

def similarity(a,b):
    return SequenceMatcher(None,norm(a),norm(b)).ratio()

def role_fit(text,role):
    c=ROLE_CANDIDATES.get(role,())
    return max((similarity(text,x) for x in c),default=0.0) if text else 0.0

def best_visible_span(text, role, max_tokens=5):
    """Select only a contiguous token span already present in reread OCR.

    Canonical role candidates influence scoring only. No candidate token is
    emitted unless it already occurs in the visible reread string.
    """
    raw=str(text or '').strip()
    tokens=re.findall(r'\S+', raw)
    if not tokens:
        return raw, 0.0
    best_text=raw
    best_fit=role_fit(raw,role)
    limit=min(max_tokens,len(tokens))
    for n in range(1,limit+1):
        for i in range(0,len(tokens)-n+1):
            span=' '.join(tokens[i:i+n])
            score=role_fit(span,role)
            if score > best_fit:
                best_text,best_fit=span,score
    return best_text,best_fit

def reconcile(original_text,reread_text,role,min_gain=0.03,min_absolute_fit=0.70):
    old_fit=role_fit(original_text,role)
    visible_candidate,new_fit=best_visible_span(reread_text,role)
    adopt=(bool(str(visible_candidate).strip()) and
           new_fit >= min_absolute_fit and
           new_fit >= old_fit + min_gain)
    return {'text':visible_candidate if adopt else original_text,
            'source':'TARGETED_REREAD' if adopt else 'ORIGINAL_OCR',
            'original_role_fit':round(old_fit,4),'reread_role_fit':round(new_fit,4),
            'minimum_absolute_fit':min_absolute_fit,
            'visible_span_selected':visible_candidate != str(reread_text or '').strip(),
            'adopted':adopt}

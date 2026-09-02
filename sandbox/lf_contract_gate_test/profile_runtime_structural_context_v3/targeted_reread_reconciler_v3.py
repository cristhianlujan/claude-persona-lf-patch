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

def reconcile(original_text,reread_text,role,min_gain=0.03,min_absolute_fit=0.70):
    old_fit=role_fit(original_text,role); new_fit=role_fit(reread_text,role)
    adopt=(bool(str(reread_text).strip()) and
           new_fit >= min_absolute_fit and
           new_fit >= old_fit + min_gain)
    return {'text':reread_text if adopt else original_text,
            'source':'TARGETED_REREAD' if adopt else 'ORIGINAL_OCR',
            'original_role_fit':round(old_fit,4),'reread_role_fit':round(new_fit,4),
            'minimum_absolute_fit':min_absolute_fit,
            'adopted':adopt}

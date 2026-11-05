"""Fail-closed semantic floor for UI output; independent semantic review still required."""
from __future__ import annotations
import unicodedata
BAD_EXACT={"unknown","pending","undefined","placeholder","lorem ipsum","por definir","no disponible","n/a","no aplica"}
INVISIBLE_CATEGORIES={"Cf","Cc","Cs","Co","Cn"}
BLANK_GLYPHS={"\u3164","\uffa0","\u115f","\u1160","\u17b4","\u17b5"}
CONFUSABLES=str.maketrans({"\u043e":"o","\u041e":"O","\u0430":"a","\u0410":"A","\u0435":"e","\u0415":"E","\u0440":"p","\u0420":"P","\u0441":"c","\u0421":"C","\u0456":"i","\u0406":"I"})

def _meaningful(v):
    raw=v.strip()
    if not raw: return False
    normalized=unicodedata.normalize("NFKC",raw).translate(CONFUSABLES).casefold()
    if normalized in BAD_EXACT: return False
    if any(unicodedata.category(c) in INVISIBLE_CATEGORIES or c in BLANK_GLYPHS for c in raw): return False
    return any(unicodedata.category(c)[0] in {"L","N"} and c not in BLANK_GLYPHS for c in raw)

def _scan(value,path,issues):
    if isinstance(value,dict):
        for k,v in value.items():_scan(v,path+"."+str(k),issues)
    elif isinstance(value,list):
        for i,v in enumerate(value):_scan(v,path+"["+str(i)+"]",issues)
    elif isinstance(value,str) and not _meaningful(value):issues.append(path)

def evaluate(payload,validator_result=None):
    if not isinstance(payload,dict) or not isinstance(validator_result,dict) or validator_result.get("status")!="PASS":
        return {"status":"BLOCKED","reason":"CANONICAL_VALIDATOR_REQUIRED"}
    issues=[]
    d=payload.get("deliverable_created",{})
    if isinstance(d,dict):
        for name in ("component_tree","density_rules","risk_controls"):
            if name in d:_scan(d[name],name,issues)
    return {"status":"PASS" if not issues else "BLOCKED","invalid_content_paths":issues[:30]}

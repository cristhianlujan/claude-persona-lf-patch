#!/usr/bin/env python3
"""Source-only dependency evidence for both governed LF profile operations."""
import hashlib
import json
import re
import sys

OPS = {"CREACION_PERFIL_LF", "ACTUALIZACION_PERFIL_LF"}
SCOPES = {"pg_proc", "pg_trigger", "cron.job", "pg_rewrite"}
REGPROC = re.compile(r"([A-Za-z_]\w*)\s+regprocedure\s*:?=\s*'([^']+)'::regprocedure",re.I)
GETDEF = re.compile(r"\bpg_get_functiondef\s*\(\s*([A-Za-z_]\w*)\s*\)",re.I)

def code_only(s):
    """Mask SQL literals and comments without changing source offsets."""
    a=list(s); i=0; n=len(s)
    while i<n:
        j=i
        if s.startswith("--",i):
            k=s.find("\n",i); i=n if k<0 else k
        elif s.startswith("/*",i):
            i+=2; depth=1
            while i<n and depth:
                if s.startswith("/*",i): depth+=1; i+=2
                elif s.startswith("*/",i): depth-=1; i+=2
                else: i+=1
        elif s[i]=="'":
            i+=1
            while i<n:
                if s[i]=="'":
                    i+=1
                    if i<n and s[i]=="'": i+=1; continue
                    break
                i+=1
        elif s[i]=="$":
            match=re.match(r"\$[A-Za-z_0-9]*\$",s[i:])
            if not match: i+=1; continue
            tag=match.group(); k=s.find(tag,i+len(tag))
            i=n if k<0 else k+len(tag)
        else: i+=1; continue
        for k in range(j,i):
            if a[k]!="\n": a[k]=" "
    return "".join(a)

def audit(p):
    if p.get("operation_code") not in OPS or p.get("temporal_scope") not in {"CURRENT","P0_HISTORICAL"}:
        raise ValueError("UNBOUND_OPERATION_OR_TIME")
    if not p.get("source_ref") or not isinstance(p.get("historical_callers"),list) or not isinstance(p.get("live_functions"),list):
        raise ValueError("UNBOUND_SOURCE")
    scopes=p.get("scopes_scanned",[])
    if not isinstance(scopes,list) or not set(scopes)<=SCOPES: raise ValueError("BAD_SCOPE")
    sources={}
    for f in p["live_functions"]:
        if not isinstance(f,dict) or not isinstance(f.get("caller"),str) or not isinstance(f.get("prosrc"),str) or f["caller"] in sources:
            raise ValueError("AMBIGUOUS_CALLER")
        sources[f["caller"]]=f["prosrc"]
    equal=changed=unknown=edges=call=string_only=missing_edge=0
    evidence=[]
    for item in p["historical_callers"]:
        if not isinstance(item,dict) or not isinstance(item.get("callees"),list): raise ValueError("BAD_INVENTORY")
        source=sources.get(item.get("caller"))
        prior=item.get("definition_md5")
        if source is None or not isinstance(prior,str) or not re.fullmatch("[0-9a-f]{32}",prior): unknown+=1
        elif hashlib.md5(source.encode()).hexdigest()==prior: equal+=1
        else: changed+=1
        for callee in item["callees"]:
            if not isinstance(callee,str): raise ValueError("BAD_CALLEE")
            name=callee.rsplit(".",1)[-1]
            if not re.fullmatch("[A-Za-z_][A-Za-z_0-9]*",name): raise ValueError("BAD_IDENTIFIER")
            edges+=1
            if source is None: state="UNKNOWN_SOURCE"
            else:
                pattern=r"(?<![A-Za-z_0-9])"+re.escape(name)+r"\s*\("
                if re.search(pattern,code_only(source),re.I):
                    state="CALLSITE_LEXICAL_NOT_EXECUTION"; call+=1
                elif name.lower() in source.lower():
                    state="TEXT_ONLY_NOT_CALL"; string_only+=1
                else: state="NO_CALLSITE"; missing_edge+=1
            evidence.append({"caller":item.get("caller"),"callee":callee,"state":state})
    readers=[]
    for caller,source in sources.items():
        bindings={k.lower():sig.split("(",1)[0] for k,sig in REGPROC.findall(source)}
        for key in GETDEF.findall(code_only(source)):
            target=bindings.get(key.lower())
            if target: readers.append({"reader":caller,"target":target,"kind":"DEFINICION_LEIDA_REGPROCEDURE","execution_verified":False})
    external={}
    for k,s in [("triggers","pg_trigger"),("cron","cron.job"),("views","pg_rewrite")]:
        value=p.get(k)
        external[k]={"status":"CURRENT_MEASURED" if s in scopes and isinstance(value,list) else "UNKNOWN_NOT_SCANNED",
                     "count":len(value) if s in scopes and isinstance(value,list) else None}
    perf={"status":"NOT_MEASURED"}
    x=p.get("performance")
    if isinstance(x,dict) and isinstance(x.get("total_runs"),int) and x["total_runs"]>0 and isinstance(x.get("runs"),list):
        valid=[y["duration_ms"] for y in x["runs"] if isinstance(y,dict) and type(y.get("duration_ms")) in (float,int) and y["duration_ms"]>=0]
        frac=len(valid)/x["total_runs"]
        perf={"status":"NO_CONCLUYENTE" if frac<.5 else "MUESTRA_SIN_CAUSALIDAD",
              "measured":len(valid),"total":x["total_runs"],"coverage":frac,
              "top2_share":sum(sorted(valid,reverse=True)[:2])/sum(valid) if sum(valid)>0 else None,
              "failures_with_time":sum(1 for y in x["runs"] if isinstance(y,dict) and y.get("failed") is True and type(y.get("duration_ms")) in (float,int))}
    vers=p.get("versions"); gaps=[]
    if isinstance(vers,list) and vers and all(type(v)==int and v>0 for v in vers):
        gaps=sorted(set(range(min(vers),max(vers)+1))-set(vers))
    critical=p.get("critical_route",{})
    priority=isinstance(critical,dict) and critical.get("confirmed") is True and bool(critical.get("evidence_ref"))
    blockers=[]
    if priority: blockers.append("CRITICAL_CONTROL_IMMEDIATE_REPORT")
    if unknown or "pg_proc" not in scopes: blockers.append("INVENTORY_UNKNOWN_OR_PARTIAL")
    if any(v["status"]=="UNKNOWN_NOT_SCANNED" for v in external.values()): blockers.append("EXTERNAL_CONSUMERS_UNKNOWN")
    if perf["status"] in ("NOT_MEASURED","NO_CONCLUYENTE"): blockers.append("PERFORMANCE_NOT_CONCLUSIVE")
    return {"schema":"LF_PROFILE_DEPENDENCY_MEASUREMENT_V1","operation":p["operation_code"],"source_ref":p["source_ref"],
      "temporal_scope":p["temporal_scope"],"hash_method":"md5(prosrc)","hash_equal":equal,"hash_changed":changed,"hash_unknown":unknown,
      "conexiones_exactas":{"declared":edges,"callsite_candidates":call,"text_only":string_only,"without_callsite":missing_edge,
                            "scope":"STATIC_LEXICAL_NOT_EXECUTION"},"edge_evidence":evidence,
      "definicion_leida":readers,"other_consumers":external,"performance":perf,"missing_versions":gaps,
      "critical_priority":priority,"zero_consumers_semantics":"UNKNOWN_UNLESS_SCOPE_AND_EXECUTION_VERIFIED",
      "blocking_codes":blockers,"status":"READ_ONLY_NOT_ADMISSION"}

if __name__=="__main__":
    with open(sys.argv[1],encoding="utf-8") as f:
        print(json.dumps(audit(json.load(f)),indent=2,ensure_ascii=False))

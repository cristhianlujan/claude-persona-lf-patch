"""Candidate: natural-language object identification from authorized LF evidence.

Not a replacement for TARGETED_EVIDENCE_ACQUISITION. This consumer decides
which known, scope-bound source to request next and when disambiguation is
truly unavoidable. No SQL execution or self-certified evidence occurs here.
"""
from __future__ import annotations
from datetime import datetime
from typing import Any, Callable

SCHEMA="PROFILE_ENTITY_LOOKUP_V1"
ACTIONS={"DISCOVER_SOURCES","QUERY_SOURCE","INVESTIGATE_CANDIDATE","ASK_USER",
         "LIMITED_RESPONSE","BLOCKED"}
WINDOWS=("RECENT","HISTORICAL")

def _reply(action: str, code: str, **kw: Any)->dict:
    return {"schema":SCHEMA,"action":action,"code":code,
            "runtime_activation":False,"write_authorized":False,**kw}

def _verified(check:Callable|None,kind:str,rec:dict)->bool:
    if not callable(check):
        return False
    try:
        return check(kind,rec) is True
    except Exception:
        return False

def _describe(row:dict)->str:
    # Only trusted human-readable readback; never ask for an opaque UUID/code.
    timestamp=row.get("occurred_at")
    filename=row.get("file_name")
    name=row.get("label")
    pieces=[]
    if isinstance(timestamp,str) and timestamp.strip():
        try:
            date=datetime.fromisoformat(timestamp.replace("Z","+00:00"))
            pieces.append(date.strftime("%d-%m-%Y a las %H:%M"))
        except ValueError:
            pass
    if isinstance(filename,str) and filename.strip():
        pieces.append("archivo "+filename[:90])
    elif isinstance(name,str) and name.strip():
        pieces.append(name[:90])
    return ", ".join(pieces)

def plan_entity_lookup(task:dict, verify_receipt:Callable[[str,dict],bool]|None=None)->dict:
    """One bounded step; caller executes authorized reads and calls again."""
    if not isinstance(task,dict) or task.get("schema")!=SCHEMA:
        return _reply("BLOCKED","INPUT_INVALID")
    subject=task.get("subject")
    if not isinstance(subject,str) or not subject.strip() or len(subject)>50:
        return _reply("BLOCKED","SUBJECT_INVALID")
    if task.get("access_scope")!="AUTHORIZED_READ_ONLY" or not _verified(verify_receipt,"scope",task):
        return _reply("BLOCKED","SCOPE_NOT_VERIFIED")
    catalog=task.get("catalog")
    if catalog is None or (isinstance(catalog,dict) and catalog.get("state")=="NOT_CHECKED"):
        return _reply("DISCOVER_SOURCES","FIND_AUTHORIZED_SOURCE_BEFORE_ASK",
                      discovery_scope="AUTHORIZED_SCHEMA_AND_BINDINGS_ONLY",
                      user_question=None)
    if not isinstance(catalog,dict) or catalog.get("state") not in ("RESOLVED","NO_SOURCE"):
        return _reply("BLOCKED","CATALOG_INVALID")
    if not _verified(verify_receipt,"catalog",catalog):
        return _reply("BLOCKED","CATALOG_READBACK_NOT_VERIFIED")
    sources=catalog.get("sources",[])
    if not isinstance(sources,list) or len(sources)>12 or any(
        not isinstance(s,dict) or not isinstance(s.get("source_ref"),str) or
        not s["source_ref"] or type(s.get("available")) is not bool
        for s in sources):
        return _reply("BLOCKED","SOURCES_INVALID")
    if len({s["source_ref"] for s in sources})!=len(sources):
        return _reply("BLOCKED","DUPLICATE_SOURCE")
    if catalog["state"]=="NO_SOURCE" or not sources:
        return _fallback(task,"NO_AUTHORIZED_SOURCE_DISCOVERED",
                         "Revisé las fuentes de cargas que puedo consultar aquí, pero no encontré una fuente disponible.")
    asked=task.get("asked_question_ids",[])
    if not isinstance(asked,list) or any(not isinstance(x,str) for x in asked):
        return _reply("BLOCKED","QUESTION_HISTORY_INVALID")
    logs=task.get("lookups",[])
    if not isinstance(logs,list) or len(logs)>24:
        return _reply("BLOCKED","LOOKUPS_INVALID")
    bykey={}
    candidates={}
    for log in logs:
        if not isinstance(log,dict) or log.get("source_ref") not in {s["source_ref"] for s in sources} or log.get("window") not in WINDOWS:
            return _reply("BLOCKED","LOOKUP_OUTSIDE_AUTHORIZED_SOURCE")
        key=(log["source_ref"],log["window"])
        if key in bykey:
            return _reply("BLOCKED","DUPLICATE_LOOKUP")
        if not _verified(verify_receipt,"lookup",log):
            return _reply("BLOCKED","LOOKUP_READBACK_NOT_VERIFIED")
        if log.get("state") not in ("SUCCESS","SOURCE_UNAVAILABLE"):
            return _reply("BLOCKED","LOOKUP_STATUS_INVALID")
        rows=log.get("rows",[])
        if not isinstance(rows,list) or len(rows)>30 or (log["state"]!="SUCCESS" and rows):
            return _reply("BLOCKED","LOOKUP_RECORDS_INVALID")
        for row in rows:
            if (not isinstance(row,dict) or not isinstance(row.get("record_ref"),str) or
                not row["record_ref"] or not isinstance(row.get("source_ref"),str) or
                row["source_ref"]!=log["source_ref"]):
                return _reply("BLOCKED","RECORD_PROVENANCE_INVALID")
            if row["record_ref"] in candidates and row!=candidates[row["record_ref"]]:
                return _reply("BLOCKED","CONFLICTING_RECORD_READBACK")
            candidates[row["record_ref"]]=row
        bykey[key]=log
    # All visible results must already be tenant-scoped by the authorized read.
    # A false scope verification above blocks enumeration altogether.
    if len(candidates)==1:
        only=next(iter(candidates.values()))
        return _reply("INVESTIGATE_CANDIDATE","ONE_PLAUSIBLE_ENTITY",
                      record_ref=only["record_ref"],
                      human_description=_describe(only) or "un registro encontrado",
                      identity_confirmed_by_user=False,
                      required_action="READ_DETAILS_AND_VALIDATE_RELEVANCE",
                      user_question=None)
    if len(candidates)>1:
        rows=sorted(candidates.values(),key=lambda r:str(r.get("occurred_at") or ""),reverse=True)
        if len(rows)<=3 and all(_describe(r) for r in rows):
            descriptions=[_describe(r) for r in rows]
            return _ask(task,"MULTIPLE_PLAUSIBLE_ENTITIES",
                 "Encontré varias "+subject+" que podrían ser. ¿Te refieres a la del "+
                 ", a la del ".join(descriptions)+"?",
                 visible_options=descriptions)
        return _ask(task,"MANY_PLAUSIBLE_ENTITIES",
              "Encontré varias "+subject+" en este entorno. ¿Recuerdas aproximadamente cuándo la subiste o el nombre del archivo?")
    # Do not ask yet: query current then historical scope in authorized sources.
    for window in WINDOWS:
        for source in sources:
            if not source["available"]:
                continue
            key=(source["source_ref"],window)
            if key not in bykey:
                return _reply("QUERY_SOURCE","CHECK_"+window+"_BEFORE_ASK",
                     source_ref=source["source_ref"],window=window,
                     user_question=None,execution_performed=False)
            if bykey[key]["state"]=="SOURCE_UNAVAILABLE":
                # Try alternative bound sources; never pretend unavailable == no rows.
                continue
    if (any(log["state"]=="SOURCE_UNAVAILABLE" for log in bykey.values()) and
        not candidates and all((s["source_ref"],w) in bykey or not s["available"]
                               for s in sources for w in WINDOWS)):
        return _reply("LIMITED_RESPONSE","PARTIAL_OR_UNAVAILABLE_SOURCE",
                      message="No encontré una carga identificable en las fuentes que respondieron; otras consultas no estuvieron disponibles. No puedo descartar que exista en el sistema.",
                      user_question=None)
    if all(not s["available"] for s in sources) or (
       bykey and all(log["state"]=="SOURCE_UNAVAILABLE" for log in bykey.values())):
        return _reply("LIMITED_RESPONSE","AUTHORIZED_SOURCE_UNAVAILABLE",
                      message="No puedo consultar las cargas desde este entorno; la fuente no está disponible. No corresponde pedir un código ni atribuir una causa.",
                      user_question=None)
    return _fallback(task,"NO_MATCH_AFTER_RECENT_AND_HISTORICAL_READBACK",
                     "Busqué cargas recientes e históricas en las fuentes autorizadas de este entorno y no encontré registros que pueda vincular con lo que describes.")

def _ask(task:dict,code:str,question:str,**other)->dict:
    if "entity_location" in task.get("asked_question_ids",[]):
        return _reply("LIMITED_RESPONSE","CLARIFICATION_ALREADY_REQUESTED",
                      user_question=None,reason=code)
    return _reply("ASK_USER",code,user_question=question,question_id="entity_location",**other)

def _fallback(task:dict,code:str,statement:str)->dict:
    return _ask(task,code,
      statement+" ¿En qué pantalla o aplicación la subiste y aproximadamente cuándo?")

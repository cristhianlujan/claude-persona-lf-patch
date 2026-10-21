#!/usr/bin/env python3
"""Two operation paths, literal-vs-call and definition read, negative evidence."""
import hashlib,importlib.util
from pathlib import Path
src=Path(__file__).resolve().parents[1]/"validators"/"measure_dependencies_v1.py"
spec=importlib.util.spec_from_file_location("audit",src); m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
one="select programacion.fn_target_v1(1); -- fn_old_v1(4)\nselect 'fn_old_v1(8)';"
two="declare v_sig regprocedure:='programacion.fn_target_v1(integer)'::regprocedure; begin v_def:=pg_get_functiondef(v_sig); end;"
for operation in ("CREACION_PERFIL_LF","ACTUALIZACION_PERFIL_LF"):
 p={"operation_code":operation,"source_ref":"supabase://test","temporal_scope":"CURRENT","scopes_scanned":["pg_proc"],
    "historical_callers":[{"caller":"programacion.caller","callees":["fn_target_v1","fn_old_v1"],"definition_md5":hashlib.md5(one.encode()).hexdigest()}],
    "live_functions":[{"caller":"programacion.caller","prosrc":one},{"caller":"programacion.reader","prosrc":two}]}
 o=m.audit(p)
 assert o["hash_equal"]==1
 assert o["conexiones_exactas"]["callsite_candidates"]==1
 assert o["conexiones_exactas"]["text_only"]==1
 assert len(o["definicion_leida"])==1 and o["definicion_leida"][0]["execution_verified"] is False
 assert o["other_consumers"]["cron"]["status"]=="UNKNOWN_NOT_SCANNED"
 p["historical_callers"][0]["definition_md5"]="0"*32
 assert m.audit(p)["hash_changed"]==1
p["scopes_scanned"]=["pg_proc","pg_trigger","cron.job","pg_rewrite"]
p["triggers"]=[{"id":1}];p["cron"]=[{"id":45}];p["views"]=[]
p["performance"]={"total_runs":10,"runs":[{"duration_ms":100},{"failed":True,"duration_ms":300}]}
p["versions"]=[2,3,5]
p["critical_route"]={"confirmed":True,"evidence_ref":"receipt://router"}
o=m.audit(p)
assert o["missing_versions"]==[4]
assert o["critical_priority"]
assert o["performance"]["status"]=="NO_CONCLUYENTE" and o["performance"]["failures_with_time"]==1
assert o["other_consumers"]["views"]["count"]==0
p["performance"]["runs"]=[{"duration_ms":12}]*8
assert m.audit(p)["performance"]["status"]=="MUESTRA_SIN_CAUSALIDAD"
assert "fn_target_v1" not in m.code_only("'fn_target_v1(1)' -- fn_target_v1(4)")
print("PASS: SOURCE_DEPENDENCY_MEASUREMENT both operations, positive/negative")

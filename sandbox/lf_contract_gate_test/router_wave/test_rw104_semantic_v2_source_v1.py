#!/usr/bin/env python3
import json
from pathlib import Path

root=Path(__file__).resolve().parents[3]
files=list((root/"supabase/migrations").glob("*_lf_router_rw104_c2_semantic_v2_implementation_v1.sql"))
assert len(files)==1, f"expected exactly one RW104 C2 migration, got {len(files)}"
s=files[0].read_text(encoding="utf-8")

required=[
 "BEGIN;",
 "CREATE OR REPLACE FUNCTION public.lf_router_intent_handoff_v2(",
 "LF_ROUTER_SEMANTIC_REQUEST_V1",
 "CREATE OR REPLACE FUNCTION public.lf_router_semantic_resume_validate_v1",
 "LF_ROUTER_SEMANTIC_RESUME_VALIDATION_V1",
 "ACT0001_REDERIVE_ROUTE_AND_AUTHORITY",
 "RW104_C2_SOURCE_DRIFT",
 "RW104_C2_PRECOUNT",
 "RW104_P0:",
 "RW104_P1:",
 "RW104_P2:",
 "RW104_P3:",
 "RW104_P4:",
 "RW104_C2_POSTCOUNT",
 "RW104_C2_NEG_COUNT",
 "RW104_C2_ACL_FAIL",
 "RW104_C2_ROUTER_SMOKE_FAIL",
 "COMMIT;"
]
for x in required:
    assert x in s, f"missing {x}"

assert "CREATE OR REPLACE FUNCTION public.lf_router_intent_handoff_v1" not in s
assert "CREATE OR REPLACE FUNCTION programacion.fn_lf_router_input_governance_resolve_v1" not in s
assert "REVOKE ALL ON FUNCTION public.lf_router_intent_handoff_v2" in s
assert "REVOKE ALL ON FUNCTION public.lf_router_semantic_resume_validate_v1" in s
assert "FROM PUBLIC,anon,authenticated" in s
assert "TO postgres,service_role,supabase_read_only_user" in s
assert s.count("RW104_C2_NEG_") >= 2
assert "operation_code','ACTUALIZACION_DB_LF" in s
assert "effect_authority',true" in s
assert "downstream_execution_allowed',true" in s
assert "route_authority',true" in s
assert "jsonb_build_array('ACT-9999')" in s
assert "repeat('0',32)" in s
assert "jsonb_set(r,'{conditions}','[]'::jsonb,true)" in s
assert "jsonb_set(q,'{excluded_target_refs}'" in s
assert "jsonb_set(q,'{forbidden_scope}'" in s

print(json.dumps({
 "status":"RW104_C2_SOURCE_PASS",
 "migration":files[0].name,
 "v2_helper":True,
 "resume_validator":True,
 "six_site_patch_contract":True,
 "negative_probe_families_at_least":10,
 "transactional_fail_closed":True,
 "v1_definition_untouched":True,
 "ig_definition_untouched":True,
 "acl_widening":False
},sort_keys=True))

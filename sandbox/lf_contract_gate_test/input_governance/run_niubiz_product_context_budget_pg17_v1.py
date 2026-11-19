#!/usr/bin/env python3
"""Real PG17: Product-context 265/275 direct rules → SHA/lazy, never lift hard gate.

The schema/data are strictly SYNTHETIC. All changes under BEGIN/ROLLBACK,
followed by a fresh, independent SELECT against the same ephemeral PostgreSQL.
This does not assert Niubiz sandbox acceptance or create LF rules.
"""
from pathlib import Path
import hashlib
import json
import os
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[3]
MIG=ROOT/"supabase/migrations/20261119001500_lf_product_context_canonical_rules_lazy_digest_v1.sql"
OUT=ROOT/".lf_ci/niubiz_product_context_budget_pg17"
DB="ig_niubiz_context_pg17"

def ensure(cond,label):
    if not cond: raise AssertionError(label)

def pg(sql,database=DB):
    return subprocess.run(
        ["psql","-X","-v","ON_ERROR_STOP=1","-A","-t",
         "-h","127.0.0.1","-p","5432","-U","postgres","-d",database,"-f","-"],
        input=sql,text=True,capture_output=True,env=os.environ.copy(),timeout=120,
        check=False,
    )

def good(sql,label,database=DB):
    r=pg(sql,database)
    ensure(r.returncode==0,label+": "+r.stderr[-1600:])
    return r

def main():
    OUT.mkdir(parents=True,exist_ok=True)
    migration=MIG.read_text(encoding="utf-8")
    begin=migration.index("CREATE OR REPLACE FUNCTION public.lf_profile_execution_channel_context_v1")
    end=migration.index("\nDO $context_post$",begin)
    function_sql=migration[begin:end].strip()
    ensure("CANONICAL_RULES_DIGEST_LAZY_V1" in function_sql,"COMPACT_BRANCH_MISSING")
    ensure("BLOCK_PRODUCT_CHANNEL_CONTEXT_BUDGET_RED" in function_sql,"HARD_GATE_REMOVED")
    ensure("when v_tokens>v_hard then 'RED'" in function_sql,"HARD_BOUND_REMOVED")
    ensure("readback_currentness_required" in function_sql,"CURRENTNESS_MARKER_MISSING")
    ensure("extensions.digest(convert_to((v_pc->'direct_rules')::text" in function_sql,
           "DIRECT_RULES_DIGEST_MISSING")
    ensure("460a9e7f9339f6387175983d404c5808" in migration,
           "EXACT_FUNCTION_PREIMAGE_GUARD_MISSING")
    ensure("PRODUCT_CONTEXT_UNRELATED_RULE_OR_CONFIG_MUTATION" in migration,
           "CANONICAL_DATA_GUARD_MISSING")
    ensure("'lf.ig_ctx_pre_rules_md5'" in migration and "'lf.ig_ctx_pre_config_md5'" in migration,
           "POSTGRESQL_TRANSACTION_LOCAL_GUC_NAMESPACED_REQUIRED")
    ensure(migration.count("CREATE OR REPLACE FUNCTION")==1,"UNEXPECTED_FUNCTION_MUTATION")
    ensure("ALTER ROLE" not in migration.upper() and "GRANT " not in migration.upper()
           and "ALTER POLICY" not in migration.upper(),"AUTHORITY_CHANGE_FORBIDDEN")

    good("CREATE DATABASE "+DB+";","CREATE_EPHEMERAL_DB_FAILED","postgres")
    schema=r"""
CREATE SCHEMA extensions;
CREATE EXTENSION pgcrypto WITH SCHEMA extensions;
CREATE SCHEMA lf_ops;
CREATE SCHEMA private;
CREATE TABLE public.lf_global_config(
 scope text NOT NULL,config_key text NOT NULL,config_value text,
 value_status text NOT NULL,PRIMARY KEY(scope,config_key));
CREATE TABLE lf_ops.modulos(module_code text PRIMARY KEY,app_shell_code text);
CREATE TABLE lf_ops.pantallas(
 id integer PRIMARY KEY,codigo text UNIQUE,nombre text,estado text,version text,
 module_code text,activa boolean DEFAULT TRUE);
CREATE TABLE lf_ops.reglas(
 id integer PRIMARY KEY,codigo text UNIQUE,titulo text,estado text,categoria text);
CREATE TABLE lf_ops.reglas_pantallas(pantalla_id integer,regla_id integer);
CREATE TABLE public.lf_operation_execution(
 execution_id text PRIMARY KEY,operation_code text,status text,manifest jsonb);
CREATE TABLE public.lf_eventos(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 evento_tipo text,entidad_tipo text,entidad_codigo text,descripcion text,
 severidad text,payload jsonb,origen text,created_by_execution_id text);
CREATE TABLE private.lf_context_budget_events_v2(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 execution_id text,estimated_tokens bigint,context_status text,source text,
 recommendation text,evidence_event_id bigint);
CREATE OR REPLACE FUNCTION public.lf_router_profile_execution_handoff_validate_v1(
 p_handoff jsonb,p_literal text,p_profile_code text) RETURNS jsonb
 LANGUAGE sql STABLE AS $$
 SELECT jsonb_build_object('valid',p_handoff->>'profile_code'='PERFIL-PRODUCT-DIRECTOR-LF'
    AND p_literal IS NOT NULL AND p_handoff->>'channel'='PRODUCTO') $$;
CREATE OR REPLACE FUNCTION public.lf_profile_screen_selector_semantic_prepare_v1(
 p_literal text,p_scope jsonb) RETURNS jsonb LANGUAGE sql STABLE
 AS $$ SELECT jsonb_build_object('status','READY') $$;
CREATE OR REPLACE FUNCTION public.lf_profile_screen_selector_semantic_validate_v1(
 p_request jsonb,p_result jsonb) RETURNS jsonb LANGUAGE sql STABLE
 AS $$ SELECT jsonb_build_object('status',
   CASE WHEN p_result->>'decision'='SELECTED'
     AND p_result->>'selected_screen_code' IN ('SCREEN-A','SCREEN-B','SCREEN-C','SCREEN-SMALL')
   THEN 'VALID' ELSE 'BLOCKED' END) $$;
CREATE OR REPLACE FUNCTION public.lf_router_product_context_v1(
 p_literal text,p_scope jsonb) RETURNS jsonb LANGUAGE sql STABLE
 AS $$ SELECT '{"status":"BLOCKED"}'::jsonb $$;
CREATE OR REPLACE FUNCTION lf_ops.fn_screen_contract_v1(
 p_shell text,p_module text,p_screen text) RETURNS TABLE(contract jsonb)
 LANGUAGE sql STABLE AS $$
 SELECT jsonb_build_object('rules',to_jsonb(ARRAY(
   SELECT generate_series(1,310)))) $$;
INSERT INTO public.lf_global_config(scope,config_key,config_value,value_status)
VALUES ('PAGOS','NIUBIZ_EMAIL_TEMPLATE','SYNTHETIC_TEMPLATE','REAL'),
       ('PAGOS','NIUBIZ_EMAIL_DOMAIN','synthetic.invalid','REAL');
INSERT INTO lf_ops.modulos(module_code,app_shell_code)
VALUES ('CLIENT_PAYMENTS','CLIENT_APP_SHELL');
INSERT INTO lf_ops.pantallas(id,codigo,nombre,estado,version,module_code)
VALUES
(30,'SCREEN-A','Tarjeta Niubiz','CANDIDATO','v0.2','CLIENT_PAYMENTS'),
(33,'SCREEN-B','Pago confirmado','CANDIDATO','v0.3','CLIENT_PAYMENTS'),
(27,'SCREEN-C','Confirmando resultado','CANDIDATO','v0.2','CLIENT_PAYMENTS'),
(99,'SCREEN-SMALL','Caso normal','CANDIDATO','v0.2','CLIENT_PAYMENTS');
INSERT INTO lf_ops.reglas(id,codigo,titulo,estado,categoria)
SELECT i,'REG-TEST-'||lpad(i::text,3,'0'),
       'Regla contractual ejemplo número '||i,'VIGENTE','PAGO'
FROM generate_series(1,275) i;
INSERT INTO lf_ops.reglas_pantallas(pantalla_id,regla_id)
SELECT 30,i FROM generate_series(1,265) i
UNION ALL SELECT 33,i FROM generate_series(1,275) i
UNION ALL SELECT 27,i FROM generate_series(1,265) i
UNION ALL SELECT 99,1;
INSERT INTO public.lf_operation_execution(execution_id,operation_code,status,manifest)
VALUES
('RUN-A','EJECUCION_PERFIL_LF','IN_PROGRESS',
 '{"screen_selection_result":{"decision":"SELECTED","selected_screen_code":"SCREEN-A"}}'),
('RUN-B','EJECUCION_PERFIL_LF','IN_PROGRESS',
 '{"screen_selection_result":{"decision":"SELECTED","selected_screen_code":"SCREEN-B"}}'),
('RUN-C','EJECUCION_PERFIL_LF','IN_PROGRESS',
 '{"screen_selection_result":{"decision":"SELECTED","selected_screen_code":"SCREEN-C"}}'),
('RUN-SMALL','EJECUCION_PERFIL_LF','IN_PROGRESS',
 '{"screen_selection_result":{"decision":"SELECTED","selected_screen_code":"SCREEN-SMALL"}}'),
('RUN-MISSING','EJECUCION_PERFIL_LF','IN_PROGRESS','{}');
"""
    good(schema,"SYNTHETIC_FIXTURES_SETUP_FAILED")
    before_sql="""SELECT jsonb_build_object(
    'rules',(SELECT count(*) FROM lf_ops.reglas),
    'links',(SELECT count(*) FROM lf_ops.reglas_pantallas),
    'config',(SELECT count(*) FROM public.lf_global_config),
    'events',(SELECT count(*) FROM public.lf_eventos),
    'budget_events',(SELECT count(*) FROM private.lf_context_budget_events_v2),
    'function',(to_regprocedure('public.lf_profile_execution_channel_context_v1(text,jsonb,jsonb)') IS NOT NULL)
)::text;"""
    before=good(before_sql,"READ_PREIMAGE").stdout.strip()
    ensure(json.loads(before)=={"rules":275,"links":806,"config":2,
        "events":0,"budget_events":0,"function":False},"PREIMAGE_WRONG "+before)
    tests=r"""
DO $test$
DECLARE v jsonb; pc jsonb; b jsonb; h jsonb;
        direct_hash text; run_id text; screen_id integer; expected_count integer;
BEGIN
 b:=jsonb_build_object(
   'context_capsule',jsonb_build_object('base_set','TRANSVERSAL_BASE_SET_V1',
                                      'lazy_refs',jsonb_build_array('supabase://source')),
   'soft_limit_tokens',1500,'hard_limit_tokens',3000
 );
 FOR run_id,screen_id,expected_count IN
   SELECT * FROM (VALUES ('RUN-A',30,265),('RUN-B',33,275),('RUN-C',27,265)) v
 LOOP
   h:=jsonb_build_object(
     'profile_code','PERFIL-PRODUCT-DIRECTOR-LF',
     'channel','PRODUCTO','literal_request','Niubiz checkout synthetic case',
     'scope',jsonb_build_object('target_type','PANTALLA','target_hint',
       CASE screen_id WHEN 30 THEN 'SCREEN-A'
                       WHEN 33 THEN 'SCREEN-B' ELSE 'SCREEN-C' END),
     'semantic_request',jsonb_build_object('router_action_binding',
       jsonb_build_object('profile_task_intent','CREATE_OR_CORRECT_RULE',
          'input_governance_requirement','REQUIRED_BY_TASK'))
   );
   v:=public.lf_profile_execution_channel_context_v1(run_id,b,h);
   IF v->>'status' IS DISTINCT FROM 'READY'
     OR v->>'context_budget_status'='RED'
     OR (v->>'context_capsule_estimated_tokens')::integer>3000
   THEN RAISE EXCEPTION 'CONTEXT_265_275_NOT_READY: %',v; END IF;
   pc:=v#>'{context_capsule,channel_context,product_context}';
   IF pc->>'projection_mode'<>'CANONICAL_RULES_DIGEST_LAZY_V1'
     OR pc ? 'direct_rules'
     OR pc->>'direct_rules_materialized'<>'false'
     OR pc->>'full_context_requires_lazy_read'<>'true'
     OR pc->>'readback_currentness_required'<>'true'
     OR (pc->>'direct_rule_count')::integer<>expected_count
     OR (pc->>'snapshot_direct_rule_count')::integer<>expected_count
     OR (pc->>'effective_rule_count')::integer<>310
     OR pc->>'snapshot_effective_rule_count'<>'310'
     OR pc->>'direct_rules_ref'<>('supabase://lf_ops.reglas_pantallas/'||
        CASE screen_id WHEN 30 THEN 'SCREEN-A' WHEN 33 THEN 'SCREEN-B' ELSE 'SCREEN-C' END)
     OR pc->>'effective_rules_ref'<>('supabase://lf_ops.fn_screen_contract_v1/CLIENT_APP_SHELL/CLIENT_PAYMENTS/'||
        CASE screen_id WHEN 30 THEN 'SCREEN-A' WHEN 33 THEN 'SCREEN-B' ELSE 'SCREEN-C' END||'#rules')
     OR pc->>'canonical_read_snapshot_sha256' !~ '^sha256:[0-9a-f]{64}$'
   THEN RAISE EXCEPTION 'CANONICAL_SOURCE_OR_COUNT_LOST: %',pc; END IF;
   SELECT 'sha256:'||encode(extensions.digest(convert_to(
     (coalesce(jsonb_agg(jsonb_build_array(r.codigo,r.titulo,r.estado)
       ORDER BY r.categoria,r.codigo),'[]'::jsonb))::text,'UTF8'),'sha256'),'hex')
   INTO direct_hash FROM lf_ops.reglas r
   JOIN lf_ops.reglas_pantallas rp ON rp.regla_id=r.id
   WHERE rp.pantalla_id=screen_id;
   IF pc->>'direct_rules_snapshot_sha256' IS DISTINCT FROM direct_hash
   THEN RAISE EXCEPTION 'SOURCE_BOUND_DIRECT_HASH_MISMATCH'; END IF;
 END LOOP;
 RAISE NOTICE 'IG_NIUBIZ_CANONICAL_3_SCREENS_265_275_PASS';
 RAISE NOTICE 'IG_NIUBIZ_RULE_COUNTS_AND_SOURCE_REFS_PRESERVED_PASS';
 RAISE NOTICE 'IG_NIUBIZ_SHA256_MATCHES_INDEPENDENT_RULE_SELECT_PASS';

 h:=jsonb_build_object(
  'profile_code','PERFIL-PRODUCT-DIRECTOR-LF',
  'channel','PRODUCTO','literal_request','small synthetic',
  'scope',jsonb_build_object('target_type','PANTALLA','target_hint','SCREEN-SMALL'),
  'semantic_request',jsonb_build_object('router_action_binding',
    jsonb_build_object('profile_task_intent','CREATE_OR_CORRECT_RULE',
     'input_governance_requirement','REQUIRED_BY_TASK'))
 );
 v:=public.lf_profile_execution_channel_context_v1('RUN-SMALL',b,h);
 pc:=v#>'{context_capsule,channel_context,product_context}';
 IF v->>'status' <> 'READY' OR pc->>'projection_mode'<>'COMPACT_DIRECT_RULES_EFFECTIVE_AGGREGATE_LAZY'
    OR jsonb_array_length(pc->'direct_rules')<>1
 THEN RAISE EXCEPTION 'SMALL_UNCHANGED_CANONICAL_READ_INVALID: %',v; END IF;
 RAISE NOTICE 'IG_NIUBIZ_SMALL_CANONICAL_RULES_STAY_MATERIALIZED_PASS';

 v:=public.lf_profile_execution_channel_context_v1('RUN-SMALL',
   jsonb_set(b,'{context_capsule}',jsonb_build_object('oversized_unrelated_input',repeat('B',30000)),true),h);
 IF v->>'status'<>'BLOCKED' OR v->>'blocking_code'<>'BLOCK_PRODUCT_CHANNEL_CONTEXT_BUDGET_RED'
 THEN RAISE EXCEPTION 'BUDGET_HARD_GATE_RELAXED: %',v; END IF;
 RAISE NOTICE 'IG_NIUBIZ_OVERSIZED_BASE_CONTEXT_STILL_BLOCKS_PASS';

 v:=public.lf_profile_execution_channel_context_v1('RUN-SMALL',b,
   h-'profile_code');
 IF v->>'blocking_code'<>'BLOCK_CHANNEL_CONTEXT_HANDOFF_INVALID'
 THEN RAISE EXCEPTION 'INVALID_HANDOFF_NOT_BLOCKED: %',v; END IF;
 RAISE NOTICE 'IG_NIUBIZ_INVALID_HANDOFF_BLOCKS_PASS';

 v:=public.lf_profile_execution_channel_context_v1('RUN-MISSING',b,h);
 IF v->>'blocking_code'<>'BLOCK_PRODUCT_CHANNEL_CONTEXT_SCREEN_SELECTION_MISSING'
 THEN RAISE EXCEPTION 'MISSING_SCREEN_SELECTION_NOT_BLOCKED: %',v; END IF;
 RAISE NOTICE 'IG_NIUBIZ_MISSING_SCREEN_RECEIPT_BLOCKS_PASS';

 UPDATE public.lf_operation_execution
 SET manifest='{"screen_selection_result":{"decision":"NO_MATCH"}}'::jsonb
 WHERE execution_id='RUN-MISSING';
 v:=public.lf_profile_execution_channel_context_v1('RUN-MISSING',b,h);
 IF v->>'blocking_code'<>'BLOCK_PRODUCT_CHANNEL_CONTEXT_SCREEN_SELECTION_INVALID'
 THEN RAISE EXCEPTION 'BAD_SCREEN_SELECTION_NOT_BLOCKED: %',v; END IF;
 RAISE NOTICE 'IG_NIUBIZ_INVALID_SCREEN_RECEIPT_BLOCKS_PASS';

 IF (SELECT count(*) FROM public.lf_eventos)<>4
    OR (SELECT count(*) FROM private.lf_context_budget_events_v2)<>4
 THEN RAISE EXCEPTION 'SUCCESSFUL_CONTEXT_EVENTS_MISSING'; END IF;
 RAISE NOTICE 'IG_NIUBIZ_ONLY_FOUR_VALID_CONTEXT_EVENTS_PASS';

 PERFORM set_config('lf.ig_ctx_pre_rules_md5','synthetic_session_hash',true);
 PERFORM set_config('lf.ig_ctx_pre_config_md5','synthetic_config_hash',true);
 IF current_setting('lf.ig_ctx_pre_rules_md5')<>'synthetic_session_hash'
    OR current_setting('lf.ig_ctx_pre_config_md5')<>'synthetic_config_hash'
 THEN RAISE EXCEPTION 'NAMESPACED_GUC_PREPOST_INCOMPATIBLE'; END IF;
 RAISE NOTICE 'IG_NIUBIZ_TRANSACTION_LOCAL_HASH_GUC_PASS';
END $test$;
"""
    r=pg("BEGIN;\n"+function_sql+"\n"+tests+"\nROLLBACK;\n")
    combined=r.stdout+"\n"+r.stderr
    (OUT/"transaction.log").write_text(combined,encoding="utf-8")
    tags=[
      "IG_NIUBIZ_CANONICAL_3_SCREENS_265_275_PASS",
      "IG_NIUBIZ_RULE_COUNTS_AND_SOURCE_REFS_PRESERVED_PASS",
      "IG_NIUBIZ_SHA256_MATCHES_INDEPENDENT_RULE_SELECT_PASS",
      "IG_NIUBIZ_SMALL_CANONICAL_RULES_STAY_MATERIALIZED_PASS",
      "IG_NIUBIZ_OVERSIZED_BASE_CONTEXT_STILL_BLOCKS_PASS",
      "IG_NIUBIZ_INVALID_HANDOFF_BLOCKS_PASS",
      "IG_NIUBIZ_MISSING_SCREEN_RECEIPT_BLOCKS_PASS",
      "IG_NIUBIZ_INVALID_SCREEN_RECEIPT_BLOCKS_PASS",
      "IG_NIUBIZ_ONLY_FOUR_VALID_CONTEXT_EVENTS_PASS",
      "IG_NIUBIZ_TRANSACTION_LOCAL_HASH_GUC_PASS",
    ]
    result={"status":"FAIL","tests":{t:t in combined for t in tags},
            "transaction_exit":r.returncode,
            "transaction_sha256":hashlib.sha256(combined.encode()).hexdigest(),
            "migration_source_sha256":hashlib.sha256(migration.encode()).hexdigest(),
            "pg17_real":True,"fixture":"SYNTHETIC_ONLY",
            "remote_supabase_written":False,"niubiz_sandbox_hyphen":"NOT_TESTED",
            "owner_v2_decisions":0,"function_change":"ONLY_EPHEMERAL_ROLLBACK"}
    after=good(before_sql,"INDEPENDENT_SELECT_AFTER_ROLLBACK").stdout.strip()
    result["preimage"]=json.loads(before)
    result["independent_readback"]=json.loads(after)
    result["readback_sha256"]=hashlib.sha256(after.encode()).hexdigest()
    ensure(r.returncode==0 and all(result["tests"].values()),
           "PG17_TESTS_FAILED "+combined[-2500:])
    ensure(before==after,"ROLLBACK_DIRTY "+before+" -> "+after)
    result["status"]="PASS"
    (OUT/"report.json").write_text(json.dumps(result,indent=2,sort_keys=True)+"\n",
                                   encoding="utf-8")
    print("IG_NIUBIZ_PRODUCT_CONTEXT_REAL_PG17_10_OF_10_PASS")
    return 0

if __name__=="__main__":
    try: sys.exit(main())
    except Exception as exc:
        print("IG_NIUBIZ_PRODUCT_CONTEXT_PG17_BLOCKED "+str(exc)[:2500],file=sys.stderr)
        sys.exit(1)

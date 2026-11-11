#!/usr/bin/env python3
"""Isolated PG17: 578 governed rule children, 56 screen hashes, atomic rollback."""
import json, os, subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
PARENT="EXEC-PROFILE-GATE2-PG17RULECHILD001"
BATCH="LF-OWNER-BULK-PG17-578"
DB="lf_bulk_atomic_pg17"
N=0
FILES=[
"sandbox/lf_contract_gate_test/db_write_transport/lf_rule_child_pg17_original_source_fixture_v1.sql",
"sandbox/lf_contract_gate_test/db_write_transport/lf_rule_child_pg17_seed_v1.sql",
"supabase/migrations/20261109092529_lf_profile_rule_update_child_execution_v1.sql",
"supabase/migrations/20261111080000_lf_rule_update_history_evidence_v1.sql",
"supabase/migrations/20261111100000_lf_rule_update_general_admin_functional_v1.sql",
"sandbox/lf_contract_gate_test/rule_update_bulk_v1/lf_rule_update_handler_live_source_fixture.sql",
"sandbox/lf_contract_gate_test/rule_update_bulk_v1/lf_rule_child_readback_live_source_fixture.sql",
"supabase/migrations/20261111115000_lf_rule_update_child_readback_state_aware_v1.sql",
"supabase/migrations/20261111123500_lf_rule_owner_bulk_atomic_governed_v1.sql",
"sandbox/lf_contract_gate_test/rule_update_bulk_v1/lf_skill_invoke_current_live_source_fixture.sql"
]
def sql(s,db=DB,fail=False):
    env=dict(os.environ);env.setdefault("PGHOST","127.0.0.1");env.setdefault("PGUSER","postgres")
    p=subprocess.run(["psql","-X","-q","-A","-t","-v","ON_ERROR_STOP=1","-d",db],
                     env=env,input=s,text=True,capture_output=True,timeout=300)
    if fail:
        if p.returncode==0:raise AssertionError("EXPECTED_FAILURE_MISSING")
        return p.stderr
    if p.returncode:raise AssertionError("PG17_SQL_ERROR:"+p.stderr[-2200:])
    return p.stdout.strip()
def check(name,condition):
    global N
    if not condition:raise AssertionError("BLOCK_"+name)
    N+=1;print("PASS_"+name,flush=True)
def one(s):
    return sql("SELECT "+s+";")
def load():
    for path in FILES:check("EXISTS_"+Path(path).stem.upper(),(ROOT/path).is_file())
    sql("CREATE DATABASE "+DB+";",db="postgres")
    for i,path in enumerate(FILES):
        content=(ROOT/path).read_text(encoding="utf-8")
        if i==4:content="SET lf.rule_update_governance_execution_id='"+PARENT+"';\n"+content
        sql(content)
    check("OFFICIAL_BATCH_INSTALLED",
          one("to_regprocedure('public.lf_rule_admin_bulk_atomic_v1(text,text)') IS NOT NULL")=="t")
    check("BULK_DENIED_TO_ANON",
          one("has_function_privilege('anon','public.lf_rule_admin_bulk_atomic_v1(text,text)','EXECUTE')")=="f")
def seed_all():
    sql(r"""
UPDATE lf_ops.reglas SET estado='VIGENTE' WHERE id=435;
INSERT INTO lf_ops.reglas(id,codigo,categoria,titulo,descripcion,razon,valor_config,
  es_transversal,estado,origen,pendiente_decision,pendiente_detalle,created_by)
SELECT id,'TEST-BULK-RULE-'||lpad((id-435)::text,4,'0'),
 'SECURITY','Titulo de prueba gobernada','Descripcion original protegida',
 'Justificacion original protegida','{"base":true}'::jsonb,false,
 CASE WHEN id<=846 THEN 'VIGENTE' ELSE 'CANDIDATO' END,
 'ISOLATED_PG17',true,'PENDING','ORIGINAL_ACTOR'
FROM generate_series(436,1012) AS id;
INSERT INTO lf_ops.pantallas(id,codigo,nombre,estado,activa,version)
SELECT id,'TEST-BULK-SCREEN-'||lpad((id-51)::text,3,'0'),'Pantalla',
  'CANDIDATO',true,'v1' FROM generate_series(52,106) id;
INSERT INTO lf_ops.reglas_pantallas(regla_id,pantalla_id,nota)
SELECT 436+(g/56)::int,51+(g%56),'ISOLATED_ONLY'
FROM generate_series(0,6174) g;
INSERT INTO public.lf_operation_execution_steps(
 execution_id,step_order,step_id,status,evidence_ref,evidence_payload)
VALUES('EXEC-PROFILE-GATE2-PG17RULECHILD001',40,'input_validate',
 'STEP_PASS_WITH_EVIDENCE','SYNTHETIC-PG17-NOT-REAL',
 jsonb_build_object('scope_authority_packet_sha256','sha256:'||repeat('a',64)));
""")
    # Only a synthetic source ledger in isolated PG17. Never mock CURRENTNESS
    # as PASS; the production code must return a post-cut verification obligation.
    sql(r"""
CREATE SCHEMA IF NOT EXISTS programacion;
CREATE TABLE programacion.input_readiness_runs(
 id bigint PRIMARY KEY,pantalla_id integer,status text,
 invalidated_at timestamptz,supersedes_run_id bigint,source_manifest jsonb
);
INSERT INTO programacion.input_readiness_runs VALUES
(929,58,'COMPLETED',NULL,NULL,
 '[{"ref":{"kind":"RULE","codigo":"TEST-BULK-RULE-0001"}}]'::jsonb),
(930,58,'COMPLETED',NULL,929,
 '[{"ref":{"kind":"RULE","codigo":"TEST-BULK-RULE-0001"}},{"ref":{"kind":"RULE","codigo":"TEST-BULK-RULE-0002"}},{"ref":{"kind":"RULE","codigo":"TEST-BULK-RULE-0003"}},{"ref":{"kind":"SCREEN_CANONICAL_GRAPH"}}]'::jsonb),
(931,59,'COMPLETED',NULL,NULL,
 '[{"ref":{"kind":"SCREEN_CANONICAL_GRAPH"}}]'::jsonb),
(932,60,'COMPLETED',NULL,NULL,
 '[{"ref":{"kind":"SCREEN_CANONICAL_GRAPH"}}]'::jsonb),
(944,61,'COMPLETED',NULL,NULL,
 '[{"ref":{"kind":"SCREEN_CANONICAL_GRAPH"}}]'::jsonb),
(951,62,'COMPLETED',NULL,NULL,
 '[{"ref":{"kind":"SCREEN_CANONICAL_GRAPH"}}]'::jsonb),
(910,58,'BLOCKED',NULL,NULL,
 '[{"ref":{"kind":"RULE","codigo":"MISSING"}}]'::jsonb),
(911,58,'COMPLETED','2026-11-01T00:00:00Z',NULL,
 '[{"ref":{"kind":"RULE","codigo":"MISSING"}}]'::jsonb);
""")
    check("578_RULES",
          one("(SELECT count(*) FROM lf_ops.reglas)=578")=="t")
    check("412_VIGENTE",
          one("(SELECT count(*) FROM lf_ops.reglas WHERE estado='VIGENTE')=412")=="t")
    check("56_SCREENS",
          one("(SELECT count(*) FROM lf_ops.pantallas)=56")=="t")
    check("6176_LINKS",
          one("(SELECT count(*) FROM lf_ops.reglas_pantallas)=6176")=="t")
    scoped=r"""
WITH ru AS(
 SELECT id,codigo,encode(extensions.digest(convert_to(
 (to_jsonb(r)-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') sha
 FROM lf_ops.reglas r
), sc AS(
 SELECT p.id,p.codigo,public.lf_asset_snapshot_sha_v1('PANTALLA',p.codigo) sha
 FROM lf_ops.pantallas p WHERE EXISTS(
 SELECT 1 FROM lf_ops.reglas_pantallas rp WHERE rp.pantalla_id=p.id)
), batch AS(
 SELECT jsonb_build_object(
 'batch_id','LF-OWNER-BULK-PG17-578','scope','ALL_CANONICAL_RULES',
 'operation_code','ACTUALIZACION_REGLA_LF','change_kind','ADMINISTRATIVE_ONLY',
 'changes',jsonb_build_object('owner_name','SUPER_ADMIN','created_by','ChatGPT'),
 'expected_count',(SELECT count(*) FROM ru),
 'source_catalog_md5',(SELECT md5(string_agg(id::text||':'||codigo,E'\n' ORDER BY id)) FROM ru),
 'rule_preimage_root_sha256',(SELECT encode(extensions.digest(convert_to(
  jsonb_agg(jsonb_build_object('id',id,'codigo',codigo,'sha',sha) ORDER BY id)::text,
  'UTF8'),'sha256'),'hex') FROM ru),
 'screen_preimage_root_sha256',(SELECT encode(extensions.digest(convert_to(
  jsonb_agg(jsonb_build_object('id',id,'codigo',codigo,'sha',sha) ORDER BY id)::text,
  'UTF8'),'sha256'),'hex') FROM sc),
 'lineage_md5',(SELECT md5(string_agg(pantalla_id::text||':'||regla_id::text,E'\n'
 ORDER BY pantalla_id,regla_id)) FROM lf_ops.reglas_pantallas)
 ) b
)
UPDATE public.lf_operation_execution_steps st SET
 evidence_payload=jsonb_set(st.evidence_payload,
 '{profile_output,deliverable_created,governed_rule_batch}',(SELECT b FROM batch),true)
WHERE st.execution_id='EXEC-PROFILE-GATE2-PG17RULECHILD001'
 AND st.step_id='execute_profile';
"""
    sql(scoped)
def call(fail=False):
    return sql("SELECT public.lf_rule_admin_bulk_atomic_v1('"+PARENT+"','"+BATCH+"');",fail=fail)
def test():
    load();seed_all()
    check("NO_OWNER_COLUMN_BEFORE_START",
          one("NOT EXISTS(SELECT 1 FROM information_schema.columns "
          "WHERE table_schema='lf_ops' AND table_name='reglas' AND column_name='owner_name')")=="t")
    sql("UPDATE public.lf_operation_execution_steps SET status='BLOCKED' "
        "WHERE execution_id='"+PARENT+"' AND step_id='input_validate';")
    check("REQUIRE_STEP40_PROOF","BLOCK_RULE_BULK_STEP40_SCOPE_NOT_ATTESTED" in call(True))
    sql("UPDATE public.lf_operation_execution_steps SET status='STEP_PASS_WITH_EVIDENCE' "
        "WHERE execution_id='"+PARENT+"' AND step_id='input_validate';")
    # Deployed input_validate records sha256:<64 hex>, not a bare digest.
    sql("""UPDATE public.lf_operation_execution_steps
SET evidence_payload=jsonb_set(evidence_payload,
    '{scope_authority_packet_sha256}',to_jsonb(repeat('a',64)),true)
WHERE execution_id='EXEC-PROFILE-GATE2-PG17RULECHILD001'
 AND step_id='input_validate';""")
    check("REJECT_UNPREFIXED_STEP40_SHA",
          "BLOCK_RULE_BULK_STEP40_SCOPE_NOT_ATTESTED" in call(True))
    sql("""UPDATE public.lf_operation_execution_steps
SET evidence_payload=jsonb_set(evidence_payload,
    '{scope_authority_packet_sha256}',to_jsonb('sha256:'||repeat('a',64)),true)
WHERE execution_id='EXEC-PROFILE-GATE2-PG17RULECHILD001'
 AND step_id='input_validate';""")
    sql("UPDATE lf_ops.reglas SET descripcion='UNAUTHORIZED' WHERE id=1000;")
    check("BLOCK_MATERIAL_DRIFT_SAME_CODES",
          "BLOCK_RULE_BULK_RULE_MATERIAL_PREIMAGE_DRIFT" in call(True))
    sql("UPDATE lf_ops.reglas SET descripcion='Descripcion original protegida' WHERE id=1000;")
    # Missing direct RULE ref MUST block before DDL, without writing.
    sql("""UPDATE programacion.input_readiness_runs
SET source_manifest='[{"ref":{"kind":"RULE","codigo":"DOES_NOT_EXIST"}}]'::jsonb
WHERE id=930;""")
    check("BLOCK_UNRESOLVED_IG_RULE_PIN",
          "BLOCK_RULE_BULK_IG_UNRESOLVED_RULE_PIN" in call(True))
    check("NO_OWNER_COLUMN_AFTER_IG_BLOCK",
          one("NOT EXISTS(SELECT 1 FROM information_schema.columns "
          "WHERE table_schema='lf_ops' AND table_name='reglas' "
          "AND column_name='owner_name')")=="t")
    sql("""UPDATE programacion.input_readiness_runs
SET source_manifest='[{"ref":{"kind":"RULE","codigo":"TEST-BULK-RULE-0001"}},{"ref":{"kind":"RULE","codigo":"TEST-BULK-RULE-0002"}},{"ref":{"kind":"RULE","codigo":"TEST-BULK-RULE-0003"}},{"ref":{"kind":"SCREEN_CANONICAL_GRAPH"}}]'::jsonb
WHERE id=930;""")
    # Malformed manifests also fail closed for linked canonical screens.
    sql("UPDATE programacion.input_readiness_runs SET source_manifest='[]'::jsonb WHERE id=931;")
    check("BLOCK_EMPTY_IG_MANIFEST",
          "BLOCK_RULE_BULK_IG_UNRESOLVED_RULE_PIN" in call(True))
    sql("""UPDATE programacion.input_readiness_runs
SET source_manifest='[{"ref":{"kind":"SCREEN_CANONICAL_GRAPH"}}]'::jsonb
WHERE id=931;""")
    sql(r"""
CREATE FUNCTION lf_ops.fail_owner_mid_batch() RETURNS trigger LANGUAGE plpgsql AS $fail$
BEGIN
 IF NEW.codigo='TEST-BULK-RULE-0289'
   AND NEW.owner_name IS DISTINCT FROM OLD.owner_name THEN
   RAISE EXCEPTION 'PG17_MID_BATCH_INJECTED_FAILURE'; END IF;
 RETURN NEW;
END $fail$;
CREATE TRIGGER t_mid BEFORE UPDATE ON lf_ops.reglas
FOR EACH ROW EXECUTE FUNCTION lf_ops.fail_owner_mid_batch();
""")
    failure=call(True)
    if not ("BLOCK_RULE_BULK_CHILD_NOT_VERIFIED" in failure
            and "PG17_MID_BATCH_INJECTED_FAILURE" in failure):
        raise AssertionError("BLOCK_MID_BATCH_FAILURE_CAUSE_MISMATCH: "+failure[-1500:])
    check("MID_BATCH_FAILURE_ROLLS_BACK",True)
    check("NO_OWNER_COLUMN_AFTER_ROLLBACK",
          one("NOT EXISTS(SELECT 1 FROM information_schema.columns "
          "WHERE table_schema='lf_ops' AND table_name='reglas' AND column_name='owner_name')")=="t")
    check("NO_RULE_CONTENT_CHANGED_AFTER_ROLLBACK",
          one("(SELECT count(*) FROM lf_ops.reglas WHERE created_by='ChatGPT')=0")=="t")
    check("NO_CHILD_EXECUTION_AFTER_ROLLBACK",
          one("(SELECT count(*) FROM public.lf_operation_execution "
          "WHERE operation_code='ACTUALIZACION_REGLA_LF')=0")=="t")
    check("NO_HISTORY_AFTER_ROLLBACK",
          one("(SELECT count(*) FROM public.lf_operation_execution_steps "
          "WHERE evidence_payload ? 'rule_update_history_v1')=0")=="t")
    sql("DROP TRIGGER t_mid ON lf_ops.reglas;DROP FUNCTION lf_ops.fail_owner_mid_batch();")
    result=json.loads(call())
    gate=result["ig_currentness_gate"]
    check("IG_GATE_STRUCTURAL_CONTRACT",
          gate["schema_version"]=="LF_RULE_BULK_IG_CURRENTNESS_GATE_V1"
          and gate["status"]=="POST_CUT_AUTHORITY_PENDING")
    check("IG_GATE_LATEST_FIVE_ONLY",
          gate["candidate_run_count"]==5
          and sorted(row["run_id"] for row in gate["candidates"])==[930,931,932,944,951])
    check("IG_GATE_MATERIAL_THREE_RULE_PINS",
          gate["material_rule_candidate_count"]==1
          and next(row for row in gate["candidates"] if row["run_id"]==930)["material_rule_pins"]==3)
    check("IG_GATE_GRAPH_ONLY_NO_BLIND_RECURATION",
          all(row["impact_class"]=="POST_CUT_CURRENTNESS_READBACK"
              for row in gate["candidates"] if row["run_id"]!=930))
    check("IG_GATE_NEVER_FORGES_CURRENT_OR_RELEASE",
          gate["source_currentness_attested"] is False
          and gate["validator_receipt_attested"] is False
          and gate["production_release_authorized"] is False
          and result["production_status"]=="REQUIRES_GOVERNED_IG_CURRENTNESS_VALIDATION"
          and all(row["source_currentness"]=="NOT_EVALUATED" for row in gate["candidates"]))
    check("578_CHILDREN_APPLIED",result["rules_updated"]==578 and result["status"]=="APPLIED_VERIFIED")
    check("578_HISTORIES_VERIFIED",result["histories_written"]==578)
    check("56_SCREENS_REHASHED",result["screens_sha_verified"]==56)
    check("6176_LINKS_VERIFIED",result["rule_links_verified"]==6176)
    check("578_OWNER_CREATOR_FINAL",
          one("(SELECT count(*) FROM lf_ops.reglas WHERE owner_name='SUPER_ADMIN' "
          "AND created_by='ChatGPT')=578")=="t")
    check("412_VIGENTE_PRESERVED",
          one("(SELECT count(*) FROM lf_ops.reglas WHERE estado='VIGENTE')=412")=="t")
    check("166_CANDIDATO_PRESERVED",
          one("(SELECT count(*) FROM lf_ops.reglas WHERE estado='CANDIDATO')=166")=="t")
    check("577_PRE_DDL_ACTORS_PRESERVED",
          one("(SELECT count(*) FROM public.lf_operation_execution_steps "
          "WHERE evidence_payload#>>'{rule_update_history_v1,pre_schema_source_row,created_by}'"
          "='ORIGINAL_ACTOR')=577")=="t")
    check("REPLAY_IS_BLOCKED",
          "BLOCK_RULE_BULK_OWNER_SCHEMA_ALREADY_PRESENT" in call(True))
    print("LF_RULE_BULK_ATOMIC_PG17_PASS",N,flush=True)
if __name__=="__main__":test()

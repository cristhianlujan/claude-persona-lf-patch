#!/usr/bin/env python3
"""Disposable PG17 negative-gate test for SALY SUNAT close candidate.

This test does not connect to Supabase. Positive 7514-row fixture, two-session
concurrency, and rollback injection remain mandatory before promotion.
"""
import os, subprocess
from pathlib import Path
DB = "saly_sunat_close_ci"
ROOT = Path(__file__).resolve().parents[3]
CANDIDATE = ROOT / "skills/ai_sales_discovery/tests/sunat_close_candidate_v1.sql"

def sql(source, success=True, error_code=None):
    p = subprocess.run(["psql","-X","-qAt","-v","ON_ERROR_STOP=1","-d",DB],
                       input=source,text=True,capture_output=True,check=False)
    if success and p.returncode: raise AssertionError(p.stderr[-2500:])
    if not success and not p.returncode: raise AssertionError("EXPECTED_SQL_REJECTION")
    if error_code is not None:
        assert not success, "ERROR_CODE_ONLY_FOR_NEGATIVE_CASES"
        if error_code not in p.stderr:
            raise AssertionError("WRONG_SQL_ERROR_EXPECTED_" + error_code + ": " + p.stderr[-2500:])
    return p.stdout.strip()

def main():
    assert os.getenv("PGHOST") == "127.0.0.1" and os.getenv("PGDATABASE") == DB, "DISPOSABLE_ONLY"
    assert sql("SHOW server_version_num").startswith("17"), "PG17_ONLY"
    sql("""
DO $roles$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon NOLOGIN; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='service_role') THEN CREATE ROLE service_role NOLOGIN; END IF;
END $roles$;
CREATE SCHEMA saly;
CREATE TABLE public.lf_operation_execution (
 execution_id text PRIMARY KEY,operation_code text,status text,lease_owner text,
 lease_fence bigint DEFAULT 0,lease_expires_at timestamptz,completed_at timestamptz,
 manifest jsonb DEFAULT '{}'::jsonb,updated_by_execution_id text,updated_at timestamptz);
CREATE TABLE public.lf_global_config (
 scope text,config_key text,config_value text,value_type text,value_status text,valid_from timestamptz);
CREATE TABLE public.lf_operation_effect_guard (
 execution_id text,effect_scope text,dispatch_key text,state text,receipt jsonb);
CREATE TABLE saly.ventas_discovery_runs (
 id uuid PRIMARY KEY,run_ref text UNIQUE,catalog_version text,scope jsonb,
 plan_hash text,estado text,finished_at timestamptz);
ALTER TABLE saly.ventas_discovery_runs
 ADD CONSTRAINT saly_l28_run_close_disabled CHECK (estado <> 'CERRADO');
CREATE TABLE saly.ventas_discovery_plan_batches (
 id uuid,run_id uuid,source_id text,batch_key text,scope_key text,estado text,filtros jsonb);
CREATE TABLE saly.ventas_discovery_ingestas (
 id uuid,run_ref text,source_id text,batch_key text,scope_key text,
 estado text,archivo_sha256 text,filas_reportadas int);
CREATE TABLE saly.ventas_hallazgos (id uuid,ingesta_id uuid,ruc_candidato text,captura_empresarial jsonb);
CREATE TABLE saly.ventas_sunat_bulk_delete_ledger_v1 (run_ref text);
CREATE VIEW saly.ventas_sunat_elegibilidad_v1 AS
SELECT h.id AS hallazgo_id,h.ingesta_id,i.run_ref,i.batch_key,
 h.ruc_candidato AS ruc,
 h.captura_empresarial #>> '{capture,normalized,workers_integer_literal}' AS nrotrab_literal,
 v.nrotrab,v.estado_mensual,v.estado_reducido,v.condicion_mensual,v.condicion_reducida,
 CASE WHEN v.nrotrab IS NULL THEN 'EXCLUIDA_SIN_DATO_EMPLEADOS'
      WHEN v.nrotrab < threshold.min_workers THEN 'EXCLUIDA_MENOS_50_EMPLEADOS'
      WHEN upper(btrim(coalesce(v.estado_mensual,''))) IS DISTINCT FROM 'ACTIVO'
        OR upper(btrim(coalesce(v.estado_reducido,''))) IS DISTINCT FROM 'ACTIVO' THEN 'EXCLUIDA_ESTADO'
      WHEN upper(btrim(coalesce(v.condicion_mensual,''))) IS DISTINCT FROM 'HABIDO'
        OR upper(btrim(coalesce(v.condicion_reducida,''))) IS DISTINCT FROM 'HABIDO' THEN 'EXCLUIDA_CONDICION'
      ELSE 'ELEGIBLE' END AS clasificacion_comercial
FROM saly.ventas_hallazgos h
JOIN saly.ventas_discovery_ingestas i ON i.id=h.ingesta_id
CROSS JOIN LATERAL (
 SELECT CASE WHEN (h.captura_empresarial #>> '{capture,normalized,workers_integer_literal}') ~ '^[0-9]{1,9}$'
             THEN (h.captura_empresarial #>> '{capture,normalized,workers_integer_literal}')::integer
             ELSE NULL::integer END AS nrotrab,
        h.captura_empresarial #>> '{capture,observations,monthly,raw,Estado}' AS estado_mensual,
        h.captura_empresarial #>> '{capture,observations,reduced,raw,estado}' AS estado_reducido,
        h.captura_empresarial #>> '{capture,observations,monthly,raw,Condicion}' AS condicion_mensual,
        h.captura_empresarial #>> '{capture,observations,reduced,raw,condicion}' AS condicion_reducida
) v
CROSS JOIN (
 SELECT config_value::integer AS min_workers FROM public.lf_global_config
 WHERE scope='SALY_DISCOVERY' AND config_key='SUNAT_COMMERCIAL_MIN_WORKERS_V1'
 AND value_type='INTEGER' AND value_status='REAL'
 AND config_value ~ '^[1-9][0-9]{0,7}$' AND valid_from <= now()
 ORDER BY valid_from DESC LIMIT 1
) threshold
WHERE i.source_id='PE-SUNAT-RUC';
CREATE FUNCTION public.fn_lf_operation_acquire_lease_v1(
 p_execution_id text,p_lease_owner text,p_ttl_seconds integer,p_actor_execution_id text)
 RETURNS jsonb LANGUAGE plpgsql AS $fn$
 DECLARE v_fence bigint;
 BEGIN
 UPDATE public.lf_operation_execution SET lease_owner=p_lease_owner,
 lease_fence=lease_fence+1,lease_expires_at=clock_timestamp()+make_interval(secs=>p_ttl_seconds)
 WHERE execution_id=p_execution_id RETURNING lease_fence INTO v_fence;
 RETURN jsonb_build_object('result','LEASE_ACQUIRED','lease_owner',p_lease_owner,
 'lease_fence',v_fence,'lease_expires_at',clock_timestamp()+make_interval(secs=>p_ttl_seconds));
 END $fn$;
""")
    sql(CANDIDATE.read_text())
    assert sql("SELECT count(*) FROM pg_constraint WHERE conname='saly_l28_run_close_disabled'") == "0"
    assert sql("SELECT count(*) FROM pg_trigger WHERE tgname='trg_saly_ventas_discovery_close_gate_v1'") == "1"
    sql("INSERT INTO saly.ventas_discovery_runs VALUES (gen_random_uuid(),'bad','v1','{}','" + "0"*64 + "','CERRADO',now())", False, "SUNAT_CLOSE_INSERT_FORBIDDEN")
    print("PASS_PG17_INSERT_CERRADO_FORBIDDEN")
    sql("INSERT INTO saly.ventas_discovery_runs VALUES (gen_random_uuid(),'run-open','v1','{}','" + "0"*64 + "','EN_EJECUCION',null)")
    sql("UPDATE saly.ventas_discovery_runs SET estado='CERRADO',finished_at=now() WHERE run_ref='run-open'", False, "SUNAT_CLOSE_GATE_REJECTED")
    assert sql("SELECT estado FROM saly.ventas_discovery_runs WHERE run_ref='run-open'") == "EN_EJECUCION"
    print("PASS_PG17_UPDATE_CERRADO_BLOCKED")
    sql("INSERT INTO public.lf_operation_execution VALUES ('run-open','INGESTA_EMPRESARIAL_SALY','IN_PROGRESS',null,0,null,null,'{}',null,null)")
    sql("SELECT saly.ventas_sunat_commercial_close_v1('run-open','actor','owner','" + "0"*64 + "')", False, "SUNAT_CLOSE_POLICY_OR_MANIFEST")
    assert sql("SELECT status FROM public.lf_operation_execution WHERE execution_id='run-open'") == "IN_PROGRESS"
    print("PASS_PG17_MISSING_POLICY_BLOCKS_WITHOUT_MUTATION")
    assert sql("SELECT has_function_privilege('authenticated','saly.ventas_sunat_commercial_close_v1(text,text,text,text)','EXECUTE')") == "f"
    assert sql("SELECT has_function_privilege('service_role','saly.ventas_sunat_commercial_close_v1(text,text,text,text)','EXECUTE')") == "f"
    sql("SELECT saly.ventas_sunat_commercial_close_v1('run-open','actor','owner',NULL)",False,"SUNAT_CLOSE_INVALID_INPUT")
    print("PASS_PG17_NULL_EVIDENCE_INPUT_REJECTED")
    print("PASS_PG17_CLIENT_ROLES_DENIED")
    print("PASS_PG17_SUNAT_CLOSE_NEGATIVE_TRANCHE")
    # Real PG17 full-size synthetic positive, dual session, and fault injection.
    from test_sunat_close_positive_pg17 import main as positive_close
    positive_close()

if __name__ == "__main__": main()

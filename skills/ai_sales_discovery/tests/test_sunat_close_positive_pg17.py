#!/usr/bin/env python3
"""Full synthetic positive, concurrent, rollback tests for SUNAT close in disposable PG17.

Called after test_sunat_close_pg17.main has installed a candidate in a clean,
private database. All figures simulate the approved baseline; no real RUC/data.
"""
from concurrent.futures import ThreadPoolExecutor
import time
from test_sunat_close_pg17 import sql

COMMERCIAL='EXEC-SALY-SUNAT-COMMERCIAL-20261123-001'
OLD='EXEC-SALY-SUNAT-PILOT-20261122-001'
MANIFEST='40300fa68d60cf5d0147dc985cef6183694768f8798aa4ef1020bdc6180d5595'

def assert_snapshot():
    result=sql("""
SELECT (SELECT count(*) FROM saly.ventas_hallazgos h
        JOIN saly.ventas_discovery_ingestas i ON i.id=h.ingesta_id
        WHERE i.source_id='PE-SUNAT-RUC')::text || ':' ||
       (SELECT count(*) FROM saly.ventas_sunat_bulk_delete_ledger_v1)::text || ':' ||
       (SELECT count(*) FROM saly.ventas_discovery_plan_batches p
        JOIN saly.ventas_discovery_runs r ON r.id=p.run_id
        WHERE r.run_ref='EXEC-SALY-SUNAT-PILOT-20261122-001')::text;
""")
    assert result=='7514:130725:479', result

def main():
    sql("""
-- Generated synthetic source history: 136 historical validated ingestas,
-- 479 historical plan rows, 5275 historical rows and 130725 historical deletes.
INSERT INTO saly.ventas_discovery_runs(id,run_ref,catalog_version,scope,plan_hash,estado,finished_at)
VALUES(gen_random_uuid(),'EXEC-SALY-SUNAT-PILOT-20261122-001','v1','{}'::jsonb,repeat('1',64),'HOLD',null),
      (gen_random_uuid(),'EXEC-SALY-SUNAT-COMMERCIAL-20261123-001','v1','{}'::jsonb,
       '40300fa68d60cf5d0147dc985cef6183694768f8798aa4ef1020bdc6180d5595','EN_EJECUCION',null);
WITH target AS (SELECT id FROM saly.ventas_discovery_runs
   WHERE run_ref='EXEC-SALY-SUNAT-PILOT-20261122-001')
INSERT INTO saly.ventas_discovery_plan_batches
 (id,run_id,source_id,batch_key,scope_key,estado,filtros)
SELECT gen_random_uuid(),target.id,'PE-SUNAT-RUC','hist-'||lpad(n::text,3,'0'),
       'LIMA_ICA',CASE WHEN n<=136 THEN 'FOUND' ELSE 'NOT_RUN' END,
       jsonb_build_object('ordinal',n,'rows',1000,'capture_sha256',repeat('1',64))
FROM generate_series(1,479) s(n) CROSS JOIN target;
WITH target AS (SELECT id FROM saly.ventas_discovery_runs
  WHERE run_ref='EXEC-SALY-SUNAT-COMMERCIAL-20261123-001')
INSERT INTO saly.ventas_discovery_plan_batches
 (id,run_id,source_id,batch_key,scope_key,estado,filtros)
SELECT gen_random_uuid(),target.id,'PE-SUNAT-RUC','new-'||n,
       'LIMA_ICA','FOUND',
       jsonb_build_object('ordinal',n,'rows',CASE WHEN n=3 THEN 239 ELSE 1000 END,
                          'capture_sha256',repeat(('a'::text),64))
FROM generate_series(1,3) s(n) CROSS JOIN target;
INSERT INTO saly.ventas_discovery_ingestas
 (id,run_ref,source_id,batch_key,scope_key,estado,archivo_sha256,filas_reportadas)
SELECT gen_random_uuid(),'EXEC-SALY-SUNAT-PILOT-20261122-001','PE-SUNAT-RUC',
       'hist-'||lpad(n::text,3,'0'),'LIMA_ICA','VALIDADA',repeat('1',64),1000
FROM generate_series(1,136) s(n);
INSERT INTO saly.ventas_discovery_ingestas
 (id,run_ref,source_id,batch_key,scope_key,estado,archivo_sha256,filas_reportadas)
SELECT gen_random_uuid(),'EXEC-SALY-SUNAT-COMMERCIAL-20261123-001','PE-SUNAT-RUC',
       'new-'||n,'LIMA_ICA','VALIDADA',repeat('a',64),
       CASE WHEN n=3 THEN 239 ELSE 1000 END
FROM generate_series(1,3) s(n);
WITH historic AS (SELECT id,row_number() over(order by batch_key) ord
 FROM saly.ventas_discovery_ingestas
 WHERE run_ref='EXEC-SALY-SUNAT-PILOT-20261122-001')
INSERT INTO saly.ventas_hallazgos(id,ingesta_id,ruc_candidato)
SELECT gen_random_uuid(),historic.id,'20'||lpad(n::text,9,'0')
FROM generate_series(1,5275) g(n)
JOIN historic ON historic.ord = ((n-1)%136)+1;
WITH commercial AS (SELECT id,row_number() over(order by batch_key) ord
 FROM saly.ventas_discovery_ingestas
 WHERE run_ref='EXEC-SALY-SUNAT-COMMERCIAL-20261123-001')
INSERT INTO saly.ventas_hallazgos(id,ingesta_id,ruc_candidato)
SELECT gen_random_uuid(),commercial.id,'20'||lpad((100000+n)::text,9,'0')
FROM generate_series(1,2239) g(n)
JOIN commercial ON commercial.ord =
 CASE WHEN n<=1000 THEN 1 WHEN n<=2000 THEN 2 ELSE 3 END;
INSERT INTO saly.ventas_sunat_bulk_delete_ledger_v1
SELECT 'EXEC-SALY-SUNAT-PILOT-20261122-001' FROM generate_series(1,130725);
-- Eligibility is a real VIEW over captured fields, not a writable table.
UPDATE saly.ventas_hallazgos h
SET captura_empresarial=jsonb_build_object(
  'capture',jsonb_build_object(
   'normalized',jsonb_build_object('workers_integer_literal','50'),
   'observations',jsonb_build_object(
     'monthly',jsonb_build_object('raw',jsonb_build_object('Estado','ACTIVO','Condicion','HABIDO')),
     'reduced',jsonb_build_object('raw',jsonb_build_object('estado','ACTIVO','condicion','HABIDO')))))
FROM saly.ventas_discovery_ingestas i
WHERE i.id=h.ingesta_id AND i.run_ref='EXEC-SALY-SUNAT-COMMERCIAL-20261123-001';
INSERT INTO public.lf_operation_execution(
 execution_id,operation_code,status,lease_owner,lease_fence,lease_expires_at,
 completed_at,manifest)
VALUES('EXEC-SALY-SUNAT-COMMERCIAL-20261123-001','INGESTA_EMPRESARIAL_SALY',
       'IN_PROGRESS','SALY-SUNAT-COMMERCIAL-V3',2,
       now()-interval '2 days',null,
       '{"sunat_plan":{"business":"SALY","scope_key":"LIMA_ICA",
          "source_id":"PE-SUNAT-RUC",
          "manifest_digest_sha256":"40300fa68d60cf5d0147dc985cef6183694768f8798aa4ef1020bdc6180d5595",
          "snapshot_sha256":["bf875a7fdf80c16dfee03210759f497b50a5b9c69a4774ed6fbb92e6dceed0a7",
                             "2cea288655227dda03d3aaab30c7e63776f3cfb6cc68f75efd56e858865a17d7"]}}');
INSERT INTO public.lf_operation_effect_guard(execution_id,effect_scope,dispatch_key,state,receipt)
SELECT 'EXEC-SALY-SUNAT-COMMERCIAL-20261123-001','batch-'||n,'new-'||n,
       'SUCCEEDED',jsonb_build_object('success',true,'rows',
                             CASE WHEN n=3 THEN 239 ELSE 1000 END)
FROM generate_series(1,3) s(n);
INSERT INTO public.lf_global_config(scope,config_key,config_value,value_type,value_status,valid_from)
VALUES
 ('SALY_DISCOVERY','SUNAT_COMMERCIAL_MIN_WORKERS_V1','50','INTEGER','REAL',now()),
 ('SALY_DISCOVERY','SUNAT_POLICY_V1',
  '{"enabled":true,"pilot_scope":"NEW_COMMERCIAL_RUN_ONLY",
     "old_manifest_replay_allowed":false,
     "commercial_run_ref":"EXEC-SALY-SUNAT-COMMERCIAL-20261123-001",
     "manifest_digest_sha256":"40300fa68d60cf5d0147dc985cef6183694768f8798aa4ef1020bdc6180d5595",
     "snapshot_sha256":["bf875a7fdf80c16dfee03210759f497b50a5b9c69a4774ed6fbb92e6dceed0a7",
                        "2cea288655227dda03d3aaab30c7e63776f3cfb6cc68f75efd56e858865a17d7"],
     "expected_batches":3,"expected_rows":2239}','JSON','REAL',now());
""")
    assert_snapshot()
    digest=sql("""
SELECT encode(sha256(convert_to(jsonb_build_object(
  'contract','SALY_SUNAT_CLOSE_V1',
  'run_ref','EXEC-SALY-SUNAT-COMMERCIAL-20261123-001',
  'plan_hash','40300fa68d60cf5d0147dc985cef6183694768f8798aa4ef1020bdc6180d5595',
  'expected_batches',3,'expected_rows',2239,
  'effect_receipt_digest',(SELECT encode(sha256(convert_to(
    coalesce(jsonb_agg(jsonb_build_object('scope',g.effect_scope,
       'dispatch',g.dispatch_key,'receipt',g.receipt)
       ORDER BY g.effect_scope)::text,'[]'),'UTF8')),'hex')
    FROM public.lf_operation_effect_guard g
    WHERE g.execution_id='EXEC-SALY-SUNAT-COMMERCIAL-20261123-001')
)::text,'UTF8')),'hex');
""")
    assert len(digest)==64,digest
    call=("SELECT saly.ventas_sunat_commercial_close_v1("
      "'EXEC-SALY-SUNAT-COMMERCIAL-20261123-001','synthetic-actor',"
      "'synthetic-close-worker','"+digest+"')")
    sql(call,False,"SUNAT_CLOSE_TTL_POLICY_MISSING")
    assert sql("SELECT status FROM public.lf_operation_execution WHERE execution_id='"+COMMERCIAL+"'")=="IN_PROGRESS"
    print('PASS_PG17_MISSING_TTL_FAILS_CLOSED')
    sql("""INSERT INTO public.lf_global_config(scope,config_key,config_value,value_type,value_status,valid_from)
VALUES('SALY_DISCOVERY','SUNAT_CLOSE_TTL_SECONDS_V1','45','INTEGER','REAL',now());""")
    sql(call.replace(digest,'0'*64),False,"SUNAT_CLOSE_EVIDENCE_HASH_MISMATCH")
    print('PASS_PG17_BAD_DIGEST_FAILS_CLOSED')
    # Coverage must be total, not merely "zero ineligible": missing classifications
    # are unsafe even when every remaining row is eligible.
    # Real VIEW must lose all rows if its governed threshold is invalidated.
    sql("UPDATE public.lf_global_config SET config_value='0' WHERE config_key='SUNAT_COMMERCIAL_MIN_WORKERS_V1'")
    assert sql("SELECT count(*) FROM saly.ventas_sunat_elegibilidad_v1 WHERE run_ref='"+COMMERCIAL+"'")=="0"
    sql(call,False,"SUNAT_CLOSE_MIN_WORKERS_POLICY_MISSING")
    assert sql("SELECT status FROM public.lf_operation_execution WHERE execution_id='"+COMMERCIAL+"'")=="IN_PROGRESS"
    sql("UPDATE public.lf_global_config SET config_value='50' WHERE config_key='SUNAT_COMMERCIAL_MIN_WORKERS_V1'")
    assert sql("SELECT count(*) FROM saly.ventas_sunat_elegibilidad_v1 WHERE run_ref='"+COMMERCIAL+"'")=="2239"
    print('PASS_PG17_MISSING_ELIGIBILITY_COVERAGE_BLOCKED')
    # Do not accept a mutated receipt, historical pilot or one missing batch.
    sql("UPDATE public.lf_operation_effect_guard SET receipt='{}'::jsonb WHERE dispatch_key='new-1'")
    sql(call,False,"SUNAT_CLOSE_EVIDENCE_HASH_MISMATCH")  # persisted-receipt SHA no longer matches
    sql("""UPDATE public.lf_operation_effect_guard SET receipt='{"rows":1000,"success":true}'::jsonb WHERE dispatch_key='new-1'""")
    sql("UPDATE saly.ventas_discovery_runs SET estado='PARTIAL' WHERE run_ref='"+OLD+"'")
    sql(call,False,"SUNAT_CLOSE_HISTORICAL_HOLD")
    sql("UPDATE saly.ventas_discovery_runs SET estado='HOLD' WHERE run_ref='"+OLD+"'")
    sql("UPDATE saly.ventas_discovery_plan_batches SET estado='NOT_RUN' WHERE batch_key='new-3'")
    sql(call,False,"SUNAT_CLOSE_PLAN_INCOMPLETE")
    sql("UPDATE saly.ventas_discovery_plan_batches SET estado='FOUND' WHERE batch_key='new-3'")
    assert sql("SELECT status FROM public.lf_operation_execution WHERE execution_id='"+COMMERCIAL+"'")=="IN_PROGRESS"
    assert_snapshot()
    print('PASS_PG17_TAMPERED_RECEIPT_HISTORICAL_HOLD_INCOMPLETE_BATCH_BLOCKED')
    sql("""
CREATE FUNCTION saly.synthetic_abort_close() RETURNS trigger LANGUAGE plpgsql AS $fn$
BEGIN IF NEW.estado='CERRADO' THEN RAISE EXCEPTION 'SYNTHETIC_SECOND_UPDATE_ROLLBACK'; END IF;
RETURN NEW; END $fn$;
CREATE TRIGGER trg_saly_synthetic_abort_close BEFORE UPDATE ON saly.ventas_discovery_runs
FOR EACH ROW EXECUTE FUNCTION saly.synthetic_abort_close();""")
    sql(call,False,"SYNTHETIC_SECOND_UPDATE_ROLLBACK")
    assert sql("SELECT status||':'||lease_fence FROM public.lf_operation_execution WHERE execution_id='"+COMMERCIAL+"'")=="IN_PROGRESS:2"
    assert sql("SELECT estado FROM saly.ventas_discovery_runs WHERE run_ref='"+COMMERCIAL+"'")=="EN_EJECUCION"
    assert_snapshot()
    print('PASS_PG17_SECOND_UPDATE_ROLLBACK_ATOMIC')
    sql("DROP TRIGGER trg_saly_synthetic_abort_close ON saly.ventas_discovery_runs")
    # Competing sessions: first holds the same global transaction advisory lock,
    # second blocks and then performs a replay after first succeeds.
    contender1="BEGIN; SELECT pg_advisory_xact_lock(hashtextextended('SALY:PE-SUNAT-RUC:SEQUENTIAL',0)); SELECT pg_sleep(0.5); "+call+"; COMMIT;"
    with ThreadPoolExecutor(max_workers=2) as pool:
        a=pool.submit(sql,contender1)
        time.sleep(0.10)
        b=pool.submit(sql,call)
        va,vb=a.result(timeout=20),b.result(timeout=20)
    assert 'SUCCESS' in va and 'ALREADY_CLOSED_SAME_EVIDENCE' in vb,(va,vb)
    assert sql("SELECT status FROM public.lf_operation_execution WHERE execution_id='"+COMMERCIAL+"'")=="COMPLETED"
    assert sql("SELECT estado FROM saly.ventas_discovery_runs WHERE run_ref='"+COMMERCIAL+"'")=="CERRADO"
    assert sql("SELECT (completed_at= (SELECT finished_at FROM saly.ventas_discovery_runs WHERE run_ref='"+COMMERCIAL+"'))::text FROM public.lf_operation_execution WHERE execution_id='"+COMMERCIAL+"'")=="true"
    assert sql("SELECT lease_owner IS NULL AND lease_expires_at IS NULL FROM public.lf_operation_execution WHERE execution_id='"+COMMERCIAL+"'")=="t"
    assert_snapshot()
    print('PASS_PG17_CONCURRENT_CLOSE_SERIALIZED')
    assert 'ALREADY_CLOSED_SAME_EVIDENCE' in sql(call)
    sql(call.replace(digest,'0'*64),False,"SUNAT_CLOSE_REPLAY_CONFLICT")
    sql("UPDATE saly.ventas_discovery_runs SET estado='HOLD' WHERE run_ref='"+COMMERCIAL+"'",False,"SUNAT_CLOSE_TERMINAL_IMMUTABLE")
    assert sql("SELECT estado FROM saly.ventas_discovery_runs WHERE run_ref='"+OLD+"'")=="HOLD"
    assert_snapshot()
    print('PASS_PG17_IDEMPOTENCY_HISTORICAL_PRESERVATION_TERMINAL')
if __name__=='__main__': main()

-- IG M10.7 G2B: isolated negative/positive fixture for atomic final gate.
-- Candidate only. NO consumer binding, real LF writes, grant, CP3 transition, or G2B PASS.
DO $preflight$
BEGIN
 IF to_regclass('programacion.input_g2b_source_fixture_v1') IS NOT NULL
  OR to_regprocedure('programacion.fn_input_g2b_fixture_commit_gate_v1(uuid,bigint,integer,text,bigint,text)') IS NOT NULL
  OR EXISTS(SELECT 1 FROM public.lf_error_knowledge WHERE codigo='IG-M107-G2B-FIXTURE-ATOMIC-GATE-020')
 THEN RAISE EXCEPTION 'G2B_FIXTURE_EXISTS'; END IF;
 IF md5(pg_get_functiondef('programacion.fn_input_governance_run_context_packet_v1(bigint)'::regprocedure))
  <>'c0d4e5e8515e79343358fa1d490d0ca6'
  OR md5(pg_get_functiondef('programacion.fn_input_run_source_currentness_v1(bigint)'::regprocedure))
  <>'ba43b8cc06220a2ae079d5d7d6c7710c'
 THEN RAISE EXCEPTION 'G2B_CANONICAL_RUNTIME_DRIFT'; END IF;
END $preflight$;

CREATE TABLE programacion.input_g2b_source_fixture_v1 (
 fixture_key uuid PRIMARY KEY,
 run_id bigint NOT NULL,
 pantalla_id integer NOT NULL,
 contract_sha256 text NOT NULL CHECK (length(contract_sha256)=64),
 source_payload jsonb NOT NULL,
 source_epoch bigint NOT NULL DEFAULT 1 CHECK (source_epoch>=1),
 close_status text NOT NULL DEFAULT 'OPEN' CHECK(close_status IN ('OPEN','ACCEPTED')),
 closed_at timestamptz
);
ALTER TABLE programacion.input_g2b_source_fixture_v1 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE programacion.input_g2b_source_fixture_v1 FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION programacion.fn_input_g2b_fixture_epoch_bump_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','programacion'
AS $gate$
BEGIN
 IF NEW.fixture_key IS DISTINCT FROM OLD.fixture_key
  OR NEW.run_id IS DISTINCT FROM OLD.run_id
  OR NEW.pantalla_id IS DISTINCT FROM OLD.pantalla_id
 THEN RAISE EXCEPTION 'G2B_FIXTURE_IDENTITY_IMMUTABLE'; END IF;
 IF NEW.source_payload IS DISTINCT FROM OLD.source_payload
  OR NEW.contract_sha256 IS DISTINCT FROM OLD.contract_sha256 THEN
  NEW.source_epoch:=OLD.source_epoch+1;
  NEW.close_status:='OPEN';
  NEW.closed_at:=NULL;
 ELSE
  NEW.source_epoch:=OLD.source_epoch;
 END IF;
 RETURN NEW;
END $gate$;
REVOKE ALL ON FUNCTION programacion.fn_input_g2b_fixture_epoch_bump_v1() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER trg_input_g2b_fixture_epoch_bump_v1
BEFORE UPDATE ON programacion.input_g2b_source_fixture_v1
FOR EACH ROW EXECUTE FUNCTION programacion.fn_input_g2b_fixture_epoch_bump_v1();

CREATE FUNCTION programacion.fn_input_g2b_fixture_commit_gate_v1(
 p_fixture_key uuid,p_run_id bigint,p_pantalla_id integer,
 p_contract_sha256 text,p_expected_epoch bigint,p_expected_source_sha256 text)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO 'pg_catalog','programacion'
AS $gate$
DECLARE
 v_row programacion.input_g2b_source_fixture_v1%ROWTYPE;
 v_sha text;
 v_reason text;
BEGIN
 -- FOR UPDATE excludes any concurrent payload UPDATE until our transaction commits.
 SELECT * INTO v_row FROM programacion.input_g2b_source_fixture_v1
 WHERE fixture_key=p_fixture_key FOR UPDATE;
 IF NOT FOUND THEN
  RETURN jsonb_build_object('accepted',false,'code','G2B_FIXTURE_MISSING');
 END IF;
 v_sha:=programacion.fn_v09_sha256_jsonb(v_row.source_payload);
 v_reason:=CASE
 WHEN v_row.run_id IS DISTINCT FROM p_run_id
  OR v_row.pantalla_id IS DISTINCT FROM p_pantalla_id
   THEN 'G2B_IDENTITY_MISMATCH'
 WHEN v_row.contract_sha256 IS DISTINCT FROM p_contract_sha256
   THEN 'G2B_CONTRACT_CHANGED'
 WHEN v_row.source_epoch IS DISTINCT FROM p_expected_epoch
   THEN 'G2B_SOURCE_EPOCH_CHANGED'
 WHEN v_sha IS DISTINCT FROM p_expected_source_sha256
   THEN 'G2B_SOURCE_SHA_CHANGED'
 WHEN v_row.close_status<>'OPEN'
   THEN 'G2B_ALREADY_CLOSED'
 END;
 IF v_reason IS NOT NULL THEN
  RETURN jsonb_build_object('accepted',false,'code',v_reason,
    'current_epoch',v_row.source_epoch,'observed_source_sha256',v_sha);
 END IF;
 -- Final check and the ONLY simulated acceptance are in one transaction.
 UPDATE programacion.input_g2b_source_fixture_v1
 SET close_status='ACCEPTED',closed_at=clock_timestamp()
 WHERE fixture_key=p_fixture_key;
 RETURN jsonb_build_object('accepted',true,'code','G2B_FIXTURE_ATOMIC_GATE_ACCEPTED',
  'source_epoch',v_row.source_epoch,'observed_source_sha256',v_sha,
  'backend_pid',pg_backend_pid(),'scope','FIXTURE_ONLY',
  'commit_required',true);
END $gate$;
REVOKE ALL ON FUNCTION programacion.fn_input_g2b_fixture_commit_gate_v1(uuid,bigint,integer,text,bigint,text) FROM PUBLIC,anon,authenticated,service_role;

DO $proof$
DECLARE
 v_key1 uuid:=gen_random_uuid();
 v_key2 uuid:=gen_random_uuid();
 v_key3 uuid:=gen_random_uuid();
 v_sha1 text;
 v_sha2 text;
 v_result jsonb;
 v_epoch bigint;
 v_pos boolean:=false;v_neg_epoch boolean:=false;
 v_neg_contract boolean:=false;v_neg_identity boolean:=false;
 v_changed_contract boolean:=false;v_pos_fresh boolean:=false;
 v_evidence jsonb;
 v_triggers integer;
BEGIN
 SELECT count(*) INTO v_triggers FROM pg_trigger t
 JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE NOT t.tgisinternal AND t.tgenabled IN ('O','A')
 AND n.nspname='programacion'
 AND c.relname IN ('input_family_assessments','input_gap_proposals','input_readiness_runs');
 IF v_triggers<>21 THEN RAISE EXCEPTION 'G2B_CANONICAL_TRIGGERS_CHANGED:%',v_triggers; END IF;
 -- All test DML rolled back by expected subtransaction sentinel.
 BEGIN
  INSERT INTO programacion.input_g2b_source_fixture_v1(fixture_key,run_id,pantalla_id,contract_sha256,source_payload)
  VALUES
   (v_key1,900001,43,repeat('c',64),'{"rule":"A"}'::jsonb),
   (v_key2,900002,43,repeat('c',64),'{"rule":"A"}'::jsonb),
   (v_key3,900003,55,repeat('c',64),'{"rule":"A"}'::jsonb);
  v_sha1:=programacion.fn_v09_sha256_jsonb('{"rule":"A"}'::jsonb);
  v_sha2:=programacion.fn_v09_sha256_jsonb('{"rule":"B"}'::jsonb);
  v_result:=programacion.fn_input_g2b_fixture_commit_gate_v1(v_key1,900001,43,repeat('c',64),1,v_sha1);
  v_pos:=coalesce((v_result->>'accepted')::boolean,false);
  IF NOT v_pos THEN RAISE EXCEPTION 'G2B_BASELINE_POSITIVE_FAILED:%',v_result; END IF;
  UPDATE programacion.input_g2b_source_fixture_v1
   SET source_payload='{"rule":"B"}'::jsonb WHERE fixture_key=v_key2;
  SELECT source_epoch INTO v_epoch FROM programacion.input_g2b_source_fixture_v1 WHERE fixture_key=v_key2;
  IF v_epoch<>2 THEN RAISE EXCEPTION 'G2B_SOURCE_EPOCH_NOT_INCREMENTED'; END IF;
  v_result:=programacion.fn_input_g2b_fixture_commit_gate_v1(v_key2,900002,43,repeat('c',64),1,v_sha1);
  v_neg_epoch:=v_result->>'code'='G2B_SOURCE_EPOCH_CHANGED';
  IF NOT v_neg_epoch THEN RAISE EXCEPTION 'G2B_STALE_FALSE_PASS:%',v_result; END IF;
  v_result:=programacion.fn_input_g2b_fixture_commit_gate_v1(v_key2,900003,43,repeat('c',64),2,v_sha2);
  v_neg_identity:=v_result->>'code'='G2B_IDENTITY_MISMATCH';
  IF NOT v_neg_identity THEN RAISE EXCEPTION 'G2B_IDENTITY_FALSE_PASS:%',v_result; END IF;
  v_result:=programacion.fn_input_g2b_fixture_commit_gate_v1(v_key2,900002,43,repeat('x',64),2,v_sha2);
  v_neg_contract:=v_result->>'code'='G2B_CONTRACT_CHANGED';
  IF NOT v_neg_contract THEN RAISE EXCEPTION 'G2B_CONTRACT_FALSE_PASS:%',v_result; END IF;
  UPDATE programacion.input_g2b_source_fixture_v1
    SET contract_sha256=repeat('d',64) WHERE fixture_key=v_key3;
  SELECT source_epoch INTO v_epoch FROM programacion.input_g2b_source_fixture_v1 WHERE fixture_key=v_key3;
  v_changed_contract:=v_epoch=2;
  IF NOT v_changed_contract THEN RAISE EXCEPTION 'G2B_CONTRACT_EPOCH_NOT_INCREMENTED'; END IF;
  v_result:=programacion.fn_input_g2b_fixture_commit_gate_v1(v_key2,900002,43,repeat('c',64),2,v_sha2);
  v_pos_fresh:=coalesce((v_result->>'accepted')::boolean,false);
  IF NOT v_pos_fresh THEN RAISE EXCEPTION 'G2B_FRESH_REVALIDATION_NOT_ACCEPTED:%',v_result; END IF;
  RAISE EXCEPTION 'G2B_FIXTURE_TEST_EXPECTED_ROLLBACK' USING ERRCODE='PZ152';
 EXCEPTION WHEN SQLSTATE 'PZ152' THEN
  IF NOT (v_pos AND v_neg_epoch AND v_neg_contract
    AND v_neg_identity AND v_changed_contract AND v_pos_fresh) THEN
   RAISE EXCEPTION 'G2B_FIXTURE_NOT_ALL_TESTS';
  END IF;
 END;
 IF EXISTS (SELECT 1 FROM programacion.input_g2b_source_fixture_v1) THEN
   RAISE EXCEPTION 'G2B_FIXTURE_TEST_RESIDUE'; END IF;
 IF has_function_privilege('anon','programacion.fn_input_g2b_fixture_commit_gate_v1(uuid,bigint,integer,text,bigint,text)','EXECUTE')
   OR has_function_privilege('authenticated','programacion.fn_input_g2b_fixture_commit_gate_v1(uuid,bigint,integer,text,bigint,text)','EXECUTE')
   OR has_function_privilege('service_role','programacion.fn_input_g2b_fixture_commit_gate_v1(uuid,bigint,integer,text,bigint,text)','EXECUTE')
 THEN RAISE EXCEPTION 'G2B_FIXTURE_UNINTENDED_EXECUTE_PRIVILEGE'; END IF;
 v_evidence:=jsonb_build_object(
  'schema','IG_M107_G2B_ISOLATED_FIXTURE_ATOMIC_GATE_V1',
  'fixture_only',true,'fixture_rows_after_tests',0,'positive_baseline',v_pos,
  'negative_source_epoch',v_neg_epoch,'negative_contract',v_neg_contract,
  'negative_cross_run',v_neg_identity,'contract_epoch_bump',v_changed_contract,
  'positive_after_revalidation',v_pos_fresh,
  'same_transaction_check_and_close',true,'row_lock_for_update',true,
  'two_distinct_pg_sessions_executed',false,'committed_concurrent_source_mutation_tested',false,
  'all_real_source_writers_covered',false,'consumer_runtime_enabled',false,
  'g2b_pass',false,'cp3_closed',false,'canonical_triggers',v_triggers);
 INSERT INTO public.lf_error_knowledge
 (id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,
 frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia,created_at,updated_at,
 lifecycle_phase,root_cause_family,detectability,source_context,source_ref)
 VALUES(gen_random_uuid(),'IG-M107-G2B-FIXTURE-ATOMIC-GATE-020','GOVERNANCE',
 'G2B fixture aislado: cierre atómico bajo bloqueo y control de época',
 'Seis pruebas dentro de una transacción con rollback, 21 triggers intactos, sin acceso público. No sustituye prueba entre dos sesiones.',
 'Riesgo de cambios entre lectura congelada y aceptación; se necesita bloqueo incompatible con writes y comprobación final.',
 'G2B_ISOLATED_EPOCH_ROW_LOCK_FIXTURE',
 'No conectar consumidores ni afirmar G2B PASS antes de probar dos sesiones reales y cobertura de todas las fuentes/writers.',
 '6 assertions + rollback + ACL + topology en Migration Train. Verificar ledger y readback.',
 'HIGH',1,clock_timestamp(),clock_timestamp(),'IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.7','ACTIVO',
 v_evidence::text,clock_timestamp(),clock_timestamp(),'PREFLIGHT',
 'R4_NO_CUESTIONA','LOUD_EARLY','Fixture only; no real source updates or runtime consumer activation',
 'programacion.input_g2b_source_fixture_v1');
END $proof$;

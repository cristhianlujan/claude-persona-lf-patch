-- IG M10.7 G1: additive, non-public, data-only RUN_PINNED source context candidate.
-- G0 admitted on main: docs/ig/IG_EXECUTION_SOURCE_CONTEXT_V1_G0.md (PR #2739).
-- Canonical Router ACT-0001 => ACTUALIZACION_DB_LF => LF Migration Merge Train.
-- No CP3 mutation, no runtime activation, no trigger removal, no grant to clients.
DO $g0$
BEGIN
 IF to_regprocedure('programacion.fn_input_governance_run_context_packet_v1(bigint)') IS NOT NULL
 THEN RAISE EXCEPTION 'IG_M107_G1_PROVIDER_ALREADY_EXISTS'; END IF;
 IF EXISTS(SELECT 1 FROM public.lf_error_knowledge WHERE codigo='IG-M107-RUN-CONTEXT-CANDIDATE-G1-010')
 THEN RAISE EXCEPTION 'IG_M107_G1_EKB_ALREADY_EXISTS'; END IF;
END $g0$;

CREATE FUNCTION programacion.fn_input_governance_run_context_packet_v1(p_run_id bigint)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = 'pg_catalog','programacion'
AS $ig_context$
DECLARE
 v_run record;
 v_family_codes jsonb;
 v_family_refs jsonb;
 v_gap_refs jsonb;
 v_admission jsonb;
 v_identity_sha text;
BEGIN
 SELECT r.id,r.pantalla_id,r.version_id,r.status,r.contract_revision,
        r.contract_snapshot_sha256,r.source_snapshot_sha256,r.source_manifest,
        r.validator_identity,r.curator_identity,r.family_count
 INTO v_run FROM programacion.input_readiness_runs r WHERE r.id=p_run_id;
 IF NOT FOUND OR v_run.status <> 'VALIDATING' THEN
   RAISE EXCEPTION 'IG_CONTEXT_RUN_NOT_VALIDATING:%',p_run_id;
 END IF;
 IF v_run.source_snapshot_sha256 IS NULL
    OR v_run.contract_snapshot_sha256 IS NULL
    OR v_run.source_manifest IS NULL
    OR v_run.validator_identity IS NULL
    OR v_run.validator_identity=v_run.curator_identity THEN
   RAISE EXCEPTION 'IG_CONTEXT_RUN_NOT_PINNED_OR_INDEPENDENT:%',p_run_id;
 END IF;
 -- Real source readback per invocation; stored SHA alone is not freshness.
 v_admission:=programacion.fn_input_governance_continuation_currentness_v1(p_run_id);
 IF NOT coalesce((v_admission->>'continuation_current')::boolean,false) THEN
   RAISE EXCEPTION 'IG_CONTEXT_CURRENTNESS_REJECTED:%:%',p_run_id,
     coalesce(v_admission->>'code','UNKNOWN');
 END IF;
 SELECT coalesce(jsonb_agg(family_code ORDER BY family_code),'[]'::jsonb)
   INTO v_family_codes
 FROM programacion.input_family_assessments a WHERE a.run_id=p_run_id;
 IF jsonb_array_length(v_family_codes)<>v_run.family_count THEN
   RAISE EXCEPTION 'IG_CONTEXT_FAMILY_UNIVERSE_MISMATCH:%',p_run_id;
 END IF;
 SELECT coalesce(jsonb_agg(ref ORDER BY ref::text),'[]'::jsonb)
   INTO v_family_refs
 FROM (
   SELECT DISTINCT e.ref
   FROM programacion.input_family_assessments a
   CROSS JOIN LATERAL jsonb_array_elements(a.source_refs) e(ref)
   WHERE a.run_id=p_run_id
 ) u;
 SELECT coalesce(jsonb_agg(ref ORDER BY ref::text),'[]'::jsonb)
   INTO v_gap_refs
 FROM (
   SELECT DISTINCT e.ref
   FROM programacion.input_gap_proposals p
   CROSS JOIN LATERAL jsonb_array_elements(p.source_refs) e(ref)
   WHERE p.run_id=p_run_id
 ) u;
 v_identity_sha:=programacion.fn_v09_sha256_jsonb(
   programacion.fn_input_source_manifest_identity_v1(v_run.source_manifest));
 RETURN jsonb_build_object(
   'schema_version','IG_EXECUTION_SOURCE_CONTEXT_V1',
   'authority','INPUT_GOVERNANCE',
   'purpose','READ_ONLY_DATA_PACKET',
   'reuse_scope','RUN_PINNED_FIELDS_ONLY',
   'independent_validator_required',true,
   'source_currentness_checked',true,
   'no_semantic_verdict',true,
   'run_id',v_run.id,
   'pantalla_id',v_run.pantalla_id,
   'version_id',v_run.version_id,
   'contract_revision',v_run.contract_revision,
   'contract_snapshot_sha256',v_run.contract_snapshot_sha256,
   'source_snapshot_sha256',v_run.source_snapshot_sha256,
   'source_manifest_identity_sha256',v_identity_sha,
   'family_codes',v_family_codes,
   'distinct_family_source_refs',v_family_refs,
   'distinct_gap_source_refs',v_gap_refs,
   'curator_identity',v_run.curator_identity,
   'validator_identity',v_run.validator_identity
 );
END;
$ig_context$;

REVOKE ALL ON FUNCTION programacion.fn_input_governance_run_context_packet_v1(bigint) FROM PUBLIC;
COMMENT ON FUNCTION programacion.fn_input_governance_run_context_packet_v1(bigint) IS
 'IG_EXECUTION_SOURCE_CONTEXT_V1 / G0: candidate-only, data-only, currentness readback each call, no public execute, no Validator decision or CP3 transition.';

DO $test$
DECLARE
 v_code constant text:='IG-M107-RUN-CONTEXT-CANDIDATE-G1-010';
 v_before integer;
 v_latest bigint;
 v_temporary bigint;
 v_validator text;
 v_validator_component bigint;
 v_curator jsonb;
 v_packet jsonb;
 v_run programacion.input_readiness_runs%rowtype;
 v_error text;
 v_positive boolean:=false;
 v_payload jsonb;
BEGIN
 IF EXISTS(
  SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  CROSS JOIN LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
  WHERE n.nspname='programacion'
   AND p.proname='fn_input_governance_run_context_packet_v1'
   AND a.grantee=0 AND a.privilege_type='EXECUTE'
 ) THEN RAISE EXCEPTION 'IG_M107_G1_PUBLIC_EXECUTE_NOT_REVOKED'; END IF;

 SELECT count(*),max(id) INTO v_before,v_latest
 FROM programacion.input_readiness_runs WHERE pantalla_id=43;
 IF v_latest IS NULL
    OR (SELECT status FROM programacion.input_readiness_runs WHERE id=v_latest)<>'COMPLETED'
 THEN RAISE EXCEPTION 'IG_M107_G1_BASELINE_NOT_TERMINAL'; END IF;
 v_error:=NULL;
 BEGIN
  PERFORM programacion.fn_input_governance_run_context_packet_v1(v_latest+10000000);
 EXCEPTION WHEN OTHERS THEN v_error:=SQLERRM;
 END;
 IF v_error NOT LIKE 'IG_CONTEXT_RUN_NOT_VALIDATING:%'
 THEN RAISE EXCEPTION 'IG_M107_G1_MISSING_ID_ACCEPTED:%',v_error; END IF;
 v_error:=NULL;
 BEGIN
  PERFORM programacion.fn_input_governance_run_context_packet_v1(v_latest);
 EXCEPTION WHEN OTHERS THEN v_error:=SQLERRM;
 END;
 IF v_error NOT LIKE 'IG_CONTEXT_RUN_NOT_VALIDATING:%'
 THEN RAISE EXCEPTION 'IG_M107_G1_TERMINAL_RUN_ACCEPTED:%',v_error; END IF;

 -- One real Curator run for one complex screen, fully subtransaction-rolled back.
 BEGIN
  v_curator:=programacion.fn_input_governance_direct_step_v1(43,'MANUAL');
  IF v_curator->>'status'<>'VALIDATOR_RUNTIME_REQUIRED'
     OR v_curator->>'step'<>'CURATOR_MATERIALIZED'
  THEN RAISE EXCEPTION 'IG_M107_G1_CURATOR_NOT_MATERIALIZED:%',left(v_curator::text,300); END IF;
  v_temporary:=(v_curator->>'run_id')::bigint;
  SELECT * INTO STRICT v_run FROM programacion.input_readiness_runs WHERE id=v_temporary;
  IF v_run.status<>'CURATING' OR v_run.source_snapshot_sha256 IS NOT NULL
     OR (SELECT count(*) FROM programacion.input_family_assessments WHERE run_id=v_temporary)<>47
  THEN RAISE EXCEPTION 'IG_M107_G1_CURATOR_READBACK_INVALID'; END IF;
  v_error:=NULL;
  BEGIN
    PERFORM programacion.fn_input_governance_run_context_packet_v1(v_temporary);
  EXCEPTION WHEN OTHERS THEN v_error:=SQLERRM;
  END;
  IF v_error NOT LIKE 'IG_CONTEXT_RUN_NOT_VALIDATING:%'
  THEN RAISE EXCEPTION 'IG_M107_G1_CURATING_RUN_ACCEPTED:%',v_error; END IF;
  v_validator:='INPUT_VALIDATOR:SQL:ig-governed-dispatch-v1:'||gen_random_uuid()::text;
  SELECT id INTO STRICT v_validator_component
    FROM programacion.componentes
    WHERE version_id=v_run.version_id AND componente_codigo='INPUT_VALIDATOR';
  UPDATE programacion.input_readiness_runs
     SET status='VALIDATING',validator_identity=v_validator,
         validator_component_id=v_validator_component
   WHERE id=v_temporary;
  SELECT * INTO STRICT v_run FROM programacion.input_readiness_runs WHERE id=v_temporary;
  IF v_run.status<>'VALIDATING' OR v_run.source_snapshot_sha256 IS NULL
  THEN RAISE EXCEPTION 'IG_M107_G1_NO_VALIDATING_SNAPSHOT'; END IF;
  v_packet:=programacion.fn_input_governance_run_context_packet_v1(v_temporary);
  IF v_packet->>'schema_version'<>'IG_EXECUTION_SOURCE_CONTEXT_V1'
     OR (v_packet->>'run_id')::bigint<>v_temporary
     OR (v_packet->>'version_id')::bigint<>v_run.version_id
     OR v_packet->>'source_snapshot_sha256' IS DISTINCT FROM v_run.source_snapshot_sha256
     OR v_packet->>'contract_snapshot_sha256' IS DISTINCT FROM v_run.contract_snapshot_sha256
     OR v_packet->>'validator_identity' IS DISTINCT FROM v_validator
     OR jsonb_array_length(v_packet->'family_codes')<>47
     OR jsonb_array_length(v_packet->'distinct_family_source_refs')=0
     OR jsonb_array_length(v_packet->'distinct_gap_source_refs')=0
     OR (v_packet->>'no_semantic_verdict')::boolean IS DISTINCT FROM true
     OR (v_packet->>'source_currentness_checked')::boolean IS DISTINCT FROM true
  THEN RAISE EXCEPTION 'IG_M107_G1_PACKET_PARITY_REJECTED:%',left(v_packet::text,350); END IF;
  IF v_packet->>'source_manifest_identity_sha256' IS DISTINCT FROM
     programacion.fn_v09_sha256_jsonb(
       programacion.fn_input_source_manifest_identity_v1(v_run.source_manifest))
  THEN RAISE EXCEPTION 'IG_M107_G1_MANIFEST_SHA_MISMATCH'; END IF;
  v_positive:=true;
  RAISE EXCEPTION 'IG_M107_G1_ROLLBACK_EXPECTED' USING ERRCODE='PZ142';
 EXCEPTION WHEN SQLSTATE 'PZ142' THEN
  IF NOT v_positive THEN RAISE EXCEPTION 'IG_M107_G1_FALSE_POSITIVE'; END IF;
 END;

 IF v_temporary IS NULL OR NOT v_positive
    OR (SELECT count(*) FROM programacion.input_readiness_runs WHERE pantalla_id=43)<>v_before
    OR EXISTS(SELECT 1 FROM programacion.input_readiness_runs WHERE id=v_temporary)
    OR EXISTS(SELECT 1 FROM programacion.input_family_assessments WHERE run_id=v_temporary)
    OR EXISTS(SELECT 1 FROM programacion.input_gap_proposals WHERE run_id=v_temporary)
 THEN RAISE EXCEPTION 'IG_M107_G1_ROLLBACK_RESIDUE_OR_MISSING_POSITIVE'; END IF;

 v_payload:=jsonb_build_object(
   'schema_version','IG_EXECUTION_SOURCE_CONTEXT_V1',
   'g0_contract','docs/ig/IG_EXECUTION_SOURCE_CONTEXT_V1_G0.md',
   'positive_temp_validating_packet',true,
   'negative_run_missing',true,'negative_run_terminal',true,
   'negative_run_curating',true,'all_runtime_changes_rolled_back',true,
   'source_manifest_sha_checked',true,'public_execute',false,
   'provider_caller_granted',false,'runtime_consumers_activated',false,
   'checkpoint_closed',false,'cross_transaction_concurrency_proven',false,
   'performance_improvement_proven',false,'next','G2 concurrency/readback tests');
 INSERT INTO public.lf_error_knowledge(
    id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,
    validacion,severidad,frecuencia,primera_vez,ultima_vez,lote_origen,
    estado,evidencia,created_at,updated_at,lifecycle_phase,root_cause_family,
    detectability,source_context,source_ref)
 VALUES (
    gen_random_uuid(),v_code,'GOVERNANCE',
    'Contexto compartido IG no decisional como candidato no activo G1',
    'Funcion nueva solo RUN_PINNED y solo VALIDATING con autoridad/currentness independiente. Sin concesion a PUBLIC. Una pantalla compleja: prueba positiva material temporal y negativas faltante/terminal/CURATING, todos los datos runtime revertidos.',
    'Trabajo redundante de fuentes y referencias en familias/propuestas. Se requiere contrato de reuse sin copiar decisiones y sin cache no verificado.',
    'GOVERNED_RUN_PINNED_SOURCE_CONTEXT',
    'No admitir reutilizacion de datos mutables sin lectura de autoridad, no ocultar cambios concurrentes, no compartir veredictos, no eliminar triggers ni controles. G2 debe probar fuentes cambiadas y aislamiento entre llamadas antes de conectar consumidores.',
    'G1 solo provisto y verificado sin runtime grant. Negativos y positivo de datos con rollback total. CP3 permanece pendiente hasta su prueba integral.',
    'HIGH',1,clock_timestamp(),clock_timestamp(),
    'IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.7','ACTIVO',
    v_payload::text,clock_timestamp(),clock_timestamp(),
    'PREFLIGHT','R4_NO_CUESTIONA','LOUD_EARLY',
    'G1 provider candidate no-public-execute through LF Migration Merge Train',
    'programacion.fn_input_governance_run_context_packet_v1(bigint)'
 );
 IF (SELECT count(*) FROM public.lf_error_knowledge WHERE codigo=v_code)<>1
 THEN RAISE EXCEPTION 'IG_M107_G1_EKB_READBACK_FAILED'; END IF;
END $test$;

DO $pre$
BEGIN
 IF md5(pg_get_functiondef('programacion.fn_input_deterministic_assess(jsonb,text,jsonb,jsonb)'::regprocedure))
   IS DISTINCT FROM '9ffa930caf6c197993bd2c3f36c9f8d9' THEN
   RAISE EXCEPTION 'IG_M107_G_DETERMINISTIC_ASSESS_DRIFT'; END IF;
 IF (SELECT count(*) FROM public.lf_error_knowledge where codigo in
   ('IG-M107-G-NATIVE-SNAPSHOT-DIGEST-COST-040','IG-M107-POST-BCD-FULLRUN-TIMING-039'))<>2
 THEN RAISE EXCEPTION 'IG_M107_G_MEASUREMENT_PRECEDENT_MISSING'; END IF;
 IF (SELECT count(*) FROM pg_trigger t where t.tgrelid='programacion.input_family_assessments'::regclass
 and t.tgfoid='programacion.fn_input_curator_compose_before_insert_v1()'::regprocedure
 and t.tgenabled IN ('O','A') and (t.tgtype&2)=2 and (t.tgtype&4)=4)<>1
 THEN RAISE EXCEPTION 'IG_M107_G_PRIVILEGED_CURATOR_TRIGGER_MISSING'; END IF;
 IF (SELECT status FROM programacion.input_readiness_runs WHERE id=944)<>'COMPLETED'
  OR (programacion.fn_input_run_source_currentness_v1(944)->>'source_current')<>'true'
 THEN RAISE EXCEPTION 'IG_M107_G_PROOF_SOURCE_NOT_CURRENT'; END IF;
 IF EXISTS(SELECT 1 FROM public.lf_error_knowledge WHERE codigo='IG-M107-G-CURATOR-SQL-FASTPATH-041')
 THEN RAISE EXCEPTION 'IG_M107_G_EKB_ALREADY_RECORDED'; END IF;
END $pre$;
CREATE OR REPLACE FUNCTION programacion.fn_input_deterministic_assess(p_subject jsonb, p_family text, p_graph jsonb, p_contract jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
declare
  v_screen int; v_version bigint; v_family text:=upper(nullif(trim(p_family),''));
  v_policy jsonb; v_ref jsonb; v_resolved jsonb; v_stage jsonb; v_assessment jsonb; v_payload jsonb;
  v_graph_sha text; v_contract_sha text;
  v_ctx jsonb; v_trusted_context boolean:=false;
begin
  if jsonb_typeof(p_subject)<>'object' or jsonb_typeof(p_graph)<>'object' or jsonb_typeof(p_contract)<>'object' then raise exception 'DETERMINISTIC_ASSESS_INVALID_INPUT'; end if;
  if upper(coalesce(p_subject->>'source_class','DETERMINISTIC'))='SEMANTIC' then raise exception 'DETERMINISTIC_ASSESS_SEMANTIC_INPUT_FORBIDDEN'; end if;
  v_screen:=nullif(p_subject->>'pantalla_id','')::int;
  v_version:=coalesce(nullif(p_subject->>'version_id','')::bigint,nullif(p_graph->>'agent_contract_version_id','')::bigint);
  if v_screen is null or v_version is null or v_family is null then raise exception 'DETERMINISTIC_ASSESS_IDENTITY_REQUIRED'; end if;
  if p_contract->>'contract_revision' not in ('5.13','5.13.1') then raise exception 'DETERMINISTIC_ASSESS_CONTRACT_REVISION'; end if;
  if p_graph->>'graph_contract' is distinct from p_contract->>'screen_graph_contract' then raise exception 'DETERMINISTIC_ASSESS_GRAPH_CONTRACT'; end if;
  if nullif(p_graph->>'agent_contract_version_id','')::bigint is distinct from v_version then raise exception 'DETERMINISTIC_ASSESS_VERSION_PIN'; end if;
  v_policy:=p_contract->'family_stage_requirements'->v_family;
  if v_policy is null then raise exception 'DETERMINISTIC_ASSESS_FAMILY'; end if;
  if coalesce(p_subject->>'applicability','')='' or coalesce(p_subject->>'coverage_status','')='' or coalesce(p_subject->>'well_defined_status','')='' then raise exception 'DETERMINISTIC_ASSESS_STATUS_REQUIRED'; end if;
  v_ref:=jsonb_build_object('kind','SCREEN_CANONICAL_GRAPH','pantalla_id',v_screen);
  v_graph_sha:=programacion.fn_v09_sha256_jsonb(p_graph);
  -- Only the privileged BEFORE INSERT Curator trigger can use the frozen graph.
  -- Ordinary invokers must still resolve the canonical source themselves.
  if pg_trigger_depth()>0
     and current_user=(select pg_get_userbyid(p.proowner) from pg_proc p
       where p.oid='programacion.fn_input_curator_compose_before_insert_v1()'::regprocedure)
  then
    begin
      v_ctx:=nullif(current_setting('lf.input_request_context_v1',true),'')::jsonb;
    exception when others then
      raise exception 'INPUT_REQUEST_CONTEXT_INVALID';
    end;
    if v_ctx is not null then
      if v_ctx->>'schema_version' is distinct from 'INPUT_GOVERNANCE_REQUEST_CONTEXT_V1'
        or v_ctx->>'strategy' not in
           ('BOOTSTRAP','REBIND','SOURCE_STALE_RECURATE','FULL_RECURATE')
        or coalesce((v_ctx->>'pantalla_id')::integer,-1)<>v_screen
        or coalesce((v_ctx->>'version_id')::bigint,-1)<>v_version
        or nullif(v_ctx->>'request_identity','') is null then
          raise exception 'INPUT_REQUEST_CONTEXT_IDENTITY_MISMATCH:%:%',v_screen,v_version;
      end if;
      if jsonb_typeof(v_ctx->'graph') is distinct from 'object'
        or v_ctx->'graph' is distinct from p_graph
        or v_ctx->>'graph_sha256' is distinct from v_graph_sha then
          raise exception 'INPUT_REQUEST_CONTEXT_GRAPH_SHA_MISMATCH:%:%',v_screen,v_version;
      end if;
      if not exists (
        select 1 from programacion.input_readiness_runs run
        where run.pantalla_id=v_screen and run.version_id=v_version
          and run.status='CURATING'
          and run.curator_identity=v_ctx->>'request_identity'
      ) then raise exception 'INPUT_REQUEST_CONTEXT_CURATOR_RUN_MISMATCH:%:%',v_screen,v_version;
      end if;
      v_trusted_context:=true;
    end if;
  end if;
  if v_trusted_context then
    v_resolved:=jsonb_build_object('ref',v_ref,'observed_sha256',v_graph_sha);
  else
    v_resolved:=programacion.fn_input_resolve_source_ref(v_ref,v_screen,v_version);
  end if;
  if v_resolved->>'observed_sha256' is distinct from v_graph_sha then raise exception 'DETERMINISTIC_ASSESS_GRAPH_DRIFT'; end if;
  v_contract_sha:=programacion.fn_v09_sha256_jsonb(p_contract);
  v_stage:=programacion.fn_input_stage_resolve_v2(v_family,v_screen,v_version,p_subject->>'coverage_status',p_subject->>'well_defined_status');
  v_assessment:=p_subject-'pantalla_id'-'version_id'-'source_class';
  if jsonb_typeof(v_assessment->'blockers') is distinct from 'array' then v_assessment:=jsonb_set(v_assessment,'{blockers}','[]'::jsonb,true); end if;
  v_assessment:=programacion.fn_input_apply_stage_authority_v2(v_assessment,v_screen,v_family,v_version);
  v_payload:=jsonb_build_object('contract','DETERMINISTIC_ASSESS_V1','subject_identity',jsonb_build_object('pantalla_id',v_screen,'version_id',v_version),'family_code',v_family,'contract_revision',p_contract->>'contract_revision','contract_sha256',v_contract_sha,'graph_contract',p_graph->>'graph_contract','graph_sha256',v_graph_sha,'graph_resolution',jsonb_build_object('ref',v_ref,'observed_sha256',v_resolved->>'observed_sha256','matches_provided',true),'family_policy',v_policy,'stage_resolution',v_stage,'assessment',v_assessment,'semantic_boundary','EXCLUDED','semantic_calls','[]'::jsonb);
  return v_payload||jsonb_build_object('result_sha256',programacion.fn_v09_sha256_jsonb(v_payload));
end;$function$;
DO $proof$
DECLARE
 v_identity text; v_out jsonb; v_run_id bigint;
 v_orig integer; v_new_families integer:=0; v_new_proposals integer:=0;
 v_positive_count integer:=0; v_base programacion.input_readiness_runs%rowtype;
 v_graph jsonb; v_contract jsonb; v_subject jsonb; v_ctx jsonb;
 v_reference jsonb; v_sha text; v_bad_sha text; v_bad_id text;
BEGIN
 SELECT count(*) INTO v_orig FROM programacion.input_readiness_runs WHERE pantalla_id=43;
 SELECT * INTO STRICT v_base FROM programacion.input_readiness_runs WHERE id=944;
 BEGIN
   v_identity:='INPUT_CURATOR:SQL:ig-governed-dispatch-v1:'||gen_random_uuid()::text;
   v_out:=programacion.fn_input_governance_curator_materialize_v1(
       43,'MANUAL',v_identity,true);
   v_run_id:=(v_out->>'run_id')::bigint;
   IF v_out->>'status' IS DISTINCT FROM 'VALIDATOR_RUNTIME_REQUIRED'
     OR v_out->>'strategy' IS DISTINCT FROM 'REBIND'
     OR v_out#>>'{request_context_summary,graph_build_exactly_once}' IS DISTINCT FROM 'true'
   THEN RAISE EXCEPTION 'IG_M107_G_SELFTEST_REBIND_NOT_READY:%',left(v_out::text,450); END IF;
   IF (SELECT curator_identity FROM programacion.input_readiness_runs WHERE id=v_run_id)
        IS DISTINCT FROM v_identity
      OR (SELECT status FROM programacion.input_readiness_runs WHERE id=v_run_id)<>'CURATING'
   THEN RAISE EXCEPTION 'IG_M107_G_CURATOR_IDENTITY_UNBOUND'; END IF;
   SELECT count(*),count(*) FILTER (
       WHERE curator_evidence->'core_invocation'->>'contract'='M5_4_DETERMINISTIC_ASSESS_BRIDGE_V1'
         AND curator_evidence->'core_invocation'->>'result_sha256' ~ '^[0-9a-f]{64}$')
    INTO v_new_families,v_positive_count
   FROM programacion.input_family_assessments WHERE run_id=v_run_id;
   SELECT count(*) INTO v_new_proposals FROM programacion.input_gap_proposals WHERE run_id=v_run_id;
   IF v_new_families<>47 OR v_positive_count<>47 OR v_new_proposals<>20 THEN
     RAISE EXCEPTION 'IG_M107_G_TEMP_FAMILIES_PROPOSALS_INVALID:%:%:%',
       v_new_families,v_positive_count,v_new_proposals; END IF;
   -- A normal non-trigger call must retain the original canonical resolution.
   SELECT c.especificacion INTO STRICT v_contract FROM programacion.contratos c
    WHERE c.version_id=v_base.version_id AND c.contrato_codigo='INPUT_READINESS_CONTRACT'
      AND c.estado='defined' AND c.fail_closed ORDER BY c.id DESC LIMIT 1;
   SELECT (to_jsonb(a)-'id'-'run_id'-'family_code') ||
      jsonb_build_object('pantalla_id',43,'version_id',v_base.version_id,'source_class','DETERMINISTIC')
    INTO STRICT v_subject
   FROM programacion.input_family_assessments a
   WHERE a.run_id=944 AND a.family_code='SCREEN_IDENTITY';
   v_graph:=programacion.fn_input_screen_canonical_graph(43,v_base.version_id);
   v_sha:=programacion.fn_v09_sha256_jsonb(v_graph);
   v_reference:=programacion.fn_input_deterministic_assess(
       v_subject,'SCREEN_IDENTITY',v_graph,v_contract);
   IF v_reference->>'graph_sha256' IS DISTINCT FROM v_sha
    OR v_reference#>>'{graph_resolution,observed_sha256}' IS DISTINCT FROM v_sha
   THEN RAISE EXCEPTION 'IG_M107_G_CANONICAL_FALLBACK_HASH_FAILED'; END IF;
   v_ctx:=jsonb_build_object(
     'schema_version','INPUT_GOVERNANCE_REQUEST_CONTEXT_V1',
     'pantalla_id',43,'version_id',v_base.version_id,
     'request_identity',v_identity,'strategy','REBIND',
     'graph',v_graph,'graph_sha256',v_sha);
   PERFORM set_config('lf.input_request_context_v1',
       jsonb_set(v_ctx,'{graph_sha256}',to_jsonb(repeat('0',64)))::text,true);
   BEGIN PERFORM programacion.fn_input_deterministic_assess(
      v_subject,'SCREEN_IDENTITY',v_graph,v_contract);
   EXCEPTION WHEN OTHERS THEN v_bad_sha:=SQLERRM; END;
   IF position('INPUT_REQUEST_CONTEXT_GRAPH_SHA_MISMATCH' in coalesce(v_bad_sha,''))=0
   THEN RAISE EXCEPTION 'IG_M107_G_SHA_TAMPER_NOT_REJECTED:%',v_bad_sha; END IF;
   PERFORM set_config('lf.input_request_context_v1',
     jsonb_set(v_ctx,'{pantalla_id}','999'::jsonb)::text,true);
   BEGIN PERFORM programacion.fn_input_deterministic_assess(
      v_subject,'SCREEN_IDENTITY',v_graph,v_contract);
   EXCEPTION WHEN OTHERS THEN v_bad_id:=SQLERRM; END;
   IF position('INPUT_REQUEST_CONTEXT_IDENTITY_MISMATCH' in coalesce(v_bad_id,''))=0
   THEN RAISE EXCEPTION 'IG_M107_G_IDENTITY_TAMPER_NOT_REJECTED:%',v_bad_id; END IF;
   PERFORM set_config('lf.input_request_context_v1','',true);
   RAISE EXCEPTION 'IG_M107_G_EXPECTED_TEMP_ROLLBACK' USING ERRCODE='PZ127';
 EXCEPTION WHEN SQLSTATE 'PZ127' THEN NULL;
 END;
 IF (SELECT count(*) FROM programacion.input_readiness_runs WHERE pantalla_id=43)<>v_orig
   OR EXISTS(SELECT 1 FROM programacion.input_readiness_runs WHERE id=v_run_id)
   OR EXISTS(SELECT 1 FROM programacion.input_family_assessments WHERE run_id=v_run_id)
   OR EXISTS(SELECT 1 FROM programacion.input_gap_proposals WHERE run_id=v_run_id)
   OR v_positive_count<>47 OR v_new_proposals<>20
 THEN RAISE EXCEPTION 'IG_M107_G_TEST_RESIDUE_OR_PARITY'; END IF;
 IF (SELECT count(*) FROM pg_trigger t where t.tgrelid='programacion.input_family_assessments'::regclass
    and (t.tgtype&16)=16 and t.tgenabled IN ('O','A') and not t.tgisinternal)<>6
 THEN RAISE EXCEPTION 'IG_M107_G_FAMILY_UPDATE_TRIGGERS_CHANGED'; END IF;
 INSERT INTO public.lf_error_knowledge(
 id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
 severidad,frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia,
 created_at,updated_at,lifecycle_phase,root_cause_family,detectability,
 source_context,source_ref)
 VALUES(gen_random_uuid(),'IG-M107-G-CURATOR-SQL-FASTPATH-041','GOVERNANCE',
 'M10.7 G: reutilizar el hash del grafo solo dentro del Curator SQL privilegiado',
 'El evaluador determinista conserva su resolución original para invocaciones ordinarias; durante el trigger Curator SECURITY DEFINER el grafo ya congelado se usa tras comprobar identidad, SHA y run CURATING.',
 'La resolución adicional del grafo por cada familia sobre el mismo contexto elevaba el costo de 47 evaluaciones; G/EKB 040 comparó ~7.06s vs ~2.47s por 12 operaciones.',
 'CURATOR_TRUSTED_TRIGGER_SAME_TRANSACTION_GRAPH_DIGEST',
 'Solo ruta interna del trigger de Curator, propietario efectivo, run CURATING, estrategia y SHA idénticos. No confiar en GUC externa, no omitir readback fuera de la ruta, no modificar Validator, contratos ni triggers.',
 'Train: selftest REBIND con 47 familias, 20 propuestas, 47 core receipts; comparador ordinario con SHA canónico, negativos SHA/identidad y rollback limpio.',
 'MEDIUM',1,clock_timestamp(),clock_timestamp(),
 'IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.7/G','ACTIVO',
 jsonb_build_object(
  'schema_version','IG_M107_G_CURATOR_TRUSTED_FASTPATH_V2',
  'screen_id',43,'baseline_run',944,'rolled_back_run',v_run_id,
  'curator_families_proven',v_positive_count,
  'proposals_materialized',v_new_proposals,'fallback_readback_kept',true,
  'only_privileged_insert_trigger',true,'corrupt_context_rejected',true,
  'wrong_identity_rejected',true,'rollback_clean',true,
  'family_update_triggers',6,
  'actual_e2e_speedup_measured',false,'CP3_closed',false)::text,
 clock_timestamp(),clock_timestamp(),'VALIDATION','R5_EROSION_PROCESO',
 'LOUD_EARLY','M10.7 G native Curator SQL fixed-scope selftest',
 'supabase/migrations/lf_ig_m107_g_curator_sql_native_fastpath_v1.sql');
END $proof$;
-- LF #3779 | Single-transaction governed owner bulk for the EXISTING rule table.
-- Depends on #3785 history, #3786 admin and state-aware skill readback.
-- No tables, parallel registrars or Router modifications. No production deployment.
BEGIN;
DO $scope_gate$
BEGIN
 IF to_regprocedure('public.lf_rule_update_history_seal_v1()') IS NULL
 OR to_regprocedure('public.lf_regla_admin_governed_write_v1(text,text,text,jsonb)') IS NULL
 OR position('RULE_CHILD_ADMIN_HISTORY_OR_STATE_MISMATCH' in pg_get_functiondef(
    'public.lf_skill_rule_child_readback_v1(text,text,text)'::regprocedure))=0
 OR position('BLOCK_RULE_FUNCTIONAL_ORIGINAL_AUTHORITY_UNVERIFIED' in pg_get_functiondef(
    'public.lf_skill_o_rule_update_v1(text,jsonb,text,text,text)'::regprocedure))=0
 THEN RAISE EXCEPTION 'BLOCK_RULE_BULK_PREREQUISITES_NOT_INSTALLED'; END IF;
 IF to_regprocedure('public.lf_rule_admin_bulk_atomic_v1(text,text)') IS NOT NULL
 THEN RAISE EXCEPTION 'BLOCK_RULE_BULK_ALREADY_INSTALLED'; END IF;
END $scope_gate$;

CREATE OR REPLACE FUNCTION public.lf_skill_o_rule_update_v1(p_child text, p_input jsonb, p_parent text, p_run text, p_request_sha text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public', 'lf_ops', 'extensions'
AS $function$
DECLARE
 v_par public.lf_operation_execution%ROWTYPE;
 v_inv public.lf_skill_invocation_v1%ROWTYPE;
 v_before lf_ops.reglas%ROWTYPE;
 v_after jsonb;
 v_profile_output jsonb;
 v_patch jsonb;
 v_changes jsonb;
 v_source_refs jsonb;
 v_semantic jsonb;
 v_decision text;
 v_rule text;
 v_screen text;
 v_snapshot text;
 v_out_sha text;
 v_step_payload jsonb;
 v_trust jsonb;
 v_rec jsonb;
 v_written jsonb;
 v_mode jsonb;
 v_reservation jsonb;
 v_field text;
 v_current text;
 v_next text;
 v_old_title text;
 v_old_desc text;
 v_old_reason text;
 v_new_title text;
 v_new_desc text;
 v_new_reason text;
 v_changed integer := 0;
 v_n integer;
 v_after_sha text;
 v_history_delta jsonb;
 v_change_kind text;
 v_new_categoria text;
 v_new_config jsonb;
 v_new_transversal boolean;
 v_new_origen text;
 v_max_patch_fields integer;
 v_expected_result text;
 v_expected_state text;
 v_bulk_id text;
 v_bulk_authority jsonb;
 v_pre_schema_row jsonb;
 v_evidence text;
 v_steps text[] := ARRAY[
  'ekb_preflight','classify','existing_check','destination_validate',
  'candidate_write','readback','trace_close'
 ];
 v_status text;
BEGIN
 IF p_input IS NULL OR jsonb_typeof(p_input)<>'object'
    OR coalesce(p_input->>'regla_codigo','') !~ '^[A-Z0-9][A-Z0-9_-]{3,159}$'
    OR coalesce(p_input->>'analysis_snapshot_sha256','') !~ '^[0-9a-f]{64}$'
    OR coalesce(p_input->>'decision_id','')=''
    OR jsonb_typeof(p_input->'candidate_patch') IS DISTINCT FROM 'object'
    OR p_input->'candidate_patch'->>'rule_code' IS DISTINCT FROM p_input->>'regla_codigo'
    OR p_input->'candidate_patch'->>'change_kind'
       NOT IN ('DOCUMENTARY_ONLY','ADMINISTRATIVE_ONLY','FUNCTIONAL_CANDIDATE')
    OR jsonb_typeof(p_input->'candidate_patch'->'changes') IS DISTINCT FROM 'object' THEN
    RAISE EXCEPTION 'BLOCK_RULE_CHILD_INPUT_OR_PATCH_CONTRACT';
 END IF;
 v_rule := p_input->>'regla_codigo';
 v_patch := p_input->'candidate_patch';
 v_changes := v_patch->'changes';
 v_change_kind := v_patch->>'change_kind';
 v_bulk_id:=nullif(p_input->>'rule_owner_batch_id','');
 v_max_patch_fields:=CASE v_change_kind
   WHEN 'ADMINISTRATIVE_ONLY' THEN 2
   WHEN 'DOCUMENTARY_ONLY' THEN 3 ELSE 7 END;
 IF (SELECT count(*) FROM jsonb_object_keys(v_patch))<>3
    OR (SELECT count(*) FROM jsonb_object_keys(v_changes))
        NOT BETWEEN 1 AND v_max_patch_fields THEN
    RAISE EXCEPTION 'BLOCK_RULE_CHILD_PATCH_KEYS';
 END IF;
 FOR v_field IN SELECT jsonb_object_keys(v_changes) LOOP
    IF (v_change_kind='DOCUMENTARY_ONLY'
        AND v_field IN ('titulo','descripcion','razon')
        AND jsonb_typeof(v_changes->v_field)='string'
        AND length(btrim(v_changes->>v_field)) BETWEEN 8 AND 8000)
    OR (v_change_kind='ADMINISTRATIVE_ONLY'
        AND v_field IN ('created_by','owner_name')
        AND jsonb_typeof(v_changes->v_field)='string'
        AND length(btrim(v_changes->>v_field)) BETWEEN 1 AND 128)
    OR (v_change_kind='FUNCTIONAL_CANDIDATE'
        AND ((v_field IN ('titulo','descripcion','razon','categoria','origen')
            AND jsonb_typeof(v_changes->v_field)='string'
            AND length(btrim(v_changes->>v_field)) BETWEEN 8 AND 8000)
         OR (v_field='valor_config'
            AND jsonb_typeof(v_changes->v_field)='object')
         OR (v_field='es_transversal'
            AND jsonb_typeof(v_changes->v_field)='boolean')))
    THEN CONTINUE; END IF;
    RAISE EXCEPTION 'BLOCK_RULE_CHILD_PROTECTED_OR_INVALID_FIELD:%',v_field;
 END LOOP;

 SELECT * INTO v_par FROM public.lf_operation_execution
 WHERE execution_id=p_parent AND operation_code='EJECUCION_PERFIL_LF'
   AND status='IN_PROGRESS' FOR UPDATE;
 IF NOT FOUND OR v_par.target_type<>'PERFIL'
    OR v_par.manifest->>'read_only' IS DISTINCT FROM 'true'
    OR v_par.manifest->>'no_write' IS DISTINCT FROM 'true'
    OR v_par.manifest->>'no_promotion' IS DISTINCT FROM 'true'
    OR v_par.manifest->'router_profile_handoff'->'router_authorization_receipt'->>'profile_execution_allowed' IS DISTINCT FROM 'true'
 THEN RAISE EXCEPTION 'BLOCK_RULE_CHILD_PARENT_NOT_AUTHORIZED'; END IF;
 IF NOT EXISTS (SELECT 1 FROM public.lf_profile_write_authority_v1
    WHERE profile_code=v_par.target_code
      AND operation_code='ACTUALIZACION_REGLA_LF' AND status='ACTIVE') THEN
    RAISE EXCEPTION 'BLOCK_RULE_CHILD_PROFILE_OPERATION_AUTHORITY'; END IF;
 SELECT * INTO v_inv FROM public.lf_skill_invocation_v1
 WHERE skill_run_id=p_run AND skill_code='RULE_UPDATE_APPLY'
   AND child_execution_id=p_child AND parent_execution_id=p_parent
   AND profile_code=v_par.target_code AND status='COMPLETED'
   AND input_sha256=encode(extensions.digest(convert_to(p_input::text,'UTF8'),'sha256'),'hex')
 FOR UPDATE;
 IF NOT FOUND OR p_request_sha IS DISTINCT FROM v_par.request_sha256 THEN
    RAISE EXCEPTION 'BLOCK_RULE_CHILD_INVOCATION_OR_REQUEST_BINDING'; END IF;
 -- Profile output is the ONLY authority for exact patch bytes. The caller may
 -- echo that patch but cannot choose new values or target independently.
 IF NOT EXISTS(SELECT 1 FROM public.lf_operation_execution_steps
    WHERE execution_id=p_parent AND step_id='output_validate'
      AND status='STEP_PASS_WITH_EVIDENCE'
      AND evidence_payload->>'output_contract_result'='PASS') THEN
    RAISE EXCEPTION 'BLOCK_RULE_CHILD_PROFILE_OUTPUT_NOT_VALIDATED'; END IF;
 SELECT evidence_payload->'semantic_judge_result' INTO v_semantic
 FROM public.lf_operation_execution_steps
 WHERE execution_id=p_parent AND step_id='semantic_judge'
   AND status='STEP_PASS_WITH_EVIDENCE'
   AND evidence_payload->'blocking_codes'='[]'::jsonb;
 IF v_semantic IS NULL OR v_semantic->>'verdict'
      NOT IN ('PASS_INDEPENDENT_SEMANTIC','PASS_REVIEWED_CURRENT_CONTEXT') THEN
    RAISE EXCEPTION 'BLOCK_RULE_CHILD_SEMANTIC_JUDGE_NOT_CLEAN'; END IF;
 SELECT evidence_payload->'profile_output' INTO v_profile_output
 FROM public.lf_operation_execution_steps
 WHERE execution_id=p_parent AND step_id='execute_profile'
   AND status='STEP_PASS_WITH_EVIDENCE';
 IF v_profile_output IS NULL OR v_profile_output->>'worker' IS DISTINCT FROM 'product_director_lf'
    OR v_profile_output->>'output_type' IS DISTINCT FROM 'PRODUCT_DIRECTION_SPEC'
    OR v_profile_output->>'self_verdict' IS DISTINCT FROM 'PASS'
    OR v_profile_output->'deliverable_created'->>'authority_status' IS NULL
    OR v_profile_output->'deliverable_created'->>'authority_status'
          NOT IN ('SUPPORTED','CONFLICT_RESOLVED') THEN
    RAISE EXCEPTION 'BLOCK_RULE_CHILD_PRODUCT_DECISION_NOT_FOUND'; END IF;
 v_out_sha := encode(extensions.digest(convert_to(v_profile_output::text,'UTF8'),'sha256'),'hex');
 IF v_profile_output->'deliverable_created'->'product_decision'->>'decision_id'
       IS DISTINCT FROM p_input->>'decision_id' THEN
    RAISE EXCEPTION 'BLOCK_RULE_CHILD_PATCH_NOT_IN_JUDGED_OUTPUT'; END IF;
 IF v_bulk_id IS NOT NULL THEN
   v_bulk_authority:=v_profile_output#>'{deliverable_created,governed_rule_batch}';
   IF v_change_kind IS DISTINCT FROM 'ADMINISTRATIVE_ONLY'
      OR jsonb_typeof(v_bulk_authority) IS DISTINCT FROM 'object'
      OR v_bulk_authority->>'batch_id' IS DISTINCT FROM v_bulk_id
      OR v_bulk_authority->>'scope' IS DISTINCT FROM 'ALL_CANONICAL_RULES'
      OR v_bulk_authority->>'operation_code' IS DISTINCT FROM 'ACTUALIZACION_REGLA_LF'
      OR v_bulk_authority->>'change_kind' IS DISTINCT FROM 'ADMINISTRATIVE_ONLY'
      OR v_bulk_authority->'changes' IS DISTINCT FROM v_changes
      OR v_patch IS DISTINCT FROM jsonb_build_object(
          'rule_code',v_rule,'change_kind','ADMINISTRATIVE_ONLY',
          'changes',v_bulk_authority->'changes')
      OR (SELECT md5(string_agg(r.id::text||':'||r.codigo,E'\n'
                     ORDER BY r.id)) FROM lf_ops.reglas r)
         IS DISTINCT FROM v_bulk_authority->>'source_catalog_md5'
      OR jsonb_typeof(p_input->'before_schema_source_row') IS DISTINCT FROM 'object'
   THEN RAISE EXCEPTION 'BLOCK_RULE_ADMIN_BATCH_PATCH_SCOPE_NOT_JUDGED'; END IF;
   -- Cross-check the exact Step40 REGLA scope before bypassing screen selection.
   -- Only an already judged ADMINISTRATIVE_ONLY full-catalog child can enter.
   IF NOT EXISTS(
     SELECT 1 FROM public.lf_operation_execution_steps st
     WHERE st.execution_id=p_parent AND st.step_id='input_validate'
       AND st.status='STEP_PASS_WITH_EVIDENCE'
       AND st.evidence_payload#>>'{scope_authority_packet_sha256}'
           ~ '^sha256:[0-9a-f]{64}$'
       AND st.evidence_payload#>>'{input_governance,status}'='READY'
       AND st.evidence_payload#>>'{input_governance,scope_type}'='REGLA'
       AND st.evidence_payload#>>'{input_governance,scope_mode}'='ALL_CANONICAL_RULES'
       AND st.evidence_payload#>>'{input_governance,source_scope_validated}'='true'
       AND st.evidence_payload#>>'{input_governance,rule_count}'='578'
       AND st.evidence_payload#>>'{input_governance,catalog_md5}'=
           v_bulk_authority->>'source_catalog_md5'
       AND st.evidence_payload#>>'{input_governance,screen_not_current_count}'='0'
       AND st.evidence_payload#>>'{input_governance,inactive_only_rule_count}'='0'
   ) THEN RAISE EXCEPTION 'BLOCK_RULE_ADMIN_BATCH_STEP40_SCOPE_NOT_ATTESTED'; END IF;
 ELSE
   IF v_profile_output->'deliverable_created'->'governed_rule_patch'
         IS DISTINCT FROM v_patch THEN
      RAISE EXCEPTION 'BLOCK_RULE_CHILD_PATCH_NOT_IN_JUDGED_OUTPUT'; END IF;
 END IF;
 v_source_refs := v_profile_output->'deliverable_created'->'product_decision'->'source_refs';
 IF jsonb_typeof(v_source_refs)<>'array'
    OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_source_refs) ref
      WHERE ref->>'authority' IN ('AUTHORITATIVE','CONSTRAINT')
        AND ref->>'current'='true'
        AND nullif(btrim(ref->>'source_ref'),'') IS NOT NULL) THEN
    RAISE EXCEPTION 'BLOCK_RULE_CHILD_AUTHORITATIVE_SOURCE_ABSENT'; END IF;
 -- A screen task cannot mutate rules unrelated to the screen actually
 -- selected by the SAME parent. No caller-provided pantalla_id is trusted.
 v_screen := v_par.manifest->'screen_selection_result'->>'selected_screen_code';
 IF v_bulk_id IS NULL THEN
   IF nullif(btrim(v_screen),'') IS NULL OR NOT EXISTS (
     SELECT 1 FROM lf_ops.pantallas s
     JOIN lf_ops.reglas_pantallas rel ON rel.pantalla_id=s.id
     JOIN lf_ops.reglas r ON r.id=rel.regla_id
     WHERE s.codigo=v_screen AND r.codigo=v_rule
   ) THEN RAISE EXCEPTION 'BLOCK_RULE_CHILD_RULE_NOT_IN_SELECTED_SCREEN'; END IF;
 END IF;
 SELECT count(*) INTO v_n FROM lf_ops.reglas WHERE codigo=v_rule;
 IF v_n<>1 THEN RAISE EXCEPTION 'BLOCK_RULE_CHILD_EXACT_RULE_CARDINALITY:%',v_n; END IF;
 SELECT * INTO v_before FROM lf_ops.reglas WHERE codigo=v_rule FOR UPDATE;
 IF v_bulk_id IS NOT NULL THEN
   v_pre_schema_row:=p_input->'before_schema_source_row';
   IF (to_jsonb(v_before)-'owner_name') IS DISTINCT FROM v_pre_schema_row
      OR (SELECT count(*) FROM jsonb_object_keys(p_input))<>6 THEN
      RAISE EXCEPTION 'BLOCK_RULE_ADMIN_BATCH_SOURCE_PREIMAGE_MISMATCH';
   END IF;
 END IF;
 IF v_before.estado NOT IN ('CANDIDATO','VIGENTE') THEN
    RAISE EXCEPTION 'BLOCK_RULE_CHILD_INVALID_RULE_STATE:%',v_before.estado;
 END IF;
 IF v_change_kind <> 'ADMINISTRATIVE_ONLY'
    AND v_before.estado<>'CANDIDATO' THEN
    IF v_change_kind='FUNCTIONAL_CANDIDATE' THEN
       RAISE EXCEPTION 'BLOCK_RULE_FUNCTIONAL_CHANGE_REQUIRES_SUPERSESSION';
    END IF;
    RAISE EXCEPTION 'BLOCK_RULE_CHILD_REQUIRES_CANDIDATO:%',v_before.estado;
 END IF;
 IF v_change_kind='FUNCTIONAL_CANDIDATE'
    AND v_profile_output#>>'{deliverable_created,product_decision,material_parity}'
        IS DISTINCT FROM 'VERIFIED' THEN
    RAISE EXCEPTION 'BLOCK_RULE_FUNCTIONAL_SEMANTIC_PARITY_NOT_VERIFIED';
 END IF;
 -- A model's semantic-parity claim alone is NOT authority. For a
 -- functional candidate write, the exact source decision must be present
 -- in the real governed decision register and in judged source refs.
 -- Its material parity is still verified by the existing judge 70.
 IF v_change_kind='FUNCTIONAL_CANDIDATE' THEN
  IF NOT EXISTS (
   SELECT 1 FROM public.lf_decisiones_gov d
   WHERE d.id_decision=p_input->>'decision_id'
     AND d.estado_normalizado IN ('VIGENTE','APROBADA')
     AND EXISTS (
       SELECT 1 FROM jsonb_array_elements(v_source_refs) ref
       WHERE ref->>'authority'='AUTHORITATIVE'
         AND ref->>'current'='true'
         AND ref->>'source_ref' IN (
           d.id_decision, 'supabase://lf_decisiones_gov/'||d.id_decision)
     )
 ) THEN
   RAISE EXCEPTION 'BLOCK_RULE_FUNCTIONAL_ORIGINAL_AUTHORITY_UNVERIFIED';
  END IF;
 END IF;
 v_snapshot := public.lf_asset_snapshot_sha_v1('REGLA',v_rule);
 IF v_snapshot IS DISTINCT FROM encode(extensions.digest(
   convert_to((to_jsonb(v_before)-'created_at'-'updated_at')::text,'UTF8'),
   'sha256'),'hex') THEN
    RAISE EXCEPTION 'BLOCK_RULE_HISTORY_ORIGINAL_ROW_SHA_MISMATCH'; END IF;
 IF v_snapshot IS DISTINCT FROM p_input->>'analysis_snapshot_sha256' THEN
    RAISE EXCEPTION 'BLOCK_RULE_CHILD_SOURCE_SNAPSHOT_STALE';
 END IF;
 v_old_title:=v_before.titulo;
 v_old_desc:=v_before.descripcion;
 v_old_reason:=v_before.razon;
 v_new_title:=COALESCE(v_changes->>'titulo',v_old_title);
 v_new_desc:=COALESCE(v_changes->>'descripcion',v_old_desc);
 v_new_reason:=COALESCE(v_changes->>'razon',v_old_reason);
 v_new_categoria:=COALESCE(v_changes->>'categoria',v_before.categoria);
 v_new_config:=COALESCE(v_changes->'valor_config',v_before.valor_config);
 v_new_transversal:=COALESCE((v_changes->>'es_transversal')::boolean,v_before.es_transversal);
 v_new_origen:=COALESCE(v_changes->>'origen',v_before.origen);
 SELECT count(*) INTO v_changed
 FROM jsonb_each(v_changes) c
 WHERE (to_jsonb(v_before)->c.key) IS DISTINCT FROM c.value;
 IF v_changed=0 THEN RAISE EXCEPTION 'BLOCK_RULE_CHILD_NO_MATERIAL_CHANGE'; END IF;
 IF v_change_kind='ADMINISTRATIVE_ONLY' THEN
   IF v_changes ? 'owner_name' AND NOT EXISTS (
     SELECT 1 FROM information_schema.columns
     WHERE table_schema='lf_ops' AND table_name='reglas'
       AND column_name='owner_name') THEN
     RAISE EXCEPTION 'BLOCK_RULE_ADMIN_OWNER_COLUMN_NOT_YET_INSTALLED';
   END IF;
   v_mode:=public.lf_resolve_operation_mode_v1(
      'ACTUALIZACION_REGLA_LF','MAINTAIN_METADATA','GOVERNED');
   IF v_mode->>'status' IS DISTINCT FROM 'READY'
      OR v_mode->>'destination_kind' IS DISTINCT FROM 'CANONICAL_EXISTING'
      OR v_mode->>'write_allowed' IS DISTINCT FROM 'true' THEN
      RAISE EXCEPTION 'BLOCK_RULE_ADMIN_GOVERNED_MODE_NOT_READY'; END IF;
 ELSE
   v_mode:=public.lf_resolve_operation_mode_v1(
      'ACTUALIZACION_REGLA_LF','REMEDIATE_EXISTING','GOVERNED');
   IF v_mode->>'status' IS DISTINCT FROM 'READY'
      OR v_mode->>'destination_kind' IS DISTINCT FROM 'CANONICAL_CANDIDATE'
      OR v_mode->>'write_allowed' IS DISTINCT FROM 'true' THEN
      RAISE EXCEPTION 'BLOCK_RULE_CHILD_GOVERNED_MODE_NOT_READY'; END IF;
 END IF;
 v_reservation:=public.fn_lf_operation_reserve_execution_v1(
   p_child,'ACTUALIZACION_REGLA_LF','REGLA',v_rule,
   'skill-child-v1:'||p_run,p_request_sha,p_parent,NULL,NULL,
   jsonb_build_object(
     'profile_handoff',jsonb_build_object(
       'source_execution_id',p_parent,'skill_run_id',p_run,'via','SKILL_INVOKER'),
     'analysis_snapshot_sha256',v_snapshot,'profile_decision_sha256',v_out_sha,
     'production_allowed',false,'promotion_authorized',false,
     'candidate_patch_scope',v_change_kind)
 );
 IF v_reservation->>'result'<>'RESERVED_NEW_EXECUTION'
    OR v_reservation->>'execution_id'<>p_child THEN
    RAISE EXCEPTION 'BLOCK_RULE_CHILD_RESERVATION_NOT_NEW'; END IF;
 v_evidence:='SKILLRUN:'||p_run;
 v_trust:=jsonb_build_object('valid',true,'code','LF_RULE_CHILD_SERVER_VALIDATED_V1',
   'server_assertions',jsonb_build_array('required_evidence_present'),
   'server_hard_fails','[]'::jsonb);
 -- Each record uses the existing canonical judge/core. No raw PASS inserts.
 v_step_payload:=jsonb_build_object(
    'ekb_refs',jsonb_build_array('INPUT_GOVERNANCE_LF_V1_4'),
    'execution_binding',p_child,'parent_execution_id',p_parent,
    'profile_decision_sha256',v_out_sha);
 PERFORM public.lf_skill_rule_step_record_v1(p_child,'ekb_preflight',v_evidence||'/10',v_step_payload,v_trust);
 v_step_payload:=jsonb_build_object(
    'rule_code',v_rule,'category',v_before.categoria,
    'candidate_classification','REGLA_UPDATE','analysis_snapshot_sha256',v_snapshot);
 PERFORM public.lf_skill_rule_step_record_v1(p_child,'classify',v_evidence||'/20',v_step_payload,v_trust);
 v_step_payload:=jsonb_build_object(
    'rule_code',v_rule,'existing_count',1,
    'expected_existence',CASE WHEN v_change_kind='ADMINISTRATIVE_ONLY'
       THEN 'ONE_CANONICAL_RULE' ELSE 'ONE_CANDIDATO' END);
 PERFORM public.lf_skill_rule_step_record_v1(p_child,'existing_check',v_evidence||'/30',v_step_payload,v_trust);
 v_step_payload:=jsonb_build_object(
    'destination_schema','lf_ops','destination_table','reglas','unique_code_guard',true);
 PERFORM public.lf_skill_rule_step_record_v1(p_child,'destination_validate',v_evidence||'/40',v_step_payload,v_trust);

 IF v_change_kind='ADMINISTRATIVE_ONLY' THEN
    v_written:=public.lf_regla_admin_governed_write_v1(
       p_child,v_rule,v_snapshot,v_changes);
 ELSE
    v_written:=public.lf_regla_candidate_write_v1(
       p_child,'REGLA_UPDATE',v_rule,v_new_categoria,v_new_title,
       v_new_desc,v_new_reason,v_new_config,
       v_new_transversal,v_new_origen);
 END IF;
 v_expected_result:=CASE WHEN v_change_kind='ADMINISTRATIVE_ONLY'
      THEN 'RULE_ADMINISTRATIVE_UPDATED' ELSE 'RULE_CANDIDATE_UPDATED' END;
 v_expected_state:=CASE WHEN v_change_kind='ADMINISTRATIVE_ONLY'
      THEN v_before.estado ELSE 'CANDIDATO' END;
 IF v_written->>'result' IS DISTINCT FROM v_expected_result
    OR v_written->'before' IS DISTINCT FROM to_jsonb(v_before)
    OR v_written->'before'->>'estado' IS DISTINCT FROM v_before.estado
    OR v_written->'after'->>'estado' IS DISTINCT FROM v_expected_state THEN
    RAISE EXCEPTION 'BLOCK_RULE_CHILD_WRITER_RESULT_MISMATCH'; END IF;
 v_step_payload:=jsonb_build_object(
    'execution_id',p_child,'rule_code',v_rule,
    'write_result',v_written->>'result',
    'estado',coalesce(v_written#>>'{after,estado}',v_before.estado),
    'writer',CASE WHEN v_change_kind='ADMINISTRATIVE_ONLY'
       THEN 'lf_regla_admin_governed_write_v1'
       ELSE 'lf_regla_candidate_write_v1' END);
 PERFORM public.lf_skill_rule_step_record_v1(p_child,'candidate_write',v_evidence||'/50',v_step_payload,v_trust);
 SELECT to_jsonb(r) INTO v_after FROM lf_ops.reglas r WHERE r.codigo=v_rule;
 IF v_after IS NULL
    OR v_after->>'estado' IS DISTINCT FROM v_expected_state
    OR (v_change_kind<>'ADMINISTRATIVE_ONLY' AND (
       v_after->>'titulo' IS DISTINCT FROM v_new_title
       OR v_after->>'descripcion' IS DISTINCT FROM v_new_desc
       OR v_after->>'razon' IS DISTINCT FROM v_new_reason
       OR v_after->>'categoria' IS DISTINCT FROM v_new_categoria
       OR v_after->>'es_transversal' IS DISTINCT FROM v_new_transversal::text
       OR v_after->'valor_config' IS DISTINCT FROM v_new_config
       OR v_after->>'origen' IS DISTINCT FROM v_new_origen
       OR v_after->>'pendiente_decision' IS DISTINCT FROM 'true'))
 THEN RAISE EXCEPTION 'BLOCK_RULE_CHILD_CANONICAL_READBACK_MISMATCH'; END IF;
 v_after_sha:=public.lf_asset_snapshot_sha_v1('REGLA',v_rule);
 IF v_after_sha IS NULL OR v_after_sha=v_snapshot THEN
    RAISE EXCEPTION 'BLOCK_RULE_CHILD_CANONICAL_HASH_NOT_CHANGED'; END IF;
 -- Compare canonical writer's before and after records, not worker claims.
 IF v_written->'after' IS DISTINCT FROM v_after
 OR v_after_sha IS DISTINCT FROM encode(extensions.digest(
    convert_to((v_after-'created_at'-'updated_at')::text,'UTF8'),
    'sha256'),'hex') THEN
    RAISE EXCEPTION 'BLOCK_RULE_HISTORY_WRITER_OR_RESULT_SHA_MISMATCH';
 END IF;
 SELECT coalesce(jsonb_object_agg(n.key,jsonb_build_object(
    'before',b.value,'after',n.value)),'{}'::jsonb)
 INTO v_history_delta
 FROM jsonb_each(v_after-'created_at'-'updated_at') n
 JOIN jsonb_each(to_jsonb(v_before)-'created_at'-'updated_at') b
 ON b.key=n.key
 WHERE n.value IS DISTINCT FROM b.value;
 IF jsonb_typeof(v_history_delta) IS DISTINCT FROM 'object'
 OR EXISTS(SELECT 1 FROM jsonb_object_keys(v_history_delta) k(field)
   WHERE (v_change_kind='ADMINISTRATIVE_ONLY'
            AND k.field NOT IN ('owner_name','created_by'))
      OR (v_change_kind='DOCUMENTARY_ONLY'
            AND k.field NOT IN (
                 'titulo','descripcion','razon','pendiente_decision','pendiente_detalle'))
      OR (v_change_kind='FUNCTIONAL_CANDIDATE'
            AND k.field NOT IN (
                 'titulo','descripcion','razon','categoria','origen',
                 'valor_config','es_transversal','pendiente_decision','pendiente_detalle'))
 ) THEN
    RAISE EXCEPTION 'BLOCK_RULE_HISTORY_UNAUTHORIZED_MATERIAL_DELTA';
 END IF;
 -- Store full source and result, both SHA, and field delta in existing
 -- official readback. Historical rows are never reconstructed.
 v_step_payload:=jsonb_build_object(
    'rule_code',v_rule,'readback_row',v_after,'estado',v_after->>'estado',
    'source_snapshot_sha256',v_snapshot,'result_snapshot_sha256',v_after_sha,
    'rule_update_history_v1',jsonb_build_object(
       'schema_version','LF_RULE_UPDATE_HISTORY_V1',
       'rule_code',v_rule,'change_kind',v_change_kind,
       'source_row',to_jsonb(v_before),
       'pre_schema_source_row',v_pre_schema_row,
       'pre_schema_source_sha256',CASE WHEN v_bulk_id IS NOT NULL
          THEN encode(extensions.digest(convert_to(
             (v_pre_schema_row-'created_at'-'updated_at')::text,
             'UTF8'),'sha256'),'hex') ELSE NULL END,
       'rule_owner_batch_id',v_bulk_id,
       'batch_source_catalog_md5',v_bulk_authority->>'source_catalog_md5',
       'result_row',v_after,
       'source_snapshot_sha256',v_snapshot,
       'result_snapshot_sha256',v_after_sha,
       'changed_fields',v_history_delta,
       'authorized_operation','ACTUALIZACION_REGLA_LF',
       'child_execution_id',p_child,
       'parent_execution_id',p_parent,
       'judged_profile_output_sha256',v_out_sha,
       'decision_id',p_input->>'decision_id'));
 PERFORM public.lf_skill_rule_step_record_v1(
    p_child,'readback',v_evidence||'/60',v_step_payload,v_trust);
 -- Verify *persisted* canonical evidence BEFORE closing the child.
 IF NOT EXISTS(SELECT 1 FROM public.lf_operation_execution_steps st
    WHERE st.execution_id=p_child AND st.step_id='readback'
      AND st.status='PASS_CLEAN'
      AND st.evidence_payload#>>'{rule_update_history_v1,schema_version}'
          ='LF_RULE_UPDATE_HISTORY_V1'
      AND st.evidence_payload#>'{rule_update_history_v1,source_row}'
          =to_jsonb(v_before)
      AND st.evidence_payload#>'{rule_update_history_v1,result_row}'
          =v_after
      AND st.evidence_payload#>'{rule_update_history_v1,changed_fields}'
          =v_history_delta
      AND st.evidence_payload#>>'{rule_update_history_v1,source_snapshot_sha256}'
          =v_snapshot
      AND st.evidence_payload#>>'{rule_update_history_v1,result_snapshot_sha256}'
          =v_after_sha) THEN
    RAISE EXCEPTION 'BLOCK_RULE_HISTORY_CANONICAL_PERSISTENCE_READBACK';
 END IF;
 v_step_payload:=jsonb_build_object(
    'execution_id',p_child,'operation_code','ACTUALIZACION_REGLA_LF',
    'trace_ref',v_evidence,'no_promotion',true,'result_snapshot_sha256',v_after_sha,
    'change_kind',v_change_kind);
 PERFORM public.lf_skill_rule_step_record_v1(p_child,'trace_close',v_evidence||'/70',v_step_payload,v_trust);
 IF (SELECT count(*) FROM public.lf_operation_execution_steps
      WHERE execution_id=p_child AND step_id=ANY(v_steps)
      AND status='PASS_CLEAN')<>7 THEN
    RAISE EXCEPTION 'BLOCK_RULE_CHILD_7_STEPS_NOT_CLEAN'; END IF;
 UPDATE public.lf_operation_execution SET
    status='COMPLETED',completed_at=now(),
    manifest=manifest||jsonb_build_object(
      'operation_closed',true,'candidate_write_verified',true,
      'result_snapshot_sha256',v_after_sha,
      'rule_state',v_after->>'estado',
      'promotion_authorized',false,'profile_continuation_required',true),
    updated_by_execution_id=p_child,updated_at=now()
 WHERE execution_id=p_child AND status='IN_PROGRESS';
 IF NOT FOUND THEN RAISE EXCEPTION 'BLOCK_RULE_CHILD_TERMINAL_WRITE_FAILED'; END IF;
 RETURN jsonb_build_object('status','APPLIED_VERIFIED','child_execution_id',p_child,
   'parent_execution_id',p_parent,'rule_code',v_rule,
   'result_snapshot_sha256',v_after_sha,'promotion_authorized',false);
END
$function$;

CREATE FUNCTION public.lf_rule_admin_bulk_atomic_v1(
  p_parent_execution_id text,
  p_batch_id text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public','lf_ops','extensions'
AS $bulk$
DECLARE
 v_parent public.lf_operation_execution%ROWTYPE;
 v_output jsonb;
 v_batch jsonb;
 v_provenance jsonb;
 v_judge jsonb;
 v_preimages jsonb;
 v_rows_root text;
 v_screens_root text;
 v_lineage_md5 text;
 v_catalog_md5 text;
 v_scope_count integer;
 v_screen_count integer;
 v_link_count integer;
 v_rule jsonb;
 v_packet jsonb;
 v_patch jsonb;
 v_receipt jsonb;
 v_pre_root jsonb;
 v_code text;
 v_status text;
 v_count integer:=0;
 v_screen record;
 v_expected_sha text;
 v_observed_sha text;
 v_old_sha text;
 v_screens_changed integer:=0;
 v_preimage_same integer;
 v_history_count integer;
 v_batch_id text;
 v_screen_pre_hashes jsonb;
 v_ig_impact jsonb := '[]'::jsonb;
 v_ig_unresolved integer := 0;
 v_ig_material integer := 0;
BEGIN
 IF coalesce(p_parent_execution_id,'')='' OR coalesce(p_batch_id,'')=''
 THEN RAISE EXCEPTION 'BLOCK_RULE_BULK_IDENTITY_MISSING'; END IF;

 -- No new entrypoint: bind to the same routed, judged Product Director RUN.
 SELECT * INTO v_parent FROM public.lf_operation_execution
 WHERE execution_id=p_parent_execution_id
   AND operation_code='EJECUCION_PERFIL_LF'
   AND target_type='PERFIL' AND target_code='PERFIL-PRODUCT-DIRECTOR-LF'
   AND status='IN_PROGRESS' FOR UPDATE;
 IF NOT FOUND
 OR v_parent.manifest->>'read_only' IS DISTINCT FROM 'true'
 OR v_parent.manifest->>'no_write' IS DISTINCT FROM 'true'
 OR v_parent.manifest->>'no_promotion' IS DISTINCT FROM 'true'
 OR v_parent.manifest#>>'{router_profile_handoff,router_authorization_receipt,profile_execution_allowed}'
      IS DISTINCT FROM 'true'
 THEN RAISE EXCEPTION 'BLOCK_RULE_BULK_ROUTER_PROFILE_AUTHORITY'; END IF;
 IF NOT EXISTS(
   SELECT 1 FROM public.lf_profile_write_authority_v1
   WHERE profile_code=v_parent.target_code
     AND operation_code='ACTUALIZACION_REGLA_LF'
     AND status='ACTIVE'
 ) THEN RAISE EXCEPTION 'BLOCK_RULE_BULK_OPERATION_AUTHORITY'; END IF;
 -- The approved owner is functional; SUPER_ADMIN remains the guard
 -- in the existing operation contract, not a rule's owner_name.
 -- Do not mistake this declared guard for a human judge receipt.
 IF NOT EXISTS(
   SELECT 1 FROM public.lf_operation_contracts c
   WHERE c.operation_code='ACTUALIZACION_REGLA_LF'
     AND c.status='ACTIVE_ENFORCEMENT'
     AND c.allowed#>>'{mode_overrides,ADMINISTRATIVE_ONLY,functional_owner}'='LF_GOVERNANCE'
     AND c.allowed#>>'{mode_overrides,ADMINISTRATIVE_ONLY,governance_guard}'='SUPER_ADMIN'
     AND c.allowed#>>'{mode_overrides,ADMINISTRATIVE_ONLY,guard_receipt_required}'='true'
 ) THEN RAISE EXCEPTION 'BLOCK_RULE_BULK_OWNER_GUARD_CONTRACT_MISMATCH'; END IF;
 IF NOT EXISTS(
   SELECT 1 FROM public.lf_operation_execution_steps s
   WHERE s.execution_id=p_parent_execution_id
     AND s.step_id='input_validate' AND s.status='STEP_PASS_WITH_EVIDENCE'
     AND coalesce(s.evidence_payload->>'scope_authority_packet_sha256','')
          ~ '^sha256:[0-9a-f]{64}$'
 ) THEN RAISE EXCEPTION 'BLOCK_RULE_BULK_STEP40_SCOPE_NOT_ATTESTED'; END IF;
 -- Fail before DDL if Step40 did not validate the entire RULE scope.
 IF NOT EXISTS(
   SELECT 1 FROM public.lf_operation_execution_steps s
   WHERE s.execution_id=p_parent_execution_id
     AND s.step_id='input_validate' AND s.status='STEP_PASS_WITH_EVIDENCE'
     AND s.evidence_payload#>>'{input_governance,status}'='READY'
     AND s.evidence_payload#>>'{input_governance,scope_type}'='REGLA'
     AND s.evidence_payload#>>'{input_governance,scope_mode}'='ALL_CANONICAL_RULES'
     AND s.evidence_payload#>>'{input_governance,source_scope_validated}'='true'
     AND s.evidence_payload#>>'{input_governance,rule_count}'='578'
     AND s.evidence_payload#>>'{input_governance,screen_not_current_count}'='0'
     AND s.evidence_payload#>>'{input_governance,inactive_only_rule_count}'='0'
 ) THEN RAISE EXCEPTION 'BLOCK_RULE_BULK_STEP40_RULE_SCOPE_NOT_ATTESTED'; END IF;
 IF NOT EXISTS(
   SELECT 1 FROM public.lf_operation_execution_steps s
   WHERE s.execution_id=p_parent_execution_id AND s.step_id='output_validate'
     AND s.status='STEP_PASS_WITH_EVIDENCE'
     AND s.evidence_payload->>'output_contract_result'='PASS'
 ) THEN RAISE EXCEPTION 'BLOCK_RULE_BULK_PROFILE_OUTPUT_INVALID'; END IF;
 SELECT s.evidence_payload->'semantic_judge_result' INTO v_judge
 FROM public.lf_operation_execution_steps s
 WHERE s.execution_id=p_parent_execution_id AND s.step_id='semantic_judge'
 AND s.status='STEP_PASS_WITH_EVIDENCE'
 AND s.evidence_payload->'blocking_codes'='[]'::jsonb;
 IF v_judge IS NULL
 OR v_judge->>'verdict' NOT IN (
   'PASS_INDEPENDENT_SEMANTIC','PASS_REVIEWED_CURRENT_CONTEXT')
 THEN RAISE EXCEPTION 'BLOCK_RULE_BULK_JUDGE_NOT_CLEAN'; END IF;
 SELECT s.evidence_payload->'profile_output' INTO v_output
 FROM public.lf_operation_execution_steps s
 WHERE s.execution_id=p_parent_execution_id AND s.step_id='execute_profile'
   AND s.status='STEP_PASS_WITH_EVIDENCE';
 IF v_output->>'worker' IS DISTINCT FROM 'product_director_lf'
 OR v_output->>'output_type' IS DISTINCT FROM 'PRODUCT_DIRECTION_SPEC'
 OR v_output->>'self_verdict' IS DISTINCT FROM 'PASS'
 OR v_output#>>'{deliverable_created,authority_status}' NOT IN ('SUPPORTED','CONFLICT_RESOLVED')
 THEN RAISE EXCEPTION 'BLOCK_RULE_BULK_PRODUCT_OUTPUT_INVALID'; END IF;
 v_batch:=v_output#>'{deliverable_created,governed_rule_batch}';
 v_provenance:=v_output#>'{deliverable_created,product_decision}';
 IF jsonb_typeof(v_batch) IS DISTINCT FROM 'object'
 OR (SELECT count(*) FROM jsonb_object_keys(v_batch))<>10
 OR v_batch->>'batch_id' IS DISTINCT FROM p_batch_id
 OR v_batch->>'scope' IS DISTINCT FROM 'ALL_CANONICAL_RULES'
 OR v_batch->>'operation_code' IS DISTINCT FROM 'ACTUALIZACION_REGLA_LF'
 OR v_batch->>'change_kind' IS DISTINCT FROM 'ADMINISTRATIVE_ONLY'
 OR v_batch->'changes' IS DISTINCT FROM
     '{"owner_name":"LF_GOVERNANCE","created_by":"ChatGPT"}'::jsonb
 OR v_batch->>'source_catalog_md5' !~ '^[0-9a-f]{32}$'
 OR v_batch->>'rule_preimage_root_sha256' !~ '^[0-9a-f]{64}$'
 OR v_batch->>'screen_preimage_root_sha256' !~ '^[0-9a-f]{64}$'
 OR v_batch->>'lineage_md5' !~ '^[0-9a-f]{32}$'
 OR v_batch->>'expected_count' IS DISTINCT FROM '578'
 OR v_provenance->>'decision_id' IS NULL
 OR jsonb_typeof(v_provenance->'source_refs') IS DISTINCT FROM 'array'
 OR NOT EXISTS(
     SELECT 1 FROM jsonb_array_elements(v_provenance->'source_refs') r
     WHERE r->>'authority'='AUTHORITATIVE'
       AND r->>'current'='true'
       AND nullif(btrim(r->>'source_ref'),'') IS NOT NULL
   )
 THEN RAISE EXCEPTION 'BLOCK_RULE_BULK_PRODUCT_SCOPE_OR_OWNER_APPROVAL'; END IF;

 -- One serial transaction protects ALL mutable rules and their lineages;
 -- external readers see original OR final data, never schema-only state.
 LOCK TABLE lf_ops.reglas IN ACCESS EXCLUSIVE MODE;
 LOCK TABLE lf_ops.reglas_pantallas IN SHARE MODE;
 LOCK TABLE lf_ops.pantallas IN SHARE MODE;
 IF EXISTS(SELECT 1 FROM information_schema.columns
     WHERE table_schema='lf_ops' AND table_name='reglas'
       AND column_name='owner_name') THEN
   RAISE EXCEPTION 'BLOCK_RULE_BULK_OWNER_SCHEMA_ALREADY_PRESENT'; END IF;
 SELECT count(*),md5(string_agg(r.id::text||':'||r.codigo,E'\n' ORDER BY r.id)),
        jsonb_agg(to_jsonb(r) ORDER BY r.id)
 INTO v_scope_count,v_catalog_md5,v_preimages FROM lf_ops.reglas r;
 IF v_scope_count<>578
 OR v_catalog_md5 IS DISTINCT FROM v_batch->>'source_catalog_md5'
 OR (SELECT count(*) FROM jsonb_array_elements(v_preimages))<>578
 OR EXISTS(SELECT 1 FROM lf_ops.reglas r
    WHERE r.estado NOT IN ('VIGENTE','CANDIDATO'))
 THEN RAISE EXCEPTION 'BLOCK_RULE_BULK_SOURCE_CATALOG_PREIMAGE_DRIFT'; END IF;

 SELECT encode(extensions.digest(convert_to(jsonb_agg(
   jsonb_build_object(
     'id',(e.value->>'id')::integer,
     'codigo',e.value->>'codigo',
     'sha',encode(extensions.digest(convert_to(
       (e.value-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex')
   ) ORDER BY (e.value->>'id')::integer)::text,'UTF8'),'sha256'),'hex')
 INTO v_rows_root FROM jsonb_array_elements(v_preimages) e(value);
 IF v_rows_root IS DISTINCT FROM v_batch->>'rule_preimage_root_sha256' THEN
   RAISE EXCEPTION 'BLOCK_RULE_BULK_RULE_MATERIAL_PREIMAGE_DRIFT'; END IF;

 SELECT count(*),
   md5(string_agg(pantalla_id::text||':'||regla_id::text,E'\n'
       ORDER BY pantalla_id,regla_id))
 INTO v_link_count,v_lineage_md5 FROM lf_ops.reglas_pantallas;
 IF v_link_count<>6176 OR v_lineage_md5 IS DISTINCT FROM
    v_batch->>'lineage_md5' THEN
   RAISE EXCEPTION 'BLOCK_RULE_BULK_SCREEN_LINEAGE_DRIFT'; END IF;

 WITH per_screen AS (
 SELECT p.id,p.codigo, public.lf_asset_snapshot_sha_v1('PANTALLA',p.codigo) sha
 FROM lf_ops.pantallas p
 WHERE EXISTS(SELECT 1 FROM lf_ops.reglas_pantallas rp
              WHERE rp.pantalla_id=p.id)
 )
 SELECT count(*),
   encode(extensions.digest(convert_to(jsonb_agg(
      jsonb_build_object('id',id,'codigo',codigo,'sha',sha)
      ORDER BY id)::text,'UTF8'),'sha256'),'hex'),
   jsonb_object_agg(codigo,sha)
 INTO v_screen_count,v_screens_root,v_screen_pre_hashes
 FROM per_screen;
 IF v_screen_count<>56 OR v_screens_root IS DISTINCT FROM
    v_batch->>'screen_preimage_root_sha256' THEN
   RAISE EXCEPTION 'BLOCK_RULE_BULK_SCREEN_SOURCE_PREIMAGE_DRIFT'; END IF;

 -- IG dependency preflight is structural, not an assertion of CURRENTNESS.
 -- Terminal runs are not mutated. A post-cut currentness/freshness verifier
 -- must decide which sources need a governed Curator->Validator successor.
 IF to_regclass('programacion.input_readiness_runs') IS NULL THEN
   RAISE EXCEPTION 'BLOCK_RULE_BULK_IG_SOURCE_LEDGER_UNAVAILABLE'; END IF;
 WITH active_runs AS (
   SELECT ir.id AS run_id, ir.pantalla_id, p.codigo AS screen_code,
          ir.source_manifest,
          CASE WHEN jsonb_typeof(ir.source_manifest)='array'
            THEN jsonb_array_length(ir.source_manifest) ELSE 0 END AS manifest_items
   FROM programacion.input_readiness_runs ir
   JOIN lf_ops.pantallas p ON p.id=ir.pantalla_id
   WHERE ir.status='COMPLETED' AND ir.invalidated_at IS NULL
     AND NOT EXISTS (
       SELECT 1 FROM programacion.input_readiness_runs successor
       WHERE successor.supersedes_run_id=ir.id AND successor.status='COMPLETED'
     )
     AND EXISTS (
       SELECT 1 FROM lf_ops.reglas_pantallas edge
       WHERE edge.pantalla_id=ir.pantalla_id
     )
 ), pins AS (
   SELECT active.run_id,active.pantalla_id,active.screen_code,
          active.manifest_items,pin.value->'ref'->>'kind' AS kind,
          pin.value->'ref'->>'codigo' AS rule_code,
          r.id AS resolved_rule_id
   FROM active_runs active
   LEFT JOIN LATERAL jsonb_array_elements(
     CASE WHEN jsonb_typeof(active.source_manifest)='array'
       THEN active.source_manifest ELSE '[]'::jsonb END
   ) pin(value) ON true
   LEFT JOIN lf_ops.reglas r ON pin.value->'ref'->>'kind'='RULE'
    AND r.codigo=pin.value->'ref'->>'codigo'
 ), per_run AS (
   SELECT run_id,pantalla_id,screen_code,max(manifest_items) manifest_items,
          count(*) FILTER(WHERE kind='RULE' AND resolved_rule_id IS NOT NULL)
            AS material_rule_pins,
          count(*) FILTER(WHERE kind='RULE' AND resolved_rule_id IS NULL)
            AS unresolved_rule_pins,
          count(*) FILTER(WHERE kind='SCREEN_RULE_SET') AS screen_rule_set_pins,
          count(*) FILTER(WHERE kind='SCREEN_CANONICAL_GRAPH') AS graph_pins,
          coalesce(jsonb_agg(DISTINCT rule_code)
            FILTER(WHERE kind='RULE' AND resolved_rule_id IS NOT NULL),
            '[]'::jsonb) AS material_rule_codes
   FROM pins GROUP BY run_id,pantalla_id,screen_code
 ), classified AS (
   SELECT *,
     CASE WHEN manifest_items=0 OR unresolved_rule_pins>0
       THEN 'BLOCK_IG_SOURCE_PIN_UNRESOLVED'
       WHEN material_rule_pins>0 OR screen_rule_set_pins>0
       THEN 'POST_CUT_FRESHNESS_DELTA_REQUIRED'
       WHEN graph_pins>0 THEN 'POST_CUT_CURRENTNESS_READBACK'
       ELSE 'NO_DIRECT_RULE_DEPENDENCY'
     END AS impact_class
   FROM per_run
 )
 SELECT coalesce(jsonb_agg(jsonb_build_object(
      'run_id',run_id,'pantalla_id',pantalla_id,'screen_code',screen_code,
      'impact_class',impact_class,'material_rule_pins',material_rule_pins,
      'screen_rule_set_pins',screen_rule_set_pins,'graph_pins',graph_pins,
      'material_rule_codes',material_rule_codes,
      'source_currentness','NOT_EVALUATED',
      'post_cut_authority','REQUIRED_NOT_ATTESTED'
    ) ORDER BY run_id)
    FILTER(WHERE impact_class<>'NO_DIRECT_RULE_DEPENDENCY'),'[]'::jsonb),
    count(*) FILTER(WHERE impact_class='BLOCK_IG_SOURCE_PIN_UNRESOLVED'),
    count(*) FILTER(WHERE impact_class='POST_CUT_FRESHNESS_DELTA_REQUIRED')
 INTO v_ig_impact,v_ig_unresolved,v_ig_material
 FROM classified;
 IF v_ig_unresolved<>0 THEN
   RAISE EXCEPTION 'BLOCK_RULE_BULK_IG_UNRESOLVED_RULE_PIN:%',
     v_ig_unresolved; END IF;

 -- Existing canonical schema is evolved IN THE SAME transaction as all
 -- canonical child writes; on any error this DDL also rolls back.
 EXECUTE 'ALTER TABLE lf_ops.reglas ADD COLUMN owner_name text';

 FOR v_rule IN SELECT value FROM jsonb_array_elements(v_preimages) LOOP
   v_code:=v_rule->>'codigo';
   IF (SELECT to_jsonb(r)-'owner_name' FROM lf_ops.reglas r
       WHERE r.codigo=v_code) IS DISTINCT FROM v_rule THEN
     RAISE EXCEPTION 'BLOCK_RULE_BULK_PER_RULE_PRE_SCHEMA_DRIFT:%',v_code;
   END IF;
   v_patch:=jsonb_build_object('rule_code',v_code,
     'change_kind','ADMINISTRATIVE_ONLY','changes',v_batch->'changes');
   v_packet:=jsonb_build_object(
     'regla_codigo',v_code,
     'analysis_snapshot_sha256',
        public.lf_asset_snapshot_sha_v1('REGLA',v_code),
     'decision_id',v_provenance->>'decision_id',
     'candidate_patch',v_patch,
     'rule_owner_batch_id',p_batch_id,
     'before_schema_source_row',v_rule);
   v_receipt:=public.lf_skill_invoke_v1(
     'RULE_UPDATE_APPLY',p_parent_execution_id,v_packet);
   IF v_receipt->>'status' IS DISTINCT FROM 'COMPLETED'
      OR v_receipt->>'effect_verified' IS DISTINCT FROM 'true'
      OR v_receipt#>>'{child_receipt,status}' IS DISTINCT FROM 'APPLIED_VERIFIED'
      OR v_receipt#>>'{child_receipt,rule_code}' IS DISTINCT FROM v_code
      OR coalesce(v_receipt->>'replay','false')='true'
   THEN RAISE EXCEPTION 'BLOCK_RULE_BULK_CHILD_NOT_VERIFIED:%:%',
      v_code,coalesce(v_receipt#>>'{child_receipt,code}',
         v_receipt->>'blocking_code',v_receipt->>'status','NO_RECEIPT'); END IF;
   v_count:=v_count+1;
 END LOOP;

 IF v_count<>578 OR (SELECT count(*) FROM lf_ops.reglas)<>578
 OR (SELECT md5(string_agg(r.id::text||':'||r.codigo,E'\n' ORDER BY r.id))
     FROM lf_ops.reglas r) IS DISTINCT FROM v_catalog_md5
 OR EXISTS(SELECT 1 FROM lf_ops.reglas r
           WHERE r.owner_name IS DISTINCT FROM 'LF_GOVERNANCE'
              OR r.created_by IS DISTINCT FROM 'ChatGPT')
 THEN RAISE EXCEPTION 'BLOCK_RULE_BULK_FINAL_RULE_READBACK'; END IF;

 -- Compare all original protected fields to the frozen before-schema source.
 SELECT count(*) INTO v_preimage_same
 FROM jsonb_array_elements(v_preimages) e(value)
 JOIN lf_ops.reglas r ON r.id=(e.value->>'id')::integer
 WHERE (to_jsonb(r)-'owner_name'-'created_by'-'updated_at')
  IS DISTINCT FROM (e.value-'created_by'-'updated_at');
 IF v_preimage_same<>0 THEN
   RAISE EXCEPTION 'BLOCK_RULE_BULK_PROTECTED_FIELDS_DRIFT:%',v_preimage_same; END IF;

 -- Verify every affected SCREEN from its ORIGINAL rule rows + target values.
 -- No rewriting or fake refreshing previous Input Governance runs.
 FOR v_screen IN
 SELECT p.id,p.codigo FROM lf_ops.pantallas p
 WHERE EXISTS(SELECT 1 FROM lf_ops.reglas_pantallas rp WHERE rp.pantalla_id=p.id)
 ORDER BY p.codigo LOOP
   SELECT encode(extensions.digest(convert_to(
      jsonb_agg((e.value
         || jsonb_build_object('owner_name','LF_GOVERNANCE','created_by','ChatGPT'))
         -'created_at'-'updated_at'
         ORDER BY e.value->>'codigo')::text,'UTF8'),'sha256'),'hex')
   INTO v_expected_sha
   FROM lf_ops.reglas_pantallas rp
   JOIN jsonb_array_elements(v_preimages) e(value)
     ON (e.value->>'id')::integer=rp.regla_id
   WHERE rp.pantalla_id=v_screen.id;
   v_observed_sha:=public.lf_asset_snapshot_sha_v1('PANTALLA',v_screen.codigo);
   IF v_expected_sha IS DISTINCT FROM v_observed_sha
      OR v_observed_sha IS NOT DISTINCT FROM
         v_screen_pre_hashes->>v_screen.codigo THEN
      RAISE EXCEPTION 'BLOCK_RULE_BULK_SCREEN_HASH_READBACK:%',v_screen.codigo;
   END IF;
   v_screens_changed:=v_screens_changed+1;
 END LOOP;
 IF v_screens_changed<>56
 OR (SELECT count(*) FROM lf_ops.reglas_pantallas)<>v_link_count
 OR (SELECT md5(string_agg(pantalla_id::text||':'||regla_id::text,E'\n'
              ORDER BY pantalla_id,regla_id))
     FROM lf_ops.reglas_pantallas) IS DISTINCT FROM v_lineage_md5
 THEN RAISE EXCEPTION 'BLOCK_RULE_BULK_LINEAGE_READBACK'; END IF;

 SELECT count(DISTINCT e.execution_id) INTO v_history_count
 FROM public.lf_operation_execution e
 JOIN public.lf_operation_execution_steps st ON st.execution_id=e.execution_id
 WHERE e.operation_code='ACTUALIZACION_REGLA_LF'
   AND e.created_by_execution_id=p_parent_execution_id
   AND e.status='COMPLETED'
   AND st.step_id='readback' AND st.status='PASS_CLEAN'
   AND st.evidence_payload#>>'{rule_update_history_v1,rule_owner_batch_id}'
       =p_batch_id
   AND st.evidence_payload#>'{rule_update_history_v1,pre_schema_source_row}'
       IS NOT NULL;
 IF v_history_count<>578 THEN
   RAISE EXCEPTION 'BLOCK_RULE_BULK_HISTORY_578_MISSING:%',v_history_count; END IF;

 RETURN jsonb_build_object(
   'status','APPLIED_VERIFIED','operation_code','ACTUALIZACION_REGLA_LF',
   'parent_execution_id',p_parent_execution_id,'batch_id',p_batch_id,
   'rules_updated',v_count,'histories_written',v_history_count,
   'screens_sha_verified',v_screens_changed,'rule_links_verified',v_link_count,
   'source_catalog_md5',v_catalog_md5,'source_preimage_root_sha256',v_rows_root,
   'screens_preimage_root_sha256',v_screens_root,
   'production_status','REQUIRES_GOVERNED_IG_CURRENTNESS_VALIDATION',
   'ig_currentness_gate',jsonb_build_object(
     'schema_version','LF_RULE_BULK_IG_CURRENTNESS_GATE_V1',
     'status','POST_CUT_AUTHORITY_PENDING',
     'candidate_run_count',jsonb_array_length(v_ig_impact),
     'material_rule_candidate_count',v_ig_material,
     'candidates',v_ig_impact,
     'source_currentness_attested',false,
     'validator_receipt_attested',false,
     'production_release_authorized',false),
   'promotion_authorized',false);
END
$bulk$;

REVOKE ALL ON FUNCTION public.lf_rule_admin_bulk_atomic_v1(text,text)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lf_rule_admin_bulk_atomic_v1(text,text)
  TO service_role;

COMMIT;

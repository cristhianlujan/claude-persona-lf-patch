-- LF Issue #3779 | Generalize existing ACTUALIZACION_REGLA_LF.
-- Dependence: #3785 LF_RULE_UPDATE_HISTORY_V1 must already be installed.
-- Existing rule table remains intact; owner_name schema field NOT added here.
-- Mode ADMINISTRATIVE_ONLY (CANDIDATO/VIGENTE), DOCUMENTARY_ONLY (CANDIDATO)
-- and FUNCTIONAL_CANDIDATE (CANDIDATO only, verified material parity).
-- VIGENTE functional change fails closed until governed supersession is defined.
BEGIN;

DO $source_guard$
BEGIN
 IF to_regprocedure('public.lf_rule_update_history_seal_v1()') IS NULL
 OR NOT EXISTS(SELECT 1 FROM pg_trigger
    WHERE tgname='trg_lf_rule_update_history_seal_v1'
      AND tgrelid='public.lf_operation_execution_steps'::regclass)
 OR position('LF_RULE_UPDATE_HISTORY_V1' in pg_get_functiondef(
   'public.lf_skill_o_rule_update_v1(text,jsonb,text,text,text)'::regprocedure))=0
 THEN RAISE EXCEPTION 'BLOCK_RULE_GENERAL_HISTORY_BASELINE_NOT_INSTALLED'; END IF;
END $source_guard$;

-- One new task-mode RECORD inside the existing governance catalog; no new
-- table, skill, router entry or child operation.
DO $mode_preflight$
BEGIN
 IF EXISTS(SELECT 1 FROM public.lf_task_mode_catalog
  WHERE task_mode='MAINTAIN_METADATA')
 OR EXISTS(SELECT 1 FROM public.lf_operation_mode_bindings
  WHERE operation_code='ACTUALIZACION_REGLA_LF'
    AND task_mode='MAINTAIN_METADATA' AND execution_mode='GOVERNED')
 THEN RAISE EXCEPTION 'BLOCK_RULE_ADMIN_MODE_ALREADY_INSTALLED'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.lf_operation_mode_bindings
   WHERE operation_code='ACTUALIZACION_REGLA_LF'
     AND task_mode='REMEDIATE_EXISTING' AND execution_mode='GOVERNED'
     AND status='ACTIVE' AND destination_kind='CANONICAL_CANDIDATE'
     AND write_allowed=true)
 THEN RAISE EXCEPTION 'BLOCK_RULE_ADMIN_EXISTING_MODE_DRIFT'; END IF;
END $mode_preflight$;

DO $mode_constraint$
BEGIN
 IF EXISTS(SELECT 1 FROM pg_constraint
    WHERE conrelid='public.lf_operation_mode_bindings'::regclass
      AND conname='lf_operation_mode_bindings_destination_kind_check') THEN
   ALTER TABLE public.lf_operation_mode_bindings
     DROP CONSTRAINT lf_operation_mode_bindings_destination_kind_check;
 END IF;
 ALTER TABLE public.lf_operation_mode_bindings
   ADD CONSTRAINT lf_operation_mode_bindings_destination_kind_check
   CHECK(destination_kind IN (
     'EXPLORATION_STORE','CANONICAL_CANDIDATE',
     'CANONICAL_EXISTING','NO_WRITE'));
END $mode_constraint$;

-- A source label is not evidence that a child execution occurred.
-- The effective write authority remains the parent judged profile RUN.
INSERT INTO public.lf_task_mode_catalog(
 task_mode,description,allows_new_target,requires_existing_target,
 mutation_intent,reference_source,status,created_by_execution_id)
VALUES (
 'MAINTAIN_METADATA',
 'Controlled administrative-only amendment retaining canonical rule state',
 false,true,true,'ISSUE-3779_USER_AUTHORIZED_SCOPE','ACTIVE',
 'MIGRATION-ISSUE-3779-NOT-EXECUTION-RECEIPT');

INSERT INTO public.lf_operation_mode_bindings(
 operation_code,task_mode,execution_mode,allowed,write_allowed,
 destination_kind,input_completeness,canonical_state,required_existing_state,
 notes,status,created_by_execution_id)
VALUES (
 'ACTUALIZACION_REGLA_LF','MAINTAIN_METADATA','GOVERNED',true,true,
 'CANONICAL_EXISTING','COMPLETE_REQUIRED',NULL,'CANDIDATO_OR_VIGENTE',
 'Changes to created_by / owner_name only, preserving status and material rule. '
 ||'Requires existing skill judged parent and child official readback.',
 'ACTIVE','MIGRATION-ISSUE-3779-NOT-EXECUTION-RECEIPT');

CREATE FUNCTION public.lf_regla_admin_governed_write_v1(
 p_execution_id text,p_rule_code text,p_expected_sha text,p_changes jsonb
) RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER
SET search_path TO 'pg_catalog','public','lf_ops','extensions'
AS $lf_admin$
DECLARE
 v_exec public.lf_operation_execution%ROWTYPE;
 v_before lf_ops.reglas%ROWTYPE;
 v_after lf_ops.reglas%ROWTYPE;
 v_before_sha text;
 v_after_sha text;
 v_owner text;
 v_creator text;
BEGIN
 IF p_changes IS NULL OR jsonb_typeof(p_changes) IS DISTINCT FROM 'object'
 OR (SELECT count(*) FROM jsonb_object_keys(p_changes)) NOT BETWEEN 1 AND 2
 OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_changes) k(field)
   WHERE k.field NOT IN ('owner_name','created_by')
     OR jsonb_typeof(p_changes->k.field) IS DISTINCT FROM 'string'
     OR length(btrim(p_changes->>k.field)) NOT BETWEEN 1 AND 128)
 THEN RAISE EXCEPTION 'BLOCK_RULE_ADMIN_WRITER_FIELD_ALLOWLIST'; END IF;
 SELECT * INTO v_exec FROM public.lf_operation_execution
 WHERE execution_id=p_execution_id AND operation_code='ACTUALIZACION_REGLA_LF'
 AND target_type='REGLA' AND target_code=p_rule_code
 AND status='IN_PROGRESS' AND manifest->>'candidate_patch_scope'='ADMINISTRATIVE_ONLY'
 AND manifest->>'promotion_authorized'='false'
 FOR UPDATE;
 IF NOT FOUND OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution_steps st
   WHERE st.execution_id=p_execution_id AND st.step_id='destination_validate'
     AND st.status='PASS_CLEAN') THEN
   RAISE EXCEPTION 'BLOCK_RULE_ADMIN_WRITER_GOVERNED_CHILD_OR_STEP'; END IF;
 IF p_changes ? 'owner_name' AND NOT EXISTS (
    SELECT 1 FROM information_schema.columns WHERE table_schema='lf_ops'
       AND table_name='reglas' AND column_name='owner_name')
 THEN RAISE EXCEPTION 'BLOCK_RULE_ADMIN_OWNER_COLUMN_NOT_YET_INSTALLED'; END IF;
 SELECT * INTO v_before FROM lf_ops.reglas WHERE codigo=p_rule_code FOR UPDATE;
 IF NOT FOUND OR v_before.estado NOT IN ('CANDIDATO','VIGENTE') THEN
   RAISE EXCEPTION 'BLOCK_RULE_ADMIN_WRITER_MISSING_OR_INVALID_STATE'; END IF;
 v_before_sha:=public.lf_asset_snapshot_sha_v1('REGLA',p_rule_code);
 IF v_before_sha IS DISTINCT FROM p_expected_sha THEN
   RAISE EXCEPTION 'BLOCK_RULE_ADMIN_WRITER_STALE_SHA'; END IF;
 v_creator:=CASE WHEN p_changes ? 'created_by'
    THEN p_changes->>'created_by' ELSE v_before.created_by END;
 IF p_changes ? 'owner_name' THEN
   -- The owner field will only be installed via separately impact-approved
   -- evolution of the existing lf_ops.reglas schema. No shadow table.
   v_owner:=p_changes->>'owner_name';
   EXECUTE 'UPDATE lf_ops.reglas SET owner_name=$1,created_by=$2,updated_at=now()
            WHERE id=$3' USING v_owner,v_creator,v_before.id;
 ELSE
   UPDATE lf_ops.reglas SET created_by=v_creator,updated_at=now()
   WHERE id=v_before.id;
 END IF;
 SELECT * INTO v_after FROM lf_ops.reglas WHERE id=v_before.id;
 IF v_after.codigo IS DISTINCT FROM v_before.codigo
 OR v_after.estado IS DISTINCT FROM v_before.estado
 OR (to_jsonb(v_after)-'created_at'-'updated_at'
      -'owner_name'-'created_by')
    IS DISTINCT FROM
    (to_jsonb(v_before)-'created_at'-'updated_at'-'owner_name'-'created_by')
 OR (to_jsonb(v_after)->>'owner_name') IS DISTINCT FROM
    CASE WHEN p_changes ? 'owner_name' THEN p_changes->>'owner_name'
         ELSE to_jsonb(v_before)->>'owner_name' END
 OR v_after.created_by IS DISTINCT FROM v_creator THEN
   RAISE EXCEPTION 'BLOCK_RULE_ADMIN_WRITER_PROTECTED_FIELD_CHANGED'; END IF;
 v_after_sha:=public.lf_asset_snapshot_sha_v1('REGLA',p_rule_code);
 IF v_after_sha IS NULL OR v_after_sha=v_before_sha THEN
   RAISE EXCEPTION 'BLOCK_RULE_ADMIN_WRITER_NO_MATERIAL_CHANGE'; END IF;
 RETURN jsonb_build_object('result','RULE_ADMINISTRATIVE_UPDATED',
    'operation_code','ACTUALIZACION_REGLA_LF','execution_id',p_execution_id,
    'before',to_jsonb(v_before),'after',to_jsonb(v_after),
    'source_snapshot_sha256',v_before_sha,'result_snapshot_sha256',v_after_sha);
END $lf_admin$;

REVOKE ALL ON FUNCTION
 public.lf_regla_admin_governed_write_v1(text,text,text,jsonb)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION
 public.lf_regla_admin_governed_write_v1(text,text,text,jsonb)
 TO service_role;

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
 IF (SELECT count(*) FROM jsonb_object_keys(v_patch))<>3
    OR (SELECT count(*) FROM jsonb_object_keys(v_changes)) NOT BETWEEN 1 AND
       CASE v_change_kind WHEN 'ADMINISTRATIVE_ONLY' THEN 2
         WHEN 'DOCUMENTARY_ONLY' THEN 3 ELSE 7 END THEN
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
 IF v_profile_output->'deliverable_created'->'governed_rule_patch'
       IS DISTINCT FROM v_patch
    OR v_profile_output->'deliverable_created'->'product_decision'->>'decision_id'
       IS DISTINCT FROM p_input->>'decision_id' THEN
    RAISE EXCEPTION 'BLOCK_RULE_CHILD_PATCH_NOT_IN_JUDGED_OUTPUT'; END IF;
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
 IF nullif(btrim(v_screen),'') IS NULL OR NOT EXISTS (
   SELECT 1 FROM lf_ops.pantallas s
   JOIN lf_ops.reglas_pantallas rel ON rel.pantalla_id=s.id
   JOIN lf_ops.reglas r ON r.id=rel.regla_id
   WHERE s.codigo=v_screen AND r.codigo=v_rule
 ) THEN RAISE EXCEPTION 'BLOCK_RULE_CHILD_RULE_NOT_IN_SELECTED_SCREEN'; END IF;
 SELECT count(*) INTO v_n FROM lf_ops.reglas WHERE codigo=v_rule;
 IF v_n<>1 THEN RAISE EXCEPTION 'BLOCK_RULE_CHILD_EXACT_RULE_CARDINALITY:%',v_n; END IF;
 SELECT * INTO v_before FROM lf_ops.reglas WHERE codigo=v_rule FOR UPDATE;
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
 IF v_written->>'result' IS DISTINCT FROM
     CASE WHEN v_change_kind='ADMINISTRATIVE_ONLY'
      THEN 'RULE_ADMINISTRATIVE_UPDATED' ELSE 'RULE_CANDIDATE_UPDATED' END
    OR v_written->'before' IS DISTINCT FROM to_jsonb(v_before)
    OR v_written->'before'->>'estado' IS DISTINCT FROM v_before.estado
    OR v_written->'after'->>'estado' IS DISTINCT FROM
       CASE WHEN v_change_kind='ADMINISTRATIVE_ONLY'
            THEN v_before.estado ELSE 'CANDIDATO' END THEN
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
    OR v_after->>'estado' IS DISTINCT FROM
       CASE WHEN v_change_kind='ADMINISTRATIVE_ONLY'
           THEN v_before.estado ELSE 'CANDIDATO' END
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
   WHERE k.field NOT IN (
    CASE WHEN v_change_kind='ADMINISTRATIVE_ONLY' THEN 'owner_name'
         ELSE 'titulo' END,
    CASE WHEN v_change_kind='ADMINISTRATIVE_ONLY' THEN 'created_by'
         ELSE 'descripcion' END,
    CASE WHEN v_change_kind='ADMINISTRATIVE_ONLY' THEN 'owner_name'
         ELSE 'razon' END,
    CASE WHEN v_change_kind='FUNCTIONAL_CANDIDATE' THEN 'categoria'
         ELSE 'pendiente_decision' END,
    CASE WHEN v_change_kind='FUNCTIONAL_CANDIDATE' THEN 'valor_config'
         ELSE 'pendiente_detalle' END,
    CASE WHEN v_change_kind='FUNCTIONAL_CANDIDATE' THEN 'es_transversal'
         ELSE 'pendiente_decision' END,
    CASE WHEN v_change_kind='FUNCTIONAL_CANDIDATE' THEN 'origen'
         ELSE 'pendiente_detalle' END,
    CASE WHEN v_change_kind='FUNCTIONAL_CANDIDATE' THEN 'pendiente_decision'
         ELSE 'pendiente_decision' END,
    CASE WHEN v_change_kind='FUNCTIONAL_CANDIDATE' THEN 'pendiente_detalle'
         ELSE 'pendiente_detalle' END)) THEN
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

DO $readback$
BEGIN
 IF to_regprocedure('public.lf_regla_admin_governed_write_v1(text,text,text,jsonb)') IS NULL
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_mode_bindings b
  WHERE b.operation_code='ACTUALIZACION_REGLA_LF'
    AND b.task_mode='MAINTAIN_METADATA' AND b.execution_mode='GOVERNED'
    AND b.destination_kind='CANONICAL_EXISTING' AND b.status='ACTIVE')
 THEN RAISE EXCEPTION 'BLOCK_RULE_GENERAL_INSTALL_READBACK'; END IF;
END $readback$;
COMMIT;

-- USER-AUTHORIZED LF IG Fase 2: persist ONLY B2B-RULE-VALIDATION-VALID-ONLY-002 CANDIDATO.
-- Existing ACT-0001 Product Director RUN, official Step70 AUTO, owner V2, RULE_CREATE_APPLY
-- Signed PR #4390 Train 44517909669. No promotion, no relink, no delete of old.
BEGIN;
DO $ig_b2b_002_persistent_create$
DECLARE
 v_parent CONSTANT text := 'EXEC-PROFILE-GATE2-258A773626E5527875866440';
 v_old CONSTANT text := 'B2B-RULE-VALIDATION-VALID-ONLY-001';
 v_new CONSTANT text := 'B2B-RULE-VALIDATION-VALID-ONLY-002';
 v_sha CONSTANT text := 'f08fc4166cddd37b8d4c17157cb09b45039264a7ab0bb0da162f75cbffe51e9a';
 v_preimage_sha CONSTANT text := 'bd8c5508b511132662ae23149ca5603ec3f6807edf19c165f7399a1d1700c3bf';
 v_train CONSTANT text := '44517909669';
 v_train_execution CONSTANT text := 'EXEC-DB-TRAIN-PR4390-20261119114747-R44517909669';
 v_train_ref CONSTANT text := 'github://cristhianlujan/claude-persona-lf-patch/actions/runs/44517909669#RULE_CONTRACT_LEVEL';
 v_te record; v_evt record;
 v_patch jsonb;v_candidate_digest text;v_pg_sha text;v_readback_sha text;v_manifest_sha text;
 v_70 jsonb;v_step70 jsonb;v_owner jsonb;v_score jsonb;v_promotion_req jsonb;
 v_old_before jsonb;v_old_after jsonb;v_old_config jsonb;v_new_cfg jsonb;
 v_old_id integer;v_new_id integer;v_before_count integer;v_before_versions integer;
 v_links integer;v_tests integer;v_cites integer;
BEGIN
 IF current_setting('server_version_num')::int/10000<>17 THEN RAISE EXCEPTION 'LF_IG_0641_PG17_REQUIRED'; END IF;
 SELECT count(*) INTO v_before_count FROM lf_ops.reglas;
 SELECT count(*) INTO v_before_versions FROM lf_ops.reglas_versiones;
 IF v_before_count<>586 THEN RAISE EXCEPTION 'LF_IG_0641_RULE_BASELINE_DRIFT:%',v_before_count; END IF;
 SELECT id,to_jsonb(r),r.valor_config INTO STRICT v_old_id,v_old_before,v_old_config
   FROM lf_ops.reglas r WHERE r.codigo=v_old AND r.estado='VIGENTE';
 SELECT count(*) INTO v_links FROM lf_ops.reglas_pantallas WHERE regla_id=v_old_id;
 SELECT count(*) INTO v_tests FROM lf_ops.regla_behavior_tests WHERE regla_codigo=v_old;
 SELECT count(*) INTO v_cites FROM lf_ops.reglas r WHERE r.codigo<>v_old AND r.valor_config::text LIKE '%'||v_old||'%';
 IF (SELECT array_agg(pantalla_id ORDER BY pantalla_id) FROM lf_ops.reglas_pantallas WHERE regla_id=v_old_id)
 IS DISTINCT FROM ARRAY[44,66,67]::integer[] OR v_links<>3 OR v_tests<>1 OR v_cites<>3
 THEN RAISE EXCEPTION 'LF_IG_0641_OLD_DEPENDENCIES_DRIFT'; END IF;
 IF EXISTS(SELECT 1 FROM lf_ops.reglas WHERE codigo=v_new)
 OR EXISTS(SELECT 1 FROM public.lf_ig_owner_decision_v2 WHERE rule_code=v_new)
 OR EXISTS(SELECT 1 FROM public.lf_ig_functional_train_evidence_v1 WHERE rule_code=v_new)
 THEN RAISE EXCEPTION 'LF_IG_0641_REPLACEMENT_ALREADY_STARTED'; END IF;
 SELECT s.evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch}'
 INTO STRICT v_patch FROM public.lf_operation_execution_steps s
 JOIN public.lf_operation_execution e ON e.execution_id=s.execution_id
 WHERE s.execution_id=v_parent AND s.step_id='execute_profile' AND s.status='STEP_PASS_WITH_EVIDENCE'
 AND e.status='IN_PROGRESS' AND e.target_code='PERFIL-PRODUCT-DIRECTOR-LF'
 AND e.operation_code='EJECUCION_PERFIL_LF'
 AND e.manifest->>'read_only'='true' AND e.manifest->>'no_write'='true'
 AND e.manifest#>>'{screen_selection_result,selected_screen_code}'='B2B-CARGA-002'
 AND s.evidence_payload#>>'{profile_output,deliverable_created,product_decision,proposed_by}'='PERFIL-PRODUCT-DIRECTOR-LF';
 IF NOT EXISTS(SELECT 1 FROM public.lf_operation_execution_steps
 WHERE execution_id=v_parent AND step_id='output_validate'
 AND status='STEP_PASS_WITH_EVIDENCE' AND evidence_payload->>'output_contract_result'='PASS')
 OR v_patch->>'rule_code' IS DISTINCT FROM v_new
 OR v_patch->>'change_kind' IS DISTINCT FROM 'CREATE'
 OR encode(extensions.digest(convert_to(v_patch::text,'UTF8'),'sha256'),'hex') IS DISTINCT FROM v_sha
 OR encode(extensions.digest(convert_to('LF_RULE_ABSENT:'||v_new,'UTF8'),'sha256'),'hex') IS DISTINCT FROM v_preimage_sha
 OR v_patch#>>'{changes,valor_config,lf_rule_scope}' IS DISTINCT FROM 'PANTALLA'
 OR v_patch#>'{changes,valor_config,lf_screen_ids}' IS DISTINCT FROM '[44,66,67]'::jsonb
 OR v_patch#>>'{changes,es_transversal}' IS DISTINCT FROM 'false'
 THEN RAISE EXCEPTION 'LF_IG_0641_PATCH_OR_SOURCE_NOT_EXACT'; END IF;
 v_new_cfg:=v_patch#>'{changes,valor_config}';
 IF (v_new_cfg-'lf_rule_scope'-'lf_screen_ids'-'lf_applicability'-'lf_replaces_rule_code'-'lf_promotion_authorized') IS DISTINCT FROM v_old_config
 THEN RAISE EXCEPTION 'LF_IG_0641_OLD_CONFIG_NOT_PRESERVED'; END IF;
 SELECT * INTO STRICT v_te FROM public.lf_operation_execution e WHERE e.execution_id=v_train_execution
 AND e.operation_code='ACTUALIZACION_DB_LF' AND e.status='COMPLETED'
 AND e.manifest->>'train_run_id'=v_train
 AND e.updated_by_execution_id='LF-MIGRATION-TRAIN-RUN-'||v_train;
 SELECT * INTO STRICT v_evt FROM public.lf_eventos evt
 WHERE evt.entidad_codigo=v_train_execution AND evt.evento_tipo='MIGRATION_TRAIN_RECEIPT_RECORDED'
 AND evt.origen='lf-migration-merge-train'
 AND evt.payload#>>'{receipt,train_run_id}'=v_train
 AND evt.payload#>>'{receipt,heads,final_head}'=v_te.manifest->>'head_sha'
 AND evt.payload#>>'{receipt,heads,final_head_is_execution_head}'='true'
 AND evt.payload#>>'{receipt,terminal_status}'='COMPLETED'
 AND evt.payload#>>'{receipt,parity,migration_source_parity}'='PASS'
 AND evt.payload#>>'{receipt,ledger_readback,matches_target}'='true'
 AND encode(extensions.digest(convert_to((evt.payload->'receipt')::text,'UTF8'),'sha256'),'hex')
      =evt.payload->>'receipt_sha256';
 IF NOT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations
 WHERE version='20261119114747' AND name='lf_ig_b2b_002_persistent_create_contract_pg17_v1')
 THEN RAISE EXCEPTION 'LF_IG_0641_SOURCE_PROOF_NOT_APPLIED'; END IF;
 v_candidate_digest:=encode(extensions.digest(convert_to(
    jsonb_build_object('rule_code',v_new,'candidate_state','CANDIDATO',
    'change_kind','CREATE','candidate_changes',v_patch->'changes')::text,'UTF8'),'sha256'),'hex');
 v_pg_sha:=encode(extensions.digest(convert_to((v_evt.payload#>'{receipt,apply}')::text,'UTF8'),'sha256'),'hex');
 v_readback_sha:=encode(extensions.digest(convert_to(
    jsonb_build_object('old_rule',v_old_before,'parent',v_parent,'patch_sha',v_sha,
    'train_head',v_te.manifest->>'head_sha','train_event_id',v_evt.id)::text,'UTF8'),'sha256'),'hex');
 v_manifest_sha:=encode(extensions.digest(convert_to(
    jsonb_build_object('source_sha',v_preimage_sha,'patch_sha',v_sha,
    'pg17_contract_train',v_train,'signed_event',v_evt.id,'screen_ids',jsonb_build_array(44,66,67),
    'proof_scope','RULE_CONTRACT_LEVEL')::text,'UTF8'),'sha256'),'hex');
 INSERT INTO public.lf_ig_functional_train_evidence_v1(
    rule_code,source_snapshot_sha256,proposal_sha256,candidate_snapshot_sha256,
    train_execution_id,train_run_id,train_event_id,train_head_sha,
    pg_rollback_status,independent_readback_status,functional_checks_status,
    negative_checks_status,pg_report_sha256,readback_sha256,check_manifest_sha256,report_ref)
 VALUES(v_new,v_preimage_sha,v_sha,v_candidate_digest,v_train_execution,v_train,v_evt.id,
        v_te.manifest->>'head_sha','PASS','PASS','PASS','PASS',
        v_pg_sha,v_readback_sha,v_manifest_sha,v_train_ref);
 v_70:=public.lf_ig_step70_functional_train_auto_v1(v_parent);
 IF v_70->>'status' IS DISTINCT FROM 'PASS' THEN RAISE EXCEPTION 'LF_IG_0641_STEP70_AUTO_BLOCKED:%',v_70; END IF;
 v_step70:=public.lf_profile_native_bridge_record_semantic_v1(v_parent,v_70,v_train_ref,v_parent);
 IF v_step70->>'status' IS DISTINCT FROM 'SEMANTIC_JUDGE_RECORDED'
 THEN RAISE EXCEPTION 'LF_IG_0641_STEP70_NOT_RECORDED:%',v_step70; END IF;
 -- Owner authorizes ONLY CREATE CANDIDATO in user's current request.
 v_owner:=public.lf_ig_rule_owner_decide_v2(v_parent,v_new,v_preimage_sha,
      '{"usuario":"Cristhian Lujan","veredicto":"APROBAR"}'::jsonb);
 IF v_owner->>'status' IS DISTINCT FROM 'APPROVED_AND_CANDIDATO_VERIFIED'
 OR v_owner->>'kind' IS DISTINCT FROM 'CREATE'
 OR v_owner->>'promotion_authorized' IS DISTINCT FROM 'false'
 OR (SELECT count(*) FROM public.lf_operation_execution_steps
   WHERE execution_id=v_owner->>'child_execution_id' AND status='PASS_CLEAN')<>7
 THEN RAISE EXCEPTION 'LF_IG_0641_CREATE_IG_V2_NOT_VERIFIED:%',v_owner; END IF;
 SELECT id,valor_config INTO STRICT v_new_id,v_new_cfg FROM lf_ops.reglas WHERE codigo=v_new
 AND estado='CANDIDATO' AND pendiente_decision=true AND created_by=v_owner->>'child_execution_id';
 IF (v_new_cfg-'lf_rule_scope'-'lf_screen_ids'-'lf_applicability'-'lf_replaces_rule_code'-'lf_promotion_authorized') IS DISTINCT FROM v_old_config
 OR v_new_cfg#>>'{lf_replaces_rule_code}' IS DISTINCT FROM v_old
 OR (SELECT count(*) FROM lf_ops.reglas)<>v_before_count+1
 OR (SELECT count(*) FROM lf_ops.reglas_pantallas WHERE regla_id=v_new_id)<>0
 OR (SELECT count(*) FROM lf_ops.regla_behavior_tests WHERE regla_codigo=v_new)<>0
 OR (SELECT count(*) FROM lf_ops.reglas_versiones WHERE codigo=v_old AND vigente_hasta IS NULL)<>1
 OR (SELECT count(*) FROM public.lf_ig_rule_change_v2
   WHERE rule_code=v_new AND kind='CREATE' AND state='CANDIDATE_VERIFIED'
   AND parent_execution_id=v_parent AND child_execution_id=v_owner->>'child_execution_id')<>1
 OR (SELECT count(*) FROM public.lf_rule_promotion_v1 WHERE rule_code=v_new)<>0
 THEN RAISE EXCEPTION 'LF_IG_0641_NEW_CANDIDATE_READBACK_FAILED'; END IF;
 SELECT to_jsonb(r) INTO STRICT v_old_after FROM lf_ops.reglas r WHERE id=v_old_id;
 IF v_old_after IS DISTINCT FROM v_old_before
 OR (SELECT count(*) FROM lf_ops.reglas_pantallas WHERE regla_id=v_old_id)<>v_links
 OR (SELECT count(*) FROM lf_ops.regla_behavior_tests WHERE regla_codigo=v_old)<>v_tests
 OR (SELECT count(*) FROM lf_ops.reglas r WHERE r.codigo<>v_old AND r.codigo<>v_new AND r.valor_config::text LIKE '%'||v_old||'%')<>v_cites
 THEN RAISE EXCEPTION 'LF_IG_0641_OLD_RULE_TOUCHED'; END IF;
 RAISE NOTICE 'LF_IG_0641_CREATE_PERSISTENT_PASS:rule=%:state=CANDIDATO:child=%:steps=7:old_untouched=true:rules=%:versions=%:snapshot_sha=%',
 v_new,v_owner->>'child_execution_id',v_before_count+1,(SELECT count(*) FROM lf_ops.reglas_versiones),v_owner->>'candidate_snapshot_sha256';
 -- Evaluate only; AUTO promotion MUST be a separate governed Train, never implicit.
 v_score:=public.lf_rule_promotion_score_v1(v_parent,v_new);
 RAISE NOTICE 'LF_IG_0641_PROMOTION_SCORE_REAL:%',v_score;
 IF v_score->>'decision'<>'AUTO' THEN
   v_promotion_req:=public.lf_rule_promotion_request_v1(v_parent,v_new,
     'Evaluación gobernada solicitada por dueño; no decidir ni aplicar promoción sin score y autoridad');
   IF v_promotion_req->>'status' NOT IN ('BLOCKED','PENDING_HUMAN_APPROVAL') THEN
     RAISE EXCEPTION 'LF_IG_0641_PROMOTION_UNEXPECTED_STATE:%',v_promotion_req; END IF;
   RAISE NOTICE 'LF_IG_0641_PROMOTION_REQUEST_REAL:%',v_promotion_req;
 ELSE
   RAISE NOTICE 'LF_IG_0641_PROMOTION_AUTO_ELIGIBLE_SEPARATE_PR_REQUIRED';
 END IF;
 IF (SELECT estado FROM lf_ops.reglas WHERE codigo=v_old)<>'VIGENTE'
 OR (SELECT estado FROM lf_ops.reglas WHERE codigo=v_new)<>'CANDIDATO'
 OR (SELECT count(*) FROM public.lf_rule_promotion_v1 WHERE rule_code=v_new AND status='APPLIED')<>0
 THEN RAISE EXCEPTION 'LF_IG_0641_UNAUTHORIZED_PROMOTION_OR_MUTATION'; END IF;
END;
$ig_b2b_002_persistent_create$;
COMMIT;

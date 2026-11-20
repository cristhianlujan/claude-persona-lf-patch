-- PR-J3B: owner delegated functional Train, typed nonsemantic Step70; PR-H unchanged.
BEGIN;

CREATE OR REPLACE FUNCTION public.lf_ig_step70_functional_train_auto_v1(p_parent text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public','lf_ops','extensions'
AS $auto$
DECLARE e public.lf_operation_execution%ROWTYPE;
        inp jsonb; prod jsonb; valid jsonb; profile jsonb; patch jsonb;
        rule text; source_sha text; patch_sha text; scope_digest text; candidate_digest text;
        train public.lf_ig_functional_train_evidence_v1%ROWTYPE;
BEGIN
 SELECT * INTO e FROM public.lf_operation_execution
 WHERE execution_id=p_parent AND operation_code='EJECUCION_PERFIL_LF'
   AND target_type='PERFIL' AND target_code='PERFIL-PRODUCT-DIRECTOR-LF'
   AND status='IN_PROGRESS'
   AND manifest->>'read_only'='true' AND manifest->>'no_write'='true'
   AND manifest#>>'{router_profile_handoff,router_authorization_receipt,profile_execution_allowed}'='true';
 IF NOT FOUND THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','AUTO_TRAIN_PARENT_INVALID'); END IF;
 SELECT evidence_payload INTO inp FROM public.lf_operation_execution_steps
 WHERE execution_id=p_parent AND step_id='input_validate' AND status='STEP_PASS_WITH_EVIDENCE';
 SELECT evidence_payload INTO prod FROM public.lf_operation_execution_steps
 WHERE execution_id=p_parent AND step_id='execute_profile' AND status='STEP_PASS_WITH_EVIDENCE';
 SELECT evidence_payload INTO valid FROM public.lf_operation_execution_steps
 WHERE execution_id=p_parent AND step_id='output_validate' AND status='STEP_PASS_WITH_EVIDENCE';
 profile:=prod->'profile_output';
 patch:=profile#>'{deliverable_created,governed_rule_patch}';
 rule:=patch->>'rule_code';
 scope_digest:=inp->>'scope_authority_packet_sha256';
 candidate_digest:=prod->>'candidate_digest';
 IF inp IS NULL OR prod IS NULL OR valid->>'output_contract_result' IS DISTINCT FROM 'PASS'
    OR profile->>'worker' IS DISTINCT FROM 'product_director_lf'
    OR profile->>'output_type' IS DISTINCT FROM 'PRODUCT_DIRECTION_SPEC'
    OR profile->>'self_verdict' IS DISTINCT FROM 'PASS'
    OR patch->>'change_kind' IS DISTINCT FROM 'FUNCTIONAL'
    OR jsonb_typeof(patch->'changes')<>'object'
    OR coalesce(rule,'') !~ '^[A-Z0-9][A-Z0-9_-]{3,159}$'
    OR coalesce(scope_digest,'') !~ '^sha256:[0-9a-f]{64}$'
    OR coalesce(candidate_digest,'') !~ '^sha256:[0-9a-f]{64}$'
 THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','AUTO_TRAIN_PROFILE_OR_STEP_INVALID'); END IF;
 IF NOT EXISTS(
   SELECT 1 FROM lf_ops.reglas r
   JOIN lf_ops.reglas_pantallas rp ON rp.regla_id=r.id
   JOIN lf_ops.pantallas s ON s.id=rp.pantalla_id
   WHERE r.codigo=rule AND r.estado='VIGENTE'
     AND s.codigo=(e.manifest#>>'{screen_selection_result,selected_screen_code}')
 ) THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','AUTO_TRAIN_VIGENTE_SCOPE_INVALID'); END IF;
 source_sha:=public.lf_asset_snapshot_sha_v1('REGLA',rule);
 patch_sha:=encode(extensions.digest(convert_to(patch::text,'UTF8'),'sha256'),'hex');
 SELECT * INTO train FROM public.lf_ig_functional_train_evidence_v1 t
 WHERE t.rule_code=rule AND t.source_snapshot_sha256=source_sha
   AND t.proposal_sha256=patch_sha
   AND t.pg_rollback_status='PASS'
   AND t.independent_readback_status='PASS'
   AND t.functional_checks_status='PASS'
   AND t.negative_checks_status='PASS'
   AND t.candidate_snapshot_sha256 ~ '^[0-9a-f]{64}$'
   AND t.pg_report_sha256 ~ '^[0-9a-f]{64}$'
   AND t.readback_sha256 ~ '^[0-9a-f]{64}$'
   AND t.check_manifest_sha256 ~ '^[0-9a-f]{64}$';
 IF NOT FOUND THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','AUTO_TRAIN_EXACT_SHA_OR_PASS_MISSING'); END IF;
 IF NOT EXISTS(
   SELECT 1 FROM public.lf_operation_execution te
   JOIN public.lf_eventos evt ON evt.id=train.train_event_id
     AND evt.entidad_codigo=te.execution_id
     AND evt.evento_tipo='MIGRATION_TRAIN_RECEIPT_RECORDED'
     AND evt.origen='lf-migration-merge-train'
   WHERE te.execution_id=train.train_execution_id
     AND te.operation_code='ACTUALIZACION_DB_LF' AND te.status='COMPLETED'
     AND te.manifest->>'train_run_id'=train.train_run_id
     AND te.manifest->>'head_sha'=train.train_head_sha
     AND te.updated_by_execution_id='LF-MIGRATION-TRAIN-RUN-'||train.train_run_id
     AND evt.payload#>>'{receipt,train_run_id}'=train.train_run_id
     AND evt.payload#>>'{receipt,heads,final_head}'=train.train_head_sha
     AND evt.payload#>>'{receipt,heads,final_head_is_execution_head}'='true'
     AND evt.payload#>>'{receipt,terminal_status}'='COMPLETED'
     AND evt.payload#>>'{receipt,parity,migration_source_parity}'='PASS'
     AND evt.payload#>>'{receipt,ledger_readback,matches_target}'='true'
     AND evt.payload->>'receipt_sha256' ~ '^[0-9a-f]{64}$'
     AND encode(extensions.digest(convert_to((evt.payload->'receipt')::text,'UTF8'),'sha256'),'hex')
          =evt.payload->>'receipt_sha256'
 ) THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','AUTO_TRAIN_SIGNED_RECEIPT_INVALID'); END IF;
 RETURN jsonb_build_object(
   'status','PASS','validator_status','PASS',
   'verdict','PASS_TRAIN_EVIDENCE_AUTOMATICO',
   'review_mode','TRAIN_EVIDENCE_AUTOMATICO','evaluator','TRAIN_EVIDENCE_AUTOMATICO',
   'judge_independence_status','NOT_ASSERTED','semantic_judge_performed',false,
   'reviewer_is_producer',false,'producer_independence_proven',false,'model_call_count',0,
   'candidate_sha256',substring(candidate_digest from 8),
   'scope_packet_sha256',substring(scope_digest from 8),
   'train_evidence',jsonb_build_object(
     'rule_code',rule,'source_snapshot_sha256',source_sha,'proposal_sha256',patch_sha,
     'candidate_snapshot_sha256',train.candidate_snapshot_sha256,
     'train_run_id',train.train_run_id,'train_head_sha',train.train_head_sha,
     'train_execution_id',train.train_execution_id,
     'pg_rollback_status','PASS','independent_readback_status','PASS',
     'functional_checks_status','PASS','negative_checks_status','PASS',
     'pg_report_sha256',train.pg_report_sha256,'readback_sha256',train.readback_sha256,
     'check_manifest_sha256',train.check_manifest_sha256,'report_ref',train.report_ref),
   'result',jsonb_build_object(
     'verdict','PASS_TRAIN_EVIDENCE_AUTOMATICO',
     'candidate_sha256',substring(candidate_digest from 8),
     'scope_packet_sha256',substring(scope_digest from 8),
     'unsupported_claims','[]'::jsonb,'blocking_codes','[]'::jsonb)
 );
END
$auto$;
REVOKE ALL ON FUNCTION public.lf_ig_step70_functional_train_auto_v1(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.lf_ig_step70_functional_train_auto_v1(text) TO postgres, service_role;


DO $j3b$ DECLARE d text; d0 text; BEGIN
 d:=pg_get_functiondef('public.lf_profile_execution_trust_validation_v2(text,text,jsonb)'::regprocedure);
 IF md5(d)<>'010080707de0c497fc07abb6cfb097df' THEN RAISE EXCEPTION 'PR_J3B_TRUST_PREIMAGE_DRIFT'; END IF;
 d0:=d;
 d:=replace(d, $orig_j3b$         )
       )
       or coalesce(candidate_digest,'') !~ '^sha256:[0-9a-f]{64}$'$orig_j3b$, $new_j3b$         )
         or (
           semantic_result->>'verdict'='PASS_TRAIN_EVIDENCE_AUTOMATICO'
           and semantic_result->>'review_mode'='TRAIN_EVIDENCE_AUTOMATICO'
           and semantic_result IS NOT DISTINCT FROM public.lf_ig_step70_functional_train_auto_v1(p_execution_id)
         )
       )
       or coalesce(candidate_digest,'') !~ '^sha256:[0-9a-f]{64}$'$new_j3b$);
 IF d=d0 THEN RAISE EXCEPTION 'PR_J3B_TRUST_REPLACEMENT_FAILED'; END IF;
 EXECUTE d;
END $j3b$;

DO $j3b$ DECLARE d text; d0 text; BEGIN
 d:=pg_get_functiondef('public.lf_ig_rule_owner_decide_v2(text,text,text,jsonb)'::regprocedure);
 IF md5(d)<>'d537e91abe7da40fb54636ccfb8c51ef' THEN RAISE EXCEPTION 'PR_J3B_OWNER_PREIMAGE_DRIFT'; END IF;
 d0:=d;
 d:=replace(d, $orig_j3b$IF coalesce(v_judge->>'verdict','') <> 'PASS_INDEPENDENT_SEMANTIC'
 THEN RAISE EXCEPTION 'LF_IG_OWNER_INDEPENDENT_JUDGE_REQUIRED'; END IF;$orig_j3b$, $new_j3b$IF coalesce(v_judge->>'verdict','') <> 'PASS_INDEPENDENT_SEMANTIC'
    AND NOT (
      v_judge->>'verdict'='PASS_TRAIN_EVIDENCE_AUTOMATICO'
      AND v_judge->>'review_mode'='TRAIN_EVIDENCE_AUTOMATICO'
      AND v_judge IS NOT DISTINCT FROM public.lf_ig_step70_functional_train_auto_v1(p_parent)
    )
 THEN RAISE EXCEPTION 'LF_IG_OWNER_VERIFIED_SEMANTIC_OR_FUNCTIONAL_TRAIN_REQUIRED'; END IF;$new_j3b$);
 IF d=d0 THEN RAISE EXCEPTION 'PR_J3B_OWNER_REPLACEMENT_FAILED'; END IF;
 EXECUTE d;
END $j3b$;

DO $j3b$ DECLARE d text; d0 text; BEGIN
 d:=pg_get_functiondef('public.lf_profile_execution_terminal_authority_receipt_v1(text)'::regprocedure);
 IF md5(d)<>'1d5f3bca8a7601c9f5f46340c83c22d7' THEN RAISE EXCEPTION 'PR_J3B_TERMINAL_PREIMAGE_DRIFT'; END IF;
 d0:=d;
 d:=replace(d, $orig_j3b$NOT IN ('PASS_INDEPENDENT_SEMANTIC','PASS_REVIEWED_CURRENT_CONTEXT')$orig_j3b$, $new_j3b$NOT IN ('PASS_INDEPENDENT_SEMANTIC','PASS_REVIEWED_CURRENT_CONTEXT','PASS_TRAIN_EVIDENCE_AUTOMATICO')$new_j3b$);
 IF d=d0 THEN RAISE EXCEPTION 'PR_J3B_TERMINAL_REPLACEMENT_FAILED'; END IF;
 EXECUTE d;
END $j3b$;

-- Real target RUN: invoke the existing canonical Step70 recorder exactly once.
-- In empty PG17 fixture databases, only DDL is exercised; no fabricated RUN.
DO $j3b_record$
DECLARE parent_run CONSTANT text:='EXEC-PROFILE-GATE2-D53B143BD852CB33AB25257F';
        auto_result jsonb; written jsonb;
BEGIN
 IF EXISTS(SELECT 1 FROM public.lf_operation_execution
           WHERE execution_id=parent_run AND status='IN_PROGRESS')
    AND NOT EXISTS(SELECT 1 FROM public.lf_operation_execution_steps
           WHERE execution_id=parent_run AND step_id='semantic_judge'
             AND status='STEP_PASS_WITH_EVIDENCE')
 THEN
  auto_result:=public.lf_ig_step70_functional_train_auto_v1(parent_run);
  IF auto_result->>'status' IS DISTINCT FROM 'PASS'
    OR auto_result#>>'{train_evidence,rule_code}' IS DISTINCT FROM 'B2B-RULE-AUTH-020'
    OR auto_result#>>'{train_evidence,proposal_sha256}' IS DISTINCT FROM 'adaffe6a15e705fc4ec48fa809135088736915cd0d4446691ede078899704a02'
    OR auto_result#>>'{train_evidence,candidate_snapshot_sha256}' IS DISTINCT FROM '16729473fcfc98cb04a04d2489cfa6338cb59f1c1cace12ce9443a4c24bee061'
  THEN RAISE EXCEPTION 'PR_J3B_STEP70_TRAIN_EVIDENCE_NOT_VERIFIED:%',auto_result->>'blocking_code'; END IF;
  written:=public.lf_record_profile_execution_step_v1(
    parent_run,'semantic_judge',
    'supabase://public.lf_ig_functional_train_evidence_v1/B2B-RULE-AUTH-020',
    jsonb_build_object(
       'semantic_judge_result',auto_result,'unsupported_claims','[]'::jsonb,
       'semantic_review_receipt_ref','supabase://public.lf_ig_functional_train_evidence_v1/B2B-RULE-AUTH-020',
       'independent_semantic_receipt_ref',null,
       'judge_independence_status','NOT_ASSERTED',
       'evaluator','TRAIN_EVIDENCE_AUTOMATICO',
       'content_findings',jsonb_build_array(
          jsonb_build_object('finding_code','SEMANTIC_JUDGE_NOT_PERFORMED',
                             'evaluator','TRAIN_EVIDENCE_AUTOMATICO'))
    ),parent_run);
  IF coalesce(written->>'status',written->>'step_status') IS DISTINCT FROM 'STEP_PASS_WITH_EVIDENCE'
  THEN RAISE EXCEPTION 'PR_J3B_STEP70_CANONICAL_RECORDER_REJECTED:%',written; END IF;
 END IF;
END $j3b_record$;
COMMIT;

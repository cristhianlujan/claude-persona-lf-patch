-- PE10_C4: two individually reviewed historical statuses, DIFFERENT dispositions.
-- A: V0.4 source PR #995 closed, explicitly [SUPERSEDED], source SHA bound => SUPERSEDED.
-- B: baseline experiment six BLOCKED steps (incl github_write), never governed PASS => CANCELLED.
-- Source commit of B is preserved, NOT treated as published or deleted.
-- TRAIN ONLY, test-first rollback and fail-closed, no profile/registry mutation.
BEGIN;
DO $pe10_c4$
DECLARE
 v_actor constant text := 'EXEC-PE10-C4-EXACT-DISPOSITIONS-20261015-007';
 v_a constant text := 'EXEC-ACTUALIZACION-PERFIL-LF-OIDC-fbe01d5e-953e-4eeb-a0fa-90b929a9d837';
 v_a_sha constant text := '6413d2830fb6f05344e71152f84e629fc0834ff2';
 v_b constant text := 'EXEC-ACTUALIZACION-PERFIL-SRCR-BASELINE-20260921-013';
 v_b_sha constant text := '8f5aee75eb2c4fa666438e33b331f18e1dad13be';
 v_prefix constant text := 'PE10_C4.EXACT_DISPOSITION_007.';
 v_asset_before jsonb;
 v_r record;
 v_old_manifest jsonb;
 v_event_payload jsonb;
 v_event_id bigint;
 v_code text;
 v_sha text;
 v_newstate text;
BEGIN
 IF (SELECT count(*) FROM public.lf_operation_execution WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND status='IN_PROGRESS')<>9
   OR (SELECT c.status FROM programacion.engineering_work_checkpoints c JOIN programacion.engineering_plan_units u USING(work_item_id)
        WHERE u.plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1' AND u.unit_code='PE10' AND c.checkpoint_code='PE10_C4')<>'PENDING'
   OR (SELECT count(*) FROM public.lf_operation_registry WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND version='v0.1' AND status='PRODUCCION_CONTROLADA')<>1
 THEN RAISE EXCEPTION 'PE10_C4_007_CURRENT_STATE_CHANGED'; END IF;
 SELECT to_jsonb(a) INTO v_asset_before FROM public.lf_activos a WHERE a.tipo_activo='PERFIL'
   AND a.codigo_activo='PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF' AND a.archived_at IS NULL;
 IF v_asset_before IS NULL THEN RAISE EXCEPTION 'PE10_C4_007_TARGET_PROFILE_MISSING'; END IF;
 IF (SELECT count(*) FROM private.lf_event_type_contracts_v2
   WHERE event_type='ARTIFACT_RECONCILED' AND active AND contract_mode='OPERATIONAL'
     AND 'operational-event/v2'=ANY(allowed_evidence_schemas))<>1
 THEN RAISE EXCEPTION 'PE10_C4_007_EVENT_CONTRACT_MISSING'; END IF;

 FOR v_r IN SELECT * FROM (VALUES
    (v_a,v_a_sha,'SUPERSEDED',10,0),
    (v_b,v_b_sha,'CANCELLED',6,6)
  ) AS x(old_id,source_sha,final_state,pass_steps,blocked_steps)
 LOOP
   v_code:=v_prefix||v_r.old_id;
   SELECT e.manifest INTO v_old_manifest FROM public.lf_operation_execution e
     WHERE e.execution_id=v_r.old_id AND e.operation_code='ACTUALIZACION_PERFIL_LF'
       AND e.status='IN_PROGRESS' AND e.completed_at IS NULL
       AND e.target_type='PERFIL' AND e.target_code='PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF'
       AND e.target_repo='cristhianlujan/claude-persona-lf-patch'
       AND e.lease_owner IS NULL AND e.updated_at<clock_timestamp()-interval '14 days'
   FOR UPDATE;
   IF v_old_manifest IS NULL THEN RAISE EXCEPTION 'PE10_C4_007_NOT_STALE:%',v_r.old_id; END IF;
   IF (SELECT count(*) FROM public.lf_operation_execution_steps s WHERE s.execution_id=v_r.old_id
       AND s.status='STEP_PASS_WITH_EVIDENCE')<>v_r.pass_steps
     OR (SELECT count(*) FROM public.lf_operation_execution_steps s WHERE s.execution_id=v_r.old_id
       AND s.status='BLOCKED_STEP_NOT_CLEAN')<>v_r.blocked_steps
     OR (SELECT count(*) FROM public.lf_operation_execution_steps s WHERE s.execution_id=v_r.old_id
       AND s.step_id='github_write' AND s.evidence_payload->>'commit_sha'=v_r.source_sha)<>1
     OR (SELECT count(*) FROM public.lf_operation_execution_steps s WHERE s.execution_id=v_r.old_id
       AND s.step_id IN ('post_merge_reconcile','close','report_output'))<>0
     OR EXISTS (SELECT 1 FROM public.lf_eventos ev WHERE ev.evento_tipo='ARTIFACT_RECONCILED'
       AND ev.entidad_codigo=v_code)
   THEN RAISE EXCEPTION 'PE10_C4_007_EXACT_STEPS_OR_COMMIT_MISMATCH:%',v_r.old_id; END IF;
   IF v_r.old_id=v_a AND
       ((SELECT count(*) FROM public.lf_operation_execution_steps s WHERE s.execution_id=v_a
          AND s.step_id='github_write' AND s.status='STEP_PASS_WITH_EVIDENCE'
            AND s.evidence_payload->>'commit_sha'=v_a_sha)<>1
        OR (SELECT count(*) FROM public.lf_operation_execution_steps s WHERE s.execution_id=v_a
          AND s.step_id='github_readback' AND s.status='STEP_PASS_WITH_EVIDENCE'
            AND s.evidence_payload->>'exact_head'=v_a_sha)<>1
        OR v_old_manifest->>'production_authorized' IS DISTINCT FROM 'false')
   THEN RAISE EXCEPTION 'PE10_C4_007_A_CANDIDATE_GIT_RECEIPT_NOT_EXACT'; END IF;
   IF v_r.old_id=v_b AND
        ((SELECT count(*) FROM public.lf_operation_execution_steps s WHERE s.execution_id=v_b
           AND s.step_id='github_write' AND s.status='BLOCKED_STEP_NOT_CLEAN')<>1
         OR (SELECT count(*) FROM public.lf_operation_execution_steps s WHERE s.execution_id=v_b
           AND s.step_id='github_readback' AND s.status='BLOCKED_STEP_NOT_CLEAN')<>1
         OR EXISTS (SELECT 1 FROM public.lf_operation_execution_steps s WHERE s.execution_id=v_b
           AND s.step_id IN ('github_write','github_readback') AND s.status='STEP_PASS_WITH_EVIDENCE'))
   THEN RAISE EXCEPTION 'PE10_C4_007_B_FALSE_WRITE_SUCCESS'; END IF;
 END LOOP;

 -- Per-case payload same for rehearsal and durable.
 FOR v_r IN SELECT * FROM (VALUES
    (v_a,v_a_sha,'SUPERSEDED',10,0,995,'SUPERSEDED_PR_CLOSED_UNMERGED'),
    (v_b,v_b_sha,'CANCELLED',6,6,null::int,'BLOCKED_GOVERNED_GITHUB_WRITE_NO_PASS')
  ) AS x(old_id,source_sha,final_state,pass_steps,blocked_steps,related_pr,basis)
 LOOP
   v_code:=v_prefix||v_r.old_id;
   v_event_payload:=jsonb_build_object(
     'evidence_schema_version','operational-event/v2',
     'execution_id',v_actor,'producer','PE10_C4_INDIVIDUAL_TERMINAL_DISPOSITION_V1',
     'purpose','Archive exact stale historical profile update without erasing branch or asserting a deploy',
     'acceptance_declared',false,'occurred_at',clock_timestamp(),
     'historical_execution_id',v_r.old_id,'candidate_commit_sha',v_r.source_sha,
     'historical_pass_steps',v_r.pass_steps,'historical_blocked_steps',v_r.blocked_steps,
     'related_github_pr',v_r.related_pr,
     'disposition_basis',v_r.basis,'disposition',v_r.final_state,
     'original_branch_preserved',true,'git_commit_preserved',true,
     'pr_was_merged',false,'deployment_claimed',false,'work_delivered_claimed',false,
     'updater_cutover_allowed',false
   );
   IF private.fn_lf_event_acceptance_signal_v2('ARTIFACT_RECONCILED',v_code,
     'Historic profile update disposed without cutover approval',v_event_payload) IS NOT NULL
   THEN RAISE EXCEPTION 'PE10_C4_007_FALSE_ACCEPTANCE_SIGNAL:%',v_r.old_id; END IF;
 END LOOP;

 -- TEST FIRST: rollback each distinct status and its evidence event atomically.
 BEGIN
   FOR v_r IN SELECT * FROM (VALUES
      (v_a,v_a_sha,'SUPERSEDED',10,0,995,'SUPERSEDED_PR_CLOSED_UNMERGED'),
      (v_b,v_b_sha,'CANCELLED',6,6,null::int,'BLOCKED_GOVERNED_GITHUB_WRITE_NO_PASS')
    ) AS x(old_id,source_sha,final_state,pass_steps,blocked_steps,related_pr,basis)
   LOOP
     v_code:=v_prefix||v_r.old_id;
     v_event_payload:=jsonb_build_object(
       'evidence_schema_version','operational-event/v2','execution_id',v_actor,
       'producer','PE10_C4_INDIVIDUAL_TERMINAL_DISPOSITION_V1',
       'purpose','Archive exact stale historical profile update without erasing branch or asserting a deploy',
       'acceptance_declared',false,'occurred_at',clock_timestamp(),
       'historical_execution_id',v_r.old_id,'candidate_commit_sha',v_r.source_sha,
       'historical_pass_steps',v_r.pass_steps,'historical_blocked_steps',v_r.blocked_steps,
       'related_github_pr',v_r.related_pr,'disposition_basis',v_r.basis,
       'disposition',v_r.final_state,'original_branch_preserved',true,
       'git_commit_preserved',true,'pr_was_merged',false,'deployment_claimed',false,
       'work_delivered_claimed',false,'updater_cutover_allowed',false
     );
     INSERT INTO public.lf_eventos(
       evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,origen,
       created_by_execution_id,payload)
     VALUES('ARTIFACT_RECONCILED','EXECUTION',v_code,
       'Historic profile update disposed without cutover approval',
       'INFO','DERIVE_FROM_EXECUTION_ID',v_actor,v_event_payload)
     RETURNING id INTO v_event_id;
     UPDATE public.lf_operation_execution SET status=v_r.final_state,
       completed_at=clock_timestamp(),updated_by_execution_id=v_actor
       WHERE execution_id=v_r.old_id AND status='IN_PROGRESS';
     IF NOT FOUND THEN RAISE EXCEPTION 'PE10_C4_007_DRY_CAS_FAILED:%',v_r.old_id; END IF;
   END LOOP;
   IF (SELECT count(*) FROM public.lf_operation_execution WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND status='IN_PROGRESS')<>7
     OR (SELECT count(*) FROM public.lf_eventos WHERE evento_tipo='ARTIFACT_RECONCILED'
        AND entidad_codigo LIKE v_prefix||'%')<>2
   THEN RAISE EXCEPTION 'PE10_C4_007_DRY_READBACK_FAILED'; END IF;
   RAISE EXCEPTION 'PE10_C4_007_MANDATORY_ROLLBACK_SENTINEL';
 EXCEPTION WHEN SQLSTATE 'P0001' THEN
   IF SQLERRM<>'PE10_C4_007_MANDATORY_ROLLBACK_SENTINEL' THEN RAISE; END IF;
 END;
 IF (SELECT count(*) FROM public.lf_operation_execution
     WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND status='IN_PROGRESS')<>9
   OR EXISTS(SELECT 1 FROM public.lf_eventos WHERE evento_tipo='ARTIFACT_RECONCILED'
     AND entidad_codigo LIKE v_prefix||'%')
 THEN RAISE EXCEPTION 'PE10_C4_007_ROLLBACK_TEST_NOT_CLEAN'; END IF;

 -- Durable replay with idempotent case-specific provenance.
 FOR v_r IN SELECT * FROM (VALUES
    (v_a,v_a_sha,'SUPERSEDED',10,0,995,'SUPERSEDED_PR_CLOSED_UNMERGED'),
    (v_b,v_b_sha,'CANCELLED',6,6,null::int,'BLOCKED_GOVERNED_GITHUB_WRITE_NO_PASS')
  ) AS x(old_id,source_sha,final_state,pass_steps,blocked_steps,related_pr,basis)
 LOOP
   v_code:=v_prefix||v_r.old_id;
   v_event_payload:=jsonb_build_object(
     'evidence_schema_version','operational-event/v2','execution_id',v_actor,
     'producer','PE10_C4_INDIVIDUAL_TERMINAL_DISPOSITION_V1',
     'purpose','Archive exact stale historical profile update without erasing branch or asserting a deploy',
     'acceptance_declared',false,'occurred_at',clock_timestamp(),
     'historical_execution_id',v_r.old_id,'candidate_commit_sha',v_r.source_sha,
     'historical_pass_steps',v_r.pass_steps,'historical_blocked_steps',v_r.blocked_steps,
     'related_github_pr',v_r.related_pr,'disposition_basis',v_r.basis,
     'disposition',v_r.final_state,'original_branch_preserved',true,
     'git_commit_preserved',true,'pr_was_merged',false,'deployment_claimed',false,
     'work_delivered_claimed',false,'updater_cutover_allowed',false
   );
   INSERT INTO public.lf_eventos(
     evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,origen,
     created_by_execution_id,payload)
   VALUES('ARTIFACT_RECONCILED','EXECUTION',v_code,
     'Historic profile update disposed without cutover approval',
     'INFO','DERIVE_FROM_EXECUTION_ID',v_actor,v_event_payload)
   RETURNING id INTO v_event_id;
   UPDATE public.lf_operation_execution SET status=v_r.final_state,
     completed_at=clock_timestamp(),updated_by_execution_id=v_actor
     WHERE execution_id=v_r.old_id AND status='IN_PROGRESS';
   IF NOT FOUND THEN RAISE EXCEPTION 'PE10_C4_007_FINAL_CAS_FAILED:%',v_r.old_id; END IF;
   IF (SELECT count(*) FROM public.lf_operation_execution
       WHERE execution_id=v_r.old_id AND status=v_r.final_state
         AND updated_by_execution_id=v_actor AND completed_at IS NOT NULL)<>1
      OR (SELECT count(*) FROM public.lf_eventos
       WHERE id=v_event_id AND entidad_codigo=v_code
         AND payload->>'candidate_commit_sha'=v_r.source_sha
         AND payload->>'disposition'=v_r.final_state
         AND payload->>'updater_cutover_allowed'='false')<>1
   THEN RAISE EXCEPTION 'PE10_C4_007_DURABLE_CASE_READBACK_FAILED:%',v_r.old_id; END IF;
 END LOOP;
 IF (SELECT count(*) FROM public.lf_operation_execution
     WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND status='IN_PROGRESS')<>7
   OR (SELECT to_jsonb(a) FROM public.lf_activos a WHERE a.tipo_activo='PERFIL'
       AND a.codigo_activo='PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF'
       AND a.archived_at IS NULL) IS DISTINCT FROM v_asset_before
   OR (SELECT count(*) FROM public.lf_operation_registry
       WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND version='v0.1')<>1
   OR (SELECT c.status FROM programacion.engineering_work_checkpoints c JOIN programacion.engineering_plan_units u USING(work_item_id)
       WHERE u.plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1'
         AND u.unit_code='PE10' AND c.checkpoint_code='PE10_C4')<>'PENDING'
 THEN RAISE EXCEPTION 'PE10_C4_007_FINAL_GLOBAL_INVARIANT_FAILED'; END IF;
END $pe10_c4$;
COMMIT;
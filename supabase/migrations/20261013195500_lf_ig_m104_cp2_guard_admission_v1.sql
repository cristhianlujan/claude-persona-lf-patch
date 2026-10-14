-- IG_CURATOR_VALIDATOR_REFACTOR_V2 / M10.4 / CP2 FREEZE_RULE.
-- Trusted-base CI guard installed by merged PR #2460, not a new authority engine.
-- CP2 only: contract+governance+source_pack aligned and genuine material assertion.
-- Edge ACTIVE_VNEXT and runtime/prod are untouched. CP3/CP4 remain pending.
BEGIN;
DO $m104_cp2$
DECLARE
 v_plan constant text := 'IG_CURATOR_VALIDATOR_REFACTOR_V2';
 v_unit constant text := 'M10.4';
 v_cp constant text := 'FREEZE_RULE';
 v_src_merge constant text := 'e8457319098886b5c541a695b77752f4051932c6';
 v_manifest_blob constant text := '8b348abaadb46b0fa4df8e936783c132a0f82456';
 v_guard_blob constant text := 'f11785f3597977a67f48463999ade6c6e9e2e796';
 v_admission_blob constant text := '8be0317816139d954f5b4784ed4704086c9e2977';
 v_baseline jsonb;
 v_metadata jsonb;
 v_spec jsonb;
 v_pack jsonb;
 v_artifacts jsonb;
 v_manifest_count integer;
 v_found_count integer;
 v_drift_count integer;
 v_current_digest text;
 v_ready jsonb;
 v_state jsonb;
 v_out jsonb;
 v_receipt jsonb;
 v_evidence text;
BEGIN
 v_state:=programacion.fn_engineering_unit_bootstrap_v3(v_plan,v_unit);
 IF v_state->>'terminal_action'<>'CONTINUE_CURRENT_CHECKPOINT'
    OR v_state#>>'{current_checkpoint,checkpoint_code}'<>v_cp
 THEN RAISE EXCEPTION 'M104_CP2_NOT_CURRENT'; END IF;
 IF (SELECT status FROM programacion.engineering_work_checkpoints
     WHERE work_item_id=476 AND checkpoint_code='FROZEN_SET_ASIS')<>'DONE'
 THEN RAISE EXCEPTION 'M104_CP2_CP1_NOT_DONE'; END IF;

 SELECT unit_metadata INTO v_metadata
 FROM programacion.engineering_plan_units
 WHERE plan_code=v_plan AND unit_code=v_unit AND work_item_id=476 FOR UPDATE;
 v_baseline:=v_metadata->'m104_freeze_baseline_v1';
 IF jsonb_typeof(v_baseline->'legacy_functions')<>'array'
    OR coalesce(v_baseline->>'freeze_ci_guard','')<>'PENDING_FREEZE_RULE_CP2'
    OR coalesce((v_baseline->>'freeze_admitted')::boolean,true)
 THEN RAISE EXCEPTION 'M104_CP2_BASELINE_NOT_FROZEN_CP1'; END IF;

 v_manifest_count:=jsonb_array_length(v_baseline->'legacy_functions');
 WITH items AS (
    SELECT m->>'identity' sig,m->>'prosrc_md5' fingerprint
    FROM jsonb_array_elements(v_baseline->'legacy_functions') m
 ), live AS (
    SELECT items.*,p.oid,p.prosrc
    FROM items
    LEFT JOIN LATERAL (
      SELECT p.oid,p.prosrc
      FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname=split_part(split_part(items.sig,'(',1),'.',1)
        AND p.proname=split_part(split_part(items.sig,'(',1),'.',2)
        AND n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')'=items.sig
    ) p ON true
 )
 SELECT count(*) FILTER (WHERE oid IS NOT NULL),
        count(*) FILTER (WHERE oid IS NULL OR md5(prosrc) IS DISTINCT FROM fingerprint),
        md5(string_agg(sig||':'||coalesce(md5(prosrc),'MISSING'),'|' ORDER BY sig))
 INTO v_found_count,v_drift_count,v_current_digest
 FROM live;

 IF v_manifest_count<1 OR v_found_count<>v_manifest_count OR v_drift_count<>0
    OR v_current_digest IS DISTINCT FROM v_baseline->>'sql_aggregate_md5'
    OR jsonb_array_length(coalesce(v_baseline->'excluded_active_vnext_edge','[]'::jsonb))<>3
    OR coalesce((v_baseline->>'legacy_edge_count')::integer,1)<>0
 THEN RAISE EXCEPTION 'M104_CP2_FROZEN_SCOPE_OR_SOURCE_DRIFT total=% found=% drift=% digest=%',
        v_manifest_count,v_found_count,v_drift_count,v_current_digest;
 END IF;
 -- A non-legacy Edge target or a stale SQL fingerprint must never admit the rule.
 IF v_baseline->'legacy_functions' @> '[{"historical_class":"ACTIVE_VNEXT"}]'::jsonb
 THEN RAISE EXCEPTION 'M104_CP2_NEGATIVE_ACTIVE_VNEXT_INCLUDED'; END IF;

 v_artifacts:=jsonb_build_array(
   jsonb_build_object(
     'path','cristhianlujan/claude-persona-lf-patch:sandbox/lf_contract_gate_test/engineering_checkpoints/m10_4/legacy_freeze_manifest_v1.json',
     'role','EVIDENCE_ARTIFACT','target_kind','EXACT_MERGED_FILE','git_blob_sha',v_manifest_blob),
   jsonb_build_object(
     'path','cristhianlujan/claude-persona-lf-patch:sandbox/lf_contract_gate_test/engineering_checkpoints/m10_4/legacy_freeze_guard.py',
     'role','MUTATION_TARGET','target_kind','EXACT_MERGED_FILE','git_blob_sha',v_guard_blob),
   jsonb_build_object(
     'path','cristhianlujan/claude-persona-lf-patch:.github/workflows/lf-independent-change-admission.yml',
     'role','MUTATION_TARGET','target_kind','EXACT_MERGED_FILE','git_blob_sha',v_admission_blob),
   jsonb_build_object(
     'path','cristhianlujan/claude-persona-lf-patch:supabase/migrations/',
     'role','MUTATION_TARGET','target_kind','ALLOWED_OUTPUT_ROOT',
     'naming_contract','<timestamp>_lf_ig_m104_cp2_guard_admission_v1.sql')
 );
 v_spec:=v_metadata#>'{action_specs_v1,FREEZE_RULE}';
 IF coalesce(v_spec->>'action_kind','')<>'MATERIALIZE_DECLARED_DELIVERABLE'
 THEN RAISE EXCEPTION 'M104_CP2_INCOMPATIBLE_ACTION_SPEC'; END IF;
 v_spec:=jsonb_set(v_spec,'{target,declared_artifacts}',v_artifacts,true);
 v_spec:=jsonb_set(v_spec,'{target,mutation_artifacts}',
   (SELECT jsonb_agg(a.value) FROM jsonb_array_elements(v_artifacts) a WHERE a.value->>'role'='MUTATION_TARGET'),true);
 v_spec:=jsonb_set(v_spec,'{target,declared_objects}',
   '["programacion.engineering_plan_units","public.lf_error_knowledge"]'::jsonb,true);
 v_spec:=jsonb_set(v_spec,'{authoring_contract,db_targets_exact}',
   '["programacion.engineering_plan_units","public.lf_error_knowledge"]'::jsonb,true);
 v_spec:=jsonb_set(v_spec,'{verification_queries}',to_jsonb(array[
    'select unit_metadata->''m104_freeze_rule_v1'' from programacion.engineering_plan_units where plan_code=''IG_CURATOR_VALIDATOR_REFACTOR_V2'' and unit_code=''M10.4''',
    'select checkpoint_code,status,evidence_ref,assertion_receipt_sha256 from programacion.engineering_work_checkpoints where work_item_id=476 order by sequence_no'
 ]),true);
 v_metadata:=jsonb_set(v_metadata,'{action_specs_v1,FREEZE_RULE}',v_spec,true);

 -- Executable source pack must point at the installed source, not only EKB.
 v_pack:=v_metadata#>'{source_pack_v1,checkpoint_inputs,FREEZE_RULE,inputs}';
 v_pack:=jsonb_set(v_pack,'{artifacts}',jsonb_build_array(
   jsonb_build_object('path','cristhianlujan/claude-persona-lf-patch/sandbox/lf_contract_gate_test/engineering_checkpoints/m10_4/legacy_freeze_manifest_v1.json','verified',true),
   jsonb_build_object('path','cristhianlujan/claude-persona-lf-patch/sandbox/lf_contract_gate_test/engineering_checkpoints/m10_4/legacy_freeze_guard.py','verified',true),
   jsonb_build_object('path','cristhianlujan/claude-persona-lf-patch/.github/workflows/lf-independent-change-admission.yml','verified',true)
 ),true);
 v_pack:=jsonb_set(v_pack,'{db_objects}',
    '["programacion.engineering_plan_units","public.lf_error_knowledge"]'::jsonb,true);
 v_pack:=jsonb_set(v_pack,'{queries}',v_spec->'verification_queries',true);
 v_metadata:=jsonb_set(v_metadata,
    '{source_pack_v1,checkpoint_inputs,FREEZE_RULE,inputs}',v_pack,true);

 v_metadata:=jsonb_set(v_metadata,'{m104_freeze_rule_v1}',
   jsonb_build_object(
     'status','INSTALLED_ENGINEERING_CI',
     'source_merge_commit',v_src_merge,
     'source_pr',2460,
     'manifest_blob',v_manifest_blob,
     'guard_blob',v_guard_blob,
     'independent_admission_workflow_blob',v_admission_blob,
     'enforcement','TRUSTED_MAIN_SOURCE_IN_LF_INDEPENDENT_CHANGE_ADMISSION',
     'merge_train_dependency','lf-independent-change-admission',
     'manifest_source_digest',v_baseline->>'sql_aggregate_md5',
     'frozen_sql_count',v_manifest_count,
     'frozen_edge_count',0,
     'adversarial_live_pr_test','PENDING_CP3_NEG_NEW_MIGRATION',
     'runtime_activation',false,
     'production_activation',false,
     'retirement_authorized',false,
     'scope','M104_CP2_ONLY'
   ),true);
 UPDATE programacion.engineering_plan_units
 SET unit_metadata=v_metadata
 WHERE plan_code=v_plan AND unit_code=v_unit AND work_item_id=476;

 v_ready:=programacion.fn_engineering_checkpoint_execution_readiness_v1(v_plan,v_unit,v_cp);
 IF v_ready->>'status'<>'READY' OR v_ready->>'execution_ready'<>'true'
 THEN RAISE EXCEPTION 'M104_CP2_READINESS_FAILED:%',v_ready; END IF;

 v_evidence:='github://cristhianlujan/claude-persona-lf-patch/pull/2460'
   ||';github://cristhianlujan/claude-persona-lf-patch/commit/'||v_src_merge
   ||';github://cristhianlujan/claude-persona-lf-patch/blob/main/sandbox/lf_contract_gate_test/engineering_checkpoints/m10_4/legacy_freeze_guard.py'
   ||';supabase://programacion.engineering_plan_units/M10.4#m104_freeze_rule_v1';
 v_out:=programacion.fn_engineering_heartbeat_normalize_v1(
    v_plan,v_unit,v_cp,'ACTION_STARTED',NULL,'{}'::jsonb,
    v_evidence,'IG_M104_CP2_TRAIN',true);
 IF v_out->>'status'<>'REPAIRED' THEN RAISE EXCEPTION 'M104_CP2_START_FAILED:%',v_out; END IF;
 v_receipt:=programacion.fn_engineering_checkpoint_assertion_record_v1(
    v_plan,v_unit,v_cp,
    jsonb_build_object(
      'status','PASS',
      'evidence_ref',v_evidence,
      'observed',jsonb_build_object(
         'git_merged',true,
         'readback_passed',true,
         'implementation_written',true
      )
    ),
    'IG_M104_CP2_TRAIN'
 );
 IF v_receipt->>'passed'<>'true' OR nullif(v_receipt->>'assertion_receipt_sha256','') IS NULL
 THEN RAISE EXCEPTION 'M104_CP2_MATERIAL_ASSERTION_MISSING'; END IF;
 v_out:=programacion.fn_engineering_heartbeat_normalize_v1(
    v_plan,v_unit,v_cp,'ACTION_DONE',NULL,'{}'::jsonb,
    v_evidence,'IG_M104_CP2_TRAIN',true);
 IF v_out->>'status'<>'REPAIRED' THEN RAISE EXCEPTION 'M104_CP2_END_FAILED:%',v_out; END IF;
 v_out:=programacion.fn_engineering_checkpoint_transition_v1(
    v_plan,v_unit,v_cp,'DONE',v_evidence,'IG_M104_CP2_TRAIN',
    'CP2 trusted-main guard installed PR2460; exact Git blobs pinned; live adversarial probe explicitly pending CP3');
 IF v_out#>>'{transition,status}'<>'APPLIED'
 THEN RAISE EXCEPTION 'M104_CP2_TRANSITION_FAILED:%',v_out; END IF;
 IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
     WHERE work_item_id=476 AND status='DONE')<>2
 THEN RAISE EXCEPTION 'M104_CP2_POSTSTATE_FAILED'; END IF;

 INSERT INTO public.lf_error_knowledge
 (codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
  severidad,estado,lote_origen,source_ref,evidencia)
 SELECT
 'IG-M104-FREEZE-RULE-CI-ENFORCEMENT-MISSING-001','INPUT_GOVERNANCE',
 'M10.4 FREEZE_RULE con regla EKB no bloqueaba cambios en PR',
 'Contrato CP2 inicial solo declaraba public.lf_error_knowledge como target: registrar una regla textual no garantiza CI anti-mutacion legacy.',
 'Desalineacion naturaleza IMPLEMENTATION CI-GUARD vs action_spec/source_pack EKB-only.',
 'RULE_RECORDED_BUT_NO_ENFORCEMENT',
 'Vincular un guard de manifest exacto a flujo trusted-base ya requerido por LF Migration Merge Train; comprobar positivo/negativo, source/ledger/readback y no confundir CP2 instalado con CP3 prueba adversarial.',
 'PR2460 merged commit '||v_src_merge||'; guard python 8/8, 26 firmas SQL, 0 Edge congelados, normal independent admission. CP3 prueba live negativa separada.',
 'HIGH','ACTIVO',v_plan||'/'||v_unit,
 'programacion.engineering_plan_units/M10.4',
 v_evidence
 WHERE NOT EXISTS (
    SELECT 1 FROM public.lf_error_knowledge
    WHERE codigo='IG-M104-FREEZE-RULE-CI-ENFORCEMENT-MISSING-001'
 );
END $m104_cp2$;
COMMIT;

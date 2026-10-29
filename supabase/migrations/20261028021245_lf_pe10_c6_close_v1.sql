-- PE10_C6: cierre gobernado del checkpoint "dry-run transaccional del candidato con controles positivo y negativo".
--
-- Cierra SOLO PE10_C6. No activa Profile Updater v0.2, no cambia registro, politicas ni contratos activos.
--
-- Candidato probado: la insercion del contrato v0.2 en estado CANDIDATO_READ_ONLY (el mismo SQL exacto que aplicara PE10_C7;
-- su sha256 queda en el recibo y PE10_C7 lo exige antes de aplicar).
-- Prueba dentro de esta transaccion, en un subbloque que se revierte (ROLLBACK):
--   positivo: tras insertar el candidato, (a) hay exactamente 1 contrato ACTIVE_ENFORCEMENT (predicado de lf_profile_update_begin_v1),
--             (b) 1 contrato visible para router/revision, (c) lf_operation_revision_sha256_v1 NO cambia, (d) el registro sigue en v0.1.
--   negativo: un segundo contrato ACTIVE_ENFORCEMENT hace que (a) deje de cumplirse (el gate lo rechazaria).
--   rollback: despues del subbloque el candidato no existe y las huellas de registro/contratos/politicas/ejecuciones/eventos son iguales.
-- Fuente: test declarado de C6 pe10_c6_transactional_dry_run_v1.py (57 casos de codigo + captura nativa del chat sobre el perfil vigente).
-- Las 57 pruebas de codigo las corrio el autor localmente antes del merge; el CI del PR no las ejecuta (no hay workflow que las dispare).
DO $mig$
DECLARE
 c_plan constant text := 'PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1';
 c_unit constant text := 'PE10';
 c_cp   constant text := 'PE10_C6';
 c_actor constant text := 'EXEC-PE10-C6-CLOSE-20261028-V1';
 c_commit constant text := '6d4b267b45ea98eb82623954e24badbcbd26262b';
 c_test_sha constant text := '58b2f0f64e9b84886179dec72f3d5e30667070f72ae4c157b8e8167f2e189fbc';
 c_capture_file_sha constant text := 'f137e43c4caf6b7b4952dcb2ece7d7539cb05ba767bc6c7e8b990ef80de47003';
 c_capture_sha constant text := 'e3c62bdc2abc6b34809c48e6c38cbe6d38941ce4b1d5a004a958ecf7a5e76ebe';
 c_handoff_sha constant text := 'b516557a80ee6528df2c63316ca90ddf283f57905963782565e771bb2cda0551';
 c_receipt_sha constant text := 'f2eb14b9e6f54de79c494c6dcfd4920bb16ec324e9725e8260230254042c679f';
 c_candidate_sql constant text := $sql$INSERT INTO public.lf_operation_contracts
 (operation_code,contract_code,contract_path,contract_sha,required_before_write,allowed,blocked,required_after_write,status,created_by_execution_id)
 SELECT c.operation_code,'CONTRACT-ACTUALIZACION-PERFIL-LF-v0.2',
        'public.lf_operation_contracts/ACTUALIZACION_PERFIL_LF/CONTRACT-ACTUALIZACION-PERFIL-LF-v0.2',NULL,
        c.required_before_write, c.allowed || '{"v02_candidate":true,"activation_authorized":false}'::jsonb, c.blocked, c.required_after_write,
        'CANDIDATO_READ_ONLY','EXEC-PE10-C7-CANDIDATE-CONTRACT-20261028-V1'
 FROM public.lf_operation_contracts c
 WHERE c.operation_code='ACTUALIZACION_PERFIL_LF' AND c.contract_code='CONTRACT-ACTUALIZACION-PERFIL-LF-v0.1' AND c.status='ACTIVE_ENFORCEMENT'$sql$;
 c_op constant text := 'ACTUALIZACION_PERFIL_LF';
 v_exec text; v_wid bigint; v_status text; v_spec jsonb; v_contract jsonb;
 v_fp_before text; v_fp_after text; v_cp_before text; v_cp_after text;
 v_rev_before text; v_rev_in text; v_n_ins int;
 v_a int; v_b int; v_ver text; v_cand int; v_pos boolean := false;
 v_neg_active int; v_neg boolean := false;
 v_after_cand int; v_rolled boolean := false;
 v_evidence text; v_observed jsonb; v_rec jsonb; v_tr jsonb; v_open_before text; v_open_after text;
BEGIN
 SELECT execution_id INTO v_exec FROM public.lf_operation_execution
 WHERE operation_code='ACTUALIZACION_DB_LF' AND target_type='MIGRATION'
  AND target_code LIKE '%lf_pe10_c6_close_v1' AND status='IN_PROGRESS' ORDER BY created_at DESC LIMIT 1;
 IF v_exec IS NULL THEN RAISE EXCEPTION 'PE10_C6_CLOSE_TRAIN_TRANSPORT_REQUIRED'; END IF;

 SELECT u.work_item_id INTO v_wid FROM programacion.engineering_plan_units u WHERE u.plan_code=c_plan AND u.unit_code=c_unit FOR UPDATE;
 IF v_wid IS NULL THEN RAISE EXCEPTION 'PE10_C6_CLOSE_UNIT_MISSING'; END IF;
 SELECT c.status INTO v_status FROM programacion.engineering_work_checkpoints c WHERE c.work_item_id=v_wid AND c.checkpoint_code=c_cp;
 IF v_status IS DISTINCT FROM 'PENDING' THEN RAISE EXCEPTION 'PE10_C6_CLOSE_NOT_PENDING:%',coalesce(v_status,'<none>'); END IF;
 IF (SELECT count(*) FROM programacion.engineering_work_checkpoints c WHERE c.work_item_id=v_wid AND c.checkpoint_code IN ('PE10_C3','PE10_C4','PE10_C5') AND c.status='DONE')<>3
    OR (SELECT status FROM programacion.engineering_work_checkpoints c WHERE c.work_item_id=v_wid AND c.checkpoint_code='PE10_C7') IS DISTINCT FROM 'PENDING'
 THEN RAISE EXCEPTION 'PE10_C6_CLOSE_GATES_STATE_INVALID'; END IF;

 v_spec := programacion.fn_engineering_checkpoint_action_spec_v3(c_plan,c_unit,c_cp);
 v_contract := programacion.fn_engineering_action_spec_assertion_contract_v1(c_plan,c_unit,c_cp,v_spec);
 IF v_contract->>'status' IS DISTINCT FROM 'READY' OR jsonb_typeof(v_contract->'pass_when') IS DISTINCT FROM 'object'
 THEN RAISE EXCEPTION 'PE10_C6_CLOSE_CONTRACT_NOT_READY:%',v_contract; END IF;

 -- estado previo exigido: v0.1 en el registro, 1 contrato activo, sin candidato v0.2.
 -- Ejecuciones abiertas heredadas de la operacion: se toleran y NO se tocan (el plan prohibe AUTO_CLOSE_LEGACY_EXECUTIONS);
 -- el candidato es invisible para ellas (la revision de la operacion no cambia) y se registran sus ids antes/despues.
 IF (SELECT count(*) FROM public.lf_operation_registry WHERE operation_code=c_op AND version='v0.1')<>1
    OR (SELECT count(*) FROM public.lf_operation_contracts WHERE operation_code=c_op AND status='ACTIVE_ENFORCEMENT')<>1
    OR (SELECT count(*) FROM public.lf_operation_contracts WHERE operation_code=c_op AND contract_code='CONTRACT-ACTUALIZACION-PERFIL-LF-v0.2')<>0
 THEN RAISE EXCEPTION 'PE10_C6_CLOSE_PRESTATE_INVALID'; END IF;

 SELECT md5(coalesce((SELECT string_agg(to_jsonb(r)::text,'|' ORDER BY r.operation_code) FROM public.lf_operation_registry r),'')||'#'||
            coalesce((SELECT string_agg(to_jsonb(k)::text,'|' ORDER BY k.operation_code,k.contract_code) FROM public.lf_operation_contracts k),'')||'#'||
            coalesce((SELECT string_agg(to_jsonb(p)::text,'|' ORDER BY p.policy_code,p.policy_version) FROM public.lf_policy_versions p),'')||'#'||
            (SELECT count(*) FROM public.lf_operation_execution)::text||'#'||(SELECT count(*) FROM public.lf_eventos)::text) INTO v_fp_before;
 SELECT string_agg(c.checkpoint_code||':'||c.status,',' ORDER BY c.checkpoint_code) INTO v_cp_before
 FROM programacion.engineering_work_checkpoints c WHERE c.work_item_id=v_wid AND c.checkpoint_code<>c_cp;
 v_rev_before := public.lf_operation_revision_sha256_v1(c_op);
 SELECT coalesce(string_agg(execution_id||'='||status,',' ORDER BY execution_id),'') INTO v_open_before FROM public.lf_operation_execution WHERE operation_code=c_op AND status='IN_PROGRESS';

 -- DRY-RUN: el subbloque se revierte siempre (RAISE al final); las variables sobreviven al rollback
 BEGIN
   EXECUTE c_candidate_sql;
   GET DIAGNOSTICS v_n_ins = ROW_COUNT;
   SELECT count(*) INTO v_a FROM public.lf_operation_contracts WHERE operation_code=c_op AND status='ACTIVE_ENFORCEMENT';
   SELECT count(*) INTO v_b FROM public.lf_operation_contracts WHERE operation_code=c_op AND status IN ('ACTIVE_ENFORCEMENT','ACTIVE','ACTIVO');
   v_rev_in := public.lf_operation_revision_sha256_v1(c_op);
   SELECT version INTO v_ver FROM public.lf_operation_registry WHERE operation_code=c_op;
   SELECT count(*) INTO v_cand FROM public.lf_operation_contracts
    WHERE operation_code=c_op AND contract_code='CONTRACT-ACTUALIZACION-PERFIL-LF-v0.2' AND status='CANDIDATO_READ_ONLY';
   v_pos := (v_n_ins=1 AND v_a=1 AND v_b=1 AND v_rev_in=v_rev_before AND v_ver='v0.1' AND v_cand=1);
   -- negativo: un segundo contrato activo debe romper el predicado de "exactamente 1 activo"
   BEGIN
     INSERT INTO public.lf_operation_contracts(operation_code,contract_code,contract_path,status,created_by_execution_id)
     VALUES (c_op,'CONTRACT-ACTUALIZACION-PERFIL-LF-NEGATIVE-PROBE','probe','ACTIVE_ENFORCEMENT',c_actor);
     SELECT count(*) INTO v_neg_active FROM public.lf_operation_contracts WHERE operation_code=c_op AND status='ACTIVE_ENFORCEMENT';
     v_neg := (v_neg_active<>1);
     RAISE EXCEPTION 'PE10_C6_NEG_PROBE_ROLLBACK';
   EXCEPTION WHEN raise_exception THEN
     IF SQLERRM <> 'PE10_C6_NEG_PROBE_ROLLBACK' THEN RAISE; END IF;
   END;
   RAISE EXCEPTION 'PE10_C6_DRYRUN_ROLLBACK';
 EXCEPTION WHEN raise_exception THEN
   IF SQLERRM <> 'PE10_C6_DRYRUN_ROLLBACK' THEN RAISE; END IF;
 END;

 -- tras el rollback: sin candidato, sin sonda negativa, huellas identicas
 SELECT count(*) INTO v_after_cand FROM public.lf_operation_contracts WHERE operation_code=c_op AND contract_code LIKE 'CONTRACT-ACTUALIZACION-PERFIL-LF-%' AND contract_code<>'CONTRACT-ACTUALIZACION-PERFIL-LF-v0.1';
 SELECT md5(coalesce((SELECT string_agg(to_jsonb(r)::text,'|' ORDER BY r.operation_code) FROM public.lf_operation_registry r),'')||'#'||
            coalesce((SELECT string_agg(to_jsonb(k)::text,'|' ORDER BY k.operation_code,k.contract_code) FROM public.lf_operation_contracts k),'')||'#'||
            coalesce((SELECT string_agg(to_jsonb(p)::text,'|' ORDER BY p.policy_code,p.policy_version) FROM public.lf_policy_versions p),'')||'#'||
            (SELECT count(*) FROM public.lf_operation_execution)::text||'#'||(SELECT count(*) FROM public.lf_eventos)::text) INTO v_fp_after;
 v_rolled := (v_after_cand=0 AND v_fp_after=v_fp_before AND public.lf_operation_revision_sha256_v1(c_op)=v_rev_before);
 IF NOT (v_pos AND v_neg AND v_rolled) THEN
   RAISE EXCEPTION 'PE10_C6_CLOSE_DRYRUN_FAILED:positive=% a=% b=% ver=% cand=% rev_same=% negative=% neg_active=% rolled_back=%',
     v_pos,v_a,v_b,v_ver,v_cand,(v_rev_in=v_rev_before),v_neg,v_neg_active,v_rolled;
 END IF;

 v_evidence := 'github://cristhianlujan/claude-persona-lf-patch/blob/'||c_commit||
  '/skills/profile_creator/evals/results/pe10_c6_same_chat_claude_material_authoring_20261027.json';
 v_observed := jsonb_build_object(
   'status','PASS','runtime_activated',false,'negative_gate_tested',v_neg,'positive_gate_tested',v_pos,'transaction_rolled_back',v_rolled,
   'candidate','CONTRACT-ACTUALIZACION-PERFIL-LF-v0.2 en CANDIDATO_READ_ONLY',
   'candidate_sql_sha256',encode(sha256(convert_to(c_candidate_sql,'UTF8')),'hex'),
   'positive_gate',jsonb_build_object('active_enforcement_contracts',v_a,'router_visible_contracts',v_b,'operation_revision_unchanged',(v_rev_in=v_rev_before),'registry_version',v_ver),
   'negative_gate',jsonb_build_object('active_enforcement_contracts_with_second_active',v_neg_active,'rejected',v_neg),
   'no_mutation_fingerprint_equal',(v_fp_after=v_fp_before),
   'open_legacy_executions_untouched',v_open_before,
   'source_tests_total',57,'source_tests_scope','RUN_LOCALLY_BY_AUTHOR_PRE_MERGE_NOT_IN_CI',
   'test_script_sha256',c_test_sha,'capture_file_sha256',c_capture_file_sha,'capture_sha256',c_capture_sha,'handoff_sha256',c_handoff_sha,
   'source_receipt_sha256',c_receipt_sha,'executor_mode','CLAUDE_NATIVE','capture_scope','NATIVE_CHAT_RAW_SOURCE_BOUND_UNATTESTED',
   'readback_scope','IN_TRANSACTION_ROLLED_BACK_SUBBLOCK',
   'open_items',jsonb_build_array('SOURCE_TESTS_NOT_RUN_IN_CI','PROFILE_DIFF_2026_10_16_TO_NOW_NOT_VISIBLE','PE10_C7_PENDING'));

 v_rec := programacion.fn_engineering_checkpoint_assertion_record_v1(c_plan,c_unit,c_cp,
   jsonb_build_object('status','PASS','evidence_ref',v_evidence,'observed',v_observed),c_actor);
 IF coalesce((v_rec->>'passed')::boolean,false) IS NOT TRUE THEN RAISE EXCEPTION 'PE10_C6_CLOSE_ASSERTION_NOT_RECORDED:%',v_rec; END IF;
 v_tr := programacion.fn_engineering_checkpoint_transition_v1(c_plan,c_unit,c_cp,'DONE',v_evidence,c_actor,
   'C6 cerrado: dry-run con ROLLBACK del contrato candidato v0.2; positivo (1 activo, revision de la operacion sin cambio, registro en v0.1) y negativo (un segundo activo se rechaza) ejecutados en esta transaccion; sin mutacion. observed='||v_observed::text);
 IF v_tr#>>'{transition,status}' IS DISTINCT FROM 'APPLIED' THEN RAISE EXCEPTION 'PE10_C6_CLOSE_TRANSITION_FAILED:%',v_tr; END IF;

 SELECT string_agg(c.checkpoint_code||':'||c.status,',' ORDER BY c.checkpoint_code) INTO v_cp_after
 FROM programacion.engineering_work_checkpoints c WHERE c.work_item_id=v_wid AND c.checkpoint_code<>c_cp;
 SELECT coalesce(string_agg(execution_id||'='||status,',' ORDER BY execution_id),'') INTO v_open_after FROM public.lf_operation_execution WHERE operation_code=c_op AND status='IN_PROGRESS';
 IF (SELECT status FROM programacion.engineering_work_checkpoints WHERE work_item_id=v_wid AND checkpoint_code=c_cp) IS DISTINCT FROM 'DONE'
    OR v_cp_after IS DISTINCT FROM v_cp_before
    OR (SELECT assertion_receipt_sha256 FROM programacion.engineering_work_checkpoints WHERE work_item_id=v_wid AND checkpoint_code=c_cp) IS NULL
    OR (SELECT count(*) FROM public.lf_operation_contracts WHERE operation_code=c_op AND contract_code<>'CONTRACT-ACTUALIZACION-PERFIL-LF-v0.1')<>0
    OR (SELECT version FROM public.lf_operation_registry WHERE operation_code=c_op)<>'v0.1'
    OR v_open_after IS DISTINCT FROM v_open_before
 THEN RAISE EXCEPTION 'PE10_C6_CLOSE_POSTSTATE_INVALID'; END IF;
END
$mig$;

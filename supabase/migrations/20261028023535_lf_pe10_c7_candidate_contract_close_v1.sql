-- PE10_C7: contrato v0.2 como CANDIDATO + correccion de la especificacion de C7 + cierre del checkpoint.
--
-- Por que se corrige la especificacion: C7 pedia "registro v0.2 = 1", pero lf_operation_registry tiene clave primaria operation_code:
-- una fila v0.2 solo existe cambiando la version de la unica fila (v0.1 -> v0.2), es decir ACTIVANDO v0.2. Eso contradice
-- "nada se activa". Decision del dueño (2026-10-27, opcion 1): C7 exige, sin activar,
--   registro sigue en v0.1 (0 filas v0.2) | contrato v0.2 en CANDIDATO_READ_ONLY (1) | politica candidata ligada por sha256
--   al evento ADMIT_CUTOVER de C5 (1) | politica activa v1.1 (1).
-- La politica candidata v1.4 NO se modifica (su sha5ae6804d... esta ligado a la admision de C5).
-- Seguridad del contrato candidato: las funciones que leen contratos de la operacion filtran por ACTIVE_ENFORCEMENT/ACTIVE/ACTIVO;
-- CANDIDATO_READ_ONLY es invisible (lo comprueba la revision lf_operation_revision_sha256_v1 antes y despues).
-- El SQL candidato es EXACTAMENTE el que PE10_C6 probo con rollback (se exige que su sha256 conste en el cierre de C6).
DO $mig$
DECLARE
 c_plan constant text := 'PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1';
 c_unit constant text := 'PE10';
 c_cp   constant text := 'PE10_C7';
 c_op   constant text := 'ACTUALIZACION_PERFIL_LF';
 c_actor constant text := 'EXEC-PE10-C7-CLOSE-20261028-V1';
 c_candidate_sql constant text := $sql$INSERT INTO public.lf_operation_contracts
 (operation_code,contract_code,contract_path,contract_sha,required_before_write,allowed,blocked,required_after_write,status,created_by_execution_id)
 SELECT c.operation_code,'CONTRACT-ACTUALIZACION-PERFIL-LF-v0.2',
        'public.lf_operation_contracts/ACTUALIZACION_PERFIL_LF/CONTRACT-ACTUALIZACION-PERFIL-LF-v0.2',NULL,
        c.required_before_write, c.allowed || '{"v02_candidate":true,"activation_authorized":false}'::jsonb, c.blocked, c.required_after_write,
        'CANDIDATO_READ_ONLY','EXEC-PE10-C7-CANDIDATE-CONTRACT-20261028-V1'
 FROM public.lf_operation_contracts c
 WHERE c.operation_code='ACTUALIZACION_PERFIL_LF' AND c.contract_code='CONTRACT-ACTUALIZACION-PERFIL-LF-v0.1' AND c.status='ACTIVE_ENFORCEMENT'$sql$;
 q_contract_old constant text := $q$(select count(*)::int from public.lf_operation_contracts where operation_code='ACTUALIZACION_PERFIL_LF' and contract_code='CONTRACT-ACTUALIZACION-PERFIL-LF-v0.2') contract_v02$q$;
 q_contract_new constant text := $q$(select count(*)::int from public.lf_operation_contracts where operation_code='ACTUALIZACION_PERFIL_LF' and contract_code='CONTRACT-ACTUALIZACION-PERFIL-LF-v0.2' and status='CANDIDATO_READ_ONLY') contract_v02$q$;
 q_policy_old constant text := $q$(select count(*)::int from public.lf_policy_versions where policy_code='POL-PROFILE-UPDATE-PASS' and status='CANDIDATE' and policy_payload#>>'{cutover,target_operation_version}'='v0.2') matching_policy_v02$q$;
 q_policy_new constant text := $q$(select count(*)::int from public.lf_policy_versions p where p.policy_code='POL-PROFILE-UPDATE-PASS' and p.status='CANDIDATE' and exists (select 1 from public.lf_eventos e where e.evento_tipo='PROFILE_EVOLUTION_CUTOVER_ADMITTED' and e.entidad_codigo='ACTUALIZACION_PERFIL_LF' and e.payload->>'status'='ADMIT_CUTOVER' and e.payload->>'candidate_policy_sha256'=p.policy_sha)) matching_policy_v02$q$;
 pw_old constant text := 'Exact v0.2 registry AND contract AND matching candidate policy authority, with no automatic activation';
 pw_new constant text := 'v0.2 contract as CANDIDATO_READ_ONLY AND candidate policy bound by sha256 to the C5 admitted event, with registry still v0.1 and policy v1.1 active (no activation)';
 ac_old constant text := 'PE10_C7: exact v0.2 registry+contract+matching candidate policy authority; separate activation gate, no automatic promotion';
 ac_new constant text := 'PE10_C7: v0.2 contract as CANDIDATO_READ_ONLY + candidate policy bound by sha256 to the C5 admission; registry stays v0.1 (activation is a separate gate, no automatic promotion)';
 v_exec text; v_wid bigint; v_meta jsonb; v_text text; v_new jsonb; v_ac jsonb; v_ac_text text;
 v_status text; v_c6_detail text; v_cand_sha text; v_q text; v_row jsonb; v_pass jsonb;
 v_rev_before text; v_rev_after text; v_n int; v_others_before text; v_others_after text;
 v_cp_before text; v_cp_after text; v_units_before text; v_units_after text; v_obs jsonb; v_tr jsonb; v_evidence text; v_open_before text; v_open_after text;
BEGIN
 SELECT execution_id INTO v_exec FROM public.lf_operation_execution
 WHERE operation_code='ACTUALIZACION_DB_LF' AND target_type='MIGRATION'
  AND target_code LIKE '%lf_pe10_c7_candidate_contract_close_v1' AND status='IN_PROGRESS' ORDER BY created_at DESC LIMIT 1;
 IF v_exec IS NULL THEN RAISE EXCEPTION 'PE10_C7_CLOSE_TRAIN_TRANSPORT_REQUIRED'; END IF;

 SELECT u.work_item_id, u.unit_metadata INTO v_wid, v_meta FROM programacion.engineering_plan_units u WHERE u.plan_code=c_plan AND u.unit_code=c_unit FOR UPDATE;
 IF v_wid IS NULL THEN RAISE EXCEPTION 'PE10_C7_CLOSE_UNIT_MISSING'; END IF;
 IF (SELECT status FROM programacion.engineering_work_checkpoints WHERE work_item_id=v_wid AND checkpoint_code='PE10_C6') IS DISTINCT FROM 'DONE'
    OR (SELECT status FROM programacion.engineering_work_checkpoints WHERE work_item_id=v_wid AND checkpoint_code=c_cp) IS DISTINCT FROM 'PENDING'
 THEN RAISE EXCEPTION 'PE10_C7_CLOSE_GATES_STATE_INVALID'; END IF;

 -- el SQL candidato es el mismo que probo C6 (su sha256 consta en el detalle del cierre de C6)
 v_cand_sha := encode(sha256(convert_to(c_candidate_sql,'UTF8')),'hex');
 SELECT w.detail INTO v_c6_detail FROM programacion.engineering_work_updates w
  WHERE w.work_item_id=v_wid AND w.summary LIKE 'Checkpoint PE10_C6 -> DONE%' ORDER BY w.id DESC LIMIT 1;
 IF v_c6_detail IS NULL OR position('"candidate_sql_sha256": "'||v_cand_sha||'"' in v_c6_detail)=0
 THEN RAISE EXCEPTION 'PE10_C7_CLOSE_CANDIDATE_SQL_NOT_THE_ONE_TESTED_BY_C6'; END IF;

 -- estado previo
 IF (SELECT count(*) FROM public.lf_operation_registry WHERE operation_code=c_op AND version='v0.1')<>1
    OR (SELECT count(*) FROM public.lf_operation_contracts WHERE operation_code=c_op AND status='ACTIVE_ENFORCEMENT')<>1
    OR (SELECT count(*) FROM public.lf_operation_contracts WHERE operation_code=c_op AND contract_code='CONTRACT-ACTUALIZACION-PERFIL-LF-v0.2')<>0
    OR (SELECT count(*) FROM public.lf_policy_versions WHERE policy_code='POL-PROFILE-UPDATE-PASS' AND status='ACTIVE')<>1
 THEN RAISE EXCEPTION 'PE10_C7_CLOSE_PRESTATE_INVALID'; END IF;

 v_text := v_meta::text;
 IF (length(v_text)-length(replace(v_text,q_contract_old,'')))/length(q_contract_old)<>3
    OR (length(v_text)-length(replace(v_text,q_policy_old,'')))/length(q_policy_old)<>3
    OR (length(v_text)-length(replace(v_text,pw_old,'')))/length(pw_old)<>2
    OR v_meta#>>'{action_specs_v1,PE10_C7,assertion_contract,pass_when,registry_v02}' IS DISTINCT FROM '1'
    OR v_meta#>>'{action_specs_v1,PE10_C7,validator_contract,validation_input,assertions,0,expected}' IS DISTINCT FROM '1'
 THEN RAISE EXCEPTION 'PE10_C7_CLOSE_SPEC_PRESTATE_DRIFT'; END IF;
 SELECT acceptance_criteria INTO v_ac FROM programacion.engineering_work_items WHERE id=v_wid FOR UPDATE;
 v_ac_text := v_ac::text;
 IF (length(v_ac_text)-length(replace(v_ac_text,ac_old,'')))/length(ac_old)<>1 THEN RAISE EXCEPTION 'PE10_C7_CLOSE_ACCEPTANCE_DRIFT'; END IF;

 -- huellas para demostrar que solo cambia lo previsto
 SELECT string_agg(c.checkpoint_code||':'||c.status,',' ORDER BY c.checkpoint_code) INTO v_cp_before
  FROM programacion.engineering_work_checkpoints c WHERE c.work_item_id=v_wid AND c.checkpoint_code<>c_cp;
 SELECT md5(string_agg(u.unit_code||md5(u.unit_metadata::text),',' ORDER BY u.unit_code)) INTO v_units_before
  FROM programacion.engineering_plan_units u WHERE u.plan_code=c_plan AND u.unit_code<>c_unit;
 v_rev_before := public.lf_operation_revision_sha256_v1(c_op);
 -- ejecuciones abiertas heredadas: se toleran y no se tocan (AUTO_CLOSE_LEGACY_EXECUTIONS prohibido)
 SELECT coalesce(string_agg(execution_id||'='||status,',' ORDER BY execution_id),'') INTO v_open_before FROM public.lf_operation_execution WHERE operation_code=c_op AND status='IN_PROGRESS';

 -- 1) correccion de la especificacion de C7 (y de sus copias en checkpoint_contracts y source_pack_v2)
 v_new := replace(replace(replace(v_text,q_contract_old,q_contract_new),q_policy_old,q_policy_new),pw_old,pw_new)::jsonb;
 v_new := jsonb_set(v_new,'{action_specs_v1,PE10_C7,assertion_contract,pass_when,registry_v02}','0'::jsonb);
 v_new := jsonb_set(v_new,'{action_specs_v1,PE10_C7,validator_contract,validation_input,assertions,0,expected}','0'::jsonb);
 UPDATE programacion.engineering_plan_units SET unit_metadata=v_new WHERE plan_code=c_plan AND unit_code=c_unit;
 UPDATE programacion.engineering_work_items SET acceptance_criteria=replace(v_ac_text,ac_old,ac_new)::jsonb WHERE id=v_wid;

 -- 2) aplicar el candidato exacto
 EXECUTE c_candidate_sql; GET DIAGNOSTICS v_n = ROW_COUNT;
 IF v_n<>1 THEN RAISE EXCEPTION 'PE10_C7_CLOSE_CANDIDATE_NOT_INSERTED:%',v_n; END IF;

 -- 3) relectura con la consulta declarada ya persistida
 SELECT unit_metadata#>>'{action_specs_v1,PE10_C7,verification_queries,0}', unit_metadata#>'{action_specs_v1,PE10_C7,assertion_contract,pass_when}'
   INTO v_q, v_pass FROM programacion.engineering_plan_units WHERE plan_code=c_plan AND unit_code=c_unit;
 EXECUTE 'select to_jsonb(t) from ('||v_q||') t' INTO v_row;
 v_rev_after := public.lf_operation_revision_sha256_v1(c_op);
 IF NOT (v_row @> v_pass) OR v_pass IS DISTINCT FROM jsonb_build_object('registry_v02',0,'contract_v02',1,'matching_policy_v02',1,'active_policy_count',1)
    OR v_rev_after IS DISTINCT FROM v_rev_before
    OR (SELECT count(*) FROM public.lf_operation_contracts WHERE operation_code=c_op AND status='ACTIVE_ENFORCEMENT')<>1
    OR (SELECT version FROM public.lf_operation_registry WHERE operation_code=c_op)<>'v0.1'
 THEN RAISE EXCEPTION 'PE10_C7_CLOSE_READBACK_FAILED:row=% pass=% rev_same=%',v_row,v_pass,(v_rev_after=v_rev_before); END IF;

 v_obs := jsonb_build_object('readback',v_row,'pass_when',v_pass,'operation_revision_unchanged',true,'registry_version','v0.1',
   'active_enforcement_contracts',1,'candidate_sql_sha256',v_cand_sha,'activation',false,'open_legacy_executions_untouched',v_open_before,
   'candidate_policy','POL-PROFILE-UPDATE-PASS v1.4-evolved-routing-candidate (no modificada)',
   'spec_correction','registry_v02 1->0 en action_specs_v1, checkpoint_contracts y source_pack_v2 (3 consultas, 2 textos pass_when, 1 criterio de aceptacion)');
 v_evidence := 'supabase://public/lf_operation_contracts/'||c_op||'/CONTRACT-ACTUALIZACION-PERFIL-LF-v0.2';
 v_tr := programacion.fn_engineering_checkpoint_transition_v1(c_plan,c_unit,c_cp,'DONE',v_evidence,c_actor,
   'C7 cerrado sin activar v0.2: contrato v0.2 en CANDIDATO_READ_ONLY, politica candidata ligada por sha al evento de C5, registro v0.1 y politica v1.1 activa. observed='||v_obs::text);
 IF v_tr#>>'{transition,status}' IS DISTINCT FROM 'APPLIED' THEN RAISE EXCEPTION 'PE10_C7_CLOSE_TRANSITION_FAILED:%',v_tr; END IF;

 -- poscondiciones: solo C7 cambia; el resto del plan no se toca
 SELECT coalesce(string_agg(execution_id||'='||status,',' ORDER BY execution_id),'') INTO v_open_after FROM public.lf_operation_execution WHERE operation_code=c_op AND status='IN_PROGRESS';
 SELECT string_agg(c.checkpoint_code||':'||c.status,',' ORDER BY c.checkpoint_code) INTO v_cp_after
  FROM programacion.engineering_work_checkpoints c WHERE c.work_item_id=v_wid AND c.checkpoint_code<>c_cp;
 SELECT md5(string_agg(u.unit_code||md5(u.unit_metadata::text),',' ORDER BY u.unit_code)) INTO v_units_after
  FROM programacion.engineering_plan_units u WHERE u.plan_code=c_plan AND u.unit_code<>c_unit;
 IF (SELECT status FROM programacion.engineering_work_checkpoints WHERE work_item_id=v_wid AND checkpoint_code=c_cp) IS DISTINCT FROM 'DONE'
    OR v_cp_after IS DISTINCT FROM v_cp_before OR v_units_after IS DISTINCT FROM v_units_before
    OR (SELECT unit_metadata::text FROM programacion.engineering_plan_units WHERE plan_code=c_plan AND unit_code=c_unit) ~ 'policy_payload#>>''\{cutover'
    OR (SELECT count(*) FROM public.lf_operation_contracts WHERE operation_code=c_op)<>2
    OR v_open_after IS DISTINCT FROM v_open_before
 THEN RAISE EXCEPTION 'PE10_C7_CLOSE_POSTSTATE_INVALID'; END IF;

 INSERT INTO public.lf_error_knowledge
   (codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,frecuencia,primera_vez,ultima_vez,lote_origen,estado,source_ref)
 SELECT 'LF-PE10-C7-REGISTRY-V02-NEEDS-ACTIVATION-20261028-001','PROFILE_EVOLUTION',
  'PE10_C7 exigia un registro v0.2 que solo existe activando v0.2',
  'La especificacion de PE10_C7 pedia registry_v02=1 sin activar. lf_operation_registry tiene clave primaria operation_code: una fila v0.2 solo se obtiene cambiando la version de la unica fila (activacion).',
  'La especificacion se escribio sin comprobar la clave primaria del registro; la condicion y la regla "nada se activa" eran incompatibles.',
  'Un checkpoint de pre-activacion que exige un objeto que solo la activacion puede crear.',
  'Antes de fijar la condicion de un checkpoint, comprobar que el estado exigido se puede crear sin el efecto prohibido (claves, restricciones).',
  'PE10_C7 corregido: registro v0.1 (0 filas v0.2) + contrato v0.2 CANDIDATO_READ_ONLY + politica candidata ligada por sha al evento de C5 + politica activa v1.1.',
  'MEDIUM',1,clock_timestamp(),clock_timestamp(),'PE10_C7','ACTIVO',
  'supabase://public/lf_operation_contracts/ACTUALIZACION_PERFIL_LF/CONTRACT-ACTUALIZACION-PERFIL-LF-v0.2'
 WHERE NOT EXISTS (SELECT 1 FROM public.lf_error_knowledge WHERE codigo='LF-PE10-C7-REGISTRY-V02-NEEDS-ACTIVATION-20261028-001');
END
$mig$;

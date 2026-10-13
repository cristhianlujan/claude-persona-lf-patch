-- Existing Profile-specific recorder has its own four current-step checks.
-- Preserve CREACION_PERFIL_LF behavior and only resolve frozen snapshot when present.
-- Train owns transaction and migration ledger.
DO $repair$
DECLARE
 v_sig regprocedure:='public.lf_record_profile_operation_step_v1(text,text,text,jsonb,text)'::regprocedure;
 v_def text;
 v_old text:='s.operation_code=v_execution.operation_code and s.required is true and s.active is true';
 v_new text:='s.operation_code=v_execution.operation_code and s.required is true and s.active is true and (not v_snapshot_applies or exists (select 1 from jsonb_array_elements_text(v_snapshot_steps) frozen(step_id) where frozen.step_id=s.step_id))';
 v_anchor text:='  v_trust jsonb;';
 v_status text:='  if v_execution.status <> ''IN_PROGRESS'' then return jsonb_build_object(''outcome'',''BLOCKED'',''code'',''EXECUTION_NOT_IN_PROGRESS'',''status'',v_execution.status,''durable'',false); end if;';
 v_guard text;
BEGIN
 SELECT pg_get_functiondef(v_sig) INTO v_def;
 IF md5(v_def)<>'d4a3b1ff4af42236e32d0419f7028e3c' THEN
  RAISE EXCEPTION 'PE10_PROFILE_WRAPPER_CURRENTNESS_CHANGED';
 END IF;
 IF (length(v_def)-length(replace(v_def,v_old,'')))/length(v_old)<>4
   OR position(v_anchor in v_def)=0 OR position(v_status in v_def)=0 THEN
   RAISE EXCEPTION 'PE10_PROFILE_WRAPPER_PATCH_ANCHOR_DRIFT';
 END IF;
 v_guard:=$guard$
  -- Resolve immutable PASS_POLICY requirements from execution, not today's catalog.
  -- Absent snapshots retain the original current-catalog enforcement.
  v_snapshot_steps:=v_execution.manifest#>'{operation_policy_snapshots,PASS_POLICY,policy_payload,required_steps}';
  IF v_snapshot_steps IS NOT NULL THEN
    IF jsonb_typeof(v_snapshot_steps)<>'array'
       OR jsonb_array_length(v_snapshot_steps)=0
       OR EXISTS (SELECT 1 FROM jsonb_array_elements(v_snapshot_steps) x WHERE jsonb_typeof(x.value)<>'string')
       OR (SELECT count(*) FROM jsonb_array_elements_text(v_snapshot_steps))
          <> (SELECT count(DISTINCT value) FROM jsonb_array_elements_text(v_snapshot_steps) t(value))
       OR EXISTS (
          SELECT 1 FROM jsonb_array_elements_text(v_snapshot_steps) t(value)
          WHERE nullif(btrim(t.value),'') IS NULL
             OR NOT EXISTS (
                SELECT 1 FROM public.lf_operation_steps st
                WHERE st.operation_code=v_execution.operation_code
                  AND st.step_id=t.value AND st.required AND st.active
             )
       ) THEN
      RETURN jsonb_build_object('outcome','BLOCKED','code','FROZEN_REQUIRED_STEPS_INVALID','durable',false);
    END IF;
    v_snapshot_applies:=true;
  END IF;
$guard$;
 v_def:=replace(v_def,v_anchor,
   '  v_snapshot_steps jsonb;'||chr(10)||
   '  v_snapshot_applies boolean := false;'||chr(10)||v_anchor);
 v_def:=replace(v_def,v_status,v_status||chr(10)||v_guard);
 v_def:=replace(v_def,v_old,v_new);
 EXECUTE v_def||';';
 IF position('v_snapshot_applies' in pg_get_functiondef(v_sig))=0
    OR (length(pg_get_functiondef(v_sig))-
        length(replace(pg_get_functiondef(v_sig),'not v_snapshot_applies or exists','')))
       /length('not v_snapshot_applies or exists')<>4 THEN
   RAISE EXCEPTION 'PE10_PROFILE_WRAPPER_POST_PATCH_READBACK_FAILED';
 END IF;
 IF (SELECT count(*) FROM public.lf_operation_execution
     WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND status='IN_PROGRESS')<>24 THEN
   RAISE EXCEPTION 'PE10_PROFILE_WRAPPER_EXECUTION_STATE_MUTATED';
 END IF;
END;
$repair$;

INSERT INTO public.lf_error_knowledge
(codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
 severidad,frecuencia,primera_vez,ultima_vez,lote_origen,estado,source_ref)
SELECT
 'LF-PE10-C4-PROFILE-WRAPPER-SECONDARY-REQUIRED-STEPS-20261013-001',
 'PROFILE_EVOLUTION',
 'Profile-specific recorder repeats required-step enforcement outside transversal recorder',
 'After PR2391 corrected operation-neutral recorder, historical UI execution still failed close with PRIOR_REQUIRED_STEP_NOT_CLEAN prior_missing=1 because public.lf_record_profile_operation_step_v1 contains four independent current-catalog required-step checks.',
 'Two distinct recorder entrypoints evaluate operation requirements independently; updating the transversal core did not affect the Profile wrapper call path.',
 'Frozen historical PASS_POLICY requires 14 steps but newer catalog requires post_merge_reconcile',
 'Review every actual consumer recorder before assuming shared-core patch propagates. For executions with a valid frozen step snapshot, enforce that snapshot in every prior/terminal check; invalid frozen snapshot fails closed; missing snapshot retains legacy behavior.',
 'Before this patch, both UI executions are 12/14 pass and wrapper close reports prior_missing=1; after patch, dry-run rollback close+report should succeed without post_merge_reconcile and current profile authority must remain unchanged.',
 'HIGH',1,clock_timestamp(),clock_timestamp(),
 'PE10_C4_PROFILE_WRAPPER_FROZEN_STEPS','ACTIVO',
 'github://cristhianlujan/claude-persona-lf-patch/pull/2396;supabase://pg_proc/public.lf_record_profile_operation_step_v1'
WHERE NOT EXISTS (SELECT 1 FROM public.lf_error_knowledge
 WHERE codigo='LF-PE10-C4-PROFILE-WRAPPER-SECONDARY-REQUIRED-STEPS-20261013-001');

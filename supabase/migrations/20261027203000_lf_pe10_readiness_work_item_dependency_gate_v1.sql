-- PE10A_SB06: la readiness de un checkpoint respeta las dependencias entre work items.
--
-- Problema verificado en produccion (solo lectura, 2026-10-27): con PEVO-PE10A_READY en BACKLOG,
-- fn_engineering_checkpoint_execution_readiness_v1 devolvia READY / reasons [] para PE10_C6 y PE10_C7,
-- mientras fn_engineering_unit_bootstrap_v3 ya devolvia terminal_action=WAIT_DEPENDENCIES para la misma unidad.
-- El cierre gobernado ya se rechazaba por el bootstrap; la readiness informaba lo contrario.
--
-- Cambio: unica funcion reemplazada, fn_engineering_checkpoint_execution_readiness_from_payload_v1.
-- Reglas:
--   * solo actua si el checkpoint esta abierto (ni DONE ni NOT_APPLICABLE) y su work item tiene
--     dependencias sin cumplir segun fn_engineering_effective_dependencies_v1 (misma regla que usa
--     fn_engineering_checkpoint_transition_v1 al consolidar el work item);
--   * en ese caso devuelve NOT_READY, execution_ready=false, razon tipada WORK_ITEM_DEPENDENCY_UNMET,
--     gate DEPENDENCIES_SATISFIED=false y el detalle de dependencias; conserva los demas gates
--     (COMPILE_READY, ACTION_EXACT, ERROR_CLOSED) tal como los calcula from_context_v1;
--   * en cualquier otro caso devuelve exactamente lo mismo que antes (sin claves nuevas).
-- No modifica datos, permisos ni otras funciones. No activa Profile Updater v0.2.

DO $mig$
DECLARE
 c_src_before constant text := '14b50e0b3167fd4e4c034d6750f0ed08';  -- md5(prosrc) de from_payload_v1 vigente
 c_dep_fn     constant text := 'c68f3d6217104c95d03d40e8497d61de';  -- md5(prosrc) de effective_dependencies_v1
 v_exec text;
 v_acl_before aclitem[];
 v_acl_after aclitem[];
BEGIN
 SELECT execution_id INTO v_exec FROM public.lf_operation_execution
 WHERE operation_code='ACTUALIZACION_DB_LF' AND target_type='MIGRATION'
  AND target_code LIKE '%lf_pe10_readiness_work_item_dependency_gate_v1'
  AND status='IN_PROGRESS'
 ORDER BY created_at DESC LIMIT 1;
 IF v_exec IS NULL THEN RAISE EXCEPTION 'PE10_READINESS_DEP_GATE_TRAIN_TRANSPORT_REQUIRED'; END IF;

 IF to_regprocedure('programacion.fn_engineering_checkpoint_execution_readiness_from_context_v1(text,jsonb,jsonb,jsonb)') IS NULL
  THEN RAISE EXCEPTION 'PE10_READINESS_DEP_GATE_CONTEXT_FN_MISSING'; END IF;

 IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='programacion' AND p.proname='fn_engineering_effective_dependencies_v1'
       AND md5(p.prosrc)=c_dep_fn)
  THEN RAISE EXCEPTION 'PE10_READINESS_DEP_GATE_DEPENDENCY_FN_DRIFT'; END IF;

 SELECT p.proacl INTO v_acl_before FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='programacion' AND p.proname='fn_engineering_checkpoint_execution_readiness_from_payload_v1'
   AND md5(p.prosrc)=c_src_before AND p.provolatile='s' AND NOT p.prosecdef;
 IF NOT FOUND THEN RAISE EXCEPTION 'PE10_READINESS_DEP_GATE_PRESTATE_DRIFT_OR_ALREADY_APPLIED'; END IF;

 EXECUTE $fn$
CREATE OR REPLACE FUNCTION programacion.fn_engineering_checkpoint_execution_readiness_from_payload_v1(
  p_plan_code text, p_unit_code text, p_checkpoint_code text, p_action_spec jsonb, p_packet jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $body$
declare
  v_meta jsonb;
  v_work_item_id bigint;
  v_base jsonb;
  v_cp_status text;
  v_unmet_count int;
  v_unmet jsonb;
begin
  select pu.unit_metadata, pu.work_item_id into v_meta, v_work_item_id
  from programacion.engineering_plan_units pu
  where pu.plan_code=p_plan_code
    and pu.unit_code=p_unit_code;

  v_base:=programacion.fn_engineering_checkpoint_execution_readiness_from_context_v1(
    p_checkpoint_code,p_action_spec,p_packet,v_meta
  );

  -- unidad inexistente o sin work item: comportamiento anterior
  if v_work_item_id is null then
    return v_base;
  end if;

  -- checkpoints ya cerrados: comportamiento anterior
  select c.status into v_cp_status
  from programacion.engineering_work_checkpoints c
  where c.work_item_id=v_work_item_id
    and c.checkpoint_code=p_checkpoint_code;
  if v_cp_status is null or v_cp_status in ('DONE','NOT_APPLICABLE') then
    return v_base;
  end if;

  select count(*),
         coalesce(jsonb_agg(jsonb_build_object(
           'work_code',d.effective_work_code,
           'status',d.effective_status,
           'resolution',d.resolution
         ) order by d.effective_work_code),'[]'::jsonb)
  into v_unmet_count, v_unmet
  from programacion.fn_engineering_effective_dependencies_v1(v_work_item_id) d
  where d.is_unmet;

  -- dependencias cumplidas o inexistentes: comportamiento anterior
  if v_unmet_count=0 then
    return v_base;
  end if;

  return v_base || jsonb_build_object(
    'status','NOT_READY',
    'execution_ready',false,
    'gates',coalesce(v_base->'gates','{}'::jsonb)
            || jsonb_build_object('DEPENDENCIES_SATISFIED',false),
    'dependencies',jsonb_build_object('unmet_count',v_unmet_count,'unmet',v_unmet),
    'reasons',coalesce(v_base->'reasons','[]'::jsonb)
              || jsonb_build_array('WORK_ITEM_DEPENDENCY_UNMET')
  );
end;
$body$
 $fn$;

 -- post-estado: la funcion cambio, sigue STABLE/no SECURITY DEFINER y los permisos no se movieron
 SELECT p.proacl INTO v_acl_after FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='programacion' AND p.proname='fn_engineering_checkpoint_execution_readiness_from_payload_v1'
   AND position('WORK_ITEM_DEPENDENCY_UNMET' IN p.prosrc)>0
   AND md5(p.prosrc)<>c_src_before AND p.provolatile='s' AND NOT p.prosecdef;
 IF NOT FOUND THEN RAISE EXCEPTION 'PE10_READINESS_DEP_GATE_POSTSTATE_FUNCTION_MISMATCH'; END IF;
 IF v_acl_after IS DISTINCT FROM v_acl_before THEN RAISE EXCEPTION 'PE10_READINESS_DEP_GATE_ACL_CHANGED'; END IF;
END
$mig$;

-- PE10: activacion del enrutamiento evolutivo de Profile Updater (v1.4-evolved-routing) -- BORRADOR, requiere autorizacion del dueno.
-- Activa: pasos method_selection y evolution_decision (+ sus jueces enlazados, contratos de paso y jueces) y la politica de pase v1.4.
-- NO cambia: lf_operation_registry (sigue v0.1), contrato v0.1 ACTIVE_ENFORCEMENT, contrato v0.2 candidato, ni ejecuciones existentes
-- (el snapshot de politica de cada ejecucion es inmutable: las abiertas siguen con v1.1 y sus 15 pasos).
-- Probado con rollback en produccion: cierre completo con v1.1 (14/14) y con v1.4 en rutas UPDATE (17 pasos) y NO_CHANGE (ruta corta).
-- Reversion: migracion nueva que vuelve los estados a CANDIDATE/inactivo y v1.1 ACTIVE (fail-forward; no se reaplica ni se cambia la version).
DO $guard$
BEGIN
 IF NOT EXISTS (SELECT 1 FROM public.lf_operation_execution WHERE operation_code='ACTUALIZACION_DB_LF' AND target_type='MIGRATION'
     AND target_code LIKE '%lf_pe10_activate_evolved_routing_v1' AND status='IN_PROGRESS')
 THEN RAISE EXCEPTION 'PE10_ACTIVATE_TRAIN_TRANSPORT_REQUIRED'; END IF;
END
$guard$;
DO $body$
DECLARE
 v_n int; v_active int;
BEGIN
 -- Estado previo exigido: nada de la evolucion esta activo todavia.
 IF (SELECT count(*) FROM public.lf_policy_versions WHERE policy_code='POL-PROFILE-UPDATE-PASS' AND policy_version='v1.1' AND status='ACTIVE')<>1
    OR (SELECT count(*) FROM public.lf_policy_versions WHERE policy_code='POL-PROFILE-UPDATE-PASS' AND policy_version='v1.4-evolved-routing-candidate' AND status='CANDIDATE' AND policy_sha LIKE '5ae6804ded17%')<>1
    OR (SELECT count(*) FROM public.lf_operation_steps WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND step_id IN ('method_selection','evolution_decision') AND active IS FALSE)<>2
    OR (SELECT count(*) FROM public.lf_operation_step_judge_bindings WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND step_id IN ('method_selection','evolution_decision') AND status='CANDIDATE')<>2
    OR (SELECT count(*) FROM public.lf_operation_step_contracts WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND step_id IN ('method_selection','evolution_decision') AND status='CANDIDATE')<>2
    OR (SELECT count(*) FROM public.lf_operation_judges WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND judge_code IN ('JUDGE-PE10-V02-METHOD-SELECTION','JUDGE-PE10-V02-EVOLUTION-DECISION') AND status='CANDIDATO_READ_ONLY')<>2
 THEN RAISE EXCEPTION 'PE10_ACTIVATE_PRESTATE_INVALID'; END IF;

 UPDATE public.lf_operation_steps SET active=true WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND step_id IN ('method_selection','evolution_decision');
 UPDATE public.lf_operation_step_judge_bindings SET status='ACTIVE_ENFORCEMENT' WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND step_id IN ('method_selection','evolution_decision');
 UPDATE public.lf_operation_step_contracts SET status='ACTIVE_ENFORCEMENT' WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND step_id IN ('method_selection','evolution_decision');
 UPDATE public.lf_operation_judges SET status='ACTIVE_ENFORCEMENT' WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND judge_code IN ('JUDGE-PE10-V02-METHOD-SELECTION','JUDGE-PE10-V02-EVOLUTION-DECISION');
 UPDATE public.lf_policy_versions SET status='SUPERSEDED' WHERE policy_code='POL-PROFILE-UPDATE-PASS' AND policy_version='v1.1';
 UPDATE public.lf_policy_versions SET status='ACTIVE' WHERE policy_code='POL-PROFILE-UPDATE-PASS' AND policy_version='v1.4-evolved-routing-candidate';

 -- Readback: exactamente lo esperado y una sola politica activa.
 SELECT count(*) INTO v_active FROM public.lf_policy_versions WHERE policy_code='POL-PROFILE-UPDATE-PASS' AND status='ACTIVE';
 IF v_active<>1
    OR (SELECT count(*) FROM public.lf_policy_versions WHERE policy_code='POL-PROFILE-UPDATE-PASS' AND policy_version='v1.4-evolved-routing-candidate' AND status='ACTIVE')<>1
    OR (SELECT count(*) FROM public.lf_operation_steps WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND step_id IN ('method_selection','evolution_decision') AND active AND required)<>2
    OR (SELECT count(*) FROM public.lf_operation_step_judge_bindings WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND step_id IN ('method_selection','evolution_decision') AND status='ACTIVE_ENFORCEMENT')<>2
    OR (SELECT count(*) FROM public.lf_operation_step_contracts WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND step_id IN ('method_selection','evolution_decision') AND status='ACTIVE_ENFORCEMENT')<>2
    OR (SELECT count(*) FROM public.lf_operation_judges WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND judge_code IN ('JUDGE-PE10-V02-METHOD-SELECTION','JUDGE-PE10-V02-EVOLUTION-DECISION') AND status='ACTIVE_ENFORCEMENT')<>2
 THEN RAISE EXCEPTION 'PE10_ACTIVATE_READBACK_FAILED'; END IF;
END
$body$;

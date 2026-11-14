-- CANDIDATE ONLY — DRAFT/NO-GO. Never apply outside LF Migration Merge Train.
-- EJECUCION_PERFIL_LF owns its plan; Router provides selected profile + context, not skills.
-- Minimal request (owner): "Ejecuta EJECUCION_PERFIL_LF para <solicitud + contexto>".
-- The only semantic parameter below is the already Router-admitted profile code.
-- Active steps/contracts and profile-skill associations come from the DATABASE.
-- Current production state: no USA_SKILL links; legacy GOBERNADO_POR CONTRACT is NOT a skill.
BEGIN;

CREATE OR REPLACE FUNCTION public.lf_profile_execution_plan_v1(p_profile_code text)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY INVOKER
SET search_path TO 'pg_catalog', 'public'
AS $operation_profile_plan$
DECLARE
 v_profile public.lf_activos%rowtype;
 v_steps jsonb;
 v_skills jsonb;
 v_count integer;
 v_invalid int;
 v_unmigrated boolean;
BEGIN
 SELECT * INTO v_profile FROM public.lf_activos
 WHERE codigo_activo=p_profile_code AND tipo_activo='PERFIL' AND archived_at IS NULL;
 IF NOT FOUND THEN
   RETURN jsonb_build_object('status','BLOCKED','blocking_code','PROFILE_NOT_IN_CANONICAL_ASSETS');
 END IF;
 SELECT count(*),count(*) FILTER(WHERE c.step_id IS NULL),
        coalesce(jsonb_agg(jsonb_build_object(
          'step_order',s.step_order,'step_id',s.step_id,
          'resolver_ref',c.resolver_ref,'required_evidence_keys',c.required_evidence_keys,
          'next_if_pass',c.next_if_pass,'next_if_blocked',c.next_if_blocked
        ) ORDER BY s.step_order),'[]'::jsonb)
 INTO v_count,v_invalid,v_steps
 FROM public.lf_operation_steps s
 LEFT JOIN public.lf_operation_step_contracts c
   ON c.operation_code=s.operation_code AND c.step_id=s.step_id
      AND c.status='ACTIVE_ENFORCEMENT'
 WHERE s.operation_code='EJECUCION_PERFIL_LF' AND s.active AND s.required;
 IF v_count<>11 OR v_invalid<>0 THEN
   RETURN jsonb_build_object('status','BLOCKED','blocking_code','PROFILE_OPERATION_STEP_CONTRACTS_INCOMPLETE',
       'step_count',v_count,'unbound_step_contracts',v_invalid);
 END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object(
    'skill_code',k.skill_code,'handler_fn',k.handler_fn,'effect',k.effect,
    'required_operation',k.required_operation,
    'invoker','public.lf_skill_invoke_v1',
    'binding_ref','public.lf_activo_relaciones/'||r.id
 ) ORDER BY k.skill_code),'[]'::jsonb)
 INTO v_skills
 FROM public.lf_activo_relaciones r
 JOIN public.lf_skill_catalog_v1 k
   ON k.skill_code=r.relacionado_codigo AND k.status='READY'
 WHERE r.codigo_activo=p_profile_code AND r.relacion_tipo='USA_SKILL'
   AND k.required_operation='EJECUCION_PERFIL_LF'
   AND k.effect IN ('READ_ONLY','PROPOSE_ONLY');
 -- Fail closed: do NOT reinterpret a governance CONTRACT as a runnable SKILL.
 -- The old profile metadata signals legacy dependency that needs a real skill binding.
 v_unmigrated := v_profile.metadata ? 'input_governance_binding_mode'
   AND jsonb_array_length(v_skills)=0;
 IF v_unmigrated THEN
   RETURN jsonb_build_object('status','BLOCKED',
     'blocking_code','PROFILE_LEGACY_DEPENDENCY_NOT_EXECUTABLE',
     'profile_code',p_profile_code,'steps',v_steps,'skills',v_skills);
 END IF;
 RETURN jsonb_build_object('status','READY','operation_code','EJECUCION_PERFIL_LF',
   'profile_code',p_profile_code,'steps',v_steps,'skills',v_skills,
   'step_source','public.lf_operation_steps+lf_operation_step_contracts',
   'skill_source','public.lf_activo_relaciones+lf_skill_catalog_v1',
   'skill_trigger_owner','EJECUCION_PERFIL_LF',
   'runtime_mode','GPT_NATIVE','model_external_api',false);
END;
$operation_profile_plan$;

-- No router-minted skill list; no implicit GRANT, no writes to live assets, no skill-specific step 40/50.
COMMIT;

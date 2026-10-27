-- LF / Input Governance: allow bounded partial matching of profile target_hint to canonical screens.
-- Keeps fail-closed cardinality semantics: 0 unresolved, 1 resolved, >1 ambiguous.
BEGIN;

CREATE OR REPLACE FUNCTION programacion.fn_lf_profile_input_governance_resolve_v1(
  p_request_text text,
  p_profile_code text,
  p_scope jsonb DEFAULT NULL,
  p_consumer text DEFAULT 'CONTEXT_PACK'
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog','public','programacion','lf_ops'
AS $fn$
DECLARE
  v_bound boolean:=false;
  v_screen_count integer:=0;
  v_pantalla_id integer;
  v_screen_code text;
  v_target_hint text:=nullif(btrim(coalesce(p_scope->>'target_hint','')),'');
  v_target_hint_like text;
  v_req text;
  v_result jsonb;
  v_worker jsonb;
BEGIN
  SELECT EXISTS(
    SELECT 1
    FROM public.lf_activo_relaciones r
    JOIN public.lf_activos a
      ON a.codigo_activo=r.codigo_activo
     AND a.archived_at IS NULL
     AND a.tipo_activo='PERFIL'
    WHERE r.codigo_activo=p_profile_code
      AND r.relacionado_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT'
      AND r.relacion_tipo='GOBERNADO_POR'
      AND a.metadata->>'input_governance_binding_mode'='DIRECT_PROFILE'
      AND a.metadata->>'input_governance_consumer'=p_consumer
  ) INTO v_bound;

  IF NOT v_bound THEN
    RETURN jsonb_build_object(
      'applicable',false,
      'status','NOT_REQUIRED',
      'decision','N/A',
      'continuation_allowed',true,
      'profile_code',p_profile_code,
      'binding_mode','NO_DIRECT_PROFILE_BINDING',
      'router_reentry_required',false
    );
  END IF;

  IF v_target_hint IS NOT NULL THEN
    -- Strip LIKE metacharacters from the model/user-derived hint so partial
    -- matching cannot widen through '%' or '_'. Canonical values remain trusted.
    v_target_hint_like:=replace(replace(v_target_hint,'%',''),'_','');

    SELECT count(*),min(id),min(codigo)
      INTO v_screen_count,v_pantalla_id,v_screen_code
    FROM lf_ops.pantallas
    WHERE activa
      AND (
        upper(codigo)=upper(v_target_hint)
        OR upper(nombre)=upper(v_target_hint)
        OR upper(codigo) LIKE '%'||upper(v_target_hint_like)||'%'
        OR upper(nombre) LIKE '%'||upper(v_target_hint_like)||'%'
        OR upper(v_target_hint_like) LIKE '%'||upper(codigo)||'%'
        OR upper(v_target_hint_like) LIKE '%'||upper(nombre)||'%'
      );
  END IF;

  IF v_screen_count=0 THEN
    v_req:=' '||btrim(regexp_replace(lower(coalesce(p_request_text,'')),'[^a-z0-9_]+',' ','g'))||' ';
    SELECT count(*),min(id),min(codigo)
      INTO v_screen_count,v_pantalla_id,v_screen_code
    FROM lf_ops.pantallas
    WHERE activa
      AND strpos(
        v_req,
        ' '||btrim(regexp_replace(lower(codigo),'[^a-z0-9_]+',' ','g'))||' '
      )>0;
  END IF;

  IF v_screen_count=0 THEN
    RETURN jsonb_build_object(
      'applicable',true,
      'status','INPUT_GOVERNANCE_REQUIRED',
      'blocking_code','BLOCK_PROFILE_INPUT_GOVERNANCE_SUBJECT_UNRESOLVED',
      'decision','PENDING',
      'continuation_allowed',false,
      'profile_code',p_profile_code,
      'consumer',p_consumer,
      'binding_mode','DIRECT_PROFILE',
      'resume_via','EJECUCION_PERFIL_LF/input_validate',
      'router_reentry_required',false
    );
  END IF;

  IF v_screen_count>1 THEN
    RETURN jsonb_build_object(
      'applicable',true,
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_INPUT_GOVERNANCE_SUBJECT_AMBIGUOUS',
      'decision','BLOCKED',
      'continuation_allowed',false,
      'profile_code',p_profile_code,
      'consumer',p_consumer,
      'binding_mode','DIRECT_PROFILE',
      'resume_via','EJECUCION_PERFIL_LF/input_validate',
      'router_reentry_required',false
    );
  END IF;

  v_result:=public.fn_input_governance_execute(v_pantalla_id,p_consumer);

  IF v_result->>'status'='READY' THEN
    RETURN jsonb_build_object(
      'applicable',true,
      'status','READY',
      'blocking_code',null,
      'decision','PASS',
      'continuation_allowed',true,
      'profile_code',p_profile_code,
      'consumer',p_consumer,
      'binding_mode','DIRECT_PROFILE',
      'pantalla_id',v_pantalla_id,
      'screen_code',v_screen_code,
      'run_id',v_result->'run_id',
      'governance_output_sha256',v_result->'output_sha256',
      'context_manifest',v_result->'context_manifest',
      'governance_result',v_result,
      'resume_via','EJECUCION_PERFIL_LF/input_validate',
      'router_reentry_required',false
    );
  END IF;

  IF v_result->>'status' IN ('CURATOR_RUNTIME_REQUIRED','VALIDATOR_RUNTIME_REQUIRED') THEN
    v_worker:=coalesce(
      v_result->'worker_spec',
      public.fn_input_governance_worker_spec(v_pantalla_id,p_consumer)
    );
    RETURN jsonb_build_object(
      'applicable',true,
      'status','INPUT_GOVERNANCE_REQUIRED',
      'blocking_code','BLOCK_PROFILE_INPUT_GOVERNANCE_RUNTIME_REQUIRED',
      'decision','PENDING',
      'continuation_allowed',false,
      'profile_code',p_profile_code,
      'consumer',p_consumer,
      'binding_mode','DIRECT_PROFILE',
      'pantalla_id',v_pantalla_id,
      'screen_code',v_screen_code,
      'agent_status',v_result->>'status',
      'worker_spec',v_worker,
      'resume_via','EJECUCION_PERFIL_LF/input_validate',
      'router_reentry_required',false
    );
  END IF;

  IF v_result->>'status'='HUMAN_DECISION_REQUIRED' THEN
    RETURN jsonb_build_object(
      'applicable',true,
      'status','HUMAN_DECISION_REQUIRED',
      'blocking_code','BLOCK_PROFILE_INPUT_GOVERNANCE_HUMAN_DECISION_REQUIRED',
      'decision','PARTIAL',
      'continuation_allowed',false,
      'profile_code',p_profile_code,
      'consumer',p_consumer,
      'binding_mode','DIRECT_PROFILE',
      'pantalla_id',v_pantalla_id,
      'screen_code',v_screen_code,
      'governance_result',v_result,
      'resume_via','EJECUCION_PERFIL_LF/input_validate',
      'router_reentry_required',false
    );
  END IF;

  RETURN jsonb_build_object(
    'applicable',true,
    'status','BLOCKED',
    'blocking_code','BLOCK_PROFILE_INPUT_GOVERNANCE',
    'decision','BLOCKED',
    'continuation_allowed',false,
    'profile_code',p_profile_code,
    'consumer',p_consumer,
    'binding_mode','DIRECT_PROFILE',
    'pantalla_id',v_pantalla_id,
    'screen_code',v_screen_code,
    'governance_result',v_result,
    'resume_via','EJECUCION_PERFIL_LF/input_validate',
    'router_reentry_required',false
  );
END
$fn$;

REVOKE ALL ON FUNCTION programacion.fn_lf_profile_input_governance_resolve_v1(text,text,jsonb,text)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION programacion.fn_lf_profile_input_governance_resolve_v1(text,text,jsonb,text)
  TO service_role;

COMMENT ON FUNCTION programacion.fn_lf_profile_input_governance_resolve_v1(text,text,jsonb,text) IS
'Profile Input Governance resolver. Resolves canonical screen from exact or bounded bidirectional LIKE target_hint matching, preserving fail-closed ambiguity, then delegates to the existing Input Governance runtime.';

DO $postcheck$
DECLARE
  v_count integer;
  v_code text;
  v_ambiguous integer;
  v_src text;
BEGIN
  SELECT count(*),min(codigo)
    INTO v_count,v_code
  FROM lf_ops.pantallas
  WHERE activa
    AND (
      upper(codigo)=upper('Iniciar sesión B2B')
      OR upper(nombre)=upper('Iniciar sesión B2B')
      OR upper(codigo) LIKE '%'||upper('Iniciar sesión B2B')||'%'
      OR upper(nombre) LIKE '%'||upper('Iniciar sesión B2B')||'%'
      OR upper('Iniciar sesión B2B') LIKE '%'||upper(codigo)||'%'
      OR upper('Iniciar sesión B2B') LIKE '%'||upper(nombre)||'%'
    );

  IF v_count<>1 OR v_code<>'B2B-AUTH-001' THEN
    RAISE EXCEPTION 'PROFILE_IG_TARGET_HINT_LIKE_REGRESSION:%:%',v_count,v_code;
  END IF;

  SELECT count(*)
    INTO v_ambiguous
  FROM lf_ops.pantallas
  WHERE activa
    AND (
      upper(codigo)=upper('B2B')
      OR upper(nombre)=upper('B2B')
      OR upper(codigo) LIKE '%'||upper('B2B')||'%'
      OR upper(nombre) LIKE '%'||upper('B2B')||'%'
      OR upper('B2B') LIKE '%'||upper(codigo)||'%'
      OR upper('B2B') LIKE '%'||upper(nombre)||'%'
    );

  IF v_ambiguous<=1 THEN
    RAISE EXCEPTION 'PROFILE_IG_TARGET_HINT_AMBIGUITY_GUARD_REGRESSION:%',v_ambiguous;
  END IF;

  v_src:=pg_get_functiondef(
    'programacion.fn_lf_profile_input_governance_resolve_v1(text,text,jsonb,text)'::regprocedure
  );

  IF strpos(v_src,'LIKE ''%''||upper(v_target_hint_like)||''%''')=0
     OR strpos(v_src,'IF v_screen_count>1 THEN')=0
     OR strpos(v_src,'BLOCK_PROFILE_INPUT_GOVERNANCE_SUBJECT_AMBIGUOUS')=0
  THEN
    RAISE EXCEPTION 'PROFILE_IG_TARGET_HINT_LIKE_SOURCE_POSTCHECK_FAILED';
  END IF;
END
$postcheck$;

COMMIT;

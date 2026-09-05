-- SECURITY DEFINER RPC isolation candidate — SOURCE ONLY / DO NOT APPLY FROM THIS FILE
-- Backlog: ERR-GOV-SECURITY-DEFINER-AUTH-RPC-ISOLATION-001
-- Required promotion vehicle: governed Supabase migration after explicit approval.
-- Proven sandbox pattern: public SECURITY INVOKER wrapper -> SECURITY DEFINER helper in non-exposed schema.
-- Hosted Data API evidence must remain db_schema=graphql_public,public.

-- Fail closed if the intended empty helper namespaces or grants drift before promotion.
DO $preflight$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname IN ('lf_client','transversal')
  ) THEN
    RAISE EXCEPTION 'RPC_ISOLATION_NAMESPACE_FUNCTION_DRIFT';
  END IF;

  IF has_schema_privilege('authenticated','lf_client','USAGE')
     OR has_schema_privilege('authenticated','transversal','USAGE')
     OR has_schema_privilege('authenticated','programacion','USAGE') THEN
    RAISE EXCEPTION 'RPC_ISOLATION_SCHEMA_GRANT_DRIFT';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_lf_client_session_context' AND p.prosecdef
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='programming_agent_knowledge_v1' AND p.prosecdef
  ) THEN
    RAISE EXCEPTION 'RPC_ISOLATION_SOURCE_ROUTINE_DRIFT';
  END IF;
END
$preflight$;

CREATE OR REPLACE FUNCTION lf_client.fn_lf_client_session_context_privileged_v1()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $$
DECLARE
  v_auth_user_id uuid;
  v_client_id uuid;
BEGIN
  v_auth_user_id := auth.uid();
  IF v_auth_user_id IS NULL THEN
    RETURN jsonb_build_object(
      'authenticated_principal', false,
      'authenticated_client_account', false,
      'client_id', null
    );
  END IF;

  SELECT ca.client_id INTO v_client_id
  FROM lf_client.client_accounts ca
  WHERE ca.auth_user_id = v_auth_user_id
    AND ca.disabled_at IS NULL
  LIMIT 1;

  RETURN jsonb_build_object(
    'authenticated_principal', true,
    'authenticated_client_account', v_client_id IS NOT NULL,
    'client_id', v_client_id
  );
END;
$$;

REVOKE ALL ON FUNCTION lf_client.fn_lf_client_session_context_privileged_v1() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION lf_client.fn_lf_client_session_context_privileged_v1() TO authenticated, service_role;
GRANT USAGE ON SCHEMA lf_client TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.fn_lf_client_session_context()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = pg_catalog
AS $$
  SELECT lf_client.fn_lf_client_session_context_privileged_v1()
$$;

REVOKE ALL ON FUNCTION public.fn_lf_client_session_context() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_lf_client_session_context() TO authenticated, service_role;

CREATE OR REPLACE FUNCTION transversal.programming_agent_knowledge_privileged_v1(p_source text)
RETURNS SETOF jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'authenticated user required';
  END IF;

  CASE p_source
    WHEN 'rules' THEN
      RETURN QUERY
      SELECT jsonb_build_object(
        'id', c.id,
        'control_codigo', c.control_codigo,
        'familia', c.familia,
        'nombre', c.nombre,
        'descripcion', c.descripcion,
        'modo_evaluacion', c.modo_evaluacion,
        'severidad', c.severidad,
        'tipo_resultado', c.tipo_resultado,
        'fuente_umbral', c.fuente_umbral,
        'politica_sin_fuente', c.politica_sin_fuente,
        'accion_fallo', c.accion_fallo,
        'estado', c.estado,
        'created_at', c.created_at
      )
      FROM programacion.controles_calidad c
      WHERE lower(coalesce(c.estado, '')) = 'defined'
      ORDER BY c.control_codigo;

    WHEN 'decisions' THEN
      RETURN QUERY
      SELECT jsonb_build_object(
        'id', d.id,
        'adr', d.adr,
        'titulo', d.titulo,
        'decision', d.decision,
        'razon', d.razon,
        'impacto', d.impacto,
        'estado', d.estado,
        'created_at', d.created_at
      )
      FROM transversal.decision_log d
      WHERE lower(coalesce(d.estado, '')) IN (
        'vigente', 'accepted', 'approved_plan', 'vigente_con_endurecimiento_pendiente'
      )
      ORDER BY d.adr;

    WHEN 'ekb' THEN
      RETURN QUERY
      SELECT jsonb_build_object(
        'id', e.id,
        'codigo', e.codigo,
        'categoria', e.categoria,
        'titulo', e.titulo,
        'descripcion', e.descripcion,
        'causa_raiz', e.causa_raiz,
        'patron', e.patron,
        'prevencion', e.prevencion,
        'validacion', e.validacion,
        'severidad', e.severidad,
        'estado', e.estado,
        'created_at', e.created_at,
        'updated_at', e.updated_at,
        'lifecycle_phase', e.lifecycle_phase,
        'consumer_role', e.consumer_role,
        'source_ref', e.source_ref
      )
      FROM transversal.error_knowledge e
      WHERE lower(coalesce(e.estado, '')) IN ('active', 'activo', 'open')
      ORDER BY e.codigo;

    WHEN 'preventions' THEN
      RETURN QUERY
      SELECT jsonb_build_object(
        'id', p.id,
        'regla_codigo', p.regla_codigo,
        'error_codigo', p.error_codigo,
        'regla', p.regla,
        'justificacion', p.justificacion,
        'prioridad', p.prioridad,
        'activa', p.activa,
        'created_at', p.created_at,
        'categoria', p.categoria,
        'lifecycle_phase', p.lifecycle_phase,
        'consumer_role', p.consumer_role
      )
      FROM transversal.prevention_rules p
      WHERE p.activa IS TRUE
      ORDER BY p.regla_codigo;

    WHEN 'best_practices' THEN
      RETURN QUERY
      SELECT jsonb_build_object(
        'id', b.id,
        'categoria', b.categoria,
        'titulo', b.titulo,
        'practica', b.practica,
        'evidencia', b.evidencia,
        'created_at', b.created_at
      )
      FROM transversal.best_practices b
      ORDER BY b.created_at, b.id;

    ELSE
      RAISE EXCEPTION 'unsupported knowledge source';
  END CASE;
END;
$$;

REVOKE ALL ON FUNCTION transversal.programming_agent_knowledge_privileged_v1(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION transversal.programming_agent_knowledge_privileged_v1(text) TO authenticated, service_role;
GRANT USAGE ON SCHEMA transversal TO authenticated;

CREATE OR REPLACE FUNCTION public.programming_agent_knowledge_v1(p_source text)
RETURNS SETOF jsonb
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = pg_catalog
AS $$
  SELECT * FROM transversal.programming_agent_knowledge_privileged_v1(p_source)
$$;

REVOKE ALL ON FUNCTION public.programming_agent_knowledge_v1(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.programming_agent_knowledge_v1(text) TO authenticated, service_role;

COMMENT ON FUNCTION public.fn_lf_client_session_context() IS
  'Authenticated read-only RPC wrapper. Privileged lookup is isolated in non-exposed lf_client schema.';
COMMENT ON FUNCTION public.programming_agent_knowledge_v1(text) IS
  'Authenticated read-only Programming Agent RPC wrapper. Privileged canonical reads are isolated in non-exposed transversal schema.';

-- Post-apply assertions. These deliberately preserve underlying table isolation.
DO $verify$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public'
      AND p.proname IN ('fn_lf_client_session_context','programming_agent_knowledge_v1')
      AND p.prosecdef
  ) THEN
    RAISE EXCEPTION 'RPC_ISOLATION_PUBLIC_WRAPPER_STILL_DEFINER';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='lf_client' AND p.proname='fn_lf_client_session_context_privileged_v1' AND p.prosecdef
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='transversal' AND p.proname='programming_agent_knowledge_privileged_v1' AND p.prosecdef
  ) THEN
    RAISE EXCEPTION 'RPC_ISOLATION_PRIVILEGED_HELPER_MISSING';
  END IF;

  IF has_function_privilege('anon','public.fn_lf_client_session_context()','EXECUTE')
     OR has_function_privilege('anon','public.programming_agent_knowledge_v1(text)','EXECUTE')
     OR has_function_privilege('anon','lf_client.fn_lf_client_session_context_privileged_v1()','EXECUTE')
     OR has_function_privilege('anon','transversal.programming_agent_knowledge_privileged_v1(text)','EXECUTE') THEN
    RAISE EXCEPTION 'RPC_ISOLATION_ANON_EXECUTE_REGRESSION';
  END IF;

  IF NOT has_function_privilege('authenticated','public.fn_lf_client_session_context()','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.programming_agent_knowledge_v1(text)','EXECUTE')
     OR NOT has_function_privilege('authenticated','lf_client.fn_lf_client_session_context_privileged_v1()','EXECUTE')
     OR NOT has_function_privilege('authenticated','transversal.programming_agent_knowledge_privileged_v1(text)','EXECUTE') THEN
    RAISE EXCEPTION 'RPC_ISOLATION_AUTHENTICATED_EXECUTE_REGRESSION';
  END IF;

  IF has_schema_privilege('authenticated','programacion','USAGE')
     OR has_table_privilege('authenticated','lf_client.client_accounts','SELECT')
     OR has_table_privilege('authenticated','programacion.controles_calidad','SELECT')
     OR has_table_privilege('authenticated','transversal.decision_log','SELECT')
     OR has_table_privilege('authenticated','transversal.error_knowledge','SELECT')
     OR has_table_privilege('authenticated','transversal.prevention_rules','SELECT')
     OR has_table_privilege('authenticated','transversal.best_practices','SELECT') THEN
    RAISE EXCEPTION 'RPC_ISOLATION_UNDERLYING_SOURCE_OPENED';
  END IF;
END
$verify$;

-- Rollback design for the governed migration vehicle:
-- 1) restore the exact prior public SECURITY DEFINER definitions from migrations
--    20260812044459 and 20260818184426;
-- 2) revoke authenticated/service_role USAGE on lf_client if absent in prestate;
-- 3) revoke authenticated USAGE on transversal if absent in prestate;
-- 4) drop the two *_privileged_v1 helpers;
-- 5) read back grants, function security mode, and RPC output equality.

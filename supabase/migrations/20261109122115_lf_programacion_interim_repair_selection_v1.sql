-- LF | Interim programming ownership by existing Reparador profile.
-- Scope: discovery/selection ONLY. Router ACT-0001, its transport, admission,
-- OIDC, runtime, skills, policy/ACL and write authority remain untouched.
-- User direction 2026-11-09: while the programming profile is separated later,
-- initial PROGRAMACION requests are governed by existing Reparador.
-- Derived / returning selections keep their existing candidates.
-- Candidate for ACTUALIZACION_DB_LF -> LF Migration Merge Train. No direct apply.
--
-- Source guard is the CURRENT live pg_get_functiondef MD5 at preparation:
--   public.lf_profile_selector_semantic_prepare_v2(text,text,jsonb,jsonb)
--   de64438021ab995e27cf0494862f5f23
-- Future separation: replace this interim clause through a new governed migration.

DO $lf_programacion_reparador_interim$
DECLARE
  v_signature CONSTANT text :=
    'public.lf_profile_selector_semantic_prepare_v2(text,text,jsonb,jsonb)';
  v_expected_md5 CONSTANT text := 'de64438021ab995e27cf0494862f5f23';
  v_profile CONSTANT text := 'PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF';
  v_function text;
  v_patched text;
  v_old text := $lf_old$
  where (v_channel is null or (p->'channels') ? v_channel)
    and (p->>'entry_policy'='DIRECT' or v_deriv is not null or (p->>'profile_code')=any(v_entry));$lf_old$;
  v_new text := $lf_new$
  where (v_channel is null or (p->'channels') ? v_channel)
    and (
      -- Temporary owner for INITIAL programming requests only, not a new
      -- entrypoint. Preserve the actual DERIVATION_ONLY policy; admission and
      -- every business/write action are still governed by their own contracts.
      (v_channel='PROGRAMACION' AND v_deriv IS NULL
        AND p->>'profile_code'='PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF'
        AND p->>'entry_policy'='DERIVATION_ONLY'
        AND EXISTS (
          SELECT 1 FROM public.lf_profile_write_authority_v1 a
          WHERE a.profile_code=p->>'profile_code'
            AND a.operation_code='EJECUCION_PERFIL_LF'
            AND a.status='ACTIVE'
        )
      )
      OR
      -- Do not intercept valid derived returns or change other channels.
      ((v_channel IS DISTINCT FROM 'PROGRAMACION' OR v_deriv IS NOT NULL)
        AND (p->>'entry_policy'='DIRECT' OR v_deriv IS NOT NULL
             OR (p->>'profile_code')=ANY(v_entry))
      )
    );$lf_new$;
  v_scope jsonb := '{"alcance":{"target_type":"PANTALLA"}}'::jsonb;
  v_request text := 'Programa Login B2B con las reglas y politicas aprobadas; no considerar pendientes.';
  v_before jsonb;
  v_after jsonb;
  v_product_before jsonb;
  v_operations_before jsonb;
  v_nchannel_before jsonb;
  v_bad_derivation jsonb;
BEGIN
  IF NOT EXISTS (
      SELECT 1 FROM public.lf_profile_selection_registry_v1 r
      JOIN public.lf_profile_selector_policy_v1 sp USING (profile_code)
      WHERE r.profile_code=v_profile AND r.descriptor_status='CURRENT'
        AND sp.entry_policy='DERIVATION_ONLY'
        AND 'PROGRAMACION'=ANY(sp.channels)
  ) THEN
    RAISE EXCEPTION 'LF_PROGRAMACION_REPAIR_OWNER_NOT_CURRENT';
  END IF;

  SELECT pg_get_functiondef(v_signature::regprocedure) INTO v_function;
  IF md5(v_function) IS DISTINCT FROM v_expected_md5 THEN
    RAISE EXCEPTION 'LF_PROGRAMACION_SELECTOR_SOURCE_DRIFT';
  END IF;
  IF length(v_function)-length(replace(v_function,v_old,'')) <> length(v_old) THEN
    RAISE EXCEPTION 'LF_PROGRAMACION_SELECTOR_EXACT_ANCHOR_REQUIRED';
  END IF;

  v_before:=public.lf_profile_selector_semantic_prepare_v2(
    v_request,'PROGRAMACION',NULL::jsonb,v_scope);
  v_product_before:=public.lf_profile_selector_semantic_prepare_v2(
    v_request,'PRODUCTO',NULL::jsonb,v_scope);
  v_operations_before:=public.lf_profile_selector_semantic_prepare_v2(
    v_request,'OPERACIONES',NULL::jsonb,v_scope);
  v_nchannel_before:=public.lf_profile_selector_semantic_prepare_v2(
    v_request,NULL::text,NULL::jsonb,v_scope);
  IF v_before->>'catalog_profile_count'<>'1'
     OR v_before#>>'{candidate_profiles,0,profile_code}'<>'PERFIL-UI-ARCHITECT'
  THEN
    RAISE EXCEPTION 'LF_PROGRAMACION_PRECHANGE_BASELINE_DRIFT';
  END IF;

  v_patched:=replace(v_function,v_old,v_new);
  EXECUTE v_patched;

  v_after:=public.lf_profile_selector_semantic_prepare_v2(
    v_request,'PROGRAMACION',NULL::jsonb,v_scope);
  v_bad_derivation:=public.lf_profile_selector_semantic_prepare_v2(
    v_request,'PROGRAMACION',
    '{"source_execution_id":"EXEC-NOT-REAL-INTERIM"}'::jsonb,v_scope);

  IF v_after->>'catalog_profile_count'<>'1'
     OR v_after#>>'{candidate_profiles,0,profile_code}'<>v_profile
     OR v_after#>>'{candidate_profiles,0,entry_policy}'<>'DERIVATION_ONLY'
     OR v_after->'derivation' IS DISTINCT FROM 'null'::jsonb
     OR v_after->>'route_authority'<>'false'
     OR v_after->>'effect_authority'<>'false'
     OR v_after->>'downstream_execution_allowed'<>'false'
  THEN
    RAISE EXCEPTION 'LF_PROGRAMACION_POSTCHANGE_OWNER_OR_AUTHORITY_INVALID';
  END IF;
  IF v_bad_derivation->'derivation' IS DISTINCT FROM 'null'::jsonb
     OR v_bad_derivation->'candidate_profiles' IS DISTINCT FROM
        v_after->'candidate_profiles'
  THEN
    RAISE EXCEPTION 'LF_PROGRAMACION_FORGED_DERIVATION_NOT_CLOSED';
  END IF;

  -- Regression boundary: PRODUCTO, OPERACIONES, unspecified channel identical.
  IF public.lf_profile_selector_semantic_prepare_v2(
       v_request,'PRODUCTO',NULL::jsonb,v_scope) IS DISTINCT FROM v_product_before
     OR public.lf_profile_selector_semantic_prepare_v2(
       v_request,'OPERACIONES',NULL::jsonb,v_scope) IS DISTINCT FROM v_operations_before
     OR public.lf_profile_selector_semantic_prepare_v2(
       v_request,NULL::text,NULL::jsonb,v_scope) IS DISTINCT FROM v_nchannel_before
  THEN
    RAISE EXCEPTION 'LF_PROGRAMACION_OTHER_CHANNEL_REGRESSION';
  END IF;

  -- Re-read precisely the only amended function within the same transaction.
  IF pg_get_functiondef(v_signature::regprocedure) IS DISTINCT FROM v_patched THEN
    RAISE EXCEPTION 'LF_PROGRAMACION_FUNCTION_READBACK_MISMATCH';
  END IF;
END
$lf_programacion_reparador_interim$;

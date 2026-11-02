-- Ephemeral PostgreSQL test; no production writes or credentials.
DO $checks$
DECLARE
  fallback jsonb;
  filtered jsonb;
  irrelevant jsonb;
  wrong_scope jsonb;
  verdict jsonb;
  selected jsonb;
  bad jsonb;
  active_total integer;
BEGIN
  SELECT count(*) INTO active_total
  FROM lf_ops.pantallas p JOIN lf_ops.modulos m ON m.module_id=p.module_id
  JOIN lf_ops.app_shells s ON s.app_shell_id=m.app_shell_id WHERE p.activa;

  fallback:=public.lf_profile_screen_selector_semantic_prepare_v1(
   'Revisar login B2B para identificar las reglas que le faltan',
   '{"target_type":"PANTALLA","target_hint":"login B2B","resolution_status":"UNRESOLVED"}'::jsonb);
  IF fallback->>'status'<>'READY'
    OR fallback->>'discovery_mode'<>'FULL_ACTIVE_CATALOG_FALLBACK'
    OR (fallback->>'deterministic_filtered_candidate_count')::integer<>0
    OR (fallback->>'candidate_screen_count')::integer<>active_total
    OR (fallback->>'deterministic_selection_performed')::boolean IS DISTINCT FROM false
    OR (fallback->>'effect_authority')::boolean IS DISTINCT FROM false
  THEN RAISE EXCEPTION 'FAIL_ZERO_HIT_FALLBACK:%',fallback; END IF;

  IF NOT EXISTS(select 1 from jsonb_array_elements(fallback->'candidate_screens') x
    where x->>'screen_code'='B2B-AUTH-001' and x->>'screen_name'='Iniciar sesión'
      and x->>'module_code'='B2B_AUTENTICACION')
  THEN RAISE EXCEPTION 'FAIL_CANONICAL_CANDIDATE_ABSENT'; END IF;
  IF EXISTS(select 1 from jsonb_array_elements(fallback->'candidate_screens') x
    where x->>'screen_code'='B2B-AUTH-005')
  THEN RAISE EXCEPTION 'FAIL_INACTIVE_SCREEN_LEAK'; END IF;

  filtered:=public.lf_profile_screen_selector_semantic_prepare_v1(
   'Revisar login B2B para identificar las reglas que le faltan',
   '{"target_type":"PANTALLA","target_hint":"B2B-AUTH-001"}'::jsonb);
  IF filtered->>'discovery_mode'<>'FILTERED_DETERMINISTIC'
    OR (filtered->>'candidate_screen_count')::integer<>1
    OR (filtered->>'deterministic_filtered_candidate_count')::integer<>1
  THEN RAISE EXCEPTION 'FAIL_ORIGINAL_FILTERED_PATH:%',filtered; END IF;

  irrelevant:=public.lf_profile_screen_selector_semantic_prepare_v1(
   'Pantalla meteorológica inexistente',
   '{"target_type":"PANTALLA","target_hint":"meteorología"}'::jsonb);
  IF irrelevant->>'discovery_mode'<>'FULL_ACTIVE_CATALOG_FALLBACK'
    OR (irrelevant->>'candidate_screen_count')::integer<>active_total
  THEN RAISE EXCEPTION 'FAIL_UNRELATED_FALLBACK'; END IF;
  verdict:=public.lf_profile_screen_selector_semantic_finalize_v1(
   irrelevant,jsonb_build_object(
    'decision','NO_MATCH','selected_screen_code',null,
    'ambiguous_screen_codes','[]'::jsonb,'reason','No semantic screen matches the unrelated request',
    'evidence_refs','[]'::jsonb,'material_ambiguities','[]'::jsonb));
  IF verdict->>'status'<>'VALID' OR verdict#>>'{result,decision}'<>'NO_MATCH'
  THEN RAISE EXCEPTION 'FAIL_NO_MATCH_SEMANTIC_OPTION:%',verdict; END IF;

  selected:=public.lf_profile_screen_selector_semantic_finalize_v1(
   fallback,jsonb_build_object(
    'decision','SELECTED','selected_screen_code','B2B-AUTH-001',
    'ambiguous_screen_codes','[]'::jsonb,
    'reason','Pantalla Iniciar sesión en el módulo de autenticación B2B, respaldada por nombre y módulo',
    'evidence_refs',jsonb_build_array(jsonb_build_object(
     'screen_code','B2B-AUTH-001','evidence_field','module_code')),
    'material_ambiguities','[]'::jsonb));
  IF selected->>'status'<>'VALID' OR selected#>>'{result,selected_screen_code}'<>'B2B-AUTH-001'
  THEN RAISE EXCEPTION 'FAIL_SEMANTIC_SELECTED_VALIDATION:%',selected; END IF;

  bad:=public.lf_profile_screen_selector_semantic_finalize_v1(
   filtered,jsonb_build_object('decision','SELECTED',
    'selected_screen_code','B2B-AUTH-005','ambiguous_screen_codes','[]'::jsonb,
    'reason','Fake selection outside candidate set',
    'evidence_refs',jsonb_build_array(jsonb_build_object(
     'screen_code','B2B-AUTH-005','evidence_field','screen_name')),
    'material_ambiguities','[]'::jsonb));
  IF bad->>'status'<>'BLOCKED'
  THEN RAISE EXCEPTION 'FAIL_OUTSIDE_CATALOG_NOT_BLOCKED'; END IF;

  wrong_scope:=public.lf_profile_screen_selector_semantic_prepare_v1(
   'Revisar login B2B','{"target_type":"DOCUMENTO","target_hint":"login B2B"}'::jsonb);
  IF wrong_scope->>'status'<>'NOT_APPLICABLE'
    OR (wrong_scope->>'candidate_screen_count')::integer<>0
  THEN RAISE EXCEPTION 'FAIL_NON_SCREEN_SCOPE'; END IF;

  IF NOT (fallback->'semantic_rules' ? 'FALLBACK_DOES_NOT_AUTHORIZE_AUTOMATIC_SELECTION')
  THEN RAISE EXCEPTION 'FAIL_SEMANTIC_AUTHORITY_RULE_MISSING'; END IF;
END;
$checks$;
SELECT 'PASS_SCREEN_SELECTOR_FILTER_THEN_FULL_ACTIVE_SEMANTIC' result;

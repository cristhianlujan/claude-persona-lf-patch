-- IG_CURATOR_VALIDATOR_REFACTOR_V2 · M2.1 / PAULO-017
-- Residual IG responsibility only: dynamic family -> source kind mapping and resolver regression coverage.
-- Generic normalized source identity (canonical key/scope/version lifecycle) remains owned by T-SOURCE
-- and POL-LF-SOURCE-RESOLUTION. This migration creates no parallel identity engine and no runtime activation.

DO $m2_1_probe$
DECLARE
  v_exec constant text := 'CHATGPT-IG-CV-M2-1-20261002';
  v_kind text;
  v_kinds constant text[] := ARRAY[
    'CAPABILITY_ABSENCE','CONTRACT','CURRENT_VISUAL_ARTIFACT','EKB_DECISION_SET',
    'EKB_ERROR_SET','EKB_PREVENTION_SET','ERROR_SET','MESSAGE_SET',
    'ROUTE_SET','RULE','SCREEN','SCREEN_CANONICAL_GRAPH',
    'SCREEN_RULE_SET','SCREEN_STATE_SET','SECURITY_POLICY_SET','TRANSITION_SET'
  ];
  v_ref jsonb;
  v_neg_ref jsonb;
  v_pantalla_id integer;
  v_neg_pantalla_id integer;
  v_version_id bigint;
  v_negative_rejected boolean;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.lf_test_suites
    WHERE suite_code='INPUT_GOVERNANCE_REGRESSION'
  ) THEN
    RAISE EXCEPTION 'M2_1_REGRESSION_SUITE_MISSING';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.lf_test_suite_cases
    WHERE suite_code='INPUT_GOVERNANCE_REGRESSION'
      AND test_code LIKE 'M2_1_KIND_%'
  ) THEN
    RAISE EXCEPTION 'M2_1_SOURCE_KIND_CASES_ALREADY_EXIST';
  END IF;

  FOREACH v_kind IN ARRAY v_kinds LOOP
    SELECT r.pantalla_id, r.version_id, m->'ref'
      INTO v_pantalla_id, v_version_id, v_ref
    FROM programacion.input_readiness_runs r
    CROSS JOIN LATERAL jsonb_array_elements(
      CASE WHEN jsonb_typeof(r.source_manifest)='array' THEN r.source_manifest ELSE '[]'::jsonb END
    ) m
    WHERE m->'ref'->>'kind'=v_kind
    ORDER BY programacion.fn_input_readiness_run_is_current(r.id) DESC, r.id DESC
    LIMIT 1;

    IF v_ref IS NULL THEN
      RAISE EXCEPTION 'M2_1_POSITIVE_SAMPLE_MISSING:%',v_kind;
    END IF;

    IF v_kind='SCREEN_CANONICAL_GRAPH' THEN
      v_ref := v_ref || jsonb_build_object('pantalla_id',v_pantalla_id);
    END IF;

    BEGIN
      PERFORM programacion.fn_input_resolve_source_ref(v_ref,v_pantalla_id,v_version_id);
    EXCEPTION WHEN OTHERS THEN
      RAISE EXCEPTION 'M2_1_POSITIVE_RESOLUTION_FAILED:%:%',v_kind,SQLERRM;
    END;

    v_neg_pantalla_id := v_pantalla_id;
    v_neg_ref := CASE v_kind
      WHEN 'CAPABILITY_ABSENCE' THEN jsonb_build_object('kind',v_kind,'capability','__M2_1_UNSUPPORTED__')
      WHEN 'CONTRACT' THEN jsonb_build_object('kind',v_kind,'codigo','__M2_1_MISSING_CONTRACT__')
      WHEN 'EKB_DECISION_SET' THEN jsonb_build_object('kind',v_kind,'adrs','[]'::jsonb)
      WHEN 'EKB_ERROR_SET' THEN jsonb_build_object('kind',v_kind,'codes','[]'::jsonb)
      WHEN 'EKB_PREVENTION_SET' THEN jsonb_build_object('kind',v_kind,'codes','[]'::jsonb)
      WHEN 'ERROR_SET' THEN jsonb_build_object('kind',v_kind,'ids','[]'::jsonb)
      WHEN 'MESSAGE_SET' THEN jsonb_build_object('kind',v_kind,'ids','[]'::jsonb)
      WHEN 'ROUTE_SET' THEN jsonb_build_object('kind',v_kind,'ids','[]'::jsonb)
      WHEN 'RULE' THEN jsonb_build_object('kind',v_kind,'codigo','__M2_1_MISSING_RULE__')
      WHEN 'SCREEN_CANONICAL_GRAPH' THEN jsonb_build_object('kind',v_kind)
      WHEN 'SECURITY_POLICY_SET' THEN jsonb_build_object('kind',v_kind,'ids','[]'::jsonb)
      WHEN 'TRANSITION_SET' THEN jsonb_build_object('kind',v_kind,'ids','[]'::jsonb)
      ELSE v_ref
    END;

    IF v_kind IN ('CURRENT_VISUAL_ARTIFACT','SCREEN','SCREEN_RULE_SET','SCREEN_STATE_SET') THEN
      v_neg_pantalla_id := -2147483648;
    END IF;

    v_negative_rejected := false;
    BEGIN
      PERFORM programacion.fn_input_resolve_source_ref(v_neg_ref,v_neg_pantalla_id,v_version_id);
    EXCEPTION WHEN OTHERS THEN
      v_negative_rejected := true;
    END;

    IF NOT v_negative_rejected THEN
      RAISE EXCEPTION 'M2_1_NEGATIVE_NOT_REJECTED:%',v_kind;
    END IF;
  END LOOP;
END
$m2_1_probe$;

WITH kinds(kind,ord) AS (
  VALUES
    ('CAPABILITY_ABSENCE',1),('CONTRACT',2),('CURRENT_VISUAL_ARTIFACT',3),('EKB_DECISION_SET',4),
    ('EKB_ERROR_SET',5),('EKB_PREVENTION_SET',6),('ERROR_SET',7),('MESSAGE_SET',8),
    ('ROUTE_SET',9),('RULE',10),('SCREEN',11),('SCREEN_CANONICAL_GRAPH',12),
    ('SCREEN_RULE_SET',13),('SCREEN_STATE_SET',14),('SECURITY_POLICY_SET',15),('TRANSITION_SET',16)
), polarities(polarity,pord) AS (
  VALUES ('POSITIVE',1),('NEGATIVE',2)
)
INSERT INTO public.lf_test_suite_cases(
  suite_code,test_code,test_order,story_code,rule_codes,title,test_type,execution_mode,severity,
  preconditions,input_payload,expected_output,prohibited_output,status,metadata,
  created_at,updated_at,created_by_execution_id,updated_by_execution_id
)
SELECT
  'INPUT_GOVERNANCE_REGRESSION',
  'M2_1_KIND_'||kind||'_'||polarity,
  200 + ((ord-1)*2) + pord,
  NULL,
  ARRAY[]::text[],
  'M2.1 source kind '||kind||' '||lower(polarity),
  'DETERMINISTIC','AUTOMATED','HIGH',
  jsonb_build_object('resolver','programacion.fn_input_resolve_source_ref','source_kind',kind),
  jsonb_build_object('source_kind',kind,'polarity',polarity),
  jsonb_build_object('resolver_outcome',CASE WHEN polarity='POSITIVE' THEN 'RESOLVES' ELSE 'REJECTS' END),
  '{}'::jsonb,
  'CANDIDATO',
  jsonb_build_object(
    'plan_id','IG_CURATOR_VALIDATOR_REFACTOR_V2',
    'unit_code','M2.1','work_code','PAULO-017',
    'source_kind',kind,'polarity',polarity,
    'family_to_kind_mapping','DYNAMIC_FROM_SOURCE_REFS',
    'generic_identity_owner','T-SOURCE',
    'source_resolution_policy','POL-LF-SOURCE-RESOLUTION@v1.4-transversal-supabase-authority-visual-support'
  ),
  now(),now(),'CHATGPT-IG-CV-M2-1-20261002','CHATGPT-IG-CV-M2-1-20261002'
FROM kinds CROSS JOIN polarities;

UPDATE public.lf_test_suites
SET metadata = coalesce(metadata,'{}'::jsonb) || jsonb_build_object(
      'm2_1_source_kind_identity',jsonb_build_object(
        'case_count',32,
        'kind_count',16,
        'positive_per_kind',true,
        'negative_per_kind',true,
        'family_to_kind_mapping','DYNAMIC_FROM_SOURCE_REFS',
        'generic_identity_owner','T-SOURCE',
        'source_resolution_policy','POL-LF-SOURCE-RESOLUTION@v1.4-transversal-supabase-authority-visual-support'
      )
    ),
    updated_at=now(),
    updated_by_execution_id='CHATGPT-IG-CV-M2-1-20261002'
WHERE suite_code='INPUT_GOVERNANCE_REGRESSION';

DO $m2_1_readback$
DECLARE
  v_cases integer;
  v_kinds integer;
  v_polarity_pairs integer;
BEGIN
  SELECT count(*),count(distinct metadata->>'source_kind')
    INTO v_cases,v_kinds
  FROM public.lf_test_suite_cases
  WHERE suite_code='INPUT_GOVERNANCE_REGRESSION'
    AND test_code LIKE 'M2_1_KIND_%';

  SELECT count(*) INTO v_polarity_pairs
  FROM (
    SELECT metadata->>'source_kind' kind
    FROM public.lf_test_suite_cases
    WHERE suite_code='INPUT_GOVERNANCE_REGRESSION'
      AND test_code LIKE 'M2_1_KIND_%'
    GROUP BY metadata->>'source_kind'
    HAVING count(*)=2
       AND bool_or(metadata->>'polarity'='POSITIVE')
       AND bool_or(metadata->>'polarity'='NEGATIVE')
  ) q;

  IF v_cases<>32 OR v_kinds<>16 OR v_polarity_pairs<>16 THEN
    RAISE EXCEPTION 'M2_1_CASE_READBACK_FAILED:cases=% kinds=% pairs=%',v_cases,v_kinds,v_polarity_pairs;
  END IF;
END
$m2_1_readback$;

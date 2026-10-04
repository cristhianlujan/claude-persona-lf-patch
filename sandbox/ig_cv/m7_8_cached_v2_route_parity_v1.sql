-- M7.8 permanent cached/no-cached parity regression.
-- T-EQUIV is the semantic authority: IG is exact-only, so the permitted
-- non-semantic exception list is intentionally empty.
-- Permanent behavioral sampling is intentionally bounded to exactly 3 screens:
-- one AUTH representative, one FORMS representative, and one highest-complexity
-- current screen distinct from those representatives. Screen identity is incidental.
-- Unchanged pair evidence is reused only while source fingerprints remain exact;
-- the demonstrated drift surface is behaviorally refreshed on each execution.
DO $test$
DECLARE
  v_version bigint;
  v_screen integer;
  v_graph jsonb;
  v_base jsonb;
  v_c1 jsonb;
  v_c2 jsonb;
  v_target_count integer:=0;
  v_family_count integer;
  r record;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.lf_capability_current
    WHERE capability_code='CONTROL_EQUIVALENCE_JUDGE' AND version='1.0.0'
  ) THEN RAISE EXCEPTION 'M7_8_TEQUIV_NOT_CURRENT'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.lf_operation_execution
    WHERE execution_id='T-EQUIV-IG-M7-8-20261004-V1' AND status='COMPLETED'
  ) THEN RAISE EXCEPTION 'M7_8_TEQUIV_BINDING_NOT_CURRENT'; END IF;

  SELECT count(*) INTO v_family_count
  FROM lf_ops.reglas q CROSS JOIN LATERAL jsonb_array_elements_text(q.valor_config->'families') e(value)
  WHERE q.codigo='B2B-RULE-STORY-READINESS-001';
  IF v_family_count<>47 THEN RAISE EXCEPTION 'M7_8_FAMILY_UNIVERSE_DRIFT:%',v_family_count; END IF;

  -- Reuse anchors for pairs without demonstrated drift. Any source change blocks
  -- and forces a targeted refresh instead of silently trusting old evidence.
  FOR r IN
    SELECT * FROM (VALUES
      ('fn_input_governance_semantic_probe_v1','0abfbb70b386a317d00167d8132a43cf'),
      ('fn_input_governance_semantic_probe_v1_cached_v1','dc6dca92f3a5f877415985fa7cba4027'),
      ('fn_input_governance_semantic_probe_v2','c2832adc0b4d9e510b83bf4e3e533256'),
      ('fn_input_governance_semantic_probe_v2_cached_v1','05d39a40acfbe0619b6c32253bf45d97'),
      ('fn_input_governance_semantic_probe_v3','90d680bbc36900576aad02c1080df542'),
      ('fn_input_governance_semantic_probe_v3_cached_v1','e1047708134aa796c68ebe5a62d57cb6'),
      ('fn_input_governance_bootstrap_classify_v1','8098a9ea36366446517628873263f757'),
      ('fn_input_governance_bootstrap_classify_v1_cached_v1','04cfdb8055850102bbc49123489c4f4f'),
      ('fn_input_governance_bootstrap_classify_v1_cached_v2','42e02cece283329a2a6f16063599a595'),
      ('fn_input_governance_bootstrap_classify_v2','df1415d143291f6bed6f65f2dab5f48e'),
      ('fn_input_governance_bootstrap_classify_v2_cached_v2','1b85e374531120adb80674ee41d8f827'),
      ('fn_input_governance_field_reference_probe_v1','25828c13562ab32d0aa9d3cb8e9bf0b2'),
      ('fn_input_governance_field_reference_probe_v1_cached_v1','b4fe5f8581c12596fd9e2a1642269099'),
      ('fn_input_na_positive_authority_v512','023828d5eb05d1a836145ebc9cd8a3e2'),
      ('fn_input_na_positive_authority_v512_cached_v1','dbb181d6df12c9bca188b0072c23fe10'),
      ('fn_input_readiness_run_is_current','99d54f5dcc27617831b0eb6098000777'),
      ('fn_input_readiness_run_is_current_cached_v1','99d54f5dcc27617831b0eb6098000777'),
      ('fn_input_readiness_run_is_current_cached_v2','99d54f5dcc27617831b0eb6098000777')
    ) x(proname,expected_md5)
  LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='programacion' AND p.proname=r.proname AND md5(p.prosrc)=r.expected_md5
    ) THEN RAISE EXCEPTION 'M7_8_REUSE_ANCHOR_DRIFT:%',r.proname; END IF;
  END LOOP;

  v_version := public.fn_lf_version_compatibility_current_version_id_v1(
    'PROGRAMACION_CONTRACT','INPUT_READINESS_CONTRACT','INPUT_GOVERNANCE_AGENT'
  );

  -- Exactly 3 dynamic screens: AUTH + FORMS + strongest current complexity.
  FOR v_screen IN
    WITH base_roles AS (
      SELECT 'AUTH'::text AS sample_role,pantalla_id
      FROM programacion.v_input_governance_representative_cohort_v1
      WHERE representative_rank=1 AND cohort_type_code='AUTH'
      UNION ALL
      SELECT 'FORMS'::text,pantalla_id
      FROM programacion.v_input_governance_representative_cohort_v1
      WHERE representative_rank=1 AND cohort_type_code='FORMS'
    ), latest AS (
      SELECT DISTINCT ON (r.pantalla_id) r.pantalla_id,r.id,r.source_manifest
      FROM programacion.input_readiness_runs r
      JOIN lf_ops.pantallas p ON p.id=r.pantalla_id AND p.activa
      WHERE r.version_id=v_version AND r.status='COMPLETED' AND r.invalidated_at IS NULL
      ORDER BY r.pantalla_id,r.id DESC
    ), complexity AS (
      SELECT 'COMPLEXITY'::text AS sample_role,l.pantalla_id,
             coalesce(jsonb_array_length(l.source_manifest),0)
             + coalesce(sum(CASE WHEN jsonb_typeof(a.source_refs)='array' THEN jsonb_array_length(a.source_refs) ELSE 0 END),0)
             + coalesce(sum(CASE WHEN jsonb_typeof(a.blockers)='array' THEN jsonb_array_length(a.blockers) ELSE 0 END),0) AS complexity_score
      FROM latest l JOIN programacion.input_family_assessments a ON a.run_id=l.id
      WHERE programacion.fn_input_readiness_run_is_current(l.id)
        AND l.pantalla_id NOT IN (SELECT pantalla_id FROM base_roles)
      GROUP BY l.pantalla_id,l.source_manifest
      ORDER BY complexity_score DESC,l.pantalla_id LIMIT 1
    ), targets AS (
      SELECT sample_role,pantalla_id FROM base_roles
      UNION ALL
      SELECT sample_role,pantalla_id FROM complexity
    )
    SELECT pantalla_id FROM targets ORDER BY sample_role,pantalla_id
  LOOP
    v_target_count:=v_target_count+1;
    v_graph:=programacion.fn_input_screen_canonical_graph(v_screen,v_version);
    v_base:=programacion.fn_input_governance_bootstrap_classify_v2(v_screen,'VISUAL_EVIDENCE',v_version);
    v_c1:=programacion.fn_input_governance_bootstrap_classify_v2_cached_v1(v_screen,'VISUAL_EVIDENCE',v_version,v_graph);
    v_c2:=programacion.fn_input_governance_bootstrap_classify_v2_cached_v2(v_screen,'VISUAL_EVIDENCE',v_version,v_graph);
    IF v_base IS DISTINCT FROM v_c1 OR v_base IS DISTINCT FROM v_c2 THEN
      RAISE EXCEPTION 'M7_8_VISUAL_CACHED_PARITY_FAILED:screen=%',v_screen;
    END IF;
    -- Negative: an observable mutation must never be accepted as equivalent.
    IF v_base IS NOT DISTINCT FROM (v_c1 || jsonb_build_object('__m7_8_negative__',true)) THEN
      RAISE EXCEPTION 'M7_8_FALSE_PASS_NEGATIVE_FAILED:screen=%',v_screen;
    END IF;
  END LOOP;

  IF v_target_count<>3 THEN RAISE EXCEPTION 'M7_8_SAMPLE_SIZE_DRIFT:expected=3:got=%',v_target_count; END IF;
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname IN ('programacion','public','private')
      AND p.proname<>'fn_input_governance_bootstrap_classify_v2_cached_v1'
      AND position('fn_input_governance_bootstrap_classify_v2_cached_v1' in p.prosrc)>0
  ) THEN RAISE EXCEPTION 'M7_8_CACHED_V1_LIVE_CALLER_FOUND'; END IF;
END
$test$;

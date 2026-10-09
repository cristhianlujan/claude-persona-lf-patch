-- IG package 3: per-family minimum test floor, written into the registry and checked deterministically.
-- Scope: (1) INPUT_FAMILY_POLICY_REGISTRY gets a top-level test_floor_policy (families payload and
-- registry_sha256 are NOT touched); (2) one new matrix manifest case with the extra cells the policy implies;
-- (3) one read-only check function. No Curator/Validator rewiring, no new suite, no new test engine.
--
-- Rule (owner delegated the number to Claude on 2026-10-08: "no fixes a number, each one must have an acceptable
-- minimum"): every family needs the 6 base kinds already in the M7.5 matrix; a kind is omitted only with reason,
-- authority and evidence. A family adds one kind per property it declares:
--   complete_criteria_v1 present            -> COMPLETITUD
--   stage_policy.conditional = true         -> ELEGIBILIDAD
--   stage_policy.coverage_required_by in QA/PRODUCTION -> LIMITE_ETAPA
-- Extra cells reuse existing M7.3 negatives (no new case is invented): 038, 027 and 044.
-- The extras are Claude's criterion about what each property implies and can be adjusted by the owner.

DO $ig_floor_registry$
DECLARE
  c_migration constant text := 'supabase/migrations/20261009050000_ig_family_test_floor_v1.sql';
  v_id bigint;
  v_spec jsonb;
  v_sha_before text;
  v_policy jsonb;
BEGIN
  SELECT c.id, c.especificacion INTO v_id, v_spec
  FROM programacion.contratos c
  WHERE c.contrato_codigo='INPUT_FAMILY_POLICY_REGISTRY' AND c.estado='defined' AND c.fail_closed
  ORDER BY c.id DESC LIMIT 1 FOR UPDATE;
  IF v_id IS NULL THEN RAISE EXCEPTION 'IG_FLOOR_REGISTRY_NOT_FOUND'; END IF;
  IF (v_spec->>'family_count')::int <> 47
     OR v_spec->>'registry_sha256' IS DISTINCT FROM programacion.fn_v09_sha256_jsonb(v_spec->'families') THEN
    RAISE EXCEPTION 'IG_FLOOR_REGISTRY_INCONSISTENT';
  END IF;
  IF v_spec #>> '{test_floor_policy,schema_version}' = 'IG_FAMILY_TEST_FLOOR_V1' THEN RETURN; END IF;
  v_sha_before := v_spec->>'registry_sha256';

  v_policy := jsonb_build_object(
    'schema_version','IG_FAMILY_TEST_FLOOR_V1',
    'authority','OWNER_DELEGATED_2026-10-08',
    'base_kinds',jsonb_build_array('POSITIVO','NEGATIVO','FALTANTE','CONTRADICCION','STALE','MUTACION'),
    'extra_kinds',jsonb_build_array(
      jsonb_build_object('kind','COMPLETITUD','when','family declares complete_criteria_v1',
        'test_code','M7_3_NEG_038_FAMILY_COMPLETE_WITH_INCOMPLETE_SUBJECT'),
      jsonb_build_object('kind','ELEGIBILIDAD','when','stage_policy.conditional is true',
        'test_code','M7_3_NEG_027_IMPLEMENTATION_READY_WITH_INCOMPLETE_COVERAGE'),
      jsonb_build_object('kind','LIMITE_ETAPA','when','stage_policy.coverage_required_by is QA or PRODUCTION',
        'test_code','M7_3_NEG_044_LATER_STAGE_GAP_BLOCKS_EARLIER_STAGE',
        'stages',jsonb_build_array('QA','PRODUCTION'))),
    'omission_rule','N/A_REQUIRES_REASON_AUTHORITY_EVIDENCE',
    'extra_manifest_test_code','M7_5_FLOOR_EXTRAS_MANIFEST',
    'base_manifest_test_code','M7_5_MATRIX_47X6_MANIFEST',
    'suite_code','INPUT_GOVERNANCE_REGRESSION');

  UPDATE programacion.contratos
     SET especificacion = jsonb_set(jsonb_set(jsonb_set(v_spec,'{test_floor_policy}',v_policy),
                          '{contract_revision}',to_jsonb('1.2.0'::text)),
                          '{source_migration}',to_jsonb(c_migration))
   WHERE id = v_id;

  SELECT especificacion INTO v_spec FROM programacion.contratos WHERE id=v_id;
  IF v_spec->>'registry_sha256' IS DISTINCT FROM v_sha_before
     OR v_spec->>'registry_sha256' IS DISTINCT FROM programacion.fn_v09_sha256_jsonb(v_spec->'families')
     OR v_spec #>> '{test_floor_policy,schema_version}' IS DISTINCT FROM 'IG_FAMILY_TEST_FLOOR_V1' THEN
    RAISE EXCEPTION 'IG_FLOOR_REGISTRY_READBACK_MISMATCH';
  END IF;
END
$ig_floor_registry$;

DO $ig_floor_cells$
DECLARE
  v_spec jsonb;
  v_cells jsonb;
  v_n int;
BEGIN
  IF EXISTS (SELECT 1 FROM public.lf_test_suite_cases WHERE test_code='M7_5_FLOOR_EXTRAS_MANIFEST') THEN RETURN; END IF;
  SELECT c.especificacion INTO v_spec FROM programacion.contratos c
  WHERE c.contrato_codigo='INPUT_FAMILY_POLICY_REGISTRY' AND c.estado='defined' AND c.fail_closed
  ORDER BY c.id DESC LIMIT 1;

  WITH fam AS (
    SELECT f.key fam, f.value v FROM jsonb_each(v_spec->'families') f
  ), extra AS (
    SELECT fam, 'COMPLETITUD' kind FROM fam WHERE v ? 'complete_criteria_v1'
    UNION ALL
    SELECT fam, 'ELEGIBILIDAD' FROM fam WHERE coalesce((v->'stage_policy'->>'conditional')::boolean,false)
    UNION ALL
    SELECT fam, 'LIMITE_ETAPA' FROM fam WHERE v->'stage_policy'->>'coverage_required_by' IN ('QA','PRODUCTION')
  ), pol AS (
    SELECT e->>'kind' kind, e->>'test_code' test_code FROM jsonb_array_elements(v_spec #> '{test_floor_policy,extra_kinds}') e
  )
  SELECT jsonb_agg(jsonb_build_object(
           'oracle','ASSURANCE_EVALUATOR@1.0.0',
           'q_class',k.metadata->>'q_class',
           'evidence',jsonb_build_object(
              'locator','latest run_id; family_code='||x.fam,
              'authority','programacion.input_family_assessments',
              'floor_policy','INPUT_FAMILY_POLICY_REGISTRY.test_floor_policy',
              'name_similarity_coverage_forbidden',true),
           'expected','REJECT_MUTATION_FAIL_CLOSED',
           'property','FAMILY_TEST_FLOOR_'||x.kind,
           'dimension','SEMANTIC',
           'test_code',p.test_code,
           'test_kind',x.kind,
           'resolution','TEST_CODE',
           'family_code',x.fam) ORDER BY x.fam, x.kind),
         count(*)
    INTO v_cells, v_n
  FROM extra x JOIN pol p ON p.kind=x.kind
  JOIN public.lf_test_suite_cases k ON k.test_code=p.test_code;

  IF v_n IS DISTINCT FROM 18 THEN RAISE EXCEPTION 'IG_FLOOR_EXTRA_CELLS_UNEXPECTED_COUNT:%', coalesce(v_n,-1); END IF;

  INSERT INTO public.lf_test_suite_cases
    (suite_code,test_code,test_order,story_code,rule_codes,title,test_type,execution_mode,severity,
     preconditions,input_payload,expected_output,prohibited_output,status,metadata,created_by_execution_id,updated_by_execution_id)
  SELECT m.suite_code,'M7_5_FLOOR_EXTRAS_MANIFEST',
         (SELECT max(test_order)+1 FROM public.lf_test_suite_cases WHERE suite_code=m.suite_code),
         m.story_code,m.rule_codes,
         'IG package 3 per-family test floor - extra cells manifest',
         m.test_type,m.execution_mode,m.severity,
         jsonb_build_object('parent_manifest','M7_5_MATRIX_47X6_MANIFEST','expected_cell_count',18,'policy','INPUT_FAMILY_POLICY_REGISTRY.test_floor_policy'),
         jsonb_build_object('schema_version','M7_5_FLOOR_EXTRAS_INPUT_V1','suite_authority',m.suite_code,'family_authority','programacion.input_family_assessments'),
         jsonb_build_object('cells',18,'na_policy','EXPLICIT_REASON_AUTHORITY_EVIDENCE_REQUIRED','orphan_cells',0,'omitted_cells',0),
         m.prohibited_output,'CANDIDATO',
         jsonb_build_object('matrix_version','M7_5_FLOOR_EXTRAS_V1','cell_count',18,'parent_manifest','M7_5_MATRIX_47X6_MANIFEST',
           'matrix_cells',v_cells,'no_parallel_suite',true,'no_parallel_taxonomy',true,'no_parallel_test_engine',true,
           'q_class','Q1','property','FAMILY_TEST_FLOOR_CELL_COMPLETENESS','dimension','STRUCTURAL',
           'na_policy','N/A_REQUIRES_REASON_AUTHORITY_EVIDENCE','unit_code','IG-PKG3'),
         'CLAUDE-IG-PKG3-FAMILY-TEST-FLOOR-20261009','CLAUDE-IG-PKG3-FAMILY-TEST-FLOOR-20261009'
  FROM public.lf_test_suite_cases m WHERE m.test_code='M7_5_MATRIX_47X6_MANIFEST';

  IF (SELECT jsonb_array_length(metadata->'matrix_cells') FROM public.lf_test_suite_cases WHERE test_code='M7_5_FLOOR_EXTRAS_MANIFEST') <> 18 THEN
    RAISE EXCEPTION 'IG_FLOOR_EXTRA_CELLS_READBACK_MISMATCH';
  END IF;
END
$ig_floor_cells$;

CREATE OR REPLACE FUNCTION programacion.fn_input_family_test_floor_check_v1()
 RETURNS TABLE(family_code text, required_kinds text[], present_kinds text[], missing_kinds text[],
               orphan_test_codes text[], required_count integer, present_count integer, status text)
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog'
AS $fn$
WITH reg AS (
  SELECT c.especificacion s FROM programacion.contratos c
  WHERE c.contrato_codigo='INPUT_FAMILY_POLICY_REGISTRY' AND c.estado='defined' AND c.fail_closed
  ORDER BY c.id DESC LIMIT 1
), pol AS (
  SELECT s #> '{test_floor_policy}' p, s FROM reg
), fam AS (
  SELECT f.key fam, f.value v, pol.p FROM pol, jsonb_each(pol.s->'families') f
), req AS (
  SELECT fam, k kind FROM fam, jsonb_array_elements_text(p->'base_kinds') k
  UNION ALL SELECT fam, 'COMPLETITUD' FROM fam WHERE v ? 'complete_criteria_v1'
  UNION ALL SELECT fam, 'ELEGIBILIDAD' FROM fam WHERE coalesce((v->'stage_policy'->>'conditional')::boolean,false)
  UNION ALL SELECT fam, 'LIMITE_ETAPA' FROM fam
    WHERE v->'stage_policy'->>'coverage_required_by' IN
      (SELECT jsonb_array_elements_text(e->'stages') FROM jsonb_array_elements(p->'extra_kinds') e WHERE e->>'kind'='LIMITE_ETAPA')
), cells AS (
  SELECT c->>'family_code' fam, c->>'test_kind' kind, c->>'test_code' tc
  FROM public.lf_test_suite_cases k, jsonb_array_elements(k.metadata->'matrix_cells') c
  WHERE k.test_code IN ('M7_5_MATRIX_47X6_MANIFEST','M7_5_FLOOR_EXTRAS_MANIFEST')
), ok_cells AS (
  SELECT c.* FROM cells c WHERE EXISTS (SELECT 1 FROM public.lf_test_suite_cases t WHERE t.test_code=c.tc)
), agg AS (
  SELECT f.fam,
    coalesce((SELECT array_agg(DISTINCT r.kind ORDER BY r.kind) FROM req r WHERE r.fam=f.fam),'{}') required,
    coalesce((SELECT array_agg(DISTINCT o.kind ORDER BY o.kind) FROM ok_cells o WHERE o.fam=f.fam),'{}') present,
    coalesce((SELECT array_agg(DISTINCT c.tc ORDER BY c.tc) FROM cells c WHERE c.fam=f.fam
              AND NOT EXISTS (SELECT 1 FROM public.lf_test_suite_cases t WHERE t.test_code=c.tc)),'{}') orphans
  FROM fam f
)
SELECT a.fam, a.required, a.present,
  coalesce((SELECT array_agg(x ORDER BY x) FROM unnest(a.required) x WHERE x<>ALL(a.present)),'{}'),
  a.orphans, cardinality(a.required),
  cardinality(coalesce((SELECT array_agg(x) FROM unnest(a.required) x WHERE x=ANY(a.present)),'{}')),
  CASE WHEN cardinality(a.orphans)>0 THEN 'ORPHAN_CELL'
       WHEN EXISTS (SELECT 1 FROM unnest(a.required) x WHERE x<>ALL(a.present)) THEN 'MISSING_CELLS'
       ELSE 'OK' END
FROM agg a ORDER BY a.fam
$fn$;

DO $ig_floor_readback$
DECLARE v_total int; v_ok int; v_rows int;
BEGIN
  SELECT count(*), count(*) FILTER (WHERE status='OK'), coalesce(sum(required_count),0)
    INTO v_rows, v_ok, v_total FROM programacion.fn_input_family_test_floor_check_v1();
  IF v_rows<>47 OR v_ok<>47 OR v_total<>300 THEN
    RAISE EXCEPTION 'IG_FLOOR_READBACK_MISMATCH rows=% ok=% total=%', v_rows, v_ok, v_total;
  END IF;
END
$ig_floor_readback$;

-- T-INDEP / PAULO-035 — real oracle independence measurement for INDEPENDENT_ASSURANCE.
-- Owner: SUPER_ADMIN.
-- Scope: reusable, read-only measurement + capability currentness materialization.
-- This migration deliberately does NOT modify the canonical review operation, route, steps or judges.
-- EKB: T-INDEP-PARALLEL-REVIEW-STACK-001; T-INDEP-OPERATION-REVISION-REQUALIFICATION-001.

DO $pre$
DECLARE
  v_revision text;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.lf_activos
    WHERE codigo_activo='INDEPENDENT_ASSURANCE'
      AND archived_at IS NULL
      AND estado_operativo='ACTIVO'
      AND estado_documental='VIGENTE'
  ) THEN
    RAISE EXCEPTION 'BLOCK_T_INDEP_INDEPENDENT_ASSURANCE_ASSET_NOT_CURRENT';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_operation_registry
    WHERE operation_code='REVISION_INDEPENDIENTE_ESTRATEGIA_LF'
      AND operation_type='INDEPENDENT_REVIEW'
      AND lifecycle_state_code='OP_OPERATIONAL'
  ) THEN
    RAISE EXCEPTION 'BLOCK_T_INDEP_CANONICAL_REVIEW_OPERATION_NOT_OPERATIONAL';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.lf_operation_registry
    WHERE operation_code='REVISION_INDEPENDIENTE_LF'
  ) THEN
    RAISE EXCEPTION 'BLOCK_T_INDEP_PARALLEL_REVIEW_STACK_PRESENT';
  END IF;

  v_revision := public.lf_operation_revision_sha256_v1('REVISION_INDEPENDIENTE_ESTRATEGIA_LF');
  IF v_revision IS NULL OR v_revision !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'BLOCK_T_INDEP_CANONICAL_OPERATION_REVISION_UNREADABLE';
  END IF;
END $pre$;

CREATE OR REPLACE FUNCTION public.lf_independent_assurance_measure_v1(
  p_dependency_schema text,
  p_producer_root text,
  p_reviewer_root text,
  p_max_depth integer DEFAULT 8,
  p_context jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public, extensions
AS $fn$
DECLARE
  v_producer_deps text[] := '{}'::text[];
  v_reviewer_deps text[] := '{}'::text[];
  v_shared text[] := '{}'::text[];
  v_exceptions text[] := '{}'::text[];
  v_unknown_exceptions text[] := '{}'::text[];
  v_unresolved text[] := '{}'::text[];
  v_producer_data text[] := '{}'::text[];
  v_reviewer_data text[] := '{}'::text[];
  v_shared_data text[] := '{}'::text[];
  v_dependency_state text;
  v_data_state text := 'UNPROVEN';
  v_author_state text := 'UNPROVEN';
  v_overall_state text;
  v_producer_author text;
  v_reviewer_author text;
  v_dependency_digest text;
  v_reviewer_digest text;
BEGIN
  IF nullif(btrim(coalesce(p_dependency_schema,'')),'') IS NULL
     OR nullif(btrim(coalesce(p_producer_root,'')),'') IS NULL
     OR nullif(btrim(coalesce(p_reviewer_root,'')),'') IS NULL
     OR p_max_depth < 1 OR p_max_depth > 16
     OR p_context IS NULL OR jsonb_typeof(p_context) <> 'object' THEN
    RETURN jsonb_build_object(
      'schema_version','LF_INDEPENDENT_ASSURANCE_MEASURE_V1',
      'state','BLOCKED',
      'code','MEASURE_INPUT_INVALID'
    );
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_namespace WHERE nspname=p_dependency_schema) THEN
    RETURN jsonb_build_object(
      'schema_version','LF_INDEPENDENT_ASSURANCE_MEASURE_V1',
      'state','BLOCKED',
      'code','DEPENDENCY_SCHEMA_NOT_FOUND',
      'dependency_schema',p_dependency_schema
    );
  END IF;

  IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname=p_dependency_schema AND p.proname=p_producer_root) <> 1
     OR (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
         WHERE n.nspname=p_dependency_schema AND p.proname=p_reviewer_root) <> 1 THEN
    RETURN jsonb_build_object(
      'schema_version','LF_INDEPENDENT_ASSURANCE_MEASURE_V1',
      'state','BLOCKED',
      'code','ROOT_FUNCTION_NOT_UNIQUE_OR_MISSING',
      'producer_root',p_producer_root,
      'reviewer_root',p_reviewer_root
    );
  END IF;

  IF p_context ? 'adjudicated_dependency_exceptions'
     AND jsonb_typeof(p_context->'adjudicated_dependency_exceptions') <> 'array' THEN
    RETURN jsonb_build_object('schema_version','LF_INDEPENDENT_ASSURANCE_MEASURE_V1','state','BLOCKED','code','EXCEPTIONS_NOT_ARRAY');
  END IF;
  IF p_context ? 'producer_data_refs' AND jsonb_typeof(p_context->'producer_data_refs') <> 'array' THEN
    RETURN jsonb_build_object('schema_version','LF_INDEPENDENT_ASSURANCE_MEASURE_V1','state','BLOCKED','code','PRODUCER_DATA_REFS_NOT_ARRAY');
  END IF;
  IF p_context ? 'reviewer_data_refs' AND jsonb_typeof(p_context->'reviewer_data_refs') <> 'array' THEN
    RETURN jsonb_build_object('schema_version','LF_INDEPENDENT_ASSURANCE_MEASURE_V1','state','BLOCKED','code','REVIEWER_DATA_REFS_NOT_ARRAY');
  END IF;

  WITH RECURSIVE
  funcs AS (
    SELECT p.proname COLLATE "C" AS proname, lower(p.prosrc) COLLATE "C" AS src
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname=p_dependency_schema
  ),
  roots(root_name) AS (
    VALUES (p_producer_root::text COLLATE "C"), (p_reviewer_root::text COLLATE "C")
  ),
  walk(root_name,fn_name,depth,path) AS (
    SELECT r.root_name,r.root_name,0,array[r.root_name]::text[] FROM roots r
    UNION ALL
    SELECT w.root_name,d.proname,w.depth+1,w.path||d.proname
    FROM walk w
    JOIN funcs s ON s.proname=w.fn_name
    JOIN funcs d ON position(lower(d.proname)||'(' in s.src)>0
    WHERE w.depth<p_max_depth AND NOT d.proname=ANY(w.path)
  )
  SELECT
    coalesce(array_agg(DISTINCT fn_name ORDER BY fn_name) FILTER (WHERE root_name=p_producer_root AND depth>0),'{}'::text[]),
    coalesce(array_agg(DISTINCT fn_name ORDER BY fn_name) FILTER (WHERE root_name=p_reviewer_root AND depth>0),'{}'::text[])
  INTO v_producer_deps,v_reviewer_deps
  FROM walk;

  SELECT coalesce(array_agg(x ORDER BY x),'{}'::text[])
    INTO v_shared
  FROM (
    SELECT unnest(v_producer_deps) x
    INTERSECT
    SELECT unnest(v_reviewer_deps) x
  ) q;

  IF p_context ? 'adjudicated_dependency_exceptions' THEN
    SELECT coalesce(array_agg(DISTINCT v ORDER BY v),'{}'::text[])
      INTO v_exceptions
    FROM jsonb_array_elements_text(p_context->'adjudicated_dependency_exceptions') t(v);
  END IF;

  SELECT coalesce(array_agg(x ORDER BY x),'{}'::text[])
    INTO v_unknown_exceptions
  FROM (
    SELECT unnest(v_exceptions) x
    EXCEPT
    SELECT unnest(v_shared) x
  ) q;

  IF cardinality(v_unknown_exceptions)>0 THEN
    RETURN jsonb_build_object(
      'schema_version','LF_INDEPENDENT_ASSURANCE_MEASURE_V1',
      'state','BLOCKED',
      'code','UNBOUND_ADJUDICATED_EXCEPTION',
      'unknown_exceptions',to_jsonb(v_unknown_exceptions)
    );
  END IF;

  SELECT coalesce(array_agg(x ORDER BY x),'{}'::text[])
    INTO v_unresolved
  FROM (
    SELECT unnest(v_shared) x
    EXCEPT
    SELECT unnest(v_exceptions) x
  ) q;

  v_dependency_state := CASE WHEN cardinality(v_unresolved)=0 THEN 'INDEPENDENT' ELSE 'NOT_INDEPENDENT' END;

  IF p_context ? 'producer_data_refs' AND p_context ? 'reviewer_data_refs' THEN
    SELECT coalesce(array_agg(DISTINCT v ORDER BY v),'{}'::text[])
      INTO v_producer_data FROM jsonb_array_elements_text(p_context->'producer_data_refs') t(v);
    SELECT coalesce(array_agg(DISTINCT v ORDER BY v),'{}'::text[])
      INTO v_reviewer_data FROM jsonb_array_elements_text(p_context->'reviewer_data_refs') t(v);
    SELECT coalesce(array_agg(x ORDER BY x),'{}'::text[])
      INTO v_shared_data
    FROM (
      SELECT unnest(v_producer_data) x
      INTERSECT
      SELECT unnest(v_reviewer_data) x
    ) q;
    v_data_state := CASE WHEN cardinality(v_shared_data)=0 THEN 'INDEPENDENT' ELSE 'NOT_INDEPENDENT' END;
  END IF;

  v_producer_author := nullif(btrim(coalesce(p_context->>'producer_author_ref','')),'');
  v_reviewer_author := nullif(btrim(coalesce(p_context->>'reviewer_author_ref','')),'');
  IF v_producer_author IS NOT NULL AND v_reviewer_author IS NOT NULL THEN
    v_author_state := CASE WHEN v_producer_author IS DISTINCT FROM v_reviewer_author THEN 'INDEPENDENT' ELSE 'NOT_INDEPENDENT' END;
  END IF;

  IF 'NOT_INDEPENDENT'=ANY(ARRAY[v_dependency_state,v_data_state,v_author_state]) THEN
    v_overall_state := 'NOT_INDEPENDENT';
  ELSIF v_dependency_state='INDEPENDENT' AND v_data_state='INDEPENDENT' AND v_author_state='INDEPENDENT' THEN
    v_overall_state := 'INDEPENDENT';
  ELSE
    v_overall_state := 'UNPROVEN';
  END IF;

  v_dependency_digest := encode(extensions.digest(convert_to(to_jsonb(v_producer_deps)::text,'UTF8'),'sha256'),'hex');
  v_reviewer_digest := encode(extensions.digest(convert_to(to_jsonb(v_reviewer_deps)::text,'UTF8'),'sha256'),'hex');

  RETURN jsonb_build_object(
    'schema_version','LF_INDEPENDENT_ASSURANCE_MEASURE_V1',
    'state',v_overall_state,
    'method','PG_PROC_STATIC_CLOSURE_V1',
    'limitations',jsonb_build_array('NO_DYNAMIC_SQL','NO_EDGE_RUNTIME_CALL_GRAPH','FUNCTION_NAME_MATCH_WITHIN_DECLARED_SCHEMA'),
    'dependency_schema',p_dependency_schema,
    'max_depth',p_max_depth,
    'producer_root',p_producer_root,
    'reviewer_root',p_reviewer_root,
    'dependency_dimension',jsonb_build_object(
      'state',v_dependency_state,
      'producer_dependency_count',cardinality(v_producer_deps),
      'reviewer_dependency_count',cardinality(v_reviewer_deps),
      'shared_dependency_count',cardinality(v_shared),
      'unresolved_shared_dependency_count',cardinality(v_unresolved),
      'adjudicated_exception_count',cardinality(v_exceptions),
      'producer_dependency_digest',v_dependency_digest,
      'reviewer_dependency_digest',v_reviewer_digest,
      'shared_dependencies',to_jsonb(v_shared),
      'unresolved_shared_dependencies',to_jsonb(v_unresolved),
      'adjudicated_dependency_exceptions',to_jsonb(v_exceptions)
    ),
    'data_dimension',jsonb_build_object(
      'state',v_data_state,
      'shared_data_refs',to_jsonb(v_shared_data)
    ),
    'author_dimension',jsonb_build_object(
      'state',v_author_state,
      'producer_author_ref',v_producer_author,
      'reviewer_author_ref',v_reviewer_author
    ),
    'criterion','INDEPENDENT only when dependency overlap after adjudicated exceptions is zero AND data sources are disjoint AND producer/reviewer author identities are distinct; any proven shared dimension => NOT_INDEPENDENT; missing data/author evidence => UNPROVEN unless another dimension is already NOT_INDEPENDENT'
  );
END
$fn$;

REVOKE ALL ON FUNCTION public.lf_independent_assurance_measure_v1(text,text,text,integer,jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.lf_independent_assurance_measure_v1(text,text,text,integer,jsonb) TO service_role;

DO $cutover$
DECLARE
  v_execution_id constant text := 'CHATGPT-T-INDEP-PAULO-035-20261002';
  v_revision_before text;
  v_revision_after text;
  v_manifest jsonb;
  v_manifest_sha text;
  v_existing_sha text;
  v_promote jsonb;
BEGIN
  v_revision_before := public.lf_operation_revision_sha256_v1('REVISION_INDEPENDIENTE_ESTRATEGIA_LF');

  UPDATE public.lf_activos
  SET owner_name='SUPER_ADMIN',
      metadata=jsonb_set(
        jsonb_set(
          coalesce(metadata,'{}'::jsonb) || jsonb_build_object(
            'oracle_independence_v1',jsonb_build_object(
              'schema_version','LF_INDEPENDENT_ASSURANCE_ORACLE_INDEPENDENCE_V1',
              'measure_function','public.lf_independent_assurance_measure_v1',
              'method','PG_PROC_STATIC_CLOSURE_V1',
              'default_max_depth',8,
              'dimensions',jsonb_build_array('DEPENDENCIES','DATA','AUTHOR'),
              'decision_states',jsonb_build_array('INDEPENDENT','NOT_INDEPENDENT','UNPROVEN','BLOCKED'),
              'exception_policy','ONLY_EXPLICIT_ADJUDICATED_SHARED_DEPENDENCIES',
              'consumer_unit','M4.4',
              'executor_unit','T-INDEP',
              'work_code','PAULO-035'
            )
          ),
          '{transversal_inventory,physical_assets}',
          jsonb_build_array('REVISION_INDEPENDIENTE_ESTRATEGIA_LF','public.lf_independent_assurance_measure_v1'),
          true
        ),
        '{transversal_inventory,gap}',
        to_jsonb('real oracle independence is now measurable; consumers must still provide data/author evidence or remain UNPROVEN'::text),
        true
      ),
      updated_at=clock_timestamp(),
      updated_by_execution_id=v_execution_id
  WHERE codigo_activo='INDEPENDENT_ASSURANCE' AND archived_at IS NULL;

  v_manifest:=jsonb_build_object(
    'schema_version','LF_CAPABILITY_MANIFEST_V1',
    'capability_code','INDEPENDENT_ASSURANCE',
    'version','1.0.0',
    'owner','SUPER_ADMIN',
    'contract',jsonb_build_object(
      'input','dependency_schema + producer_root + reviewer_root + optional provider-bound data/author evidence + adjudicated exceptions',
      'output','LF_INDEPENDENT_ASSURANCE_MEASURE_V1',
      'authority','READ_ONLY_FAIL_CLOSED_ORACLE_INDEPENDENCE_MEASUREMENT'
    ),
    'delivery',jsonb_build_object(
      'mode','SUPABASE_NATIVE_READ_ONLY_MEASURE_PLUS_EXISTING_REVIEW_OPERATION',
      'measure_function','public.lf_independent_assurance_measure_v1',
      'canonical_review_operation','REVISION_INDEPENDIENTE_ESTRATEGIA_LF'
    ),
    'installation',jsonb_build_object(
      'required',false,
      'reinstall_required',false,
      'package_update_mode','DATABASE_NATIVE_CUTOVER'
    ),
    'dependencies',jsonb_build_object(
      'governance',jsonb_build_array('LF_GOVERNANCE','ORCHESTRATOR_EXECUTION_GUARD_V1'),
      'canonical_operation',jsonb_build_array('REVISION_INDEPENDIENTE_ESTRATEGIA_LF')
    ),
    'compatibility',jsonb_build_object(
      'parallel_review_operation',false,
      'parallel_route',false,
      'new_judge_codes',false,
      'canonical_operation_revision_change',false,
      'strategy_review_behavior_changed',false,
      'runtime_activation',false,
      'production_activation',false
    ),
    'measurement',jsonb_build_object(
      'method','PG_PROC_STATIC_CLOSURE_V1',
      'max_depth_default',8,
      'dimensions',jsonb_build_array('DEPENDENCIES','DATA','AUTHOR'),
      'dependency_pass_condition','ZERO_UNRESOLVED_SHARED_TRANSITIVE_DEPENDENCIES',
      'limitations',jsonb_build_array('NO_DYNAMIC_SQL','NO_EDGE_RUNTIME_CALL_GRAPH')
    ),
    'usage',jsonb_build_object(
      'entrypoint','public.fn_lf_capability_bind_from_orchestrator_v1',
      'measure','public.lf_independent_assurance_measure_v1',
      'docs','sandbox/lf_contract_gate_test/transversal_assets/independent_assurance/README.md'
    ),
    'currentness',jsonb_build_object(
      'authority_ref','github://cristhianlujan/claude-persona-lf-patch/supabase/migrations/20261003001000_independent_assurance_oracle_independence_measure_v1.sql',
      'source_revision_immutable',false,
      'verification','MIGRATION_SOURCE_PARITY_REQUIRED_POST_MERGE'
    ),
    'migration',jsonb_build_object(
      'work_code','PAULO-035',
      'unit_code','T-INDEP',
      'mode','CAPABILITY_REGISTRY_CURRENTNESS_PLUS_READ_ONLY_MEASURE',
      'operation_revision_mutation',false
    ),
    'rollback',jsonb_build_object(
      'supported',true,
      'mode','TRANSACTIONAL_ROLLBACK_PROBE_AND_CURRENT_POINTER_RESTORE',
      'rule','remove INDEPENDENT_ASSURANCE current/version/registry entries introduced by this change, restore prior asset metadata, drop only lf_independent_assurance_measure_v1; do not mutate canonical review operation'
    )
  );
  v_manifest_sha:=encode(extensions.digest(convert_to(v_manifest::text,'UTF8'),'sha256'),'hex');

  INSERT INTO public.lf_capability_registry(
    capability_code,capability_name,capability_kind,owner_scope,status,description,
    created_by_execution_id,updated_by_execution_id,entry_guard_required,entry_guard_code
  ) VALUES (
    'INDEPENDENT_ASSURANCE','Independent Assurance','TRANSVERSAL','SUPER_ADMIN','ACTIVE',
    'Existing canonical independent-review capability plus reusable fail-closed real-oracle independence measurement.',
    v_execution_id,v_execution_id,true,'ORCHESTRATOR_EXECUTION_GUARD_V1'
  )
  ON CONFLICT(capability_code) DO UPDATE SET
    capability_name=excluded.capability_name,
    capability_kind=excluded.capability_kind,
    owner_scope='SUPER_ADMIN',
    status='ACTIVE',
    description=excluded.description,
    entry_guard_required=true,
    entry_guard_code='ORCHESTRATOR_EXECUTION_GUARD_V1',
    updated_at=clock_timestamp(),
    updated_by_execution_id=v_execution_id;

  SELECT manifest_sha256 INTO v_existing_sha
  FROM public.lf_capability_version_registry
  WHERE capability_code='INDEPENDENT_ASSURANCE' AND version='1.0.0';
  IF v_existing_sha IS NOT NULL AND v_existing_sha<>v_manifest_sha THEN
    RAISE EXCEPTION 'BLOCK_T_INDEP_CAPABILITY_VERSION_MANIFEST_CONFLICT';
  END IF;

  INSERT INTO public.lf_capability_version_registry(
    capability_code,version,version_major,version_minor,version_patch,release_state,supersedes_version,
    manifest,manifest_sha256,source_ref,docs_ref,validator_ref,created_by_execution_id
  ) VALUES (
    'INDEPENDENT_ASSURANCE','1.0.0',1,0,0,'RELEASED',NULL,
    v_manifest,v_manifest_sha,
    'supabase://public/lf_independent_assurance_measure_v1',
    'github://cristhianlujan/claude-persona-lf-patch/sandbox/lf_contract_gate_test/transversal_assets/independent_assurance/README.md',
    'github://cristhianlujan/claude-persona-lf-patch/sandbox/lf_contract_gate_test/transversal_assets/independent_assurance/test_independent_review_boundary_v1.py',
    v_execution_id
  ) ON CONFLICT(capability_code,version) DO NOTHING;

  v_promote:=public.fn_lf_capability_promote_v1(
    'INDEPENDENT_ASSURANCE','1.0.0',NULL,v_execution_id,
    'T-INDEP materializes reusable real-oracle independence measurement without changing canonical review operation revision.'
  );
  IF coalesce((v_promote->>'ready')::boolean,false) IS NOT TRUE THEN
    RAISE EXCEPTION 'BLOCK_T_INDEP_CAPABILITY_CURRENT_POINTER:%',v_promote::text;
  END IF;

  v_revision_after := public.lf_operation_revision_sha256_v1('REVISION_INDEPENDIENTE_ESTRATEGIA_LF');
  IF v_revision_after IS DISTINCT FROM v_revision_before THEN
    RAISE EXCEPTION 'BLOCK_T_INDEP_CANONICAL_OPERATION_REVISION_DRIFT:%->%',v_revision_before,v_revision_after;
  END IF;
END $cutover$;

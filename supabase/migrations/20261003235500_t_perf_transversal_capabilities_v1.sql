-- T-PERF transversal capability registration/currentness.
-- Owner: SUPER_ADMIN (D-V2.2).
-- Scope: repository-bound current capabilities only; no role/session/function timeout mutation,
-- no runtime/deploy/production activation, no automatic timeout extension.
-- Exact source bundle SHA-256: 9083697e9b330291cc54371408dfef22bd9151748c4fe71de281f445083b8a6d.

DO $pre$
DECLARE
  v_count integer;
BEGIN
  SELECT count(*) INTO v_count
  FROM public.lf_activos
  WHERE archived_at IS NULL
    AND codigo_activo IN ('TIMEOUT_PHASE_BUDGET_POLICY','PERFORMANCE_EXACT_SOURCE_BENCHMARK')
    AND estado_documental='CANDIDATO'
    AND estado_operativo='READ_ONLY'
    AND runtime_estado='NO_RUNTIME_CHANGE'
    AND impacto_automatico='BLOQUEADO'
    AND owner_name='S30';
  IF v_count<>2 THEN
    RAISE EXCEPTION 'BLOCK_T_PERF_ASSET_PRESTATE:%',v_count;
  END IF;

  SELECT count(*) INTO v_count
  FROM public.lf_capability_registry
  WHERE capability_code IN ('TIMEOUT_PHASE_BUDGET_POLICY','PERFORMANCE_EXACT_SOURCE_BENCHMARK');
  IF v_count<>0 THEN
    RAISE EXCEPTION 'BLOCK_T_PERF_REGISTRY_ALREADY_PRESENT:%',v_count;
  END IF;

  SELECT count(*) INTO v_count
  FROM public.lf_capability_current
  WHERE capability_code IN ('TIMEOUT_PHASE_BUDGET_POLICY','PERFORMANCE_EXACT_SOURCE_BENCHMARK');
  IF v_count<>0 THEN
    RAISE EXCEPTION 'BLOCK_T_PERF_CURRENT_ALREADY_PRESENT:%',v_count;
  END IF;

  SELECT count(*) INTO v_count
  FROM public.lf_capability_version_registry
  WHERE capability_code IN ('TIMEOUT_PHASE_BUDGET_POLICY','PERFORMANCE_EXACT_SOURCE_BENCHMARK');
  IF v_count<>0 THEN
    RAISE EXCEPTION 'BLOCK_T_PERF_VERSION_ALREADY_PRESENT:%',v_count;
  END IF;
END
$pre$;

DO $register$
DECLARE
  v_execution_id constant text := 'CHATGPT-SADM-T-PERF-CURRENT-20261003';
  v_source_bundle_sha constant text := '9083697e9b330291cc54371408dfef22bd9151748c4fe71de281f445083b8a6d';
  r record;
  v_manifest jsonb;
  v_manifest_sha text;
  v_promote jsonb;
BEGIN
  FOR r IN
    SELECT * FROM (VALUES
      (
        'TIMEOUT_PHASE_BUDGET_POLICY'::text,
        'Timeout Phase Budget Policy'::text,
        'sandbox/lf_contract_gate_test/transversal_assets/performance/timeout_phase_budget_policy_v1.py'::text,
        '2cad51daede0b0da0ed3465da1b3d4f7b5595f52'::text,
        'PHASE_BUDGET_POLICY'::text
      ),
      (
        'PERFORMANCE_EXACT_SOURCE_BENCHMARK'::text,
        'Performance Exact Source Benchmark'::text,
        'sandbox/lf_contract_gate_test/transversal_assets/performance/performance_exact_source_benchmark_v1.py'::text,
        'fe3e8190705ac95c112d34d8331289887e6853cf'::text,
        'EXACT_SOURCE_BENCHMARK'::text
      )
    ) AS t(capability_code,capability_name,source_path,git_blob_sha1,capability_mode)
  LOOP
    v_manifest := jsonb_build_object(
      'schema_version','LF_CAPABILITY_MANIFEST_V1',
      'capability_code',r.capability_code,
      'version','1.0.0',
      'owner','SUPER_ADMIN',
      'mode',r.capability_mode,
      'contract',jsonb_build_object(
        'input',case when r.capability_code='TIMEOUT_PHASE_BUDGET_POLICY'
          then 'explicit phase + requested timeout + policy + exact source SHA + optional benchmark receipt'
          else 'exact source SHA + caller-supplied phase callables + bounded sample/warmup counts' end,
        'output',case when r.capability_code='TIMEOUT_PHASE_BUDGET_POLICY'
          then 'lf-timeout-phase-budget-decision/v1'
          else 'lf-performance-exact-source-benchmark-receipt/v1' end,
        'phase_model',jsonb_build_array('CONNECT','READ','INFERENCE','JOB','ORCHESTRATION'),
        'unknown_phase_policy','BLOCK',
        'automatic_timeout_mutation',false
      ),
      'delivery',jsonb_build_object(
        'mode','REPOSITORY_BOUND_PURE_PYTHON',
        'source_path',r.source_path,
        'git_blob_sha1',r.git_blob_sha1,
        'source_bundle_sha256',v_source_bundle_sha
      ),
      'installation',jsonb_build_object(
        'required',false,
        'reinstall_required',false,
        'runtime_deploy_required',false
      ),
      'dependencies',jsonb_build_object(
        'governance',jsonb_build_array('D-V2.2','SUPER_ADMIN'),
        'ekb',jsonb_build_array(
          'PROFILE-ROUTER-INPUT-GOV-CURRENTNESS-TIMEOUT-001',
          'PERF-HARNESS-CTE-INLINING-001',
          'GOV-EXTERNAL-API-JOB-POLICY-001'
        ),
        'consumer_policy_required',true
      ),
      'compatibility',jsonb_build_object(
        'role_timeout_changed',false,
        'session_timeout_changed',false,
        'input_governance_function_changed',false,
        'runtime_activation',false,
        'production_activation',false,
        'blind_timeout_extension_forbidden',true
      ),
      'migration',jsonb_build_object(
        'mode','CAPABILITY_REGISTRY_AND_CURRENT_POINTER_ONLY',
        'source_version','20261003235500',
        'subject_runtime_cutover',false
      ),
      'rollback',jsonb_build_object(
        'supported',true,
        'mode','RESTORE_ASSET_CANDIDATE_S30_AND_REMOVE_T_PERF_CURRENT_VERSION_REGISTRY_ROWS',
        'runtime_state_untouched',true,
        'timeout_settings_untouched',true
      ),
      'usage',jsonb_build_object(
        'consumer_supplies_phase_budget',true,
        'exact_source_benchmark_required_for_extension',true,
        'extension_decision','EVIDENCE_BOUND_EXTENSION_CANDIDATE_REQUIRES_HIGHER_AUTHORITY',
        'mutates_timeout',false
      ),
      'currentness',jsonb_build_object(
        'source_bundle_sha256',v_source_bundle_sha,
        'source_git_blob_sha1',r.git_blob_sha1,
        'source_ref','github://cristhianlujan/claude-persona-lf-patch@7317ee15d631462d22292d0342566269d499dec7/'||r.source_path,
        'test_git_blob_sha1','59178b49d9d2bf5fcaed1747e1b5f437d8eda51f',
        'test_observation','PASS_T_PERF_PHASE_BUDGET_BENCHMARK_V1 checks=7'
      ),
      'qualification',case when r.capability_code='PERFORMANCE_EXACT_SOURCE_BENCHMARK' then
        jsonb_build_object(
          'scope','GENERIC_HARNESS_SYNTHETIC_QUALIFICATION_NOT_IG_PRODUCTION_LATENCY',
          'exact_source_sha256',v_source_bundle_sha,
          'sample_count_per_phase',20,
          'one_call_per_sample',true,
          'phases',jsonb_build_object(
            'CONNECT',jsonb_build_object('p50_ms',0.002278,'p95_ms',0.002521,'p99_ms',0.002780),
            'READ',jsonb_build_object('p50_ms',0.004707,'p95_ms',0.004755,'p99_ms',0.005029),
            'INFERENCE',jsonb_build_object('p50_ms',0.014216,'p95_ms',0.014877,'p99_ms',0.014953),
            'JOB',jsonb_build_object('p50_ms',0.030920,'p95_ms',0.032783,'p99_ms',0.044429),
            'ORCHESTRATION',jsonb_build_object('p50_ms',0.036173,'p95_ms',0.037526,'p99_ms',0.048045)
          ),
          'historical_ig_runs_exact_code_binding',false
        )
      else
        jsonb_build_object(
          'negative','CALL_OVER_BUDGET_CANCELLED_AND_BLIND_EXTENSION_BLOCKED',
          'exact_test_blob_sha1','59178b49d9d2bf5fcaed1747e1b5f437d8eda51f',
          'test_observation','PASS_T_PERF_PHASE_BUDGET_BENCHMARK_V1 checks=7'
        )
      end
    );
    v_manifest_sha := encode(extensions.digest(convert_to(v_manifest::text,'UTF8'),'sha256'),'hex');

    INSERT INTO public.lf_capability_registry(
      capability_code,capability_name,capability_kind,owner_scope,status,description,
      created_by_execution_id,updated_by_execution_id,entry_guard_required,entry_guard_code
    ) VALUES (
      r.capability_code,r.capability_name,'TRANSVERSAL','SUPER_ADMIN','ACTIVE',
      case when r.capability_code='TIMEOUT_PHASE_BUDGET_POLICY'
        then 'Phase-aware timeout decision policy; blocks blind timeout extensions and never mutates timeouts automatically.'
        else 'Exact-source phase benchmark receipt producer; reports p50/p95/p99 without owning runtime or production activation.' end,
      v_execution_id,v_execution_id,false,'ORCHESTRATOR_EXECUTION_GUARD_V1'
    );

    INSERT INTO public.lf_capability_version_registry(
      capability_code,version,version_major,version_minor,version_patch,release_state,supersedes_version,
      manifest,manifest_sha256,source_ref,docs_ref,validator_ref,created_by_execution_id
    ) VALUES (
      r.capability_code,'1.0.0',1,0,0,'RELEASED',NULL,
      v_manifest,v_manifest_sha,
      'github://cristhianlujan/claude-persona-lf-patch@7317ee15d631462d22292d0342566269d499dec7/'||r.source_path,
      'github://cristhianlujan/claude-persona-lf-patch@7317ee15d631462d22292d0342566269d499dec7/sandbox/lf_contract_gate_test/transversal_assets/performance/README.md',
      'github://cristhianlujan/claude-persona-lf-patch@7317ee15d631462d22292d0342566269d499dec7/sandbox/lf_contract_gate_test/transversal_assets/performance/test_t_perf_phase_budget_benchmark_v1.py',
      v_execution_id
    );

    v_promote := public.fn_lf_capability_promote_v1(
      r.capability_code,'1.0.0',NULL,v_execution_id,
      'T-PERF generalized SUPER_ADMIN repository-bound capability; no runtime activation and no timeout mutation.'
    );
    IF coalesce((v_promote->>'ready')::boolean,false) IS NOT TRUE THEN
      RAISE EXCEPTION 'BLOCK_T_PERF_PROMOTION:%:%',r.capability_code,v_promote::text;
    END IF;

    UPDATE public.lf_activos
    SET estado_documental='VIGENTE',
        estado_operativo='READ_ONLY',
        runtime_estado='REPOSITORY_BOUND',
        impacto_automatico='BLOQUEADO',
        version='1.0.0',
        owner_name='SUPER_ADMIN',
        ruta_esperada=r.source_path,
        ultima_revision=v_source_bundle_sha,
        raw_payload=coalesce(raw_payload,'{}'::jsonb) || jsonb_build_object(
          'status','CURRENT_REPOSITORY_BOUND_NO_AUTO_TIMEOUT_MUTATION',
          'prior_owner_name','S30',
          'current_pointer_present',true,
          'runtime_authorized',false,
          'production_authorized',false,
          'timeout_mutation_authorized',false
        ),
        metadata=jsonb_set(
          jsonb_set(
            coalesce(metadata,'{}'::jsonb),
            '{transversal_inventory,inventory_status}',
            to_jsonb('CURRENT_REPOSITORY_BOUND_SUPER_ADMIN'::text),true
          ),
          '{t_perf_currentness}',
          jsonb_build_object(
            'schema_version','LF_T_PERF_CURRENTNESS_V1',
            'source_bundle_sha256',v_source_bundle_sha,
            'source_git_blob_sha1',r.git_blob_sha1,
            'test_git_blob_sha1','59178b49d9d2bf5fcaed1747e1b5f437d8eda51f',
            'negative_event_ref','supabase://public/lf_eventos/20125',
            'runtime_activation',false,
            'timeout_mutation',false
          ),true
        ),
        updated_at=clock_timestamp(),
        updated_by_execution_id=v_execution_id
    WHERE codigo_activo=r.capability_code AND archived_at IS NULL;
  END LOOP;

  IF (SELECT count(*) FROM public.lf_capability_current WHERE capability_code IN ('TIMEOUT_PHASE_BUDGET_POLICY','PERFORMANCE_EXACT_SOURCE_BENCHMARK') AND version='1.0.0')<>2 THEN
    RAISE EXCEPTION 'BLOCK_T_PERF_CURRENT_READBACK';
  END IF;
  IF (SELECT count(*) FROM public.lf_capability_registry WHERE capability_code IN ('TIMEOUT_PHASE_BUDGET_POLICY','PERFORMANCE_EXACT_SOURCE_BENCHMARK') AND owner_scope='SUPER_ADMIN' AND entry_guard_required IS FALSE)<>2 THEN
    RAISE EXCEPTION 'BLOCK_T_PERF_REGISTRY_READBACK';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.lf_activos
    WHERE codigo_activo IN ('TIMEOUT_PHASE_BUDGET_POLICY','PERFORMANCE_EXACT_SOURCE_BENCHMARK')
      AND archived_at IS NULL
      AND (impacto_automatico<>'BLOQUEADO' OR runtime_estado<>'REPOSITORY_BOUND' OR owner_name<>'SUPER_ADMIN')
  ) THEN
    RAISE EXCEPTION 'BLOCK_T_PERF_ASSET_READBACK';
  END IF;
END
$register$;

-- IG_CURATOR_VALIDATOR_REFACTOR_V2 / M1.A9 / PAULO-038
-- Single versioned contract-clause accessor + removal of duplicated readiness revision literals.
-- Reuses POLICY_CONSUMPTION / programacion.contratos; no parallel policy or contract store.
-- Owner: SUPER_ADMIN.

DO $pre$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.lf_activos
    WHERE codigo_activo='POLICY_CONSUMPTION'
      AND archived_at IS NULL
      AND estado_documental='VIGENTE'
      AND estado_operativo='ACTIVO'
  ) THEN
    RAISE EXCEPTION 'BLOCK_M1_A9_POLICY_CONSUMPTION_NOT_CURRENT';
  END IF;

  IF to_regprocedure('programacion.fn_input_contract_clause_v1(bigint,text,text[])') IS NOT NULL THEN
    RAISE EXCEPTION 'BLOCK_M1_A9_ACCESSOR_PREEXISTING';
  END IF;

  IF md5(pg_get_functiondef('programacion.fn_input_governance_bootstrap_classify_v1(integer,text,bigint)'::regprocedure)) <> '2ebfa25bdde741e5052bd6dadde1bc29' THEN
    RAISE EXCEPTION 'M1_A9_CLASSIFY_V1_SOURCE_DRIFT';
  END IF;
  IF md5(pg_get_functiondef('programacion.fn_input_governance_bootstrap_classify_v1_cached_v1(integer,text,bigint,jsonb)'::regprocedure)) <> '478c66b884a68430671701ecf7d3bf8e' THEN
    RAISE EXCEPTION 'M1_A9_CLASSIFY_CACHED_V1_SOURCE_DRIFT';
  END IF;
  IF md5(pg_get_functiondef('programacion.fn_input_governance_bootstrap_classify_v1_cached_v2(integer,text,bigint,jsonb)'::regprocedure)) <> '13e07ad8c2036f3886a8cb5448485e06' THEN
    RAISE EXCEPTION 'M1_A9_CLASSIFY_CACHED_V2_SOURCE_DRIFT';
  END IF;
  IF md5(pg_get_functiondef('programacion.fn_input_governance_bootstrap_materialize_v1(integer,text,text)'::regprocedure)) <> '1124648cb0e8ee1414bd9ca06f010887' THEN
    RAISE EXCEPTION 'M1_A9_MATERIALIZE_V1_SOURCE_DRIFT';
  END IF;
END $pre$;

CREATE OR REPLACE FUNCTION programacion.fn_input_contract_clause_v1(
  p_version_id bigint,
  p_contract_code text,
  p_path text[]
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path=pg_catalog,programacion
AS $function$
DECLARE
  c record;
  v_value jsonb;
  v_payload jsonb;
BEGIN
  IF p_version_id IS NULL
     OR p_contract_code IS NULL
     OR btrim(p_contract_code)=''
     OR p_path IS NULL
     OR cardinality(p_path)=0 THEN
    RAISE EXCEPTION 'INPUT_CONTRACT_CLAUSE_INVALID_SELECTOR';
  END IF;

  SELECT id,version_id,contrato_codigo,estado,fail_closed,especificacion
  INTO c
  FROM programacion.contratos
  WHERE version_id=p_version_id
    AND contrato_codigo=p_contract_code
    AND estado='defined'
    AND fail_closed
  ORDER BY id DESC
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'INPUT_CONTRACT_VERSION_NOT_PINNED:%:%',p_contract_code,p_version_id;
  END IF;

  IF nullif(c.especificacion->>'contract_revision','') IS NULL THEN
    RAISE EXCEPTION 'INPUT_CONTRACT_REVISION_NOT_PINNED:%:%',p_contract_code,p_version_id;
  END IF;

  v_value:=c.especificacion #> p_path;
  IF v_value IS NULL THEN
    RAISE EXCEPTION 'INPUT_CONTRACT_CLAUSE_MISSING:%:%:%',
      p_contract_code,
      c.especificacion->>'contract_revision',
      array_to_string(p_path,'.');
  END IF;

  v_payload:=jsonb_build_object(
    'schema_version','INPUT_CONTRACT_CLAUSE_RECEIPT_V1',
    'contract_code',c.contrato_codigo,
    'version_id',c.version_id,
    'contract_revision',c.especificacion->>'contract_revision',
    'path',to_jsonb(p_path),
    'value',v_value,
    'contract_sha256',programacion.fn_v09_sha256_jsonb(
      jsonb_build_object(
        'id',c.id,
        'version_id',c.version_id,
        'contrato_codigo',c.contrato_codigo,
        'fail_closed',c.fail_closed,
        'estado',c.estado,
        'especificacion',c.especificacion
      )
    )
  );

  RETURN v_payload;
END;
$function$;

DO $patch$
DECLARE
  r record;
  v_def text;
  v_new text;
BEGIN
  FOR r IN
    SELECT * FROM (VALUES
      ('programacion.fn_input_governance_bootstrap_classify_v1(integer,text,bigint)'::regprocedure,'2ebfa25bdde741e5052bd6dadde1bc29'),
      ('programacion.fn_input_governance_bootstrap_classify_v1_cached_v1(integer,text,bigint,jsonb)'::regprocedure,'478c66b884a68430671701ecf7d3bf8e'),
      ('programacion.fn_input_governance_bootstrap_classify_v1_cached_v2(integer,text,bigint,jsonb)'::regprocedure,'13e07ad8c2036f3886a8cb5448485e06')
    ) q(sig,expected_md5)
  LOOP
    v_def:=pg_get_functiondef(r.sig);
    IF md5(v_def)<>r.expected_md5 THEN
      RAISE EXCEPTION 'M1_A9_SOURCE_DRIFT:%',r.sig;
    END IF;
    IF position($s$'revision','5.13'$s$ IN v_def)=0 THEN
      RAISE EXCEPTION 'M1_A9_REVISION_ANCHOR_MISSING:%',r.sig;
    END IF;
    v_new:=replace(
      v_def,
      $s$'revision','5.13'$s$,
      $s$'revision',programacion.fn_input_contract_clause_v1(p_version_id,'INPUT_READINESS_CONTRACT',array['family_stage_requirements','CONTEXT_BUDGET_RETRIEVAL_POLICY'])->>'contract_revision'$s$
    );
    EXECUTE v_new;
  END LOOP;

  v_def:=pg_get_functiondef('programacion.fn_input_governance_bootstrap_materialize_v1(integer,text,text)'::regprocedure);
  IF md5(v_def)<>'1124648cb0e8ee1414bd9ca06f010887' THEN
    RAISE EXCEPTION 'M1_A9_MATERIALIZE_SOURCE_DRIFT';
  END IF;
  IF position($s$v_contract_revision not in ('5.12','5.13')$s$ IN v_def)=0 THEN
    RAISE EXCEPTION 'M1_A9_MATERIALIZE_ANCHOR_MISSING';
  END IF;
  v_new:=replace(
    v_def,
    $s$v_contract_revision not in ('5.12','5.13')$s$,
    $s$v_contract_revision is distinct from (programacion.fn_input_contract_clause_v1(v_version,'INPUT_READINESS_CONTRACT',array['family_stage_requirements'])->>'contract_revision')$s$
  );
  EXECUTE v_new;
END $patch$;

DO $asset$
DECLARE
  v_batch uuid:='e14f1d14-5d36-4f6c-a01e-1a0f10900001'::uuid;
  v_exec text:='CHATGPT-IG-CV-M1-A9-20261003';
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.lf_activos
    WHERE codigo_activo='PROGRAMACION_FN_INPUT_CONTRACT_CLAUSE_V1'
      AND archived_at IS NULL
  ) THEN
    INSERT INTO public.lf_activos(
      codigo_activo,nombre_canonico,tipo_activo,subtipo_activo,
      estado_documental,estado_operativo,
      source_spreadsheet_id,source_spreadsheet_title,source_sheet_name,source_row_number,
      migration_batch_id,formato_nativo,linea_codigo,nivel_control,runtime_estado,impacto_automatico,
      raw_payload,metadata,created_by_execution_id,updated_by_execution_id
    ) VALUES (
      'PROGRAMACION_FN_INPUT_CONTRACT_CLAUSE_V1',
      'PROGRAMACION_FN_INPUT_CONTRACT_CLAUSE_V1',
      'CAPABILITY','DB_FUNCTION',
      'CANDIDATO','READ_ONLY',
      'SUPABASE_DIRECT_CONTROLLED_ENTRY','LF_OPERATION_CONTROLLED_CANDIDATES',
      'IG_CURATOR_VALIDATOR_REFACTOR_V2_M1_A9',2026100301,
      v_batch,'SUPABASE_FUNCTION','IG_CURATOR_VALIDATOR_REFACTOR_V2','CONTROLADO','CANDIDATE_READ_ONLY','BLOQUEADO',
      jsonb_build_object(
        'signature','programacion.fn_input_contract_clause_v1(bigint,text,text[])',
        'contract','INPUT_CONTRACT_CLAUSE_RECEIPT_V1',
        'authority','programacion.contratos',
        'policy_consumption','POLICY_CONSUMPTION'
      ),
      jsonb_build_object(
        'domain','INPUT_GOVERNANCE',
        'unit_code','M1.A9',
        'consumer_adapter',true,
        'no_duplicate_engine',true,
        'source_of_truth','programacion.contratos.especificacion',
        'fail_closed',true
      ),
      v_exec,v_exec
    );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_activo_relaciones
    WHERE codigo_activo='PROGRAMACION_FN_INPUT_CONTRACT_CLAUSE_V1'
      AND relacionado_codigo='POLICY_CONSUMPTION'
      AND relacion_tipo='DEPENDE_DE'
  ) THEN
    INSERT INTO public.lf_activo_relaciones(
      codigo_activo,relacionado_codigo,relacion_tipo,valor_original,fuente,
      migration_batch_id,created_by_execution_id
    ) VALUES (
      'PROGRAMACION_FN_INPUT_CONTRACT_CLAUSE_V1','POLICY_CONSUMPTION','DEPENDE_DE',
      'VERSIONED_CONTRACT_POLICY_CONSUMPTION','IG_CURATOR_VALIDATOR_REFACTOR_V2:M1.A9',
      v_batch,v_exec
    );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_activo_relaciones
    WHERE codigo_activo='PROGRAMACION_FN_INPUT_GOVERNANCE_CURATION_SET'
      AND relacionado_codigo='PROGRAMACION_FN_INPUT_CONTRACT_CLAUSE_V1'
      AND relacion_tipo='DEPENDE_DE'
  ) THEN
    INSERT INTO public.lf_activo_relaciones(
      codigo_activo,relacionado_codigo,relacion_tipo,valor_original,fuente,
      migration_batch_id,created_by_execution_id
    ) VALUES (
      'PROGRAMACION_FN_INPUT_GOVERNANCE_CURATION_SET','PROGRAMACION_FN_INPUT_CONTRACT_CLAUSE_V1','DEPENDE_DE',
      'CONTRACT_CLAUSE_ACCESSOR','IG_CURATOR_VALIDATOR_REFACTOR_V2:M1.A9',v_batch,v_exec
    );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_activo_relaciones
    WHERE codigo_activo='PROGRAMACION_FN_INPUT_GOVERNANCE_SEMANTIC_CLASSIFICATION_SET'
      AND relacionado_codigo='PROGRAMACION_FN_INPUT_CONTRACT_CLAUSE_V1'
      AND relacion_tipo='DEPENDE_DE'
  ) THEN
    INSERT INTO public.lf_activo_relaciones(
      codigo_activo,relacionado_codigo,relacion_tipo,valor_original,fuente,
      migration_batch_id,created_by_execution_id
    ) VALUES (
      'PROGRAMACION_FN_INPUT_GOVERNANCE_SEMANTIC_CLASSIFICATION_SET','PROGRAMACION_FN_INPUT_CONTRACT_CLAUSE_V1','DEPENDE_DE',
      'CONTRACT_CLAUSE_ACCESSOR','IG_CURATOR_VALIDATOR_REFACTOR_V2:M1.A9',v_batch,v_exec
    );
  END IF;
END $asset$;

INSERT INTO public.lf_test_suite_cases(
  suite_code,test_code,test_order,rule_codes,title,test_type,execution_mode,severity,
  preconditions,input_payload,expected_output,prohibited_output,status,metadata,
  created_by_execution_id,updated_by_execution_id
)
SELECT
  'INPUT_GOVERNANCE_REGRESSION','M1_A9_CONTRACT_CLAUSE_PARITY_POSITIVE',540,array[]::text[],
  'M1.A9 versioned contract clause parity','DETERMINISTIC','AUTOMATED','HIGH',
  jsonb_build_object('accessor','programacion.fn_input_contract_clause_v1','authority','programacion.contratos'),
  jsonb_build_object('contract_code','INPUT_READINESS_CONTRACT','path',jsonb_build_array('family_stage_requirements','CONTEXT_BUDGET_RETRIEVAL_POLICY')),
  jsonb_build_object('outcome','MATCHES_VERSIONED_CONTRACT','revision_source','CONTRACT_RECEIPT'),
  '{}'::jsonb,'CANDIDATO',
  jsonb_build_object('plan_id','IG_CURATOR_VALIDATOR_REFACTOR_V2','unit_code','M1.A9','work_code','PAULO-038','scenario','PARITY_POSITIVE'),
  'CHATGPT-IG-CV-M1-A9-20261003','CHATGPT-IG-CV-M1-A9-20261003'
WHERE NOT EXISTS (
  SELECT 1 FROM public.lf_test_suite_cases
  WHERE suite_code='INPUT_GOVERNANCE_REGRESSION' AND test_code='M1_A9_CONTRACT_CLAUSE_PARITY_POSITIVE'
);

INSERT INTO public.lf_test_suite_cases(
  suite_code,test_code,test_order,rule_codes,title,test_type,execution_mode,severity,
  preconditions,input_payload,expected_output,prohibited_output,status,metadata,
  created_by_execution_id,updated_by_execution_id
)
SELECT
  'INPUT_GOVERNANCE_REGRESSION','M1_A9_CONTRACT_VERSION_UNPINNED_NEGATIVE',541,array[]::text[],
  'M1.A9 unpinned contract version fails closed','DETERMINISTIC','AUTOMATED','HIGH',
  jsonb_build_object('accessor','programacion.fn_input_contract_clause_v1'),
  jsonb_build_object('scenario','UNPINNED_VERSION'),
  jsonb_build_object('outcome','FAIL_CLOSED','error_family','INPUT_CONTRACT_VERSION_NOT_PINNED'),
  '{}'::jsonb,'CANDIDATO',
  jsonb_build_object('plan_id','IG_CURATOR_VALIDATOR_REFACTOR_V2','unit_code','M1.A9','work_code','PAULO-038','scenario','UNPINNED_VERSION_NEGATIVE'),
  'CHATGPT-IG-CV-M1-A9-20261003','CHATGPT-IG-CV-M1-A9-20261003'
WHERE NOT EXISTS (
  SELECT 1 FROM public.lf_test_suite_cases
  WHERE suite_code='INPUT_GOVERNANCE_REGRESSION' AND test_code='M1_A9_CONTRACT_VERSION_UNPINNED_NEGATIVE'
);

INSERT INTO public.lf_test_suite_cases(
  suite_code,test_code,test_order,rule_codes,title,test_type,execution_mode,severity,
  preconditions,input_payload,expected_output,prohibited_output,status,metadata,
  created_by_execution_id,updated_by_execution_id
)
SELECT
  'INPUT_GOVERNANCE_REGRESSION','M1_A9_CONTRACT_CLAUSE_MISSING_NEGATIVE',542,array[]::text[],
  'M1.A9 missing contract clause fails closed','DETERMINISTIC','AUTOMATED','HIGH',
  jsonb_build_object('accessor','programacion.fn_input_contract_clause_v1'),
  jsonb_build_object('scenario','MISSING_CLAUSE'),
  jsonb_build_object('outcome','FAIL_CLOSED','error_family','INPUT_CONTRACT_CLAUSE_MISSING'),
  '{}'::jsonb,'CANDIDATO',
  jsonb_build_object('plan_id','IG_CURATOR_VALIDATOR_REFACTOR_V2','unit_code','M1.A9','work_code','PAULO-038','scenario','MISSING_CLAUSE_NEGATIVE'),
  'CHATGPT-IG-CV-M1-A9-20261003','CHATGPT-IG-CV-M1-A9-20261003'
WHERE NOT EXISTS (
  SELECT 1 FROM public.lf_test_suite_cases
  WHERE suite_code='INPUT_GOVERNANCE_REGRESSION' AND test_code='M1_A9_CONTRACT_CLAUSE_MISSING_NEGATIVE'
);

DO $post$
DECLARE
  v_lits integer;
  v_receipt jsonb;
  v_missing_clause boolean:=false;
  v_unpinned boolean:=false;
BEGIN
  SELECT coalesce(sum((SELECT count(*) FROM regexp_matches(p.prosrc,$$'5\.1[0-9]'$$,'g'))),0)::integer
  INTO v_lits
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='programacion'
    AND p.proname LIKE 'fn_input%'
    AND p.prosrc ~ $$'5\.1[0-9]'$$;

  IF v_lits<>0 THEN
    RAISE EXCEPTION 'M1_A9_REVISION_LITERAL_REMAINS:%',v_lits;
  END IF;

  v_receipt:=programacion.fn_input_contract_clause_v1(
    19,'INPUT_READINESS_CONTRACT',array['family_stage_requirements','CONTEXT_BUDGET_RETRIEVAL_POLICY']
  );
  IF v_receipt->>'contract_revision' IS DISTINCT FROM (
    SELECT especificacion->>'contract_revision'
    FROM programacion.contratos
    WHERE version_id=19 AND contrato_codigo='INPUT_READINESS_CONTRACT'
  ) THEN
    RAISE EXCEPTION 'M1_A9_CONTRACT_PARITY_FAILED:%',v_receipt;
  END IF;

  BEGIN
    PERFORM programacion.fn_input_contract_clause_v1(19,'INPUT_READINESS_CONTRACT',array['does_not_exist']);
  EXCEPTION WHEN OTHERS THEN
    v_missing_clause:=sqlerrm LIKE 'INPUT_CONTRACT_CLAUSE_MISSING:%';
  END;
  BEGIN
    PERFORM programacion.fn_input_contract_clause_v1(999999,'INPUT_READINESS_CONTRACT',array['family_stage_requirements']);
  EXCEPTION WHEN OTHERS THEN
    v_unpinned:=sqlerrm LIKE 'INPUT_CONTRACT_VERSION_NOT_PINNED:%';
  END;
  IF NOT v_missing_clause OR NOT v_unpinned THEN
    RAISE EXCEPTION 'M1_A9_NEGATIVE_TEST_FAILED missing_clause=% unpinned=%',v_missing_clause,v_unpinned;
  END IF;

  IF (SELECT count(*) FROM public.lf_test_suite_cases
      WHERE suite_code='INPUT_GOVERNANCE_REGRESSION'
        AND test_code IN (
          'M1_A9_CONTRACT_CLAUSE_PARITY_POSITIVE',
          'M1_A9_CONTRACT_VERSION_UNPINNED_NEGATIVE',
          'M1_A9_CONTRACT_CLAUSE_MISSING_NEGATIVE'
        ))<>3 THEN
    RAISE EXCEPTION 'M1_A9_TEST_REGISTRY_INCOMPLETE';
  END IF;
END $post$;

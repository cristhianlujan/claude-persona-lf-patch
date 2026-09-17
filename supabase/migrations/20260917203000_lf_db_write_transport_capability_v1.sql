-- LF DB_WRITE_TRANSPORT capability registration and ACTUALIZACION_DB_LF consumer binding v1
-- Source-first only. No production activation, no Router bypass and no migration replay.
-- Capability source already merged by PR #880 at 1027cf217cc8301c9f56cc7e5b54e6fc2a84bb1d.

DO $db_write_transport$
DECLARE
  v_execution_id constant text := 'EXEC-S30-DB-WRITE-TRANSPORT-REGISTER-20260917-001';
  v_capability_code constant text := 'DB_WRITE_TRANSPORT';
  v_version constant text := '1.0.0';
  v_manifest jsonb := $manifest$
  {
    "schema_version":"LF_CAPABILITY_MANIFEST_V1",
    "capability_code":"DB_WRITE_TRANSPORT",
    "version":"1.0.0",
    "contract":{
      "input":"LF_DB_WRITE_TARGET_V1",
      "output":"LF_DB_WRITE_TRANSPORT_DECISION_V1",
      "authority":"SELECTOR_ONLY_NO_PERMISSION_GRANT"
    },
    "delivery":{
      "mode":"VERSIONED_REPOSITORY_CAPABILITY",
      "selector":"sandbox/lf_contract_gate_test/db_write_transport/lf_db_write_transport.py",
      "consumer_operation":"ACTUALIZACION_DB_LF"
    },
    "installation":{
      "required":false,
      "reinstall_required":false,
      "package_update_mode":"REPOSITORY_BOUND"
    },
    "dependencies":{
      "packages":["python>=3.11"],
      "capabilities":[],
      "governance":["ACT-0001","MIGRATION_SOURCE_PARITY","CI-MIGRATION-SOURCE-PARITY-001"]
    },
    "compatibility":{
      "supported_target_types":["MIGRATION","DB","FUNCTION","TRIGGER"],
      "migration_mode":"EXACT_VERSION_SOURCE_FIRST",
      "direct_mode":"SUPABASE_MCP",
      "unknown_target":"FAIL_CLOSED"
    },
    "migration":{
      "primary_executor":"SUPABASE_CLI_DB_PUSH_LINKED",
      "fallback_executor":"SOURCE_FIRST_EXACT_VERSION_MANUAL_LEDGER_DML",
      "exact_filename_version_required":true,
      "forbidden_executor_when_exact_version_required":"SUPABASE_MCP_APPLY_MIGRATION",
      "post_apply_timestamp_rename_normal_flow":false
    },
    "rollback":{
      "supported":true,
      "rule":"RESTORE_OPERATION_CONTRACT_AND_POINTER_ONLY;DO_NOT_REPLAY_APPLIED_DDL",
      "source_preserved":true
    },
    "usage":{
      "operation":"ACTUALIZACION_DB_LF",
      "selector":"sandbox/lf_contract_gate_test/db_write_transport/lf_db_write_transport.py",
      "docs":"sandbox/lf_contract_gate_test/db_write_transport/README.md",
      "self_test":"python sandbox/lf_contract_gate_test/db_write_transport/lf_db_write_transport.py --self-test"
    },
    "currentness":{
      "authority_ref":"github://cristhianlujan/claude-persona-lf-patch@1027cf217cc8301c9f56cc7e5b54e6fc2a84bb1d",
      "source_revision_immutable":true,
      "execution_binding_required":true,
      "prewrite_capability_preflight_required":true,
      "migration_source_parity_required":true
    }
  }
  $manifest$::jsonb;
  v_manifest_sha text;
  v_promotion jsonb;
  v_inventory_batch constant uuid := 'f4f3c7a9-5f2f-4e1b-8c67-31e7b56ad901'::uuid;
BEGIN
  -- Governed execution binding: the migration can only materialize through ACTUALIZACION_DB_LF.
  IF NOT EXISTS (
    SELECT 1
    FROM public.lf_operation_execution
    WHERE execution_id=v_execution_id
      AND operation_code='ACTUALIZACION_DB_LF'
      AND target_type='MIGRATION'
      AND target_code='DB_WRITE_TRANSPORT_V1'
      AND target_repo='cristhianlujan/claude-persona-lf-patch'
      AND target_path='supabase/migrations/20260917203000_lf_db_write_transport_capability_v1.sql'
      AND status='IN_PROGRESS'
  ) THEN
    RAISE EXCEPTION 'BLOCK_DB_WRITE_TRANSPORT_EXECUTION_BINDING';
  END IF;

  IF to_regprocedure('public.fn_lf_capability_promote_v1(text,text,text,text,text)') IS NULL
     OR to_regprocedure('public.fn_lf_capability_preflight_v1(text,text)') IS NULL
     OR to_regprocedure('public.fn_lf_capability_bind_current_v1(text,text,text,text)') IS NULL THEN
    RAISE EXCEPTION 'BLOCK_DB_WRITE_TRANSPORT_CAPABILITY_INFRASTRUCTURE_MISSING';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_operation_contracts
    WHERE operation_code='ACTUALIZACION_DB_LF'
      AND contract_code='CONTRACT-ACTUALIZACION-DB-LF-v0.1'
      AND status='ACTIVE_ENFORCEMENT'
  ) OR (
    SELECT count(*) FROM public.lf_operation_contracts
    WHERE operation_code='ACTUALIZACION_DB_LF' AND status='ACTIVE_ENFORCEMENT'
  ) <> 1 THEN
    RAISE EXCEPTION 'BLOCK_DB_WRITE_TRANSPORT_DB_CONTRACT_CARDINALITY';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_activos
    WHERE codigo_activo='MIGRATION_SOURCE_PARITY'
      AND estado_operativo='ACTIVO'
      AND archived_at IS NULL
  ) THEN
    RAISE EXCEPTION 'BLOCK_DB_WRITE_TRANSPORT_PARITY_CAPABILITY_MISSING';
  END IF;

  IF EXISTS (SELECT 1 FROM public.lf_capability_registry WHERE capability_code=v_capability_code)
     OR EXISTS (SELECT 1 FROM public.lf_capability_version_registry WHERE capability_code=v_capability_code)
     OR EXISTS (SELECT 1 FROM public.lf_capability_current WHERE capability_code=v_capability_code)
     OR EXISTS (SELECT 1 FROM public.lf_activos WHERE codigo_activo=v_capability_code AND archived_at IS NULL) THEN
    RAISE EXCEPTION 'BLOCK_DB_WRITE_TRANSPORT_PREEXISTING_STATE';
  END IF;

  INSERT INTO public.lf_capability_registry(
    capability_code,capability_name,capability_kind,owner_scope,status,description,
    created_by_execution_id,updated_by_execution_id
  ) VALUES (
    v_capability_code,'LF DB Write Transport','TRANSVERSAL','LF_GOVERNANCE_S30_DB','ACTIVE',
    'Deterministic transport selector for governed LF database writes. MIGRATION is exact-version source-first; DB/FUNCTION/TRIGGER use governed Supabase MCP direct transport.',
    v_execution_id,v_execution_id
  );

  v_manifest_sha := encode(extensions.digest(convert_to(v_manifest::text,'UTF8'),'sha256'),'hex');

  INSERT INTO public.lf_capability_version_registry(
    capability_code,version,version_major,version_minor,version_patch,release_state,
    supersedes_version,manifest,manifest_sha256,source_ref,docs_ref,validator_ref,created_by_execution_id
  ) VALUES (
    v_capability_code,v_version,1,0,0,'RELEASED',null,v_manifest,v_manifest_sha,
    'github://cristhianlujan/claude-persona-lf-patch@1027cf217cc8301c9f56cc7e5b54e6fc2a84bb1d/sandbox/lf_contract_gate_test/db_write_transport/lf_db_write_transport.py',
    'github://cristhianlujan/claude-persona-lf-patch@1027cf217cc8301c9f56cc7e5b54e6fc2a84bb1d/sandbox/lf_contract_gate_test/db_write_transport/README.md',
    'github://cristhianlujan/claude-persona-lf-patch@1027cf217cc8301c9f56cc7e5b54e6fc2a84bb1d/sandbox/lf_contract_gate_test/db_write_transport/lf_db_write_transport.py#self_test',
    v_execution_id
  );

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_capability_version_registry
    WHERE capability_code=v_capability_code
      AND version=v_version
      AND release_state='RELEASED'
      AND manifest=v_manifest
      AND manifest_sha256=v_manifest_sha
  ) THEN
    RAISE EXCEPTION 'BLOCK_DB_WRITE_TRANSPORT_VERSION_READBACK';
  END IF;

  v_promotion := public.fn_lf_capability_promote_v1(
    v_capability_code,v_version,null,v_execution_id,
    'Bootstrap current DB_WRITE_TRANSPORT v1 from merged source PR880 exact-head CI green'
  );
  IF coalesce((v_promotion->>'ready')::boolean,false) IS NOT TRUE THEN
    RAISE EXCEPTION 'BLOCK_DB_WRITE_TRANSPORT_CURRENT_PROMOTION:%',v_promotion::text;
  END IF;

  INSERT INTO public.lf_activos(
    id,codigo_activo,nombre_canonico,tipo_activo,subtipo_activo,
    estado_documental,estado_operativo,nivel_control,runtime_estado,impacto_automatico,
    version,ruta_esperada,url,owner_name,ultima_revision,rol_arquitectura,
    source_spreadsheet_id,source_spreadsheet_title,source_sheet_name,source_row_number,
    migration_batch_id,raw_payload,metadata,created_by_execution_id,updated_by_execution_id
  ) VALUES (
    nextval('public.lf_activos_id_seq'),
    v_capability_code,'TRANSVERSAL_DB_WRITE_TRANSPORT','CAPABILITY','TRANSVERSAL_CAPABILITY_INFRASTRUCTURE',
    'VIGENTE','ACTIVO','FAIL_CLOSED','REPOSITORY_BOUND','TRANSVERSAL',
    v_version,'sandbox/lf_contract_gate_test/db_write_transport/lf_db_write_transport.py',
    'supabase://public/lf_capability_registry/DB_WRITE_TRANSPORT/1.0.0','LF_GOVERNANCE_S30_DB',
    '1027cf217cc8301c9f56cc7e5b54e6fc2a84bb1d','TRANSVERSAL_DB_WRITE_TRANSPORT',
    'NATIVE_SUPABASE','LF_TRANSVERSAL_CAPABILITY_INVENTORY','S30_DB_WRITE_TRANSPORT_20260917',1,
    v_inventory_batch,
    jsonb_build_object(
      'key',v_capability_code,'class','CAPABILITY_INFRASTRUCTURE','status','FORMAL_TRANSVERSAL_ACTIVE',
      'assets',jsonb_build_array(
        'public.lf_capability_registry:DB_WRITE_TRANSPORT',
        'sandbox/lf_contract_gate_test/db_write_transport/lf_db_write_transport.py',
        'sandbox/lf_contract_gate_test/db_write_transport/README.md'
      ),
      'consumers_known',jsonb_build_array('ACTUALIZACION_DB_LF'),
      'validation_refs',jsonb_build_array('MIGRATION_SOURCE_PARITY','CI-MIGRATION-SOURCE-PARITY-001')
    ),
    jsonb_build_object(
      'source_kind','GITHUB_SOURCE_PLUS_SUPABASE_REGISTRY',
      'transversal_inventory',jsonb_build_object(
        'schema_version','TRANSVERSAL_ASSET_INDEX_V1',
        'logical_key',v_capability_code,
        'class','CAPABILITY_INFRASTRUCTURE',
        'inventory_status','FORMAL_TRANSVERSAL_ACTIVE',
        'lookup_rule','ASSET_INVENTORY_FIRST_THEN_CURRENTNESS_THEN_EXPAND_SEARCH',
        'physical_assets',jsonb_build_array(
          'public.lf_capability_registry:DB_WRITE_TRANSPORT',
          'public.lf_capability_current:DB_WRITE_TRANSPORT@1.0.0',
          'sandbox/lf_contract_gate_test/db_write_transport/lf_db_write_transport.py',
          'sandbox/lf_contract_gate_test/db_write_transport/README.md'
        ),
        'consumers_known',jsonb_build_array('ACTUALIZACION_DB_LF'),
        'no_duplicate_engine',true,
        'source_pr',880,
        'source_main_sha','1027cf217cc8301c9f56cc7e5b54e6fc2a84bb1d',
        'migration_transport_rule','EXACT_VERSION_SOURCE_FIRST',
        'direct_transport_rule','SUPABASE_MCP',
        'inventory_execution_id',v_execution_id
      )
    ),
    v_execution_id,v_execution_id
  );

  -- Bind the transversal capability to the canonical DB update operation contract.
  UPDATE public.lf_operation_contracts
  SET
    allowed = allowed || jsonb_build_object(
      'db_write_transport_capability',v_capability_code,
      'db_write_transport_version',v_version,
      'db_write_transport_selector_ref','sandbox/lf_contract_gate_test/db_write_transport/lf_db_write_transport.py',
      'migration_transport_mode','EXACT_VERSION_SOURCE_FIRST',
      'migration_primary_executor','SUPABASE_CLI_DB_PUSH_LINKED',
      'migration_fallback_executor','SOURCE_FIRST_EXACT_VERSION_MANUAL_LEDGER_DML',
      'direct_db_write_executor','SUPABASE_MCP'
    ),
    required_before_write = (
      SELECT coalesce(jsonb_agg(to_jsonb(v) ORDER BY v),'[]'::jsonb)
      FROM (
        SELECT DISTINCT value AS v
        FROM jsonb_array_elements_text(
          required_before_write || jsonb_build_array(
            'db_write_transport_capability_preflight',
            'db_write_transport_capability_binding'
          )
        )
      ) q
    ),
    blocked = (
      SELECT coalesce(jsonb_agg(to_jsonb(v) ORDER BY v),'[]'::jsonb)
      FROM (
        SELECT DISTINCT value AS v
        FROM jsonb_array_elements_text(
          blocked || jsonb_build_array(
            'exact_version_migration_via_apply_migration',
            'migration_server_timestamp_remint',
            'migration_transport_without_selector'
          )
        )
      ) q
    ),
    required_after_write = (
      SELECT coalesce(jsonb_agg(to_jsonb(v) ORDER BY v),'[]'::jsonb)
      FROM (
        SELECT DISTINCT value AS v
        FROM jsonb_array_elements_text(
          required_after_write || jsonb_build_array('db_write_transport_readback')
        )
      ) q
    ),
    updated_at=clock_timestamp(),
    updated_by_execution_id=v_execution_id
  WHERE operation_code='ACTUALIZACION_DB_LF'
    AND contract_code='CONTRACT-ACTUALIZACION-DB-LF-v0.1'
    AND status='ACTIVE_ENFORCEMENT';

  UPDATE public.lf_operation_contracts
  SET contract_sha=encode(extensions.digest(convert_to(jsonb_build_object(
      'operation_code',operation_code,
      'contract_code',contract_code,
      'contract_path',contract_path,
      'required_before_write',required_before_write,
      'allowed',allowed,
      'blocked',blocked,
      'required_after_write',required_after_write
    )::text,'UTF8'),'sha256'),'hex'),
    updated_at=clock_timestamp(),
    updated_by_execution_id=v_execution_id
  WHERE operation_code='ACTUALIZACION_DB_LF'
    AND contract_code='CONTRACT-ACTUALIZACION-DB-LF-v0.1'
    AND status='ACTIVE_ENFORCEMENT';

  -- Surface the binding in the step contracts actually consumed by operation runners.
  UPDATE public.lf_operation_step_contracts
  SET
    input_required=(
      SELECT coalesce(jsonb_agg(to_jsonb(v) ORDER BY v),'[]'::jsonb)
      FROM (SELECT DISTINCT value AS v FROM jsonb_array_elements_text(input_required || jsonb_build_array('db_write_transport_capability_binding'))) q
    ),
    required_evidence_keys=(
      SELECT coalesce(jsonb_agg(to_jsonb(v) ORDER BY v),'[]'::jsonb)
      FROM (SELECT DISTINCT value AS v FROM jsonb_array_elements_text(required_evidence_keys || jsonb_build_array('db_write_transport_capability_binding'))) q
    ),
    updated_at=clock_timestamp(),updated_by_execution_id=v_execution_id
  WHERE operation_code='ACTUALIZACION_DB_LF' AND step_id='preflight' AND status='ACTIVE_ENFORCEMENT';

  UPDATE public.lf_operation_step_contracts
  SET
    resolver_ref=v_capability_code,
    input_required=(
      SELECT coalesce(jsonb_agg(to_jsonb(v) ORDER BY v),'[]'::jsonb)
      FROM (SELECT DISTINCT value AS v FROM jsonb_array_elements_text(input_required || jsonb_build_array('db_write_transport_decision'))) q
    ),
    output_payload=(
      SELECT coalesce(jsonb_agg(to_jsonb(v) ORDER BY v),'[]'::jsonb)
      FROM (SELECT DISTINCT value AS v FROM jsonb_array_elements_text(output_payload || jsonb_build_array('db_write_transport_receipt'))) q
    ),
    required_evidence_keys=(
      SELECT coalesce(jsonb_agg(to_jsonb(v) ORDER BY v),'[]'::jsonb)
      FROM (SELECT DISTINCT value AS v FROM jsonb_array_elements_text(required_evidence_keys || jsonb_build_array('db_write_transport_decision','db_write_transport_receipt'))) q
    ),
    notes=coalesce(notes,'') || ' DB_WRITE_TRANSPORT selects exact-version source-first for MIGRATION and governed SUPABASE_MCP for direct DB/FUNCTION/TRIGGER writes.',
    updated_at=clock_timestamp(),updated_by_execution_id=v_execution_id
  WHERE operation_code='ACTUALIZACION_DB_LF' AND step_id='patch' AND status='ACTIVE_ENFORCEMENT';

  UPDATE public.lf_operation_step_contracts
  SET
    input_required=(
      SELECT coalesce(jsonb_agg(to_jsonb(v) ORDER BY v),'[]'::jsonb)
      FROM (SELECT DISTINCT value AS v FROM jsonb_array_elements_text(input_required || jsonb_build_array('db_write_transport_readback'))) q
    ),
    required_evidence_keys=(
      SELECT coalesce(jsonb_agg(to_jsonb(v) ORDER BY v),'[]'::jsonb)
      FROM (SELECT DISTINCT value AS v FROM jsonb_array_elements_text(required_evidence_keys || jsonb_build_array('db_write_transport_readback'))) q
    ),
    updated_at=clock_timestamp(),updated_by_execution_id=v_execution_id
  WHERE operation_code='ACTUALIZACION_DB_LF' AND step_id='verify' AND status='ACTIVE_ENFORCEMENT';

  UPDATE public.lf_operation_steps
  SET evidence_required=CASE
        WHEN evidence_required ILIKE '%db_write_transport_binding%' THEN evidence_required
        ELSE evidence_required || '; db_write_transport_binding'
      END,
      updated_at=clock_timestamp(),updated_by_execution_id=v_execution_id
  WHERE operation_code='ACTUALIZACION_DB_LF' AND step_id='preflight' AND active=true;

  UPDATE public.lf_operation_steps
  SET evidence_required=CASE
        WHEN evidence_required ILIKE '%db_write_transport_receipt%' THEN evidence_required
        ELSE evidence_required || '; db_write_transport_decision; db_write_transport_receipt'
      END,
      updated_at=clock_timestamp(),updated_by_execution_id=v_execution_id
  WHERE operation_code='ACTUALIZACION_DB_LF' AND step_id='patch' AND active=true;

  UPDATE public.lf_operation_steps
  SET evidence_required=CASE
        WHEN evidence_required ILIKE '%db_write_transport_readback%' THEN evidence_required
        ELSE evidence_required || '; db_write_transport_readback'
      END,
      updated_at=clock_timestamp(),updated_by_execution_id=v_execution_id
  WHERE operation_code='ACTUALIZACION_DB_LF' AND step_id='verify' AND active=true;

  UPDATE public.lf_operation_registry
  SET source_paths=(
      SELECT coalesce(jsonb_agg(to_jsonb(v) ORDER BY v),'[]'::jsonb)
      FROM (
        SELECT DISTINCT value AS v
        FROM jsonb_array_elements_text(source_paths || jsonb_build_array(
          'public.lf_capability_registry','public.lf_capability_current','public.lf_capability_binding'
        ))
      ) q
    ),
    notes=coalesce(notes,'') || ' DB_WRITE_TRANSPORT v1 is the transversal selector for write-channel choice; authority remains in Router/contracts.',
    updated_at=clock_timestamp(),updated_by_execution_id=v_execution_id
  WHERE operation_code='ACTUALIZACION_DB_LF';

  -- Exact postconditions: capability is current, inventoried and enforced by the DB updater.
  IF NOT EXISTS (
    SELECT 1
    FROM public.lf_capability_current c
    JOIN public.lf_capability_version_registry v
      ON v.capability_code=c.capability_code AND v.version=c.version AND v.manifest_sha256=c.manifest_sha256
    WHERE c.capability_code=v_capability_code
      AND c.version=v_version
      AND c.manifest_sha256=v_manifest_sha
      AND v.release_state='RELEASED'
  ) THEN
    RAISE EXCEPTION 'BLOCK_DB_WRITE_TRANSPORT_CURRENT_READBACK';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_activos
    WHERE codigo_activo=v_capability_code
      AND nombre_canonico='TRANSVERSAL_DB_WRITE_TRANSPORT'
      AND tipo_activo='CAPABILITY'
      AND estado_documental='VIGENTE'
      AND estado_operativo='ACTIVO'
      AND version=v_version
      AND ruta_esperada='sandbox/lf_contract_gate_test/db_write_transport/lf_db_write_transport.py'
      AND metadata #>> '{transversal_inventory,inventory_status}'='FORMAL_TRANSVERSAL_ACTIVE'
      AND archived_at IS NULL
  ) THEN
    RAISE EXCEPTION 'BLOCK_DB_WRITE_TRANSPORT_ASSET_READBACK';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_operation_contracts
    WHERE operation_code='ACTUALIZACION_DB_LF'
      AND contract_code='CONTRACT-ACTUALIZACION-DB-LF-v0.1'
      AND status='ACTIVE_ENFORCEMENT'
      AND allowed->>'db_write_transport_capability'=v_capability_code
      AND allowed->>'db_write_transport_version'=v_version
      AND allowed->>'migration_transport_mode'='EXACT_VERSION_SOURCE_FIRST'
      AND allowed->>'migration_primary_executor'='SUPABASE_CLI_DB_PUSH_LINKED'
      AND allowed->>'direct_db_write_executor'='SUPABASE_MCP'
      AND required_before_write ? 'db_write_transport_capability_preflight'
      AND required_before_write ? 'db_write_transport_capability_binding'
      AND blocked ? 'exact_version_migration_via_apply_migration'
      AND blocked ? 'migration_server_timestamp_remint'
      AND required_after_write ? 'db_write_transport_readback'
      AND contract_sha ~ '^[0-9a-f]{64}$'
  ) THEN
    RAISE EXCEPTION 'BLOCK_DB_WRITE_TRANSPORT_OPERATION_CONTRACT_READBACK';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_operation_step_contracts
    WHERE operation_code='ACTUALIZACION_DB_LF'
      AND step_id='patch'
      AND status='ACTIVE_ENFORCEMENT'
      AND resolver_ref=v_capability_code
      AND input_required ? 'db_write_transport_decision'
      AND output_payload ? 'db_write_transport_receipt'
      AND required_evidence_keys ? 'db_write_transport_decision'
      AND required_evidence_keys ? 'db_write_transport_receipt'
  ) THEN
    RAISE EXCEPTION 'BLOCK_DB_WRITE_TRANSPORT_PATCH_STEP_READBACK';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_operation_step_contracts
    WHERE operation_code='ACTUALIZACION_DB_LF'
      AND step_id='preflight'
      AND status='ACTIVE_ENFORCEMENT'
      AND input_required ? 'db_write_transport_capability_binding'
      AND required_evidence_keys ? 'db_write_transport_capability_binding'
  ) OR NOT EXISTS (
    SELECT 1 FROM public.lf_operation_step_contracts
    WHERE operation_code='ACTUALIZACION_DB_LF'
      AND step_id='verify'
      AND status='ACTIVE_ENFORCEMENT'
      AND input_required ? 'db_write_transport_readback'
      AND required_evidence_keys ? 'db_write_transport_readback'
  ) THEN
    RAISE EXCEPTION 'BLOCK_DB_WRITE_TRANSPORT_STEP_CONTRACT_READBACK';
  END IF;
END
$db_write_transport$;

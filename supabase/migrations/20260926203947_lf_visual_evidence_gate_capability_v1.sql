-- LF_VISUAL_EVIDENCE_GATE_CAPABILITY_V1
-- Registry/currentness materialization only. No carrier, runtime, production, or automatic-impact activation.
-- Canonical source revision: b7853ab92fda1e4c9d66f7f3db36e7f6311a8354

do $lf_visual_capability$
declare
  v_execution_id constant text := 'EXEC-VISUAL-EVIDENCE-GATE-REGISTER-20260926-001';
  v_capability_code constant text := 'VISUAL_EVIDENCE_GATE';
  v_version constant text := '1.0.0';
  v_source_sha constant text := 'b7853ab92fda1e4c9d66f7f3db36e7f6311a8354';
  v_target_path constant text := 'supabase/migrations/20260926203947_lf_visual_evidence_gate_capability_v1.sql';
  v_inventory_batch uuid := gen_random_uuid();
  v_manifest jsonb := $manifest${
    "schema_version":"LF_CAPABILITY_MANIFEST_V1",
    "capability_code":"VISUAL_EVIDENCE_GATE",
    "version":"1.0.0",
    "contract":{
      "input":"LF_VISUAL_EVIDENCE_GATE_INPUT_V1",
      "output":"LF_VISUAL_EVIDENCE_GATE_RESULT_V1",
      "authority":"VISUAL_COMPLETENESS_FIDELITY_VALIDATION_ONLY_NO_APPLICABILITY_OR_ADMISSION_OR_RUNTIME_AUTHORIZATION"
    },
    "delivery":{
      "mode":"VERSIONED_REPOSITORY_CAPABILITY",
      "runner":"sandbox/lf_contract_gate_test/visual_evidence_gate/visual_evidence_gate_v1.py",
      "consumer_state":"REGISTERED_NOT_CUTOVER",
      "legacy_orchestration_alias":"P0_VISUAL_RUNTIME"
    },
    "installation":{
      "required":false,
      "reinstall_required":false,
      "package_update_mode":"REPOSITORY_BOUND"
    },
    "dependencies":{
      "packages":[
        "python>=3.11",
        "Pillow==12.3.0",
        "numpy==2.3.5",
        "opencv-python-headless==4.13.0.92",
        "tesseract==5.3.4",
        "tesseract-languages=spa+eng"
      ],
      "capabilities":["CURRENTNESS_AUTHORITY"],
      "governance":["ACT-0001"],
      "runtime_config":"sandbox/story_creator_p0_visual/v1.1/evals/p0-visual-quality-runtime-config.json"
    },
    "compatibility":{
      "unknown_target":"FAIL_CLOSED",
      "legacy_alias_preserved":true,
      "visual_quality_bundle":"sandbox/lf_contract_gate_test/P0_VISUAL_QUALITY_REGRESSION_BUNDLE_V1.py",
      "carrier_cutover":"PENDING_SEPARATE_PR"
    },
    "migration":{
      "mode":"REGISTRY_ONLY_NO_CARRIER_CUTOVER",
      "registration_source":"supabase/migrations/20260926203947_lf_visual_evidence_gate_capability_v1.sql"
    },
    "rollback":{
      "supported":true,
      "rule":"SEPARATELY_GOVERNED_REGISTRY_RELATION_POINTER_REVERSAL;NO_RUNTIME_OR_PRODUCTION_CHANGE",
      "source_preserved":true
    },
    "usage":{
      "runner":"sandbox/lf_contract_gate_test/visual_evidence_gate/visual_evidence_gate_v1.py",
      "docs":"sandbox/lf_contract_gate_test/visual_evidence_gate/README.md",
      "validator":"sandbox/lf_contract_gate_test/visual_evidence_gate/test_visual_evidence_gate_v1.py",
      "legacy_bundle":"sandbox/lf_contract_gate_test/P0_VISUAL_QUALITY_REGRESSION_BUNDLE_V1.py",
      "ownership_guard":"sandbox/lf_contract_gate_test/test_e16_visual_ownership_cleanup_v1.py"
    },
    "currentness":{
      "authority_capability":"CURRENTNESS_AUTHORITY",
      "authority_ref":"github://cristhianlujan/claude-persona-lf-patch@b7853ab92fda1e4c9d66f7f3db36e7f6311a8354",
      "source_revision_immutable":true,
      "runtime_authorized":false,
      "production_authorized":false,
      "carrier_cutover_authorized":false,
      "automatic_impact_authorized":false
    }
  }$manifest$::jsonb;
  v_manifest_sha text;
  v_promotion jsonb;
  v_count bigint;
begin
  if not exists (
    select 1
    from public.lf_operation_execution
    where execution_id=v_execution_id
      and operation_code='ACTUALIZACION_DB_LF'
      and target_type='MIGRATION'
      and target_code='VISUAL_EVIDENCE_GATE_CAPABILITY_V1'
      and target_repo='cristhianlujan/claude-persona-lf-patch'
      and target_path=v_target_path
      and status='IN_PROGRESS'
  ) then
    raise exception 'BLOCK_VISUAL_CAPABILITY_EXECUTION_BINDING';
  end if;

  if to_regprocedure('public.fn_lf_capability_promote_v1(text,text,text,text,text)') is null then
    raise exception 'BLOCK_VISUAL_CAPABILITY_PROMOTER_NOT_FOUND';
  end if;

  if not exists (
    select 1
    from public.lf_capability_registry r
    join public.lf_capability_current c using (capability_code)
    join public.lf_capability_version_registry v
      on v.capability_code=c.capability_code and v.version=c.version
    where r.capability_code='CURRENTNESS_AUTHORITY'
      and r.status='ACTIVE'
      and v.release_state='RELEASED'
      and v.manifest_sha256=c.manifest_sha256
  ) then
    raise exception 'BLOCK_VISUAL_CAPABILITY_CURRENTNESS_AUTHORITY_NOT_CURRENT';
  end if;

  if exists (select 1 from public.lf_capability_registry where capability_code=v_capability_code)
     or exists (select 1 from public.lf_capability_version_registry where capability_code=v_capability_code)
     or exists (select 1 from public.lf_capability_current where capability_code=v_capability_code)
     or exists (select 1 from public.lf_activos where codigo_activo=v_capability_code and archived_at is null)
     or exists (select 1 from public.lf_activo_relaciones where codigo_activo=v_capability_code) then
    raise exception 'BLOCK_VISUAL_CAPABILITY_PREEXISTING_STATE';
  end if;

  insert into public.lf_capability_registry(
    capability_code,capability_name,capability_kind,owner_scope,status,description,
    created_by_execution_id,updated_by_execution_id
  ) values (
    v_capability_code,'LF Visual Evidence Gate','TRANSVERSAL','LF_GOVERNANCE','ACTIVE',
    'Standalone fail-closed visual completeness/fidelity validation capability. Registry currentness does not authorize applicability, path admission, exact-head transport, human decisions, carrier/runtime activation, production, or automatic impact.',
    v_execution_id,v_execution_id
  );

  v_manifest_sha := encode(extensions.digest(convert_to(v_manifest::text,'UTF8'),'sha256'),'hex');

  insert into public.lf_capability_version_registry(
    capability_code,version,version_major,version_minor,version_patch,release_state,
    supersedes_version,manifest,manifest_sha256,source_ref,docs_ref,validator_ref,created_by_execution_id
  ) values (
    v_capability_code,v_version,1,0,0,'RELEASED',null,v_manifest,v_manifest_sha,
    'github://cristhianlujan/claude-persona-lf-patch@b7853ab92fda1e4c9d66f7f3db36e7f6311a8354/sandbox/lf_contract_gate_test/visual_evidence_gate/visual_evidence_gate_v1.py',
    'github://cristhianlujan/claude-persona-lf-patch@b7853ab92fda1e4c9d66f7f3db36e7f6311a8354/sandbox/lf_contract_gate_test/visual_evidence_gate/README.md',
    'github://cristhianlujan/claude-persona-lf-patch@b7853ab92fda1e4c9d66f7f3db36e7f6311a8354/sandbox/lf_contract_gate_test/visual_evidence_gate/test_visual_evidence_gate_v1.py',
    v_execution_id
  );

  v_promotion := public.fn_lf_capability_promote_v1(
    v_capability_code,v_version,null,v_execution_id,
    'Register current VISUAL_EVIDENCE_GATE v1 from exact main source without carrier/runtime/production cutover'
  );
  if coalesce((v_promotion->>'ready')::boolean,false) is not true then
    raise exception 'BLOCK_VISUAL_CAPABILITY_CURRENT_PROMOTION:%',v_promotion::text;
  end if;

  insert into public.lf_activos(
    codigo_activo,nombre_canonico,tipo_activo,subtipo_activo,
    estado_documental,estado_operativo,nivel_control,runtime_estado,impacto_automatico,
    version,ruta_esperada,url,owner_name,ultima_revision,rol_arquitectura,
    source_spreadsheet_id,source_spreadsheet_title,source_sheet_name,source_row_number,
    migration_batch_id,raw_payload,metadata,created_by_execution_id,updated_by_execution_id
  ) values (
    v_capability_code,'TRANSVERSAL_VISUAL_EVIDENCE_GATE','CAPABILITY','TRANSVERSAL_VISUAL_VALIDATION_CAPABILITY',
    'VIGENTE','READ_ONLY','FAIL_CLOSED','NO_HABILITADO','BLOQUEADO',
    v_version,'sandbox/lf_contract_gate_test/visual_evidence_gate/visual_evidence_gate_v1.py',
    'supabase://public/lf_capability_registry/VISUAL_EVIDENCE_GATE/1.0.0','LF_GOVERNANCE',
    v_source_sha,'TRANSVERSAL_VISUAL_EVIDENCE_GATE',
    'NATIVE_SUPABASE','LF_TRANSVERSAL_CAPABILITY_INVENTORY','VISUAL_EVIDENCE_GATE_20260926',1,
    v_inventory_batch,
    jsonb_build_object(
      'key',v_capability_code,
      'class','VISUAL_VALIDATION_CAPABILITY',
      'status','REGISTERED_NOT_CUTOVER',
      'legacy_alias','P0_VISUAL_RUNTIME',
      'source_main_sha',v_source_sha,
      'production_authorized',false,
      'runtime_authorized',false,
      'carrier_cutover_authorized',false
    ),
    jsonb_build_object(
      'source_kind','GITHUB_SOURCE_PLUS_SUPABASE_REGISTRY',
      'current_pointer_semantics','CANONICAL_CAPABILITY_VERSION_ONLY',
      'carrier_state','NOT_CUTOVER',
      'automatic_impact_authorized',false,
      'visual_dependency_config','sandbox/story_creator_p0_visual/v1.1/evals/p0-visual-quality-runtime-config.json',
      'inventory_execution_id',v_execution_id
    ),
    v_execution_id,v_execution_id
  );

  insert into public.lf_activo_relaciones(
    codigo_activo,relacionado_codigo,relacion_tipo,valor_original,fuente,
    migration_batch_id,created_by_execution_id,updated_by_execution_id
  ) values (
    v_capability_code,'CURRENTNESS_AUTHORITY','DEPENDE_DE','CURRENTNESS_AUTHORITY',
    v_target_path,v_inventory_batch,v_execution_id,v_execution_id
  );

  if not exists (
    select 1 from public.lf_capability_registry
    where capability_code=v_capability_code
      and capability_name='LF Visual Evidence Gate'
      and capability_kind='TRANSVERSAL'
      and owner_scope='LF_GOVERNANCE'
      and status='ACTIVE'
  ) then
    raise exception 'BLOCK_VISUAL_CAPABILITY_REGISTRY_READBACK';
  end if;

  if not exists (
    select 1 from public.lf_capability_version_registry
    where capability_code=v_capability_code and version=v_version
      and release_state='RELEASED'
      and manifest=v_manifest and manifest_sha256=v_manifest_sha
      and source_ref='github://cristhianlujan/claude-persona-lf-patch@b7853ab92fda1e4c9d66f7f3db36e7f6311a8354/sandbox/lf_contract_gate_test/visual_evidence_gate/visual_evidence_gate_v1.py'
  ) then
    raise exception 'BLOCK_VISUAL_CAPABILITY_VERSION_READBACK';
  end if;

  if not exists (
    select 1 from public.lf_capability_current
    where capability_code=v_capability_code and version=v_version and manifest_sha256=v_manifest_sha
  ) then
    raise exception 'BLOCK_VISUAL_CAPABILITY_CURRENT_READBACK';
  end if;

  if not exists (
    select 1 from public.lf_activos
    where codigo_activo=v_capability_code
      and estado_documental='VIGENTE'
      and estado_operativo='READ_ONLY'
      and nivel_control='FAIL_CLOSED'
      and runtime_estado='NO_HABILITADO'
      and impacto_automatico='BLOQUEADO'
      and version=v_version
      and ultima_revision=v_source_sha
      and archived_at is null
  ) then
    raise exception 'BLOCK_VISUAL_CAPABILITY_ASSET_READBACK';
  end if;

  select count(*) into v_count
  from public.lf_activo_relaciones
  where codigo_activo=v_capability_code
    and relacionado_codigo='CURRENTNESS_AUTHORITY'
    and relacion_tipo='DEPENDE_DE';
  if v_count <> 1 then
    raise exception 'BLOCK_VISUAL_CAPABILITY_RELATION_READBACK:%',v_count;
  end if;

  if (v_manifest #>> '{currentness,runtime_authorized}')::boolean
     or (v_manifest #>> '{currentness,production_authorized}')::boolean
     or (v_manifest #>> '{currentness,carrier_cutover_authorized}')::boolean
     or (v_manifest #>> '{currentness,automatic_impact_authorized}')::boolean then
    raise exception 'BLOCK_VISUAL_CAPABILITY_UNAUTHORIZED_ACTIVATION';
  end if;
end
$lf_visual_capability$;

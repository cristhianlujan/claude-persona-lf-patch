-- IG_CURATOR_VALIDATOR_REFACTOR_V2 · M1.A2 / PAULO-037
-- Semantic technology ADR + INPUT_GOVERNANCE_EXECUTION_CONTRACT 1.6.
-- Architecture/contract only. No runtime deploy, no M2.6/M2.8/M3.7 implementation.

do $$
declare
  v_execution_id constant text := 'CHATGPT-IG-CV-M1A2-PAULO037-20261004';
  v_contract_path constant text := 'docs/input-governance/contracts/input_governance_execution_contract_v1_6.json';
  v_git_blob constant text := '7fca301bd4bb81c169139a307f1efed353a57398';
  v_db_sha text;
  v_count integer;
begin
  -- Exact preconditions: no broad rediscovery and no silent overwrite of drift.
  if (select count(*) from programacion.contratos
      where id=42 and version_id=19
        and contrato_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT'
        and estado='defined'
        and especificacion->>'contract_revision'='1.5') <> 1 then
    raise exception 'BLOCK_M1A2_EXEC_CONTRACT_PRECONDITION_DRIFT';
  end if;

  if (select count(*) from transversal.decision_log
      where adr='DEC-INPUT-GOV-RUNTIME-001'
        and upper(coalesce(estado,'')) in ('VIGENTE','ACTIVE','ACTIVO')) <> 1 then
    raise exception 'BLOCK_M1A2_RUNTIME_ADR_NOT_CURRENT';
  end if;

  if exists (select 1 from transversal.decision_log where adr='DEC-INPUT-GOV-SEMANTIC-TECH-001') then
    raise exception 'BLOCK_M1A2_SEMANTIC_ADR_ALREADY_EXISTS_REVALIDATE';
  end if;

  if (select count(*) from public.lf_capability_registry
      where capability_code in (
        'CAPABILITY_SELECTOR','CURRENTNESS_AUTHORITY','TYPED_EVIDENCE_REGISTRY',
        'DECISION_CONTEXT_ASOF','CAPABILITY_VERSION_COMPATIBILITY','INDEPENDENT_ASSURANCE'
      ) and status='ACTIVE') <> 6 then
    raise exception 'BLOCK_M1A2_REQUIRED_TRANSVERSAL_CAPABILITY_NOT_ACTIVE';
  end if;

  insert into transversal.decision_log(adr,titulo,decision,razon,impacto,estado)
  values(
    'DEC-INPUT-GOV-SEMANTIC-TECH-001',
    'Tecnologia semantica deterministica-first para Input Governance',
    'M1.A2 / PAULO-037 define una sola frontera semantica: determinismo gana cuando satisface el contrato; solo gaps semanticos no derivables pueden invocar capacidad no determinista. CAPABILITY_SELECTOR selecciona capacidades desde signals/catalog/policy; CAPABILITY_VERSION_COMPATIBILITY resuelve versiones compatibles; execution profile/model/provider se resuelven dinamicamente por policy y atestacion, sin hardcode en IG. Output de modelo es evidencia/propuesta y nunca autoridad por si mismo. UNCERTAIN, CONTRADICTORY o INSUFFICIENT_EVIDENCE fallan cerrado o disparan refresh material acotado. La no determinacion queda aislada al gap declarado y no puede reescribir campos ya resueltos deterministicamente. IG consume TYPED_EVIDENCE_REGISTRY, CURRENTNESS_AUTHORITY, DECISION_CONTEXT_ASOF e INDEPENDENT_ASSURANCE; no crea autoridad ni motor paralelo. Owner humano SUPER_ADMIN.',
    'El contrato 1.5 declaraba UNBOUND_SEMANTIC_RUNTIME y EXTERNAL_SEMANTIC_RUNTIME_REQUIRED_FOR_NEW_OR_CHANGED_SCOPE aunque Agent/Curator/Validator ya existen live y Curator delega en SQL/RPC gobernado. La decision corrige el contrato sin reemplazar runtime, preserva DEC-INPUT-GOV-RUNTIME-001 y permite que consumidores posteriores distingan resolucion determinista de gap semantico real.',
    'ADR + enmienda contractual. No despliega runtime, no autoriza promocion/produccion y no implementa M2.6, M2.8 ni M3.7. Evidencia historica valida no se invalida por una ejecucion nueva; refresh solo por MISSING/CONTRADICTION/STALE/DRIFT/material fingerprint change.',
    'vigente'
  );

  update programacion.contratos
  set especificacion = especificacion || jsonb_build_object(
        'contract_revision','1.6',
        'semantic_technology_decision','DEC-INPUT-GOV-SEMANTIC-TECH-001',
        'human_owner','SUPER_ADMIN',
        'runtime_binding_status','BOUND_ROLE_RUNTIMES_POLICY_DRIVEN_SEMANTIC_CAPABILITY',
        'semantic_curator_runtime','POLICY_SELECTED_CAPABILITY_ONLY_FOR_NON_DERIVABLE_GAPS',
        'semantic_provider','POLICY_SELECTED_NO_HARDCODED_PROVIDER',
        'historical_evidence_policy','NEW_RUN_DOES_NOT_INVALIDATE_VALID_PRIOR_EVIDENCE',
        'fresh_check_sample_policy','RUN_HISTORY_EFFECTIVENESS_SAMPLE_V1',
        'semantic_resolution_contract',jsonb_build_object(
          'mode','DETERMINISTIC_FIRST',
          'deterministic_priority',true,
          'model_allowed_only_for','NON_DERIVABLE_SEMANTIC_GAP',
          'model_output_authority',false,
          'input_required',jsonb_build_array(
            'subject_version_identity','requested_obligations','authority_refs_digests',
            'typed_evidence','deterministic_results','unresolved_semantic_gaps',
            'consumer_policy_ref_version','currentness_compatibility_state','execution_id_trace_id'
          ),
          'output_required',jsonb_build_array(
            'gap_results','evidence_refs','uncertainty_state','contradictions',
            'selection_attestation','execution_receipt_digests','fallback_or_block_reason'
          ),
          'selection',jsonb_build_object(
            'capability_selector','CAPABILITY_SELECTOR',
            'version_resolver','CAPABILITY_VERSION_COMPATIBILITY',
            'typed_evidence','TYPED_EVIDENCE_REGISTRY',
            'currentness','CURRENTNESS_AUTHORITY',
            'decision_context','DECISION_CONTEXT_ASOF',
            'independent_assurance','INDEPENDENT_ASSURANCE',
            'execution_profile_model_provider','POLICY_DRIVEN',
            'hardcoded_provider_model',false,
            'selection_does_not_grant_authority',true
          ),
          'states',jsonb_build_object(
            'uncertain','NO_CANONICAL_ADMISSION',
            'contradictory','FAIL_CLOSED',
            'insufficient_evidence','BOUNDED_MATERIAL_REFRESH_ONLY'
          ),
          'reproducibility',jsonb_build_object(
            'deterministic_portion_exact_replay',true,
            'non_determinism_isolated_to_declared_gaps',true,
            'bind_contract_authority_policy_capability_runtime_and_raw_output_digests',true
          ),
          'fallback_order',jsonb_build_array(
            'DETERMINISTIC_GOVERNED_RESOLUTION',
            'POLICY_SELECTED_SEMANTIC_CAPABILITY',
            'CONSUMER_CONFIGURED_GOVERNED_FALLBACK',
            'FAIL_CLOSED'
          ),
          'authority_boundary','IG_CONSUMER_ORCHESTRATOR_NOT_OWNER_OF_TRANSVERSAL_AUTHORITIES'
        )
      ),
      descripcion = 'Fail-closed Input Governance execution contract. Deterministic-first; governed semantic capability only for non-derivable gaps; model output is non-authoritative. Existing Agent/Curator/Validator role runtimes remain bound.'
  where id=42 and version_id=19
    and contrato_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT'
    and estado='defined'
    and especificacion->>'contract_revision'='1.5';

  if not found then
    raise exception 'BLOCK_M1A2_EXEC_CONTRACT_UPDATE_MISSED';
  end if;

  select encode(extensions.digest(convert_to(especificacion::text,'UTF8'),'sha256'),'hex')
    into v_db_sha
  from programacion.contratos
  where id=42 and version_id=19 and contrato_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT';

  update public.lf_activos
  set version='1.6',
      ruta_esperada=v_contract_path,
      raw_payload=(raw_payload - 'db_sha256' - 'git_blob_sha') || jsonb_build_object(
        'source_contract_id',42,
        'source_version_id',19,
        'contract_revision','1.6',
        'canonical_authority','programacion.contratos',
        'db_sha256',v_db_sha,
        'git_blob_sha',v_git_blob,
        'git_path',v_contract_path,
        'supersedes_revision','1.5'
      ),
      metadata=metadata || jsonb_build_object(
        'plan_id','IG_CURATOR_VALIDATOR_REFACTOR_V2',
        'unit_code','M1.A2',
        'work_code','PAULO-037',
        'source_pack','SOURCE_PACK_V1',
        'fast_path','SOURCE_PACK_FAST_PATH_V1',
        'human_owner','SUPER_ADMIN',
        'runtime_authorized',false,
        'production_authorized',false
      ),
      updated_at=now(),
      updated_by_execution_id=v_execution_id
  where codigo_activo='INPUT_GOVERNANCE_EXECUTION_CONTRACT'
    and archived_at is null
    and version='1.5';

  if not found then
    raise exception 'BLOCK_M1A2_CONTRACT_ASSET_UPDATE_MISSED';
  end if;

  update public.lf_activo_relaciones
  set valor_original='programacion.contratos id=42 version_id=19 revision=1.6; deterministic-first semantic contract; frozen Git snapshot for governed consumption',
      fuente=v_contract_path,
      updated_by_execution_id=v_execution_id
  where codigo_activo='EDGE_FN_INPUT_GOVERNANCE_AGENT_V1'
    and relacionado_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT'
    and relacion_tipo='FUENTE_RECTORA';

  get diagnostics v_count = row_count;
  if v_count <> 1 then
    raise exception 'BLOCK_M1A2_CONTRACT_RELATION_COUNT:%', v_count;
  end if;

  -- Terminal in-migration readback.
  if (select especificacion->>'contract_revision' from programacion.contratos where id=42) <> '1.6' then
    raise exception 'BLOCK_M1A2_REVISION_READBACK';
  end if;
  if (select especificacion#>>'{semantic_resolution_contract,mode}' from programacion.contratos where id=42) <> 'DETERMINISTIC_FIRST' then
    raise exception 'BLOCK_M1A2_MODE_READBACK';
  end if;
  if coalesce((select (especificacion#>>'{semantic_resolution_contract,model_output_authority}')::boolean from programacion.contratos where id=42),true) then
    raise exception 'BLOCK_M1A2_MODEL_AUTHORITY_READBACK';
  end if;
  if (select count(*) from transversal.decision_log where adr='DEC-INPUT-GOV-SEMANTIC-TECH-001' and estado='vigente') <> 1 then
    raise exception 'BLOCK_M1A2_ADR_READBACK';
  end if;
end $$;

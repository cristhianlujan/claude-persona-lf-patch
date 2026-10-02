-- IG_CURATOR_VALIDATOR_REFACTOR_V2 · M1.A4 / PAULO-124
-- R16 Git-first reconciliation.
-- Reconciles the already-live VIGENTE family-universe rule with canonical Git source,
-- updates INPUT_READINESS_CONTRACT 5.13 to D-M1.4 authority, and keeps the M1.A1
-- contract snapshot asset hashes aligned with the byte-exact Git snapshot in this PR.
-- No runtime/deploy/production activation.

do $$
declare
  v_execution_id constant text := 'CHATGPT-IG-CV-M1A4-R16-20261002';
  v_old_db_sha constant text := '95a6a97ae457c3a11f494f840770a00dfec3fc547c5e553f73d2c0d4292e9df3';
  v_old_git_blob constant text := '8531ae2dc9f5ed65ed5fea6fc27df01ff1f42bb7';
  v_new_db_sha constant text := '9b337b4ee4b7b4438ae42fe681b2e704d78e18a008abb1c697d45dac7bbadfbc';
  v_new_git_blob constant text := '5524dd88c74c2f6daa42b0c150e37eacd32caa51';
  v_count integer;
  v_sha text;
  v_bytes integer;
begin
  -- D-M1.4 is the explicit owner authority required by this unit.
  if not exists (
    select 1
    from transversal.decision_log
    where adr='DEC-INPUT-GOV-D-M1.4'
      and lower(estado)='vigente'
  ) then
    raise exception 'BLOCK_M1A4_DM14_NOT_VIGENTE';
  end if;

  -- Rule 463 source reconciliation. Current sandbox is already VIGENTE; therefore
  -- this UPDATE is intentionally a no-op there and does not churn updated_at.
  select count(*) into v_count
  from lf_ops.reglas
  where id=463
    and codigo='B2B-RULE-STORY-READINESS-001'
    and estado in ('CANDIDATO','VIGENTE')
    and not pendiente_decision
    and jsonb_array_length(valor_config->'families')=47;
  if v_count <> 1 then
    raise exception 'BLOCK_M1A4_RULE_463_PRESTATE:%',v_count;
  end if;

  update lf_ops.reglas
  set estado='VIGENTE',
      updated_at=clock_timestamp()
  where id=463
    and codigo='B2B-RULE-STORY-READINESS-001'
    and estado='CANDIDATO'
    and not pendiente_decision
    and jsonb_array_length(valor_config->'families')=47;

  if not exists (
    select 1 from lf_ops.reglas
    where id=463
      and codigo='B2B-RULE-STORY-READINESS-001'
      and estado='VIGENTE'
      and not pendiente_decision
      and jsonb_array_length(valor_config->'families')=47
  ) then
    raise exception 'BLOCK_M1A4_RULE_463_NOT_VIGENTE';
  end if;

  -- Guard the exact 5.13 contract snapshot frozen by M1.A1 before changing one field.
  select
    encode(extensions.digest(convert_to(especificacion::text,'UTF8'),'sha256'),'hex'),
    octet_length(especificacion::text)
  into v_sha,v_bytes
  from programacion.contratos
  where id=37
    and contrato_codigo='INPUT_READINESS_CONTRACT'
    and especificacion->>'contract_revision'='5.13'
    and especificacion->>'canonical_universe_rule'='B2B-RULE-STORY-READINESS-001';

  if v_sha is distinct from v_old_db_sha or v_bytes <> 30697 then
    raise exception 'BLOCK_M1A4_CONTRACT_513_PRESTATE:sha=% bytes=%',coalesce(v_sha,'<missing>'),coalesce(v_bytes,-1);
  end if;

  update programacion.contratos
  set especificacion=jsonb_set(
    especificacion,
    '{canonical_universe_rule}',
    to_jsonb('DEC-INPUT-GOV-D-M1.4'::text),
    false
  )
  where id=37
    and contrato_codigo='INPUT_READINESS_CONTRACT';

  select
    encode(extensions.digest(convert_to(especificacion::text,'UTF8'),'sha256'),'hex'),
    octet_length(especificacion::text)
  into v_sha,v_bytes
  from programacion.contratos
  where id=37
    and contrato_codigo='INPUT_READINESS_CONTRACT'
    and especificacion->>'canonical_universe_rule'='DEC-INPUT-GOV-D-M1.4';

  if v_sha is distinct from v_new_db_sha or v_bytes <> 30689 then
    raise exception 'BLOCK_M1A4_CONTRACT_513_POSTSTATE:sha=% bytes=%',coalesce(v_sha,'<missing>'),coalesce(v_bytes,-1);
  end if;

  -- Keep the M1.A1 governed snapshot asset truthful after the contract pointer change.
  select count(*) into v_count
  from public.lf_activos
  where codigo_activo='INPUT_READINESS_CONTRACT'
    and archived_at is null
    and version='5.13'
    and ruta_esperada='docs/input-governance/contracts/input_readiness_contract_v5_13.json'
    and raw_payload->>'source_contract_id'='37'
    and raw_payload->>'db_sha256'=v_old_db_sha
    and raw_payload->>'git_blob_sha'=v_old_git_blob;
  if v_count <> 1 then
    raise exception 'BLOCK_M1A4_CONTRACT_ASSET_PRESTATE:%',v_count;
  end if;

  update public.lf_activos
  set raw_payload=jsonb_set(
                    jsonb_set(raw_payload,'{db_sha256}',to_jsonb(v_new_db_sha),false),
                    '{git_blob_sha}',to_jsonb(v_new_git_blob),false
                  ),
      updated_at=clock_timestamp(),
      updated_by_execution_id=v_execution_id
  where codigo_activo='INPUT_READINESS_CONTRACT'
    and archived_at is null
    and version='5.13'
    and ruta_esperada='docs/input-governance/contracts/input_readiness_contract_v5_13.json';

  select count(*) into v_count
  from public.lf_activos
  where codigo_activo='INPUT_READINESS_CONTRACT'
    and archived_at is null
    and version='5.13'
    and raw_payload->>'db_sha256'=v_new_db_sha
    and raw_payload->>'git_blob_sha'=v_new_git_blob;
  if v_count <> 1 then
    raise exception 'BLOCK_M1A4_CONTRACT_ASSET_POSTSTATE:%',v_count;
  end if;

  -- Existing governing relation must remain intact; this unit does not rewire it.
  select count(*) into v_count
  from public.lf_activo_relaciones
  where codigo_activo='EDGE_FN_INPUT_GOVERNANCE_AGENT_V1'
    and relacionado_codigo='INPUT_READINESS_CONTRACT'
    and relacion_tipo='FUENTE_RECTORA'
    and fuente='docs/input-governance/contracts/input_readiness_contract_v5_13.json';
  if v_count <> 1 then
    raise exception 'BLOCK_M1A4_READINESS_RELATION_DRIFT:%',v_count;
  end if;

  -- Universe must still be 47/47 across rule, contract and assessments.
  if (select jsonb_array_length(valor_config->'families') from lf_ops.reglas where id=463) <> 47
     or (select count(*) from programacion.contratos,jsonb_object_keys(especificacion->'family_stage_requirements') where id=37) <> 47
     or (select count(distinct family_code) from programacion.input_family_assessments) <> 47 then
    raise exception 'BLOCK_M1A4_UNIVERSE_COUNT_DRIFT';
  end if;
end $$;

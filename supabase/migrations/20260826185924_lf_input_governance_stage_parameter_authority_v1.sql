-- INPUT_GOVERNANCE_AGENT 5.12
-- Owner-approved Stage Authority 47/47 + governed parameter provenance.
-- Approval: "Ok conforme" (2026-08-26).
-- No production authorization. No silent fallback to STORY. No retroactive attribution of legacy values.

do $decision$
declare
  v_decision_number bigint;
  v_batch uuid := gen_random_uuid();
begin
  perform pg_advisory_xact_lock(hashtext('lf_decisiones_gov:decision_number')::bigint);
  if not exists (
    select 1 from public.lf_decisiones_gov
    where id_decision='DEC-INPUT-GOV-512-STAGE-PARAM-AUTH-HUMAN-001'
  ) then
    select coalesce(max(decision_number),0)+1
      into v_decision_number
    from public.lf_decisiones_gov;

    insert into public.lf_decisiones_gov(
      id_decision,fecha,decision,contexto,impacto,
      estado_original,estado_normalizado,documento_relacionado,observaciones,
      source_sheet_name,migration_batch_id,raw_payload,decision_number,
      created_by_execution_id
    ) values (
      'DEC-INPUT-GOV-512-STAGE-PARAM-AUTH-HUMAN-001',
      '2026-08-26',
      'Para INPUT_GOVERNANCE_AGENT 5.12 se aprueba autoridad de etapa explícita para las 47 familias: STORY=20, IMPLEMENTATION=22, QA=4 y PRODUCTION=1. La etapa representa la primera etapa bloqueante. Una fuente canónica específica, o una fuente expresamente delegada por contrato, puede establecer un vector blocks_* más específico. La ausencia de etapa nunca se convierte implícitamente en STORY: debe fallar como CONTRACT_STAGE_UNRESOLVED. Se aprueba además separar regla estructural de parámetro configurable: si la regla existe pero falta un valor parametrizable, puede utilizarse una referencia externa aplicable o un default provisional LF sin hardcodear, conservando procedencia exacta y sin convertirlo silenciosamente en autoridad LF.',
      'El owner revisó la matriz, cuestionó específicamente RATE_LIMIT y aclaró que los valores configurables deben vivir como parámetros modificables sin afectar programación. Aprobó que, cuando la regla existe y falta un valor, pueda adoptarse temporalmente un estándar internacional, guía de industria o default LF debidamente identificado, manteniendo el origen en la misma tabla de política/configuración. La aprobación final fue "Ok conforme".',
      'Elimina falsos bloqueos de Story por controles cuyo primer bloqueo pertenece a Implementation, QA o Production; mantiene fail-closed para gaps funcionales reales. Añade trazabilidad por parámetro y obliga a refrescar procedencia cuando cambia un valor configurable. No autoriza producción, promoción ni inventar requisitos, perfiles, estados, transiciones o valores normativos.',
      'OWNER_APPROVED',
      'CANDIDATO_CONTROLADO',
      'INPUT_GOVERNANCE_AGENT_5_12_STAGE_PARAMETER_AUTHORITY',
      'Los 8 stage mappings existentes se preservan, incluido API_DATA_CONTRACT condicional. Los 39 faltantes reciben autoridad explícita. Los valores legacy existentes no reciben una procedencia inventada: se conservan operativamente y, cuando sean modificados, deben declarar provenance por parámetro. INTERNATIONAL_STANDARD exige referencia trazable; INDUSTRY_GUIDANCE no puede etiquetarse como estándar; LF_PROVISIONAL_DEFAULT nunca se vuelve LF_CANONICAL por antigüedad.',
      '06_DECISIONES',
      v_batch,
      jsonb_build_object(
        'approval_text','Ok conforme',
        'approval_scope','INPUT_GOVERNANCE_AGENT_5_12_STAGE_PARAMETER_AUTHORITY',
        'authority_mode','OWNER_POSITIVE_APPROVAL',
        'stage_distribution',jsonb_build_object('STORY',20,'IMPLEMENTATION',22,'QA',4,'PRODUCTION',1),
        'stage_semantics','EARLIEST_BLOCKING_STAGE',
        'missing_stage_policy','CONTRACT_STAGE_UNRESOLVED',
        'parameter_origin_types',jsonb_build_array('LF_CANONICAL','INTERNATIONAL_STANDARD','INDUSTRY_GUIDANCE','LF_PROVISIONAL_DEFAULT','UNCLASSIFIED_LEGACY'),
        'provisional_silent_canonicalization','DENY',
        'production_authorized',false
      ),
      v_decision_number,
      'INPUT_GOVERNANCE_STAGE_PARAM_AUTH_20260826'
    );
  end if;
end;
$decision$;

-- Per-parameter provenance lives with the policy/configuration row; no parallel global-variable authority is introduced.
alter table lf_ops.politicas_rate_limit add column if not exists parameter_provenance jsonb not null default '{}'::jsonb;
alter table lf_ops.politicas_timeout add column if not exists parameter_provenance jsonb not null default '{}'::jsonb;
alter table lf_ops.politicas_sesion add column if not exists parameter_provenance jsonb not null default '{}'::jsonb;
alter table lf_ops.otp_politicas add column if not exists parameter_provenance jsonb not null default '{}'::jsonb;
alter table lf_ops.politicas_seguridad add column if not exists parameter_provenance jsonb not null default '{}'::jsonb;

create or replace function programacion.fn_input_parameter_provenance_valid_v1(p_provenance jsonb)
returns boolean
language plpgsql
immutable
set search_path to 'pg_catalog'
as $function$
declare
  r record;
  v_origin text;
  v_status text;
  v_decision text;
  v_ref text;
  v_clause text;
  v_version text;
begin
  if p_provenance is null or jsonb_typeof(p_provenance)<>'object' then
    return false;
  end if;

  for r in select key,value from jsonb_each(p_provenance)
  loop
    if nullif(btrim(r.key),'') is null or jsonb_typeof(r.value)<>'object' then return false; end if;
    v_origin:=r.value->>'origin_type';
    v_status:=r.value->>'value_status';
    v_decision:=nullif(btrim(coalesce(r.value->>'decision_ref','')),'');
    v_ref:=nullif(btrim(coalesce(r.value->>'origin_reference','')),'');
    v_clause:=nullif(btrim(coalesce(r.value->>'origin_clause','')),'');
    v_version:=nullif(btrim(coalesce(r.value->>'origin_version','')),'');

    if v_origin not in ('LF_CANONICAL','INTERNATIONAL_STANDARD','INDUSTRY_GUIDANCE','LF_PROVISIONAL_DEFAULT','UNCLASSIFIED_LEGACY') then return false; end if;
    if v_status not in ('LF_CANONICAL','EXTERNAL_REFERENCE','LF_PROVISIONAL','LEGACY_UNCLASSIFIED') then return false; end if;

    if v_origin='LF_CANONICAL' and (v_status<>'LF_CANONICAL' or v_decision is null) then return false; end if;
    if v_origin='INTERNATIONAL_STANDARD' and (v_ref is null or (v_clause is null and v_version is null)) then return false; end if;
    if v_origin='INDUSTRY_GUIDANCE' and v_ref is null then return false; end if;
    if v_origin='LF_PROVISIONAL_DEFAULT' and (
      v_status<>'LF_PROVISIONAL'
      or r.value->>'replacement_policy'<>'MUST_BE_RATIFIED_OR_OVERRIDDEN'
    ) then return false; end if;
    if v_origin='UNCLASSIFIED_LEGACY' and v_status<>'LEGACY_UNCLASSIFIED' then return false; end if;

    -- External provenance may become LF canonical only through an explicit LF ratification decision.
    if v_status='LF_CANONICAL' and v_origin<>'LF_CANONICAL' and (
      coalesce((r.value->>'ratified_by_lf')::boolean,false) is not true
      or v_decision is null
    ) then return false; end if;
  end loop;
  return true;
exception when others then
  return false;
end;
$function$;

do $constraints$
declare
  v_table text;
  v_name text;
begin
  foreach v_table in array array['politicas_rate_limit','politicas_timeout','politicas_sesion','otp_politicas','politicas_seguridad']
  loop
    v_name:=v_table||'_parameter_provenance_ck';
    if not exists(
      select 1 from pg_constraint c
      join pg_class t on t.oid=c.conrelid
      join pg_namespace n on n.oid=t.relnamespace
      where n.nspname='lf_ops' and t.relname=v_table and c.conname=v_name
    ) then
      execute format(
        'alter table lf_ops.%I add constraint %I check (programacion.fn_input_parameter_provenance_valid_v1(parameter_provenance))',
        v_table,v_name
      );
    end if;
  end loop;
end;
$constraints$;

create or replace function programacion.fn_guard_input_parameter_provenance_v1()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog','programacion'
as $function$
declare
  v_new jsonb:=to_jsonb(new);
  v_old jsonb:=case when tg_op='UPDATE' then to_jsonb(old) else '{}'::jsonb end;
  v_prov jsonb:=coalesce(v_new->'parameter_provenance','{}'::jsonb);
  v_old_prov jsonb:=coalesce(v_old->'parameter_provenance','{}'::jsonb);
  v_keys text[];
  v_key text;
  v_changed boolean;
  v_old_cfg jsonb;
  v_new_cfg jsonb;
begin
  if not programacion.fn_input_parameter_provenance_valid_v1(v_prov) then
    raise exception 'PARAMETER_PROVENANCE_INVALID:%',tg_table_name;
  end if;

  if tg_table_name='politicas_rate_limit' then
    v_keys:=array['window_seconds','max_requests','burst_limit','scope_key'];
  elsif tg_table_name='politicas_timeout' then
    v_keys:=array['timeout_seconds','retry_limit','backoff_strategy'];
  elsif tg_table_name='politicas_sesion' then
    v_keys:=array['idle_timeout_seconds','warning_before_timeout_seconds','absolute_timeout_seconds','access_token_ttl_seconds','refresh_rotation_enabled','max_concurrent_sessions','extend_on_user_activity'];
  elsif tg_table_name='otp_politicas' then
    v_keys:=array['longitud','digitos_permitidos','expiracion_minutos','max_intentos','max_reenvios','bloqueo_reenvio_min','canal_primario','canal_fallback','fallback_segundos'];
  elsif tg_table_name='politicas_seguridad' then
    v_old_cfg:=coalesce(v_old->'policy_config','{}'::jsonb);
    v_new_cfg:=coalesce(v_new->'policy_config','{}'::jsonb);
    for v_key in
      select key from (
        select jsonb_object_keys(v_old_cfg) key
        union
        select jsonb_object_keys(v_new_cfg) key
      ) q order by key
    loop
      v_changed:=tg_op='INSERT' or (v_new_cfg->v_key is distinct from v_old_cfg->v_key);
      if v_changed then
        if not (v_prov ? v_key) then
          raise exception 'PARAMETER_PROVENANCE_REQUIRED:%:%',tg_table_name,v_key;
        end if;
        if tg_op='UPDATE' and v_prov->v_key is not distinct from v_old_prov->v_key then
          raise exception 'PARAMETER_PROVENANCE_REFRESH_REQUIRED:%:%',tg_table_name,v_key;
        end if;
      end if;
    end loop;
    return new;
  else
    raise exception 'PARAMETER_PROVENANCE_TABLE_UNSUPPORTED:%',tg_table_name;
  end if;

  foreach v_key in array v_keys
  loop
    v_changed:=tg_op='INSERT' or (v_new->v_key is distinct from v_old->v_key);
    if v_changed and jsonb_typeof(v_new->v_key)<>'null' then
      if not (v_prov ? v_key) then
        raise exception 'PARAMETER_PROVENANCE_REQUIRED:%:%',tg_table_name,v_key;
      end if;
      if tg_op='UPDATE' and v_prov->v_key is not distinct from v_old_prov->v_key then
        raise exception 'PARAMETER_PROVENANCE_REFRESH_REQUIRED:%:%',tg_table_name,v_key;
      end if;
    end if;
  end loop;
  return new;
end;
$function$;

do $triggers$
declare
  v_table text;
  v_trigger text;
begin
  foreach v_table in array array['politicas_rate_limit','politicas_timeout','politicas_sesion','otp_politicas','politicas_seguridad']
  loop
    v_trigger:='trg_'||v_table||'_parameter_provenance';
    if not exists(
      select 1 from pg_trigger tr
      join pg_class t on t.oid=tr.tgrelid
      join pg_namespace n on n.oid=t.relnamespace
      where not tr.tgisinternal and n.nspname='lf_ops' and t.relname=v_table and tr.tgname=v_trigger
    ) then
      execute format(
        'create trigger %I before insert or update on lf_ops.%I for each row execute function programacion.fn_guard_input_parameter_provenance_v1()',
        v_trigger,v_table
      );
    end if;
  end loop;
end;
$triggers$;

comment on function programacion.fn_input_parameter_provenance_valid_v1(jsonb)
is 'Validates per-parameter origin. External guidance cannot masquerade as an international standard or LF canonical authority; provisional defaults require explicit replacement policy.';
comment on function programacion.fn_guard_input_parameter_provenance_v1()
is 'Requires same-row per-parameter provenance for new/changed configurable policy values and requires provenance refresh whenever the value changes. Existing untouched rows are retained as legacy-unclassified rather than retroactively attributed.';

-- Fill the 39 missing family stages while preserving the 8 previously authorized entries, including conditional API_DATA_CONTRACT.
update programacion.contratos
set especificacion =
  jsonb_set(
    especificacion,
    '{family_stage_requirements}',
    coalesce(especificacion->'family_stage_requirements','{}'::jsonb)
    || jsonb_build_object(
    'ACTIONS',jsonb_build_object(
      'authority','DEC-INPUT-GOV-512-STAGE-PARAM-AUTH-HUMAN-001',
      'coverage_required_by','STORY',
      'allow_story_ready_when_incomplete',false,
      'allow_implementation_ready_when_incomplete',false,
      'allow_qa_ready_when_incomplete',false,
      'allow_production_ready_when_incomplete',false
    ),
    'APPLICABILITY_READINESS',jsonb_build_object(
      'authority','DEC-INPUT-GOV-512-STAGE-PARAM-AUTH-HUMAN-001',
      'coverage_required_by','STORY',
      'allow_story_ready_when_incomplete',false,
      'allow_implementation_ready_when_incomplete',false,
      'allow_qa_ready_when_incomplete',false,
      'allow_production_ready_when_incomplete',false
    ),
    'CONFLICT_PRECEDENCE',jsonb_build_object(
      'authority','DEC-INPUT-GOV-512-STAGE-PARAM-AUTH-HUMAN-001',
      'coverage_required_by','STORY',
      'allow_story_ready_when_incomplete',false,
      'allow_implementation_ready_when_incomplete',false,
      'allow_qa_ready_when_incomplete',false,
      'allow_production_ready_when_incomplete',false
    ),
    'CONTEXT_BUDGET_RETRIEVAL_POLICY',jsonb_build_object(
      'authority','DEC-INPUT-GOV-512-STAGE-PARAM-AUTH-HUMAN-001',
      'coverage_required_by','STORY',
      'allow_story_ready_when_incomplete',false,
      'allow_implementation_ready_when_incomplete',false,
      'allow_qa_ready_when_incomplete',false,
      'allow_production_ready_when_incomplete',false
    ),
    'EKB',jsonb_build_object(
      'authority','DEC-INPUT-GOV-512-STAGE-PARAM-AUTH-HUMAN-001',
      'coverage_required_by','STORY',
      'allow_story_ready_when_incomplete',false,
      'allow_implementation_ready_when_incomplete',false,
      'allow_qa_ready_when_incomplete',false,
      'allow_production_ready_when_incomplete',false
    ),
    'ERRORS',jsonb_build_object(
      'authority','DEC-INPUT-GOV-512-STAGE-PARAM-AUTH-HUMAN-001',
      'coverage_required_by','STORY',
      'allow_story_ready_when_incomplete',false,
      'allow_implementation_ready_when_incomplete',false,
      'allow_qa_ready_when_incomplete',false,
      'allow_production_ready_when_incomplete',false
    ),
    'FIELDS',jsonb_build_object(
      'authority','DEC-INPUT-GOV-512-STAGE-PARAM-AUTH-HUMAN-001',
      'coverage_required_by','STORY',
      'allow_story_ready_when_incomplete',false,
      'allow_implementation_ready_when_incomplete',false,
      'allow_qa_ready_when_incomplete',false,
      'allow_production_ready_when_incomplete',false
    ),
    'FRESHNESS_INVALIDATION',jsonb_build_object(
      'authority','DEC-INPUT-GOV-512-STAGE-PARAM-AUTH-HUMAN-001',
      'coverage_required_by','STORY',
      'allow_story_ready_when_incomplete',false,
      'allow_implementation_ready_when_incomplete',false,
      'allow_qa_ready_when_incomplete',false,
      'allow_production_ready_when_incomplete',false
    ),
    'MFA_OTP_SSO',jsonb_build_object(
      'authority','DEC-INPUT-GOV-512-STAGE-PARAM-AUTH-HUMAN-001',
      'coverage_required_by','STORY',
      'allow_story_ready_when_incomplete',false,
      'allow_implementation_ready_when_incomplete',false,
      'allow_qa_ready_when_incomplete',false,
      'allow_production_ready_when_incomplete',false
    ),
    'NEGATIVE_REQUIREMENTS',jsonb_build_object(
      'authority','DEC-INPUT-GOV-512-STAGE-PARAM-AUTH-HUMAN-001',
      'coverage_required_by','STORY',
      'allow_story_ready_when_incomplete',false,
      'allow_implementation_ready_when_incomplete',false,
      'allow_qa_ready_when_incomplete',false,
      'allow_production_ready_when_incomplete',false
    ),
    'OBJECTIVE_OUTCOMES',jsonb_build_object(
      'authority','DEC-INPUT-GOV-512-STAGE-PARAM-AUTH-HUMAN-001',
      'coverage_required_by','STORY',
      'allow_story_ready_when_incomplete',false,
      'allow_implementation_ready_when_incomplete',false,
      'allow_qa_ready_when_incomplete',false,
      'allow_production_ready_when_incomplete',false
    ),
    'PERMISSIONS',jsonb_build_object(
      'authority','DEC-INPUT-GOV-512-STAGE-PARAM-AUTH-HUMAN-001',
      'coverage_required_by','STORY',
      'allow_story_ready_when_incomplete',false,
      'allow_implementation_ready_when_incomplete',false,
      'allow_qa_ready_when_incomplete',false,
      'allow_production_ready_when_incomplete',false
    ),
    'PROFILES',jsonb_build_object(
      'authority','DEC-INPUT-GOV-512-STAGE-PARAM-AUTH-HUMAN-001',
      'coverage_required_by','STORY',
      'allow_story_ready_when_incomplete',false,
      'allow_implementation_ready_when_incomplete',false,
      'allow_qa_ready_when_incomplete',false,
      'allow_production_ready_when_incomplete',false
    ),
    'ROUTING_NAVIGATION',jsonb_build_object(
      'authority','DEC-INPUT-GOV-512-STAGE-PARAM-AUTH-HUMAN-001',
      'coverage_required_by','STORY',
      'allow_story_ready_when_incomplete',false,
      'allow_implementation_ready_when_incomplete',false,
      'allow_qa_ready_when_incomplete',false,
      'allow_production_ready_when_incomplete',false
    ),
    'SCREEN_IDENTITY',jsonb_build_object(
      'authority','DEC-INPUT-GOV-512-STAGE-PARAM-AUTH-HUMAN-001',
      'coverage_required_by','STORY',
      'allow_story_ready_when_incomplete',false,
      'allow_implementation_ready_when_incomplete',false,
      'allow_qa_ready_when_incomplete',false,
      'allow_production_ready_when_incomplete',false
    ),
    'SOURCE_AUTHORITY_PROVENANCE',jsonb_build_object(
      'authority','DEC-INPUT-GOV-512-STAGE-PARAM-AUTH-HUMAN-001',
      'coverage_required_by','STORY',
      'allow_story_ready_when_incomplete',false,
      'allow_implementation_ready_when_incomplete',false,
      'allow_qa_ready_when_incomplete',false,
      'allow_production_ready_when_incomplete',false
    ),
    'STATES',jsonb_build_object(
      'authority','DEC-INPUT-GOV-512-STAGE-PARAM-AUTH-HUMAN-001',
      'coverage_required_by','STORY',
      'allow_story_ready_when_incomplete',false,
      'allow_implementation_ready_when_incomplete',false,
      'allow_qa_ready_when_incomplete',false,
      'allow_production_ready_when_incomplete',false
    ),
    'TRANSITIONS',jsonb_build_object(
      'authority','DEC-INPUT-GOV-512-STAGE-PARAM-AUTH-HUMAN-001',
      'coverage_required_by','STORY',
      'allow_story_ready_when_incomplete',false,
      'allow_implementation_ready_when_incomplete',false,
      'allow_qa_ready_when_incomplete',false,
      'allow_production_ready_when_incomplete',false
    ),
    'VALIDATIONS',jsonb_build_object(
      'authority','DEC-INPUT-GOV-512-STAGE-PARAM-AUTH-HUMAN-001',
      'coverage_required_by','STORY',
      'allow_story_ready_when_incomplete',false,
      'allow_implementation_ready_when_incomplete',false,
      'allow_qa_ready_when_incomplete',false,
      'allow_production_ready_when_incomplete',false
    ),
    'ACCESSIBILITY',jsonb_build_object(
      'authority','DEC-INPUT-GOV-512-STAGE-PARAM-AUTH-HUMAN-001',
      'coverage_required_by','IMPLEMENTATION',
      'allow_story_ready_when_incomplete',true,
      'allow_implementation_ready_when_incomplete',false,
      'allow_qa_ready_when_incomplete',false,
      'allow_production_ready_when_incomplete',false
    ),
    'ASSETS_ICONS',jsonb_build_object(
      'authority','DEC-INPUT-GOV-512-STAGE-PARAM-AUTH-HUMAN-001',
      'coverage_required_by','IMPLEMENTATION',
      'allow_story_ready_when_incomplete',true,
      'allow_implementation_ready_when_incomplete',false,
      'allow_qa_ready_when_incomplete',false,
      'allow_production_ready_when_incomplete',false
    ),
    'AUDIT',jsonb_build_object(
      'authority','DEC-INPUT-GOV-512-STAGE-PARAM-AUTH-HUMAN-001',
      'coverage_required_by','IMPLEMENTATION',
      'allow_story_ready_when_incomplete',true,
      'allow_implementation_ready_when_incomplete',false,
      'allow_qa_ready_when_incomplete',false,
      'allow_production_ready_when_incomplete',false
    ),
    'DEPENDENCIES',jsonb_build_object(
      'authority','DEC-INPUT-GOV-512-STAGE-PARAM-AUTH-HUMAN-001',
      'coverage_required_by','IMPLEMENTATION',
      'allow_story_ready_when_incomplete',true,
      'allow_implementation_ready_when_incomplete',false,
      'allow_qa_ready_when_incomplete',false,
      'allow_production_ready_when_incomplete',false
    ),
    'DESIGN_SYSTEM',jsonb_build_object(
      'authority','DEC-INPUT-GOV-512-STAGE-PARAM-AUTH-HUMAN-001',
      'coverage_required_by','IMPLEMENTATION',
      'allow_story_ready_when_incomplete',true,
      'allow_implementation_ready_when_incomplete',false,
      'allow_qa_ready_when_incomplete',false,
      'allow_production_ready_when_incomplete',false
    ),
    'FEATURE_FLAGS',jsonb_build_object(
      'authority','DEC-INPUT-GOV-512-STAGE-PARAM-AUTH-HUMAN-001',
      'coverage_required_by','IMPLEMENTATION',
      'allow_story_ready_when_incomplete',true,
      'allow_implementation_ready_when_incomplete',false,
      'allow_qa_ready_when_incomplete',false,
      'allow_production_ready_when_incomplete',false
    ),
    'I18N_FORMATS',jsonb_build_object(
      'authority','DEC-INPUT-GOV-512-STAGE-PARAM-AUTH-HUMAN-001',
      'coverage_required_by','IMPLEMENTATION',
      'allow_story_ready_when_incomplete',true,
      'allow_implementation_ready_when_incomplete',false,
      'allow_qa_ready_when_incomplete',false,
      'allow_production_ready_when_incomplete',false
    ),
    'LOADING_EMPTY_ERROR_STATES',jsonb_build_object(
      'authority','DEC-INPUT-GOV-512-STAGE-PARAM-AUTH-HUMAN-001',
      'coverage_required_by','IMPLEMENTATION',
      'allow_story_ready_when_incomplete',true,
      'allow_implementation_ready_when_incomplete',false,
      'allow_qa_ready_when_incomplete',false,
      'allow_production_ready_when_incomplete',false
    ),
    'OBSERVABILITY',jsonb_build_object(
      'authority','DEC-INPUT-GOV-512-STAGE-PARAM-AUTH-HUMAN-001',
      'coverage_required_by','IMPLEMENTATION',
      'allow_story_ready_when_incomplete',true,
      'allow_implementation_ready_when_incomplete',false,
      'allow_qa_ready_when_incomplete',false,
      'allow_production_ready_when_incomplete',false
    ),
    'PRIVACY_PII',jsonb_build_object(
      'authority','DEC-INPUT-GOV-512-STAGE-PARAM-AUTH-HUMAN-001',
      'coverage_required_by','IMPLEMENTATION',
      'allow_story_ready_when_incomplete',true,
      'allow_implementation_ready_when_incomplete',false,
      'allow_qa_ready_when_incomplete',false,
      'allow_production_ready_when_incomplete',false
    ),
    'RATE_LIMIT',jsonb_build_object(
      'authority','DEC-INPUT-GOV-512-STAGE-PARAM-AUTH-HUMAN-001',
      'coverage_required_by','IMPLEMENTATION',
      'allow_story_ready_when_incomplete',true,
      'allow_implementation_ready_when_incomplete',false,
      'allow_qa_ready_when_incomplete',false,
      'allow_production_ready_when_incomplete',false
    ),
    'RESPONSIVE',jsonb_build_object(
      'authority','DEC-INPUT-GOV-512-STAGE-PARAM-AUTH-HUMAN-001',
      'coverage_required_by','IMPLEMENTATION',
      'allow_story_ready_when_incomplete',true,
      'allow_implementation_ready_when_incomplete',false,
      'allow_qa_ready_when_incomplete',false,
      'allow_production_ready_when_incomplete',false
    ),
    'RUNTIME_CONFIG',jsonb_build_object(
      'authority','DEC-INPUT-GOV-512-STAGE-PARAM-AUTH-HUMAN-001',
      'coverage_required_by','IMPLEMENTATION',
      'allow_story_ready_when_incomplete',true,
      'allow_implementation_ready_when_incomplete',false,
      'allow_qa_ready_when_incomplete',false,
      'allow_production_ready_when_incomplete',false
    ),
    'SECURITY',jsonb_build_object(
      'authority','DEC-INPUT-GOV-512-STAGE-PARAM-AUTH-HUMAN-001',
      'coverage_required_by','IMPLEMENTATION',
      'allow_story_ready_when_incomplete',true,
      'allow_implementation_ready_when_incomplete',false,
      'allow_qa_ready_when_incomplete',false,
      'allow_production_ready_when_incomplete',false
    ),
    'SESSION',jsonb_build_object(
      'authority','DEC-INPUT-GOV-512-STAGE-PARAM-AUTH-HUMAN-001',
      'coverage_required_by','IMPLEMENTATION',
      'allow_story_ready_when_incomplete',true,
      'allow_implementation_ready_when_incomplete',false,
      'allow_qa_ready_when_incomplete',false,
      'allow_production_ready_when_incomplete',false
    ),
    'TIMEOUT_RETRY',jsonb_build_object(
      'authority','DEC-INPUT-GOV-512-STAGE-PARAM-AUTH-HUMAN-001',
      'coverage_required_by','IMPLEMENTATION',
      'allow_story_ready_when_incomplete',true,
      'allow_implementation_ready_when_incomplete',false,
      'allow_qa_ready_when_incomplete',false,
      'allow_production_ready_when_incomplete',false
    ),
    'UI_MESSAGES',jsonb_build_object(
      'authority','DEC-INPUT-GOV-512-STAGE-PARAM-AUTH-HUMAN-001',
      'coverage_required_by','IMPLEMENTATION',
      'allow_story_ready_when_incomplete',true,
      'allow_implementation_ready_when_incomplete',false,
      'allow_qa_ready_when_incomplete',false,
      'allow_production_ready_when_incomplete',false
    ),
    'PERFORMANCE',jsonb_build_object(
      'authority','DEC-INPUT-GOV-512-STAGE-PARAM-AUTH-HUMAN-001',
      'coverage_required_by','QA',
      'allow_story_ready_when_incomplete',true,
      'allow_implementation_ready_when_incomplete',true,
      'allow_qa_ready_when_incomplete',false,
      'allow_production_ready_when_incomplete',false
    ),
    'VISUAL_EVIDENCE',jsonb_build_object(
      'authority','DEC-INPUT-GOV-512-STAGE-PARAM-AUTH-HUMAN-001',
      'coverage_required_by','QA',
      'allow_story_ready_when_incomplete',true,
      'allow_implementation_ready_when_incomplete',true,
      'allow_qa_ready_when_incomplete',false,
      'allow_production_ready_when_incomplete',false
    ),
    'ROLLOUT_PRODUCTION_GATES',jsonb_build_object(
      'authority','DEC-INPUT-GOV-512-STAGE-PARAM-AUTH-HUMAN-001',
      'coverage_required_by','PRODUCTION',
      'allow_story_ready_when_incomplete',true,
      'allow_implementation_ready_when_incomplete',true,
      'allow_qa_ready_when_incomplete',true,
      'allow_production_ready_when_incomplete',false
    )
    ),
    true
  )
  || jsonb_build_object(
    'stage_authority_policy',jsonb_build_object(
      'authority','DEC-INPUT-GOV-512-STAGE-PARAM-AUTH-HUMAN-001',
      'semantics','EARLIEST_BLOCKING_STAGE',
      'family_count',47,
      'distribution',jsonb_build_object('STORY',20,'IMPLEMENTATION',22,'QA',4,'PRODUCTION',1),
      'specific_source_vector_precedence','CANONICAL_OR_CONTRACT_DELEGATED_EXPLICIT_BLOCKS_VECTOR_THEN_FAMILY_BASE',
      'missing_stage','CONTRACT_STAGE_UNRESOLVED',
      'implicit_story_fallback','DENY'
    ),
    'parameterization_contract',jsonb_build_object(
      'authority','DEC-INPUT-GOV-512-STAGE-PARAM-AUTH-HUMAN-001',
      'rule_modes',jsonb_build_array('STRUCTURAL','PARAMETERIZED','HYBRID'),
      'origin_types',jsonb_build_array('LF_CANONICAL','INTERNATIONAL_STANDARD','INDUSTRY_GUIDANCE','LF_PROVISIONAL_DEFAULT','UNCLASSIFIED_LEGACY'),
      'value_statuses',jsonb_build_array('LF_CANONICAL','EXTERNAL_REFERENCE','LF_PROVISIONAL','LEGACY_UNCLASSIFIED'),
      'provenance_storage','SAME_POLICY_ROW_PARAMETER_PROVENANCE_JSONB',
      'legacy_existing_values_policy','RETAIN_RUNTIME_BEHAVIOR_REQUIRE_PROVENANCE_ON_CHANGE',
      'missing_parameter_value_alone_blocks_story',false,
      'external_value_can_fill_missing_parameter',true,
      'international_standard_requires_exact_traceability',true,
      'industry_guidance_must_not_be_labeled_standard',true,
      'provisional_silent_canonicalization','DENY',
      'hardcoded_configurable_thresholds','DENY',
      'lf_canonical_requires_decision',true
    ),
    'negative_tests',coalesce(especificacion->'negative_tests','[]'::jsonb)
      || jsonb_build_array(
        'CONTRACT_STAGE_UNRESOLVED',
        'MISSING_FAMILY_STAGE_IMPLICITLY_DEFAULTS_TO_STORY',
        'PARAMETER_VALUE_MISSING_AS_STORY_BLOCKER_WHEN_STRUCTURAL_RULE_EXISTS',
        'PROVISIONAL_VALUE_SILENTLY_CANONICALIZED',
        'INDUSTRY_GUIDANCE_MISLABELED_AS_INTERNATIONAL_STANDARD',
        'HARDCODED_CONFIGURABLE_THRESHOLD',
        'PARAMETER_VALUE_CHANGED_WITHOUT_PROVENANCE_REFRESH'
      ),
    'remediation_revision','V512_STAGE_PARAMETER_AUTHORITY_20260826'
  )
where version_id=19
  and contrato_codigo='INPUT_READINESS_CONTRACT';

create or replace function programacion.fn_input_stage_resolve_v2(
  p_family_code text,
  p_pantalla_id integer,
  p_version_id bigint,
  p_coverage_status text,
  p_well_defined_status text
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','programacion'
as $function$
declare
  v_cfg jsonb;
  v_base text;
  v_stage text;
  v_conditional boolean;
  v_applies boolean;
begin
  select coalesce(c.especificacion->'family_stage_requirements'->p_family_code,'{}'::jsonb)
    into v_cfg
  from programacion.contratos c
  where c.version_id=p_version_id and c.contrato_codigo='INPUT_READINESS_CONTRACT';

  if coalesce(v_cfg,'{}'::jsonb)='{}'::jsonb then
    return jsonb_build_object('resolved',false,'family_code',p_family_code,'error_code','CONTRACT_STAGE_UNRESOLVED');
  end if;

  v_base:=upper(coalesce(nullif(v_cfg->>'coverage_required_by',''),'UNRESOLVED'));
  if v_base not in ('STORY','IMPLEMENTATION','QA','PRODUCTION') then
    return jsonb_build_object('resolved',false,'family_code',p_family_code,'error_code','CONTRACT_STAGE_UNRESOLVED','observed_stage',v_base);
  end if;

  v_conditional:=coalesce((v_cfg->>'conditional')::boolean,false);
  v_applies:=programacion.fn_input_stage_authority_applies_v1(
    p_family_code,p_pantalla_id,p_version_id,p_coverage_status,p_well_defined_status
  );
  v_stage:=case
    when v_conditional and v_applies then upper(coalesce(nullif(v_cfg->>'eligible_coverage_required_by',''),v_base))
    else v_base
  end;

  if v_stage not in ('STORY','IMPLEMENTATION','QA','PRODUCTION') then
    return jsonb_build_object('resolved',false,'family_code',p_family_code,'error_code','CONTRACT_STAGE_UNRESOLVED','observed_stage',v_stage);
  end if;

  return jsonb_build_object(
    'resolved',true,
    'family_code',p_family_code,
    'base_stage',v_base,
    'effective_stage',v_stage,
    'conditional',v_conditional,
    'conditional_authority_applies',v_applies,
    'authority',v_cfg->>'authority',
    'blocks_story',v_stage='STORY',
    'blocks_implementation',v_stage in ('STORY','IMPLEMENTATION'),
    'blocks_qa',v_stage in ('STORY','IMPLEMENTATION','QA'),
    'blocks_production',true
  );
end;
$function$;

create or replace function programacion.fn_input_apply_stage_authority_v2(
  p_assessment jsonb,
  p_pantalla_id integer,
  p_family_code text,
  p_version_id bigint
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','programacion'
as $function$
declare
  v jsonb:=coalesce(p_assessment,'{}'::jsonb);
  v_stage jsonb;
  v_effective text;
  v_blockers jsonb:=coalesce(v->'blockers','[]'::jsonb);
begin
  if v->>'applicability'='NOT_APPLICABLE' then return v; end if;
  if coalesce(v->>'coverage_status','')='COMPLETE' and coalesce(v->>'well_defined_status','')='COMPLETE' then return v; end if;

  v_stage:=programacion.fn_input_stage_resolve_v2(
    p_family_code,p_pantalla_id,p_version_id,v->>'coverage_status',v->>'well_defined_status'
  );

  if coalesce((v_stage->>'resolved')::boolean,false) is not true then
    v:=jsonb_set(v,'{required_by_stage}','"UNRESOLVED"'::jsonb,true);
    v:=jsonb_set(v,'{severity}','"P0"'::jsonb,true);
    v:=jsonb_set(v,'{story_ready_status}','"BLOCKED"'::jsonb,true);
    v:=jsonb_set(v,'{implementation_ready_status}','"BLOCKED"'::jsonb,true);
    v:=jsonb_set(v,'{qa_ready_status}','"BLOCKED"'::jsonb,true);
    v:=jsonb_set(v,'{production_ready_status}','"BLOCKED"'::jsonb,true);
    v:=jsonb_set(v,'{blockers}',
      v_blockers||jsonb_build_array(jsonb_build_object('code','CONTRACT_STAGE_UNRESOLVED','family_code',p_family_code)),
      true
    );
    return v;
  end if;

  v_effective:=v_stage->>'effective_stage';
  v:=jsonb_set(v,'{required_by_stage}',to_jsonb(v_effective),true);

  if v_effective='STORY' then
    v:=jsonb_set(v,'{severity}','"P0"'::jsonb,true);
    v:=jsonb_set(v,'{story_ready_status}','"BLOCKED"'::jsonb,true);
    v:=jsonb_set(v,'{implementation_ready_status}','"BLOCKED"'::jsonb,true);
    v:=jsonb_set(v,'{qa_ready_status}','"BLOCKED"'::jsonb,true);
    v:=jsonb_set(v,'{production_ready_status}','"BLOCKED"'::jsonb,true);
  elsif v_effective='IMPLEMENTATION' then
    v:=jsonb_set(v,'{severity}','"P1"'::jsonb,true);
    v:=jsonb_set(v,'{story_ready_status}','"READY"'::jsonb,true);
    v:=jsonb_set(v,'{implementation_ready_status}','"NOT_READY"'::jsonb,true);
    v:=jsonb_set(v,'{qa_ready_status}','"BLOCKED"'::jsonb,true);
    v:=jsonb_set(v,'{production_ready_status}','"BLOCKED"'::jsonb,true);
  elsif v_effective='QA' then
    v:=jsonb_set(v,'{severity}','"P2"'::jsonb,true);
    v:=jsonb_set(v,'{story_ready_status}','"READY"'::jsonb,true);
    v:=jsonb_set(v,'{implementation_ready_status}','"READY"'::jsonb,true);
    v:=jsonb_set(v,'{qa_ready_status}','"BLOCKED"'::jsonb,true);
    v:=jsonb_set(v,'{production_ready_status}','"BLOCKED"'::jsonb,true);
  elsif v_effective='PRODUCTION' then
    v:=jsonb_set(v,'{severity}','"P3"'::jsonb,true);
    v:=jsonb_set(v,'{story_ready_status}','"READY"'::jsonb,true);
    v:=jsonb_set(v,'{implementation_ready_status}','"READY"'::jsonb,true);
    v:=jsonb_set(v,'{qa_ready_status}','"READY"'::jsonb,true);
    v:=jsonb_set(v,'{production_ready_status}','"NOT_READY"'::jsonb,true);
  end if;

  if jsonb_array_length(v_blockers)>0 then
    select coalesce(jsonb_agg(
      case when jsonb_typeof(x.value)='object'
        then x.value||jsonb_build_object('earliest_blocking_stage',v_effective)
        else x.value end
      order by x.ordinality
    ),'[]'::jsonb)
    into v_blockers
    from jsonb_array_elements(v_blockers) with ordinality x(value,ordinality);
    v:=jsonb_set(v,'{blockers}',v_blockers,true);
  end if;
  return v;
end;
$function$;

-- Remove the implicit v1 fallback to STORY.
do $patch_v1$
declare
  v_def text;
  v_old text := $old$v_stage:=upper(coalesce(v_stage_cfg->>'coverage_required_by','STORY'));$old$;
  v_new text := $new$v_stage:=upper(coalesce(v_stage_cfg->>'coverage_required_by','UNRESOLVED'));$new$;
begin
  select pg_get_functiondef('programacion.fn_input_governance_bootstrap_classify_v1(integer,text,bigint)'::regprocedure) into v_def;
  if position(v_new in v_def)=0 then
    if position(v_old in v_def)=0 then raise exception 'STAGE_AUTH_V1_FALLBACK_PATCH_SOURCE_MISMATCH'; end if;
    execute replace(v_def,v_old,v_new);
  end if;
end;
$patch_v1$;

-- Normalize all incomplete semantic results through explicit stage authority instead of hard-forcing P0/Story.
do $patch_v2$
declare
  v_def text;
  v_old text := $old$  v:=v-'classifier_sha256';
  return v||jsonb_build_object('classifier_sha256',programacion.fn_v09_sha256_jsonb(v));$old$;
  v_new text := $new$  v:=programacion.fn_input_apply_stage_authority_v2(v,p_pantalla_id,p_family_code,p_version_id);
  v:=v-'classifier_sha256';
  return v||jsonb_build_object('classifier_sha256',programacion.fn_v09_sha256_jsonb(v));$new$;
begin
  select pg_get_functiondef('programacion.fn_input_governance_bootstrap_classify_v2(integer,text,bigint)'::regprocedure) into v_def;
  if position('fn_input_apply_stage_authority_v2' in v_def)=0 then
    if position(v_old in v_def)=0 then raise exception 'STAGE_AUTH_V2_NORMALIZER_PATCH_SOURCE_MISMATCH'; end if;
    execute replace(v_def,v_old,v_new);
  end if;
end;
$patch_v2$;

-- Persisted assessments must never bypass an absent or malformed family stage.
do $patch_guard$
declare
  v_def text;
  v_old_missing text := $old$  if coalesce(v_cfg,'{}'::jsonb)='{}'::jsonb then
    return new;
  end if;$old$;
  v_new_missing text := $new$  if coalesce(v_cfg,'{}'::jsonb)='{}'::jsonb then
    raise exception 'CONTRACT_STAGE_UNRESOLVED:%',new.family_code;
  end if;$new$;
  v_old_branch text := $old$  if v_stage='IMPLEMENTATION' then$old$;
  v_new_branch text := $new$  if v_stage not in ('STORY','IMPLEMENTATION','QA','PRODUCTION') then
    raise exception 'CONTRACT_STAGE_UNRESOLVED:%',new.family_code;
  end if;

  if v_stage='STORY' then
    if new.story_ready_status='READY' or new.severity<>'P0' then
      raise exception 'STAGE_AUTHORITY_SEVERITY_MISMATCH:% expected=P0 actual=%',new.family_code,new.severity;
    end if;
  elsif v_stage='IMPLEMENTATION' then$new$;
begin
  select pg_get_functiondef('programacion.fn_guard_input_stage_earliest_boundary()'::regprocedure) into v_def;
  if position('raise exception ''CONTRACT_STAGE_UNRESOLVED:%'',new.family_code;' in v_def)=0 then
    if position(v_old_missing in v_def)=0 then raise exception 'STAGE_GUARD_MISSING_CFG_PATCH_SOURCE_MISMATCH'; end if;
    v_def:=replace(v_def,v_old_missing,v_new_missing);
  end if;
  if position('if v_stage=''STORY'' then' in v_def)=0 then
    if position(v_old_branch in v_def)=0 then raise exception 'STAGE_GUARD_STORY_BRANCH_PATCH_SOURCE_MISMATCH'; end if;
    v_def:=replace(v_def,v_old_branch,v_new_branch);
  end if;
  execute v_def;
end;
$patch_guard$;

comment on function programacion.fn_input_stage_resolve_v2(text,integer,bigint,text,text)
is 'Resolves explicit earliest blocking stage. Missing or malformed stage returns CONTRACT_STAGE_UNRESOLVED; conditional API authority is preserved.';
comment on function programacion.fn_input_apply_stage_authority_v2(jsonb,integer,text,bigint)
is 'Normalizes incomplete classifier results to P0/P1/P2/P3 from explicit stage authority instead of semantic-incomplete=>P0. Does not change coverage evidence.';

revoke all on function programacion.fn_input_stage_resolve_v2(text,integer,bigint,text,text) from public;
revoke all on function programacion.fn_input_apply_stage_authority_v2(jsonb,integer,text,bigint) from public;
grant execute on function programacion.fn_input_stage_resolve_v2(text,integer,bigint,text,text) to service_role,programacion_builder,programacion_auditor,programacion_verifier;
grant execute on function programacion.fn_input_apply_stage_authority_v2(jsonb,integer,text,bigint) to service_role,programacion_builder,programacion_auditor,programacion_verifier;

-- Introduction self-tests: authority completeness, distribution, regression examples and provenance semantics.
do $selftest$
declare
  v_count integer;
  v_story integer;
  v_impl integer;
  v_qa integer;
  v_prod integer;
  v_j jsonb;
  v_def text;
  v_decision_number bigint;
  v_universe jsonb;
  v_keys jsonb;
  v_legacy_count integer;
begin
  select decision_number into v_decision_number
  from public.lf_decisiones_gov where id_decision='DEC-INPUT-GOV-512-STAGE-PARAM-AUTH-HUMAN-001';
  if v_decision_number is null then raise exception 'SELFTEST_STAGE_PARAM_OWNER_DECISION_MISSING'; end if;

  select jsonb_agg(f.value order by f.value) into v_universe
  from lf_ops.reglas r
  cross join lateral jsonb_array_elements_text(coalesce(r.valor_config->'families','[]'::jsonb)) f(value)
  where r.codigo='B2B-RULE-STORY-READINESS-001';

  select jsonb_agg(k order by k) into v_keys
  from programacion.contratos c
  cross join lateral jsonb_object_keys(coalesce(c.especificacion->'family_stage_requirements','{}'::jsonb)) k
  where c.version_id=19 and c.contrato_codigo='INPUT_READINESS_CONTRACT';

  if v_universe is distinct from v_keys or jsonb_array_length(v_keys)<>47 then
    raise exception 'SELFTEST_STAGE_AUTHORITY_UNIVERSE_MISMATCH universe=% keys=%',v_universe,v_keys;
  end if;

  select
    count(*),
    count(*) filter(where upper(value->>'coverage_required_by')='STORY'),
    count(*) filter(where upper(value->>'coverage_required_by')='IMPLEMENTATION'),
    count(*) filter(where upper(value->>'coverage_required_by')='QA'),
    count(*) filter(where upper(value->>'coverage_required_by')='PRODUCTION')
  into v_count,v_story,v_impl,v_qa,v_prod
  from programacion.contratos c
  cross join lateral jsonb_each(c.especificacion->'family_stage_requirements') x(key,value)
  where c.version_id=19 and c.contrato_codigo='INPUT_READINESS_CONTRACT';

  if (v_count,v_story,v_impl,v_qa,v_prod) is distinct from (47,20,22,4,1) then
    raise exception 'SELFTEST_STAGE_DISTRIBUTION_INVALID total=% story=% impl=% qa=% prod=%',v_count,v_story,v_impl,v_qa,v_prod;
  end if;

  v_j:=programacion.fn_input_stage_resolve_v2('NO_SUCH_FAMILY',58,19,'MISSING','MISSING');
  if coalesce((v_j->>'resolved')::boolean,true) or v_j->>'error_code'<>'CONTRACT_STAGE_UNRESOLVED' then
    raise exception 'SELFTEST_UNKNOWN_STAGE_MUST_FAIL_CLOSED:%',v_j;
  end if;

  v_j:=programacion.fn_input_governance_bootstrap_classify_v2(58,'RATE_LIMIT',19);
  if v_j->>'required_by_stage'<>'IMPLEMENTATION' or v_j->>'story_ready_status'<>'READY' or v_j->>'severity'<>'P1' then
    raise exception 'SELFTEST_RATE_LIMIT_STAGE_INVALID:%',v_j;
  end if;

  v_j:=programacion.fn_input_governance_bootstrap_classify_v2(58,'PERFORMANCE',19);
  if v_j->>'required_by_stage'<>'QA' or v_j->>'story_ready_status'<>'READY' or v_j->>'implementation_ready_status'<>'READY' or v_j->>'severity'<>'P2' then
    raise exception 'SELFTEST_PERFORMANCE_STAGE_INVALID:%',v_j;
  end if;

  v_j:=programacion.fn_input_governance_bootstrap_classify_v2(58,'STATES',19);
  if v_j->>'required_by_stage'<>'STORY' or v_j->>'story_ready_status'<>'BLOCKED' or v_j->>'severity'<>'P0' then
    raise exception 'SELFTEST_STATES_STAGE_INVALID:%',v_j;
  end if;

  v_j:=programacion.fn_input_governance_bootstrap_classify_v2(58,'API_DATA_CONTRACT',19);
  if v_j->>'story_ready_status'<>'READY' or v_j->>'severity'<>'P1' or v_j->>'required_by_stage'<>'IMPLEMENTATION' then
    raise exception 'SELFTEST_REC001_API_CONDITIONAL_STAGE_REGRESSION:%',v_j;
  end if;

  if not programacion.fn_input_parameter_provenance_valid_v1(jsonb_build_object(
    'max_requests',jsonb_build_object(
      'origin_type','LF_PROVISIONAL_DEFAULT',
      'value_status','LF_PROVISIONAL',
      'origin_name','LF governed provisional default',
      'replacement_policy','MUST_BE_RATIFIED_OR_OVERRIDDEN'
    )
  )) then raise exception 'SELFTEST_PROVISIONAL_PROVENANCE_VALID_EXPECTED'; end if;

  if programacion.fn_input_parameter_provenance_valid_v1(jsonb_build_object(
    'max_requests',jsonb_build_object(
      'origin_type','INDUSTRY_GUIDANCE',
      'value_status','LF_CANONICAL',
      'origin_name','guidance',
      'origin_reference','https://example.invalid/guidance'
    )
  )) then raise exception 'SELFTEST_GUIDANCE_CANNOT_SILENTLY_BECOME_LF_CANONICAL'; end if;

  if programacion.fn_input_parameter_provenance_valid_v1(jsonb_build_object(
    'max_requests',jsonb_build_object(
      'origin_type','INTERNATIONAL_STANDARD',
      'value_status','EXTERNAL_REFERENCE',
      'origin_name','standard-without-traceability'
    )
  )) then raise exception 'SELFTEST_STANDARD_REQUIRES_EXACT_TRACEABILITY'; end if;

  select count(*) into v_legacy_count
  from lf_ops.politicas_rate_limit
  where parameter_provenance='{}'::jsonb;
  if v_legacy_count=0 then
    raise exception 'SELFTEST_LEGACY_VALUES_MUST_NOT_BE_RETROACTIVELY_ATTRIBUTED';
  end if;

  select pg_get_functiondef('programacion.fn_input_governance_bootstrap_classify_v1(integer,text,bigint)'::regprocedure) into v_def;
  if position('coverage_required_by'',''STORY' in v_def)>0 or position('coverage_required_by'',''UNRESOLVED' in v_def)=0 then
    raise exception 'SELFTEST_IMPLICIT_STORY_FALLBACK_STILL_PRESENT';
  end if;

  select pg_get_functiondef('programacion.fn_input_governance_bootstrap_classify_v2(integer,text,bigint)'::regprocedure) into v_def;
  if position('fn_input_apply_stage_authority_v2' in v_def)=0 then
    raise exception 'SELFTEST_STAGE_NORMALIZER_NOT_BOUND';
  end if;

  select pg_get_functiondef('programacion.fn_guard_input_stage_earliest_boundary()'::regprocedure) into v_def;
  if position('CONTRACT_STAGE_UNRESOLVED' in v_def)=0 or position('if v_stage=''STORY'' then' in v_def)=0 then
    raise exception 'SELFTEST_STAGE_GUARD_FAIL_CLOSED_NOT_BOUND';
  end if;

  if coalesce((select (especificacion->'parameterization_contract'->>'missing_parameter_value_alone_blocks_story')::boolean
               from programacion.contratos where version_id=19 and contrato_codigo='INPUT_READINESS_CONTRACT'),true) then
    raise exception 'SELFTEST_PARAMETER_VALUE_MISSING_STORY_POLICY_INVALID';
  end if;
end;
$selftest$;

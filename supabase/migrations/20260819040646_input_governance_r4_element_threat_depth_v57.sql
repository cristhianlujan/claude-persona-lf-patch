alter table programacion.input_family_assessments
  add column if not exists subject_coverage jsonb not null default '[]'::jsonb,
  add column if not exists threat_coverage jsonb not null default '[]'::jsonb,
  add column if not exists semantic_depth_sha256 text;

create or replace function programacion.fn_input_subject_depth_expected(p_pantalla_id integer, p_family_code text)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, programacion, lf_ops, lf_design
as $$
declare
  v_label_typography boolean := false;
  v_result jsonb := '[]'::jsonb;
begin
  if p_family_code = 'DESIGN_SYSTEM' then
    select exists(
      select 1
      from lf_ops.pantalla_variantes pv
      join lf_design.component_tokens lct on lct.component_token_id = pv.layout_component_token_id
      where pv.pantalla_id = p_pantalla_id
        and coalesce(lct.token_bindings,'{}'::jsonb) ? 'label_typography'
    ) into v_label_typography;

    select coalesce(jsonb_agg(x.subject order by x.orden_visual, x.subject_id), '[]'::jsonb)
      into v_result
    from (
      select c.id as subject_id,
             cp.orden_visual,
             jsonb_build_object(
               'subject_type','FIELD',
               'subject_id',c.id,
               'subject_code',c.codigo,
               'status',case when
                   ct.component_token_id is not null
                   and coalesce(ct.token_bindings,'{}'::jsonb) ? 'text'
                   and coalesce(ct.token_bindings,'{}'::jsonb) ? 'border'
                   and coalesce(ct.token_bindings,'{}'::jsonb) ? 'background'
                   and coalesce(ct.token_bindings,'{}'::jsonb) ? 'radius'
                   and coalesce(ct.token_bindings,'{}'::jsonb) ? 'typography'
                   and v_label_typography
                   and (
                     coalesce(ct.token_bindings,'{}'::jsonb) ? 'placeholder_typography'
                     or coalesce(ct.token_bindings,'{}'::jsonb) ? 'placeholder_color'
                     or coalesce(ct.token_bindings,'{}'::jsonb) ? 'placeholder_style'
                   )
                 then 'COMPLETE' else 'PARTIAL' end,
               'checks',jsonb_build_array(
                 jsonb_build_object('check_code','COMPONENT_TOKEN','status',case when ct.component_token_id is not null then 'COMPLETE' else 'MISSING' end,'source_ref','lf_ops.campos_pantallas.component_token_id'),
                 jsonb_build_object('check_code','TEXT_COLOR','status',case when coalesce(ct.token_bindings,'{}'::jsonb) ? 'text' then 'COMPLETE' else 'MISSING' end,'source_ref','lf_design.component_tokens.token_bindings.text'),
                 jsonb_build_object('check_code','BORDER_COLOR','status',case when coalesce(ct.token_bindings,'{}'::jsonb) ? 'border' then 'COMPLETE' else 'MISSING' end,'source_ref','lf_design.component_tokens.token_bindings.border'),
                 jsonb_build_object('check_code','BACKGROUND_COLOR','status',case when coalesce(ct.token_bindings,'{}'::jsonb) ? 'background' then 'COMPLETE' else 'MISSING' end,'source_ref','lf_design.component_tokens.token_bindings.background'),
                 jsonb_build_object('check_code','RADIUS','status',case when coalesce(ct.token_bindings,'{}'::jsonb) ? 'radius' then 'COMPLETE' else 'MISSING' end,'source_ref','lf_design.component_tokens.token_bindings.radius'),
                 jsonb_build_object('check_code','INPUT_TYPOGRAPHY','status',case when coalesce(ct.token_bindings,'{}'::jsonb) ? 'typography' then 'COMPLETE' else 'MISSING' end,'source_ref','lf_design.component_tokens.token_bindings.typography'),
                 jsonb_build_object('check_code','LABEL_TYPOGRAPHY','status',case when v_label_typography then 'COMPLETE' else 'MISSING' end,'source_ref','lf_ops.pantalla_variantes.layout_component_token_id -> lf_design.component_tokens.token_bindings.label_typography'),
                 jsonb_build_object('check_code','PLACEHOLDER_STYLE','status',case when
                     coalesce(ct.token_bindings,'{}'::jsonb) ? 'placeholder_typography'
                     or coalesce(ct.token_bindings,'{}'::jsonb) ? 'placeholder_color'
                     or coalesce(ct.token_bindings,'{}'::jsonb) ? 'placeholder_style'
                   then 'COMPLETE' else 'MISSING' end,'source_ref','lf_design.component_tokens.token_bindings.placeholder_*')
               )
             ) as subject
      from lf_ops.campos_pantallas cp
      join lf_ops.campos c on c.id = cp.campo_id
      left join lf_design.component_tokens ct on ct.component_token_id = cp.component_token_id
      where cp.pantalla_id = p_pantalla_id
    ) x;
    return v_result;
  end if;

  if p_family_code = 'SECURITY' then
    select coalesce(jsonb_agg(x.subject order by x.orden_visual, x.subject_id), '[]'::jsonb)
      into v_result
    from (
      select c.id as subject_id,
             cp.orden_visual,
             jsonb_build_object(
               'subject_type','FIELD',
               'subject_id',c.id,
               'subject_code',c.codigo,
               'status',case when
                   c.es_sensible is not null
                   and c.pii_classification is not null
                   and c.masking_rule is not null
                   and c.logs_allowed is false
                   and c.analytics_allowed is false
                   and c.retention_class is not null
                   and (c.tipo_dato <> 'password' or (
                     exists(select 1 from lf_ops.reglas r join lf_ops.reglas_pantallas rp on rp.regla_id=r.id where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-005' and r.valor_config->>'persistence'='DENY')
                     and exists(select 1 from lf_ops.reglas r join lf_ops.reglas_pantallas rp on rp.regla_id=r.id where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-015' and r.valor_config->>'transport'='HTTPS_REQUIRED' and coalesce((r.valor_config->>'password_field_id')::integer,-1)=c.id)
                     and exists(select 1 from lf_ops.reglas r join lf_ops.reglas_pantallas rp on rp.regla_id=r.id where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-015' and r.valor_config->>'credentials_in_url'='DENY' and r.valor_config->>'credentials_in_query_string'='DENY')
                   ))
                 then 'COMPLETE' else 'PARTIAL' end,
               'checks',
                 jsonb_build_array(
                   jsonb_build_object('check_code','SENSITIVITY_CLASSIFICATION','status',case when c.es_sensible is not null and c.pii_classification is not null then 'COMPLETE' else 'MISSING' end,'source_ref','lf_ops.campos.es_sensible+pii_classification'),
                   jsonb_build_object('check_code','MASKING','status',case when c.masking_rule is not null then 'COMPLETE' else 'MISSING' end,'source_ref','lf_ops.campos.masking_rule'),
                   jsonb_build_object('check_code','NO_LOGS','status',case when c.logs_allowed is false then 'COMPLETE' else 'MISSING' end,'source_ref','lf_ops.campos.logs_allowed'),
                   jsonb_build_object('check_code','NO_ANALYTICS','status',case when c.analytics_allowed is false then 'COMPLETE' else 'MISSING' end,'source_ref','lf_ops.campos.analytics_allowed'),
                   jsonb_build_object('check_code','RETENTION_CLASS','status',case when c.retention_class is not null then 'COMPLETE' else 'MISSING' end,'source_ref','lf_ops.campos.retention_class')
                 ) || case when c.tipo_dato='password' then jsonb_build_array(
                   jsonb_build_object('check_code','PASSWORD_RUNTIME_ONLY','status',case when exists(select 1 from lf_ops.reglas r join lf_ops.reglas_pantallas rp on rp.regla_id=r.id where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-005' and r.valor_config->>'persistence'='DENY') then 'COMPLETE' else 'MISSING' end,'source_ref','B2B-RULE-AUTH-005'),
                   jsonb_build_object('check_code','HTTPS_TRANSPORT','status',case when exists(select 1 from lf_ops.reglas r join lf_ops.reglas_pantallas rp on rp.regla_id=r.id where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-015' and r.valor_config->>'transport'='HTTPS_REQUIRED' and coalesce((r.valor_config->>'password_field_id')::integer,-1)=c.id) then 'COMPLETE' else 'MISSING' end,'source_ref','B2B-RULE-AUTH-015'),
                   jsonb_build_object('check_code','NO_URL_QUERY_EXPOSURE','status',case when exists(select 1 from lf_ops.reglas r join lf_ops.reglas_pantallas rp on rp.regla_id=r.id where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-015' and r.valor_config->>'credentials_in_url'='DENY' and r.valor_config->>'credentials_in_query_string'='DENY') then 'COMPLETE' else 'MISSING' end,'source_ref','B2B-RULE-AUTH-015')
                 ) else '[]'::jsonb end
             ) as subject
      from lf_ops.campos_pantallas cp
      join lf_ops.campos c on c.id = cp.campo_id
      where cp.pantalla_id = p_pantalla_id
    ) x;
    return v_result;
  end if;

  return '[]'::jsonb;
end;
$$;

create or replace function programacion.fn_input_security_threat_expected(p_pantalla_id integer)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, programacion, lf_ops
as $$
declare
  v_auth021 boolean; v_auth008 boolean; v_auth004 boolean; v_auth023 boolean; v_sessionfix boolean;
  v_auth005 boolean; v_auth015 boolean; v_auth024 boolean; v_tls boolean;
  v_ddos boolean; v_sqli boolean; v_xss boolean; v_csrf boolean; v_ssrf boolean; v_clickjacking boolean;
  v_cors boolean; v_headers boolean; v_replay boolean; v_supply boolean; v_payload_limit boolean;
begin
  select
    bool_or(r.codigo='B2B-RULE-AUTH-021'),
    bool_or(r.codigo='B2B-RULE-AUTH-008'),
    bool_or(r.codigo='B2B-RULE-AUTH-004'),
    bool_or(r.codigo='B2B-RULE-AUTH-023'),
    bool_or(r.codigo='B2B-RULE-SESSION-002'),
    bool_or(r.codigo='B2B-RULE-AUTH-005'),
    bool_or(r.codigo='B2B-RULE-AUTH-015'),
    bool_or(r.codigo='B2B-RULE-AUTH-024'),
    bool_or(r.codigo='B2B-RULE-AUTH-015' and r.valor_config->>'transport'='HTTPS_REQUIRED'),
    bool_or(lower(coalesce(r.descripcion,'')) like '%ddos%' or lower(coalesce(r.valor_config::text,'')) like '%ddos%' or lower(coalesce(r.valor_config::text,'')) like '%resource_exhaustion%'),
    bool_or(lower(coalesce(r.descripcion,'')) like '%sql injection%' or lower(coalesce(r.valor_config::text,'')) like '%sql_injection%' or lower(coalesce(r.valor_config::text,'')) like '%parameterized quer%' or lower(coalesce(r.valor_config::text,'')) like '%prepared statement%'),
    bool_or(lower(coalesce(r.descripcion,'')) like '%cross-site scripting%' or lower(coalesce(r.descripcion,'')) like '% xss%' or lower(coalesce(r.valor_config::text,'')) like '%"xss"%'),
    bool_or(lower(coalesce(r.descripcion,'')) like '%csrf%' or lower(coalesce(r.valor_config::text,'')) like '%csrf%' or lower(coalesce(r.valor_config::text,'')) like '%same_site%'),
    bool_or(lower(coalesce(r.descripcion,'')) like '%ssrf%' or lower(coalesce(r.valor_config::text,'')) like '%ssrf%'),
    bool_or(lower(coalesce(r.descripcion,'')) like '%clickjacking%' or lower(coalesce(r.valor_config::text,'')) like '%frame-ancestors%' or lower(coalesce(r.valor_config::text,'')) like '%x-frame-options%'),
    bool_or(lower(coalesce(r.descripcion,'')) like '%cors%' or lower(coalesce(r.valor_config::text,'')) like '%allowed_origin%' or lower(coalesce(r.valor_config::text,'')) like '%allowed_origins%'),
    bool_or(lower(coalesce(r.valor_config::text,'')) like '%strict-transport-security%' or lower(coalesce(r.valor_config::text,'')) like '%content-security-policy%' or lower(coalesce(r.valor_config::text,'')) like '%x-content-type-options%'),
    bool_or(lower(coalesce(r.descripcion,'')) like '%replay attack%' or lower(coalesce(r.valor_config::text,'')) like '%replay_protection%' or lower(coalesce(r.valor_config::text,'')) like '%anti_replay%'),
    bool_or(lower(coalesce(r.descripcion,'')) like '%supply chain%' or lower(coalesce(r.valor_config::text,'')) like '%sbom%' or lower(coalesce(r.valor_config::text,'')) like '%dependency vulnerability%'),
    bool_or(lower(coalesce(r.descripcion,'')) like '%payload size%' or lower(coalesce(r.valor_config::text,'')) like '%max_payload%' or lower(coalesce(r.valor_config::text,'')) like '%request_body_limit%')
  into v_auth021,v_auth008,v_auth004,v_auth023,v_sessionfix,v_auth005,v_auth015,v_auth024,v_tls,
       v_ddos,v_sqli,v_xss,v_csrf,v_ssrf,v_clickjacking,v_cors,v_headers,v_replay,v_supply,v_payload_limit
  from lf_ops.reglas r
  join lf_ops.reglas_pantallas rp on rp.regla_id=r.id
  where rp.pantalla_id=p_pantalla_id;

  return jsonb_build_array(
    jsonb_build_object('threat_code','AUTH_BRUTE_FORCE','applicability','APPLICABLE','status',case when coalesce(v_auth021,false) then 'COMPLETE' else 'MISSING' end,'evidence_refs',case when coalesce(v_auth021,false) then jsonb_build_array('B2B-RULE-AUTH-021') else '[]'::jsonb end),
    jsonb_build_object('threat_code','CREDENTIAL_STUFFING','applicability','APPLICABLE','status',case when coalesce(v_auth021,false) then 'COMPLETE' else 'MISSING' end,'evidence_refs',case when coalesce(v_auth021,false) then jsonb_build_array('B2B-RULE-AUTH-021') else '[]'::jsonb end),
    jsonb_build_object('threat_code','PASSWORD_SPRAYING','applicability','APPLICABLE','status',case when coalesce(v_auth021,false) then 'COMPLETE' else 'MISSING' end,'evidence_refs',case when coalesce(v_auth021,false) then jsonb_build_array('B2B-RULE-AUTH-021') else '[]'::jsonb end),
    jsonb_build_object('threat_code','USER_ENUMERATION','applicability','APPLICABLE','status',case when coalesce(v_auth004,false) then 'COMPLETE' else 'MISSING' end,'evidence_refs',case when coalesce(v_auth004,false) then jsonb_build_array('B2B-RULE-AUTH-004') else '[]'::jsonb end),
    jsonb_build_object('threat_code','AUTOMATION_BOT_ABUSE','applicability','APPLICABLE','status',case when coalesce(v_auth008,false) and coalesce(v_auth021,false) then 'COMPLETE' else 'PARTIAL' end,'evidence_refs',jsonb_build_array('B2B-RULE-AUTH-008','B2B-RULE-AUTH-021')),
    jsonb_build_object('threat_code','DOS_DDOS_RESOURCE_EXHAUSTION','applicability','APPLICABLE','status',case when coalesce(v_ddos,false) then 'COMPLETE' else 'MISSING' end,'evidence_refs','[]'::jsonb,'rationale','Rate limit/anti-bot de autenticación no se considera por sí solo control completo de DoS/DDoS y agotamiento de recursos.'),
    jsonb_build_object('threat_code','SQL_INJECTION','applicability','APPLICABLE','status',case when coalesce(v_sqli,false) then 'COMPLETE' else 'MISSING' end,'evidence_refs','[]'::jsonb),
    jsonb_build_object('threat_code','XSS_SCRIPT_INJECTION','applicability','APPLICABLE','status',case when coalesce(v_xss,false) then 'COMPLETE' else 'MISSING' end,'evidence_refs','[]'::jsonb),
    jsonb_build_object('threat_code','CSRF_LOGIN_REQUEST','applicability',case when coalesce(v_csrf,false) then 'APPLICABLE' else 'UNRESOLVED' end,'status',case when coalesce(v_csrf,false) then 'COMPLETE' else 'UNRESOLVED' end,'evidence_refs','[]'::jsonb,'rationale','La aplicabilidad depende del contrato real de sesión/cookies y del endpoint materializado; no se infiere N/A.'),
    jsonb_build_object('threat_code','OPEN_REDIRECT','applicability','APPLICABLE','status',case when coalesce(v_auth023,false) then 'COMPLETE' else 'MISSING' end,'evidence_refs',case when coalesce(v_auth023,false) then jsonb_build_array('B2B-RULE-AUTH-023') else '[]'::jsonb end),
    jsonb_build_object('threat_code','SESSION_FIXATION_REPLAY','applicability','APPLICABLE','status',case when coalesce(v_sessionfix,false) and coalesce(v_replay,false) then 'COMPLETE' when coalesce(v_sessionfix,false) then 'PARTIAL' else 'MISSING' end,'evidence_refs',case when coalesce(v_sessionfix,false) then jsonb_build_array('B2B-RULE-SESSION-002') else '[]'::jsonb end,'rationale','Session fixation está gobernado; replay requiere evidencia propia.'),
    jsonb_build_object('threat_code','SSRF_BACKEND_FETCH','applicability',case when coalesce(v_ssrf,false) then 'APPLICABLE' else 'UNRESOLVED' end,'status',case when coalesce(v_ssrf,false) then 'COMPLETE' else 'UNRESOLVED' end,'evidence_refs','[]'::jsonb,'rationale','No se declara N/A sin demostrar que no existe fetch backend controlable por input.'),
    jsonb_build_object('threat_code','CLICKJACKING','applicability','APPLICABLE','status',case when coalesce(v_clickjacking,false) then 'COMPLETE' else 'MISSING' end,'evidence_refs','[]'::jsonb),
    jsonb_build_object('threat_code','CORS_ORIGIN_CONTROL','applicability','APPLICABLE','status',case when coalesce(v_cors,false) then 'COMPLETE' else 'MISSING' end,'evidence_refs','[]'::jsonb),
    jsonb_build_object('threat_code','SECURITY_HEADERS_TLS','applicability','APPLICABLE','status',case when coalesce(v_tls,false) and coalesce(v_headers,false) then 'COMPLETE' when coalesce(v_tls,false) then 'PARTIAL' else 'MISSING' end,'evidence_refs',case when coalesce(v_tls,false) then jsonb_build_array('B2B-RULE-AUTH-015') else '[]'::jsonb end,'rationale','HTTPS está definido; faltan headers de seguridad explícitos si no existe evidencia adicional.'),
    jsonb_build_object('threat_code','SECRET_CREDENTIAL_EXPOSURE','applicability','APPLICABLE','status',case when coalesce(v_auth005,false) and coalesce(v_auth015,false) and coalesce(v_auth024,false) then 'COMPLETE' else 'PARTIAL' end,'evidence_refs',jsonb_build_array('B2B-RULE-AUTH-005','B2B-RULE-AUTH-015','B2B-RULE-AUTH-024')),
    jsonb_build_object('threat_code','DEPENDENCY_SUPPLY_CHAIN','applicability','APPLICABLE','status',case when coalesce(v_supply,false) then 'COMPLETE' else 'MISSING' end,'evidence_refs','[]'::jsonb),
    jsonb_build_object('threat_code','REQUEST_PAYLOAD_RESOURCE_LIMIT','applicability','APPLICABLE','status',case when coalesce(v_payload_limit,false) then 'COMPLETE' else 'MISSING' end,'evidence_refs','[]'::jsonb)
  );
end;
$$;

create or replace function programacion.fn_guard_input_family_semantic_depth()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, programacion
as $$
declare
  v_revision text;
  v_pantalla_id integer;
  v_expected_subject jsonb := '[]'::jsonb;
  v_expected_threat jsonb := '[]'::jsonb;
  v_bad integer := 0;
  v_hash text;
begin
  select r.contract_revision,r.pantalla_id into v_revision,v_pantalla_id
  from programacion.input_readiness_runs r where r.id=coalesce(new.run_id,old.run_id);
  if v_revision is distinct from '5.7' then return new; end if;

  if tg_op='INSERT' then
    if new.family_code in ('DESIGN_SYSTEM','SECURITY') then
      v_expected_subject:=programacion.fn_input_subject_depth_expected(v_pantalla_id,new.family_code);
      new.subject_coverage:=v_expected_subject;
    else
      new.subject_coverage:='[]'::jsonb;
    end if;

    if new.family_code='SECURITY' then
      v_expected_threat:=programacion.fn_input_security_threat_expected(v_pantalla_id);
      new.threat_coverage:=v_expected_threat;
    else
      new.threat_coverage:='[]'::jsonb;
    end if;

    new.semantic_depth_sha256:=programacion.fn_v09_sha256_jsonb(jsonb_build_object(
      'family_code',new.family_code,
      'subject_coverage',new.subject_coverage,
      'threat_coverage',new.threat_coverage
    ));
    new.curator_evidence:=jsonb_set(coalesce(new.curator_evidence,'{}'::jsonb),'{semantic_depth_sha256}',to_jsonb(new.semantic_depth_sha256),true);

    if new.family_code in ('DESIGN_SYSTEM','SECURITY') then
      select count(*) into v_bad from jsonb_array_elements(new.subject_coverage) s where s->>'status' not in ('COMPLETE','NOT_APPLICABLE');
      if v_bad>0 and new.coverage_status='COMPLETE' then raise exception 'FAMILY_COMPLETE_WITH_INCOMPLETE_SUBJECT:%:%',new.family_code,v_bad; end if;
      if v_bad>0 and new.well_defined_status='COMPLETE' then raise exception 'FAMILY_WELL_DEFINED_WITH_INCOMPLETE_SUBJECT:%:%',new.family_code,v_bad; end if;
    end if;
    if new.family_code='SECURITY' then
      select count(*) into v_bad from jsonb_array_elements(new.threat_coverage) t where t->>'status' not in ('COMPLETE','NOT_APPLICABLE');
      if v_bad>0 and new.coverage_status='COMPLETE' then raise exception 'SECURITY_COMPLETE_WITH_UNRESOLVED_THREAT:%',v_bad; end if;
      if v_bad>0 and new.well_defined_status='COMPLETE' then raise exception 'SECURITY_WELL_DEFINED_WITH_UNRESOLVED_THREAT:%',v_bad; end if;
    end if;
    return new;
  end if;

  if new.subject_coverage is distinct from old.subject_coverage or new.threat_coverage is distinct from old.threat_coverage or new.semantic_depth_sha256 is distinct from old.semantic_depth_sha256 then
    raise exception 'SEMANTIC_DEPTH_IMMUTABLE:%',old.family_code;
  end if;

  if old.validator_outcome='PENDING' and new.validator_outcome<>'PENDING' then
    if new.validator_evidence->>'semantic_depth_sha256' is distinct from old.semantic_depth_sha256 then
      raise exception 'VALIDATOR_SEMANTIC_DEPTH_HASH_MISMATCH:%',old.family_code;
    end if;
    if old.family_code in ('DESIGN_SYSTEM','SECURITY') then
      v_expected_subject:=programacion.fn_input_subject_depth_expected(v_pantalla_id,old.family_code);
      if old.subject_coverage is distinct from v_expected_subject then raise exception 'SEMANTIC_SUBJECT_DEPTH_STALE_DURING_VALIDATION:%',old.family_code; end if;
    end if;
    if old.family_code='SECURITY' then
      v_expected_threat:=programacion.fn_input_security_threat_expected(v_pantalla_id);
      if old.threat_coverage is distinct from v_expected_threat then raise exception 'SEMANTIC_THREAT_DEPTH_STALE_DURING_VALIDATION'; end if;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_input_family_assessment_01_semantic_depth_insert on programacion.input_family_assessments;
create trigger trg_input_family_assessment_01_semantic_depth_insert
before insert on programacion.input_family_assessments
for each row execute function programacion.fn_guard_input_family_semantic_depth();

drop trigger if exists trg_input_family_assessment_01_semantic_depth_update on programacion.input_family_assessments;
create trigger trg_input_family_assessment_01_semantic_depth_update
before update on programacion.input_family_assessments
for each row execute function programacion.fn_guard_input_family_semantic_depth();

create or replace function programacion.fn_guard_input_family_assessment_insert()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog','programacion','lf_ops'
as $$
declare
  v_status text; v_contract_version integer; v_contract_pin_revision text; v_contract_pin_sha text;
  v_pantalla_id integer; v_version_id bigint; v_families jsonb; v_payload jsonb; v_ref jsonb; v_mode text; v_states text[];
  v_governance_family boolean; v_has_independent_ekb boolean; v_has_contract_ref boolean;
  v_contract_schema integer; v_contract_revision text; v_contract_payload jsonb; v_contract_sha text;
  v_non_absence_authority boolean:=false; v_stage_cfg jsonb;
  v_allow_story_incomplete boolean:=false; v_allow_impl_incomplete boolean:=false; v_allow_qa_incomplete boolean:=false; v_allow_prod_incomplete boolean:=false;
begin
  select r.status,r.contract_version,r.contract_revision,r.contract_snapshot_sha256,r.pantalla_id,r.version_id,q.valor_config->'families'
    into v_status,v_contract_version,v_contract_pin_revision,v_contract_pin_sha,v_pantalla_id,v_version_id,v_families
  from programacion.input_readiness_runs r join lf_ops.reglas q on q.id=r.universe_rule_id where r.id=new.run_id;
  if v_status is null then raise exception 'INPUT_READINESS_RUN_NOT_FOUND'; end if;

  select (c.especificacion->>'schema_version')::integer,c.especificacion->>'contract_revision',
         jsonb_build_object('id',c.id,'version_id',c.version_id,'contrato_codigo',c.contrato_codigo,'fail_closed',c.fail_closed,'estado',c.estado,'especificacion',c.especificacion)
    into v_contract_schema,v_contract_revision,v_contract_payload
  from programacion.contratos c where c.version_id=v_version_id and c.contrato_codigo='INPUT_READINESS_CONTRACT';
  v_contract_sha:=programacion.fn_v09_sha256_jsonb(v_contract_payload);
  if v_contract_version<>v_contract_schema or v_contract_pin_revision is distinct from v_contract_revision or v_contract_pin_sha is distinct from v_contract_sha then
    raise exception 'INPUT_READINESS_CONTRACT_PIN_STALE_FOR_CURATOR:%',new.family_code;
  end if;
  v_stage_cfg:=coalesce(v_contract_payload->'especificacion'->'family_stage_requirements'->new.family_code,'{}'::jsonb);
  v_allow_story_incomplete:=coalesce((v_stage_cfg->>'allow_story_ready_when_incomplete')::boolean,false);
  v_allow_impl_incomplete:=coalesce((v_stage_cfg->>'allow_implementation_ready_when_incomplete')::boolean,false);
  v_allow_qa_incomplete:=coalesce((v_stage_cfg->>'allow_qa_ready_when_incomplete')::boolean,false);
  v_allow_prod_incomplete:=coalesce((v_stage_cfg->>'allow_production_ready_when_incomplete')::boolean,false);

  if v_status<>'CURATING' then raise exception 'CURATOR_INSERT_CLOSED_FOR_RUN_STATUS_%',v_status; end if;
  if jsonb_typeof(v_families)<>'array' or not (v_families ? new.family_code) then raise exception 'FAMILY_NOT_IN_CANONICAL_UNIVERSE:%',new.family_code; end if;
  if jsonb_typeof(new.source_refs)<>'array' or jsonb_array_length(new.source_refs)=0 then raise exception 'SOURCE_REFS_REQUIRED:%',new.family_code; end if;
  if new.severity not in ('P0','P1','P2','P3','P4') then raise exception 'SEVERITY_MUST_BE_RESOLVED_P0_P4:%:%',new.family_code,new.severity; end if;

  for v_ref in select value from jsonb_array_elements(new.source_refs) loop
    if v_ref->>'kind' in ('SCREEN','SCREEN_RULE_SET','SCREEN_STATE_SET','CURRENT_VISUAL_ARTIFACT','CAPABILITY_ABSENCE') then
      if not (v_ref ? 'pantalla_id') or (v_ref->>'pantalla_id')::integer<>v_pantalla_id then
        raise exception 'SCREEN_SCOPED_SOURCE_REF_REQUIRES_EXPLICIT_PANTALLA_ID:%:%',new.family_code,v_ref->>'kind';
      end if;
    end if;
    if v_ref->>'kind'<>'CAPABILITY_ABSENCE' then v_non_absence_authority:=true; end if;
    perform programacion.fn_input_resolve_source_ref(v_ref,v_pantalla_id,v_version_id);
  end loop;

  if new.applicability='NOT_APPLICABLE' and not v_non_absence_authority then
    raise exception 'NOT_APPLICABLE_REQUIRES_POSITIVE_NON_ABSENCE_AUTHORITY:%',new.family_code;
  end if;

  v_governance_family:=new.family_code in ('SOURCE_AUTHORITY_PROVENANCE','FRESHNESS_INVALIDATION','NEGATIVE_REQUIREMENTS','CONFLICT_PRECEDENCE','APPLICABILITY_READINESS');
  if v_governance_family then
    select coalesce(bool_or(programacion.fn_input_source_authority_class(value)='INDEPENDENT_EKB'),false),coalesce(bool_or(value->>'kind'='CONTRACT'),false)
      into v_has_independent_ekb,v_has_contract_ref from jsonb_array_elements(new.source_refs);
    if not v_has_independent_ekb then raise exception 'GOVERNANCE_FAMILY_REQUIRES_INDEPENDENT_EKB_AUTHORITY:%',new.family_code; end if;
    if v_has_contract_ref then raise exception 'GOVERNANCE_FAMILY_CONTRACT_CANNOT_SELF_AUTHORIZE:%',new.family_code; end if;
  end if;

  if coalesce(new.curator_evidence->>'contract_revision','')<>v_contract_revision then raise exception 'CURATOR_EVIDENCE_CONTRACT_REVISION_MISMATCH:%',new.family_code; end if;

  v_states:=array[new.coverage_status,new.well_defined_status,new.story_ready_status,new.implementation_ready_status,new.qa_ready_status,new.production_ready_status];
  if new.applicability='APPLICABLE' and 'NOT_APPLICABLE'=any(v_states) then raise exception 'APPLICABLE_FAMILY_CANNOT_HAVE_NOT_APPLICABLE_READINESS:%',new.family_code; end if;
  if new.applicability='NOT_APPLICABLE' and exists(select 1 from unnest(v_states) s where s<>'NOT_APPLICABLE') then raise exception 'NOT_APPLICABLE_FAMILY_REQUIRES_ALL_NOT_APPLICABLE_READINESS:%',new.family_code; end if;
  if new.applicability='UNRESOLVED' then
    if new.story_ready_status='READY' then raise exception 'UNRESOLVED_APPLICABILITY_CANNOT_BE_STORY_READY:%',new.family_code; end if;
    if new.severity<>'P0' then raise exception 'UNRESOLVED_APPLICABILITY_REQUIRES_P0:%',new.family_code; end if;
  end if;
  if new.applicability='APPLICABLE' then
    if new.story_ready_status<>'READY' and new.severity<>'P0' then raise exception 'STORY_OPEN_REQUIRES_P0:%',new.family_code; end if;
    if new.story_ready_status='READY' and (new.coverage_status in ('MISSING','PENDING','BLOCKED') or new.well_defined_status in ('MISSING','PENDING','BLOCKED')) and not v_allow_story_incomplete then raise exception 'STORY_READY_REQUIRES_NON_MISSING_COVERAGE_AND_DEFINITION:%',new.family_code; end if;
    if new.implementation_ready_status='READY' and new.story_ready_status<>'READY' then raise exception 'IMPLEMENTATION_READY_REQUIRES_STORY_READY:%',new.family_code; end if;
    if new.implementation_ready_status='READY' and (new.coverage_status<>'COMPLETE' or new.well_defined_status<>'COMPLETE') and not v_allow_impl_incomplete then raise exception 'IMPLEMENTATION_READY_REQUIRES_COMPLETE_COVERAGE_DEFINITION:%',new.family_code; end if;
    if new.qa_ready_status='READY' and new.implementation_ready_status<>'READY' then raise exception 'QA_READY_REQUIRES_IMPLEMENTATION_READY:%',new.family_code; end if;
    if new.qa_ready_status='READY' and (new.coverage_status<>'COMPLETE' or new.well_defined_status<>'COMPLETE') and not v_allow_qa_incomplete then raise exception 'QA_READY_REQUIRES_COMPLETE_COVERAGE_DEFINITION:%',new.family_code; end if;
    if new.production_ready_status='READY' and new.qa_ready_status<>'READY' then raise exception 'PRODUCTION_READY_REQUIRES_QA_READY:%',new.family_code; end if;
    if new.production_ready_status='READY' and (new.coverage_status<>'COMPLETE' or new.well_defined_status<>'COMPLETE') and not v_allow_prod_incomplete then raise exception 'PRODUCTION_READY_REQUIRES_COMPLETE_COVERAGE_DEFINITION:%',new.family_code; end if;
  end if;

  if new.validator_outcome<>'PENDING' or new.validator_identity is not null or new.validator_sha256 is not null or new.validator_assessed_at is not null or new.validator_findings<>'[]'::jsonb or new.validator_evidence<>'{}'::jsonb then raise exception 'CURATOR_CANNOT_PREVALIDATE:%',new.family_code; end if;
  v_mode:='DB_MANIFEST_V'||v_contract_version::text;
  new.freshness:=jsonb_build_object('mode',v_mode,'status','PENDING_RUN_SNAPSHOT');
  v_payload:=jsonb_build_object('run_id',new.run_id,'family_code',new.family_code,'severity',new.severity,'applicability',new.applicability,'coverage_status',new.coverage_status,'well_defined_status',new.well_defined_status,'story_ready_status',new.story_ready_status,'implementation_ready_status',new.implementation_ready_status,'qa_ready_status',new.qa_ready_status,'production_ready_status',new.production_ready_status,'source_refs',new.source_refs,'rationale',new.rationale,'blockers',new.blockers,'negative_requirements',new.negative_requirements,'test_obligations',new.test_obligations,'freshness',new.freshness,'curator_evidence',new.curator_evidence,'subject_coverage',new.subject_coverage,'threat_coverage',new.threat_coverage,'semantic_depth_sha256',new.semantic_depth_sha256);
  new.curator_sha256:=programacion.fn_v09_sha256_jsonb(v_payload);
  return new;
end;
$$;

create or replace function programacion.fn_guard_input_family_assessment_update()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog','programacion'
as $$
declare
  v_payload jsonb; v_run_status text; v_run_sha text; v_curator_identity text; v_validator_identity text; v_validator_component_id bigint;
  v_version_id bigint; v_pantalla_id integer; v_run_contract_revision text; v_run_contract_sha text;
  v_contract_revision text; v_contract_payload jsonb; v_contract_sha text;
  v_current_manifest jsonb; v_current_sha text; v_bad_assertions integer; v_assertion jsonb; v_eval jsonb; v_governance_family boolean;
begin
  if new.run_id is distinct from old.run_id or new.family_code is distinct from old.family_code or new.severity is distinct from old.severity or new.applicability is distinct from old.applicability or new.coverage_status is distinct from old.coverage_status or new.well_defined_status is distinct from old.well_defined_status or new.story_ready_status is distinct from old.story_ready_status or new.implementation_ready_status is distinct from old.implementation_ready_status or new.qa_ready_status is distinct from old.qa_ready_status or new.production_ready_status is distinct from old.production_ready_status or new.source_refs is distinct from old.source_refs or new.rationale is distinct from old.rationale or new.blockers is distinct from old.blockers or new.negative_requirements is distinct from old.negative_requirements or new.test_obligations is distinct from old.test_obligations or new.freshness is distinct from old.freshness or new.curator_evidence is distinct from old.curator_evidence or new.curator_sha256 is distinct from old.curator_sha256 or new.subject_coverage is distinct from old.subject_coverage or new.threat_coverage is distinct from old.threat_coverage or new.semantic_depth_sha256 is distinct from old.semantic_depth_sha256 or new.created_at is distinct from old.created_at then raise exception 'CURATOR_FIELDS_IMMUTABLE:%',old.family_code; end if;
  if old.validator_outcome<>'PENDING' then raise exception 'VALIDATOR_RECEIPT_IMMUTABLE:%',old.family_code; end if;
  if new.validator_outcome='PENDING' then raise exception 'VALIDATOR_UPDATE_MUST_BE_TERMINAL:%',old.family_code; end if;

  select r.status,r.source_snapshot_sha256,r.curator_identity,r.validator_identity,r.validator_component_id,r.version_id,r.pantalla_id,r.contract_revision,r.contract_snapshot_sha256
    into v_run_status,v_run_sha,v_curator_identity,v_validator_identity,v_validator_component_id,v_version_id,v_pantalla_id,v_run_contract_revision,v_run_contract_sha
  from programacion.input_readiness_runs r where r.id=old.run_id;
  if v_run_status<>'VALIDATING' then raise exception 'VALIDATOR_REQUIRES_VALIDATING_RUN:%',old.family_code; end if;
  if v_validator_component_id is null then raise exception 'RUN_VALIDATOR_COMPONENT_REQUIRED'; end if;
  if v_validator_identity is null or v_validator_identity=v_curator_identity then raise exception 'VALIDATOR_IDENTITY_NOT_INDEPENDENT'; end if;
  if new.validator_identity is distinct from v_validator_identity then raise exception 'VALIDATOR_IDENTITY_MISMATCH:%',old.family_code; end if;

  select c.especificacion->>'contract_revision',jsonb_build_object('id',c.id,'version_id',c.version_id,'contrato_codigo',c.contrato_codigo,'fail_closed',c.fail_closed,'estado',c.estado,'especificacion',c.especificacion)
    into v_contract_revision,v_contract_payload from programacion.contratos c where c.version_id=v_version_id and c.contrato_codigo='INPUT_READINESS_CONTRACT';
  v_contract_sha:=programacion.fn_v09_sha256_jsonb(v_contract_payload);
  if v_run_contract_revision is distinct from v_contract_revision or v_run_contract_sha is distinct from v_contract_sha then raise exception 'INPUT_READINESS_CONTRACT_PIN_STALE_DURING_VALIDATION:%',old.family_code; end if;

  if new.validator_assessed_at is null then new.validator_assessed_at:=now(); end if;
  if jsonb_typeof(new.validator_evidence)<>'object' or new.validator_evidence='{}'::jsonb then raise exception 'VALIDATOR_EVIDENCE_REQUIRED:%',old.family_code; end if;
  if new.validator_evidence->>'source_snapshot_sha256' is distinct from v_run_sha then raise exception 'VALIDATOR_EVIDENCE_SOURCE_SNAPSHOT_MISMATCH:%',old.family_code; end if;
  if new.validator_evidence->>'curator_sha256' is distinct from old.curator_sha256 then raise exception 'VALIDATOR_EVIDENCE_CURATOR_HASH_MISMATCH:%',old.family_code; end if;
  if coalesce((new.validator_evidence->>'direct_source_readback')::boolean,false) is not true then raise exception 'VALIDATOR_DIRECT_SOURCE_READBACK_REQUIRED:%',old.family_code; end if;
  if new.validator_evidence->>'execution_mode'<>'INDEPENDENT_VALIDATOR' then raise exception 'VALIDATOR_EXECUTION_MODE_REQUIRED:%',old.family_code; end if;
  if coalesce(new.validator_evidence->>'contract_revision','')<>v_contract_revision then raise exception 'VALIDATOR_EVIDENCE_CONTRACT_REVISION_MISMATCH:%',old.family_code; end if;
  if v_contract_revision='5.7' and new.validator_evidence->>'semantic_depth_sha256' is distinct from old.semantic_depth_sha256 then raise exception 'VALIDATOR_EVIDENCE_SEMANTIC_DEPTH_MISMATCH:%',old.family_code; end if;
  if jsonb_typeof(new.validator_evidence->'assertions')<>'array' or jsonb_array_length(new.validator_evidence->'assertions')=0 then raise exception 'VALIDATOR_ASSERTIONS_REQUIRED:%',old.family_code; end if;
  select count(*) into v_bad_assertions from jsonb_array_elements(new.validator_evidence->'assertions') a where jsonb_typeof(a)<>'object' or not (a?'actual') or not (a?'expected') or not (a?'operator') or not (a?'source_ref') or not (a?'path');
  if v_bad_assertions>0 then raise exception 'VALIDATOR_ASSERTION_SCHEMA_INVALID:%',old.family_code; end if;

  v_governance_family:=old.family_code in ('SOURCE_AUTHORITY_PROVENANCE','FRESHNESS_INVALIDATION','NEGATIVE_REQUIREMENTS','CONFLICT_PRECEDENCE','APPLICABILITY_READINESS');
  for v_assertion in select value from jsonb_array_elements(new.validator_evidence->'assertions') loop
    if v_assertion->'source_ref'->>'kind' in ('SCREEN','SCREEN_RULE_SET','SCREEN_STATE_SET','CURRENT_VISUAL_ARTIFACT','CAPABILITY_ABSENCE','SCREEN_CANONICAL_GRAPH') then
      if not (v_assertion->'source_ref'?'pantalla_id') or (v_assertion->'source_ref'->>'pantalla_id')::integer<>v_pantalla_id then raise exception 'VALIDATOR_SCREEN_SOURCE_REF_REQUIRES_EXPLICIT_PANTALLA_ID:%',old.family_code; end if;
    end if;
    if v_governance_family then
      if not programacion.fn_input_governance_assertion_relevant(old.family_code,v_assertion->'source_ref',v_assertion->'path') then raise exception 'GOVERNANCE_VALIDATOR_ASSERTION_REQUIRES_INDEPENDENT_AUTHORITY:%',old.family_code; end if;
    else
      if not programacion.fn_input_assertion_is_relevant(old.family_code,v_assertion->'source_ref',v_assertion->'path') then raise exception 'VALIDATOR_ASSERTION_NOT_RELEVANT:%',old.family_code; end if;
    end if;
    v_eval:=programacion.fn_input_evaluate_assertion(old.run_id,old.family_code,v_assertion);
    if new.validator_outcome='PASS' and coalesce((v_eval->>'passed')::boolean,false) is not true then raise exception 'VALIDATOR_ASSERTION_FAILED:%',old.family_code; end if;
  end loop;

  v_current_manifest:=programacion.fn_input_build_source_manifest(old.run_id); v_current_sha:=programacion.fn_v09_sha256_jsonb(v_current_manifest);
  if v_current_sha<>v_run_sha then raise exception 'SOURCE_SNAPSHOT_STALE_DURING_VALIDATION:%',old.family_code; end if;
  v_payload:=jsonb_build_object('curator_sha256',old.curator_sha256,'semantic_depth_sha256',old.semantic_depth_sha256,'source_snapshot_sha256',v_run_sha,'validator_outcome',new.validator_outcome,'validator_findings',new.validator_findings,'validator_evidence',new.validator_evidence,'validator_identity',new.validator_identity,'validator_assessed_at',new.validator_assessed_at);
  new.validator_sha256:=programacion.fn_v09_sha256_jsonb(v_payload);
  return new;
end;
$$;

update programacion.contratos
set especificacion = especificacion || jsonb_build_object(
  'schema_version',5,
  'contract_revision','5.7',
  'remediation_revision','AUDIT_20260818_R4_ELEMENT_THREAT_DEPTH',
  'semantic_depth_contract',jsonb_build_object(
    'mode','FAMILY_PLUS_CANONICAL_SUBJECT_DEPTH',
    'new_family_created',false,
    'new_agent_created',false,
    'subject_depth_required_families',jsonb_build_array('DESIGN_SYSTEM','SECURITY'),
    'complete_requires_all_subjects_complete',true,
    'security_threat_matrix_required',true,
    'threat_not_applicable_requires_positive_evidence',true,
    'security_threat_catalog',jsonb_build_array(
      'AUTH_BRUTE_FORCE','CREDENTIAL_STUFFING','PASSWORD_SPRAYING','USER_ENUMERATION','AUTOMATION_BOT_ABUSE',
      'DOS_DDOS_RESOURCE_EXHAUSTION','SQL_INJECTION','XSS_SCRIPT_INJECTION','CSRF_LOGIN_REQUEST','OPEN_REDIRECT',
      'SESSION_FIXATION_REPLAY','SSRF_BACKEND_FETCH','CLICKJACKING','CORS_ORIGIN_CONTROL','SECURITY_HEADERS_TLS',
      'SECRET_CREDENTIAL_EXPOSURE','DEPENDENCY_SUPPLY_CHAIN','REQUEST_PAYLOAD_RESOURCE_LIMIT'
    ),
    'subject_registry_reuse','lf_ops.campos + lf_ops.campos_pantallas + lf_ops.pantalla_elementos',
    'semantic_depth_hash_binding','REQUIRED_CURATOR_AND_VALIDATOR'
  ),
  'family_stage_requirements',jsonb_build_object(
    'BROWSER_PLATFORM',jsonb_build_object(
      'coverage_required_by','QA',
      'well_defined_required_by','QA',
      'allow_story_ready_when_incomplete',true,
      'allow_implementation_ready_when_incomplete',true,
      'allow_qa_ready_when_incomplete',false,
      'allow_production_ready_when_incomplete',false,
      'authority','INPUT_READINESS_CONTRACT_5_7'
    )
  ),
  'negative_tests',coalesce(especificacion->'negative_tests','[]'::jsonb) || jsonb_build_array(
    'FAMILY_COMPLETE_WITH_INCOMPLETE_SUBJECT','FAMILY_WELL_DEFINED_WITH_INCOMPLETE_SUBJECT',
    'SECURITY_COMPLETE_WITH_UNRESOLVED_THREAT','SECURITY_THREAT_OMITTED',
    'SEMANTIC_DEPTH_MUTATION_AFTER_CURATOR','VALIDATOR_SEMANTIC_DEPTH_HASH_MISMATCH',
    'LATER_STAGE_GAP_BLOCKS_EARLIER_STAGE','BROWSER_PLATFORM_QA_GAP_AS_STORY_BLOCKER'
  ),
  'audit_remediation',coalesce(especificacion->'audit_remediation','[]'::jsonb) || jsonb_build_array(
    'AUD-IGA-022_ELEMENT_LEVEL_SEMANTIC_DEPTH','AUD-IGA-023_SECURITY_THREAT_MATRIX','AUD-IGA-024_STAGE_SPECIFIC_BLOCKING'
  )
)
where version_id=19 and contrato_codigo='INPUT_READINESS_CONTRACT';

update lf_ops.reglas
set valor_config = valor_config || jsonb_build_object(
  'element_depth_required',true,
  'security_threat_matrix_required',true,
  'complete_requires_all_required_subject_checks',true,
  'no_silent_threat_omission',true,
  'family_count',47
)
where codigo='B2B-RULE-STORY-READINESS-001';

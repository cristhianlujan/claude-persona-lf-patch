-- B2B-AUTH-001 critical implementation-readiness remediation v1
-- SECURITY: materialize canonical baseline controls without claiming implementation.
-- TIMEOUT_RETRY: reconcile the existing AUTH_LOGIN_API timeout policy and bind it to AUTH-016.
-- Both families remain fail-closed at Implementation while sources are CANDIDATO/pending.

begin;

do $preflight$
declare
  v_screen_id integer;
  v_timeout_status text;
  v_timeout_operation text;
  v_auth016 jsonb;
begin
  select id into v_screen_id
  from lf_ops.pantallas
  where id=51 and codigo='B2B-AUTH-001';

  if v_screen_id is null then
    raise exception 'B2B_AUTH_001_SCREEN_NOT_FOUND';
  end if;

  select status,operation_code
    into v_timeout_status,v_timeout_operation
  from lf_ops.politicas_timeout
  where timeout_policy_id=10;

  if v_timeout_operation is distinct from 'AUTH_LOGIN_API' then
    raise exception 'AUTH_LOGIN_TIMEOUT_POLICY_DRIFT: operation=%',v_timeout_operation;
  end if;

  if v_timeout_status not in ('ARCHIVADO','CANDIDATO') then
    raise exception 'AUTH_LOGIN_TIMEOUT_POLICY_UNEXPECTED_STATUS:%',v_timeout_status;
  end if;

  select valor_config into v_auth016
  from lf_ops.reglas
  where codigo='B2B-RULE-AUTH-016';

  if v_auth016 is null then
    raise exception 'B2B_RULE_AUTH_016_MISSING';
  end if;

  if coalesce(v_auth016->>'auth_automatic_retry','')<>'DENY'
     or coalesce(v_auth016->>'session_on_timeout','')<>'DENY' then
    raise exception 'B2B_RULE_AUTH_016_FAIL_CLOSED_CONTRACT_DRIFT:%',v_auth016;
  end if;

  if nullif(v_auth016->>'timeout_policy_id','') is not null
     and v_auth016->>'timeout_policy_id'<>'10' then
    raise exception 'B2B_RULE_AUTH_016_TIMEOUT_REFERENCE_DRIFT:%',v_auth016->>'timeout_policy_id';
  end if;
end;
$preflight$;

-- Canonical security baseline for the Login capability.
insert into lf_ops.reglas(
  codigo,
  categoria,
  titulo,
  descripcion,
  razon,
  valor_config,
  es_transversal,
  estado,
  origen,
  pendiente_decision,
  pendiente_detalle,
  created_by
)
values(
  'B2B-RULE-SECURITY-BASELINE-001',
  'SECURITY',
  'Baseline técnico de seguridad del Login B2B',
  'El Login B2B debe aplicar defensa contra DDoS y resource exhaustion, validación server-side contra injection con prepared statements/parameterized queries, mitigación XSS, SSRF, clickjacking, control CORS, TLS y security headers, replay protection, controles de supply chain/SBOM y límites de request payload. La definición es canónica; la implementación y QA permanecen pendientes.',
  'Cerrar la cobertura semántica de amenazas del Login sin confundir definición con implementación.',
  jsonb_build_object(
    'security_control_contract','B2B_LOGIN_SECURITY_BASELINE_V1',
    'implementation_status','PENDING_IMPLEMENTATION_QA',
    'production_authorized',false,
    'backend_runtime','SPRING_BOOT_CORE',
    'edge_runtime',jsonb_build_array('CLOUDFRONT_WAF','ALB_WAF'),
    'ddos_control','WAF_RATE_AND_RESOURCE_EXHAUSTION_GUARD_REQUIRED',
    'resource_exhaustion','DENY_UNBOUNDED_REQUEST_PROCESSING',
    'server_input_injection','DENY',
    'parameterized_query','REQUIRED',
    'prepared_statement','REQUIRED',
    'xss','DENY_UNTRUSTED_SCRIPT_EXECUTION',
    'content-security-policy','REQUIRED',
    'output_encoding','CONTEXT_AWARE_REQUIRED',
    'ssrf','DENY_USER_CONTROLLED_BACKEND_FETCH_TARGETS',
    'user_controlled_backend_fetch_target','DENY',
    'clickjacking','DENY',
    'frame-ancestors','DENY_EMBEDDING',
    'x-frame-options','DENY',
    'cors','EXPLICIT_ORIGIN_POLICY_REQUIRED',
    'allowed_origin','SAME_ORIGIN_OR_EXPLICIT_ALLOWLIST_ONLY',
    'transport','HTTPS_REQUIRED',
    'strict-transport-security','REQUIRED',
    'x-content-type-options','nosniff',
    'replay_protection','REQUIRED',
    'anti_replay','REQUIRED_FOR_SESSION_OR_TOKEN_REUSE_PATHS',
    'supply_chain','SBOM_AND_DEPENDENCY_VULNERABILITY_CONTROL_REQUIRED',
    'sbom','REQUIRED',
    'dependency_vulnerability_scan','REQUIRED',
    'request_body_limit','REQUIRED',
    'max_payload_source','EDGE_AND_BACKEND_RUNTIME_CONFIG',
    'numeric_thresholds_in_rule','DENY',
    'source_authority','SUPABASE_GOVERNED_CANONICAL_RULE'
  ),
  false,
  'CANDIDATO',
  'LF_INPUT_GOV_B2B_AUTH_CRITICAL_READINESS_V1',
  false,
  null,
  'INPUT_GOVERNANCE_REMEDIATION'
)
on conflict (codigo) do update
set categoria=excluded.categoria,
    titulo=excluded.titulo,
    descripcion=excluded.descripcion,
    razon=excluded.razon,
    valor_config=excluded.valor_config,
    es_transversal=excluded.es_transversal,
    estado=case
      when lf_ops.reglas.estado='CANDIDATO' then excluded.estado
      else lf_ops.reglas.estado
    end,
    origen=excluded.origen,
    pendiente_decision=false,
    pendiente_detalle=null,
    updated_at=now();

insert into lf_ops.reglas_pantallas(regla_id,pantalla_id,nota)
select r.id,51,'Baseline técnico SECURITY para Input Governance B2B-AUTH-001.'
from lf_ops.reglas r
where r.codigo='B2B-RULE-SECURITY-BASELINE-001'
  and not exists(
    select 1
    from lf_ops.reglas_pantallas rp
    where rp.regla_id=r.id and rp.pantalla_id=51
  );

-- Reconcile the existing unique AUTH_LOGIN_API timeout policy.
update lf_ops.politicas_timeout
set status='CANDIDATO',
    source_decision_id='DEC-B2B-HANDOFF-SCREEN-PACKAGE-001',
    source_decision_number=52,
    updated_at=now()
where timeout_policy_id=10
  and operation_code='AUTH_LOGIN_API'
  and status in ('ARCHIVADO','CANDIDATO');

update lf_ops.reglas
set valor_config=
      (coalesce(valor_config,'{}'::jsonb)
        - 'application_repository'
        - 'application_head_observed')
      || jsonb_build_object(
        'timeout_policy_id',10,
        'timeout_registry','lf_ops.politicas_timeout',
        'policy_assignment_status','CANDIDATE_POLICY_BOUND_IMPLEMENTATION_QA_PENDING',
        'implementation_status','PENDING_IMPLEMENTATION_QA',
        'source_authority','SUPABASE_GOVERNED_CANONICAL_POLICY'
      ),
    updated_at=now()
where codigo='B2B-RULE-AUTH-016';

-- Add lifecycle-aware SECURITY and TIMEOUT_RETRY semantic handling to both
-- normal and cached v3 probes.
do $patch$
declare
  r record;
  v_def text;
  v_anchor text := $$  if p_family_code='RATE_LIMIT' then$$;
  v_insert text :=
$$  if p_family_code='SECURITY' and v_screen_code like 'B2B-%' then
    select
      count(*),
      count(*) filter(where r.estado='CANDIDATO'),
      count(*) filter(
        where coalesce(r.valor_config->>'implementation_status','') ~* '(PENDING|NOT_READY|BLOCKED)'
      )
    into v_rule_count,v_candidate_count,v_missing_source_count
    from lf_ops.reglas_pantallas rp
    join lf_ops.reglas r on r.id=rp.regla_id
    where rp.pantalla_id=p_pantalla_id
      and r.codigo='B2B-RULE-SECURITY-BASELINE-001'
      and r.estado<>'DEPRECADO';

    select count(*) into v_broken_ref_count
    from jsonb_array_elements(programacion.fn_input_security_threat_expected(p_pantalla_id)) t
    where t->>'status' not in ('COMPLETE','NOT_APPLICABLE');

    select count(*) into v_unresolved_count_b2b
    from jsonb_array_elements(programacion.fn_input_subject_depth_expected(p_pantalla_id,'SECURITY')) s
    where s->>'status'<>'COMPLETE';

    if v_rule_count>0
       and v_broken_ref_count=0
       and v_unresolved_count_b2b=0 then
      return jsonb_build_object(
        'handled',true,
        'family_code',p_family_code,
        'level','COMPLETE',
        'severity',case
          when v_candidate_count>0 or v_missing_source_count>0 then 'P1'
          else 'P4'
        end,
        'blocker_code',case
          when v_candidate_count>0 or v_missing_source_count>0
            then 'SECURITY_BASELINE_IMPLEMENTATION_PENDING'
          else null
        end,
        'stage_statuses',jsonb_build_object(
          'story','READY',
          'implementation',case
            when v_candidate_count>0 or v_missing_source_count>0 then 'NOT_READY'
            else 'READY'
          end,
          'qa',case
            when v_candidate_count>0 or v_missing_source_count>0 then 'BLOCKED'
            else 'READY'
          end,
          'production',case
            when v_candidate_count>0 or v_missing_source_count>0 then 'BLOCKED'
            else 'READY'
          end
        ),
        'stage_blockers',case
          when v_candidate_count>0 or v_missing_source_count>0 then
            jsonb_build_array(jsonb_build_object(
              'code','SECURITY_BASELINE_IMPLEMENTATION_PENDING',
              'earliest_blocking_stage','IMPLEMENTATION'
            ))
          else '[]'::jsonb
        end,
        'probe',jsonb_build_object(
          'resolution_contract','B2B_SECURITY_BASELINE_RESOLUTION_V1',
          'baseline_rule_count',v_rule_count,
          'candidate_baseline_rule_count',v_candidate_count,
          'implementation_pending_count',v_missing_source_count,
          'threat_incomplete_count',v_broken_ref_count,
          'subject_incomplete_count',v_unresolved_count_b2b
        )
      );
    end if;

    return v_base;
  end if;

  if p_family_code='TIMEOUT_RETRY' and v_screen_code like 'B2B-%' then
    with timeout_rules as (
      select r.*
      from lf_ops.reglas_pantallas rp
      join lf_ops.reglas r on r.id=rp.regla_id
      where rp.pantalla_id=p_pantalla_id
        and r.codigo='B2B-RULE-AUTH-016'
        and r.estado<>'DEPRECADO'
    ), resolved as (
      select
        r.id as rule_id,
        r.estado as rule_status,
        r.valor_config,
        p.timeout_policy_id,
        p.policy_code,
        p.operation_code,
        p.retry_limit,
        p.backoff_strategy,
        p.status as policy_status
      from timeout_rules r
      left join lf_ops.politicas_timeout p
        on coalesce(r.valor_config->>'timeout_policy_id','') ~ '^[0-9]+$'
       and p.timeout_policy_id=(r.valor_config->>'timeout_policy_id')::bigint
    )
    select
      count(*),
      count(*) filter(where rule_status='CANDIDATO'),
      count(*) filter(where timeout_policy_id is null),
      count(*) filter(where policy_status='CANDIDATO'),
      count(*) filter(
        where coalesce(valor_config->>'implementation_status','') ~* '(PENDING|NOT_READY|BLOCKED)'
           or coalesce(valor_config->>'policy_assignment_status','') ~* '(PENDING|NOT_READY|BLOCKED)'
      ),
      count(*) filter(
        where timeout_policy_id is not null
          and operation_code='AUTH_LOGIN_API'
          and retry_limit=0
          and backoff_strategy='NONE'
          and coalesce(valor_config->>'auth_automatic_retry','')='DENY'
          and coalesce(valor_config->>'session_on_timeout','')='DENY'
      )
    into
      v_rule_count,
      v_candidate_count,
      v_broken_ref_count,
      v_unresolved_count_b2b,
      v_missing_source_count,
      v_story_source_count
    from resolved;

    if v_rule_count>0
       and v_broken_ref_count=0
       and v_story_source_count=v_rule_count then
      return jsonb_build_object(
        'handled',true,
        'family_code',p_family_code,
        'level','COMPLETE',
        'severity',case
          when v_candidate_count>0 or v_unresolved_count_b2b>0 or v_missing_source_count>0 then 'P1'
          else 'P4'
        end,
        'blocker_code',case
          when v_candidate_count>0 or v_unresolved_count_b2b>0 or v_missing_source_count>0
            then 'TIMEOUT_POLICY_CANDIDATE_NOT_IMPLEMENTATION_READY'
          else null
        end,
        'stage_statuses',jsonb_build_object(
          'story','READY',
          'implementation',case
            when v_candidate_count>0 or v_unresolved_count_b2b>0 or v_missing_source_count>0
              then 'NOT_READY' else 'READY' end,
          'qa',case
            when v_candidate_count>0 or v_unresolved_count_b2b>0 or v_missing_source_count>0
              then 'BLOCKED' else 'READY' end,
          'production',case
            when v_candidate_count>0 or v_unresolved_count_b2b>0 or v_missing_source_count>0
              then 'BLOCKED' else 'READY' end
        ),
        'stage_blockers',case
          when v_candidate_count>0 or v_unresolved_count_b2b>0 or v_missing_source_count>0 then
            jsonb_build_array(jsonb_build_object(
              'code','TIMEOUT_POLICY_CANDIDATE_NOT_IMPLEMENTATION_READY',
              'earliest_blocking_stage','IMPLEMENTATION'
            ))
          else '[]'::jsonb
        end,
        'probe',jsonb_build_object(
          'resolution_contract','B2B_AUTH_TIMEOUT_POLICY_RESOLUTION_V2',
          'auth_timeout_rule_count',v_rule_count,
          'candidate_rule_count',v_candidate_count,
          'missing_policy_reference_count',v_broken_ref_count,
          'candidate_policy_count',v_unresolved_count_b2b,
          'implementation_pending_count',v_missing_source_count,
          'fail_closed_policy_match_count',v_story_source_count,
          'automatic_retry','DENY'
        )
      );
    end if;

    if v_rule_count>0 then
      return jsonb_build_object(
        'handled',true,
        'family_code',p_family_code,
        'level','PARTIAL',
        'severity','P1',
        'blocker_code','TIMEOUT_POLICY_REFERENCE_OR_FAIL_CLOSED_CONTRACT_INCOMPLETE',
        'stage_statuses',jsonb_build_object(
          'story','READY','implementation','NOT_READY','qa','BLOCKED','production','BLOCKED'
        ),
        'stage_blockers',jsonb_build_array(jsonb_build_object(
          'code','TIMEOUT_POLICY_REFERENCE_OR_FAIL_CLOSED_CONTRACT_INCOMPLETE',
          'earliest_blocking_stage','IMPLEMENTATION'
        )),
        'probe',jsonb_build_object(
          'resolution_contract','B2B_AUTH_TIMEOUT_POLICY_RESOLUTION_V2',
          'auth_timeout_rule_count',v_rule_count,
          'missing_policy_reference_count',v_broken_ref_count,
          'fail_closed_policy_match_count',v_story_source_count
        )
      );
    end if;

    return v_base;
  end if;

  if p_family_code='RATE_LIMIT' then$$;
begin
  for r in
    select sig
    from (
      values
        ('programacion.fn_input_governance_semantic_probe_v3(integer,text,bigint)'),
        ('programacion.fn_input_governance_semantic_probe_v3_cached_v1(integer,text,bigint,jsonb)')
    ) x(sig)
  loop
    select pg_get_functiondef(to_regprocedure(r.sig)) into v_def;

    if v_def is null then
      raise exception 'B2B_CRITICAL_READINESS_SEMANTIC_FUNCTION_MISSING:%',r.sig;
    end if;

    if position('B2B_SECURITY_BASELINE_RESOLUTION_V1' in v_def)=0 then
      if position(v_anchor in v_def)=0 then
        raise exception 'B2B_CRITICAL_READINESS_SEMANTIC_SOURCE_DRIFT:%',r.sig;
      end if;
      v_def:=replace(v_def,v_anchor,v_insert);
      execute v_def;
    end if;
  end loop;
end;
$patch$;

do $postconditions$
declare
  v_bad_threats integer;
  v_security jsonb;
  v_timeout jsonb;
  v_policy_status text;
  v_rule_policy_id text;
begin
  select count(*) into v_bad_threats
  from jsonb_array_elements(programacion.fn_input_security_threat_expected(51)) t
  where t->>'status' not in ('COMPLETE','NOT_APPLICABLE');

  if v_bad_threats<>0 then
    raise exception 'SECURITY_THREAT_COVERAGE_POSTCONDITION_FAILED:%',v_bad_threats;
  end if;

  v_security:=programacion.fn_input_governance_bootstrap_classify_v2(51,'SECURITY',19);
  if v_security->>'coverage_status'<>'COMPLETE'
     or v_security->>'well_defined_status'<>'COMPLETE'
     or v_security->>'story_ready_status'<>'READY'
     or v_security->>'implementation_ready_status'<>'NOT_READY'
     or v_security->'blockers'->0->>'code'<>'SECURITY_BASELINE_IMPLEMENTATION_PENDING'
     or v_security#>>'{probe,resolution_contract}'<>'B2B_SECURITY_BASELINE_RESOLUTION_V1' then
    raise exception 'SECURITY_CLASSIFIER_POSTCONDITION_FAILED:%',v_security;
  end if;

  select status into v_policy_status
  from lf_ops.politicas_timeout
  where timeout_policy_id=10 and operation_code='AUTH_LOGIN_API';

  if v_policy_status<>'CANDIDATO' then
    raise exception 'AUTH_LOGIN_TIMEOUT_POLICY_STATUS_POSTCONDITION_FAILED:%',v_policy_status;
  end if;

  select valor_config->>'timeout_policy_id' into v_rule_policy_id
  from lf_ops.reglas
  where codigo='B2B-RULE-AUTH-016';

  if v_rule_policy_id<>'10' then
    raise exception 'AUTH_016_TIMEOUT_BINDING_POSTCONDITION_FAILED:%',v_rule_policy_id;
  end if;

  v_timeout:=programacion.fn_input_governance_bootstrap_classify_v2(51,'TIMEOUT_RETRY',19);
  if v_timeout->>'coverage_status'<>'COMPLETE'
     or v_timeout->>'well_defined_status'<>'COMPLETE'
     or v_timeout->>'story_ready_status'<>'READY'
     or v_timeout->>'implementation_ready_status'<>'NOT_READY'
     or v_timeout->'blockers'->0->>'code'<>'TIMEOUT_POLICY_CANDIDATE_NOT_IMPLEMENTATION_READY'
     or v_timeout#>>'{probe,resolution_contract}'<>'B2B_AUTH_TIMEOUT_POLICY_RESOLUTION_V2' then
    raise exception 'TIMEOUT_CLASSIFIER_POSTCONDITION_FAILED:%',v_timeout;
  end if;
end;
$postconditions$;

commit;

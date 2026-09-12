-- INPUT GOVERNANCE 5.12: semantic coherence, positive N/A authority, proposal separation, EKB recurrence hardening

update programacion.contratos
set especificacion = jsonb_set(
    jsonb_set(
      jsonb_set(
        jsonb_set(
          jsonb_set(
            jsonb_set(
              especificacion,
              '{contract_revision}', '"5.12"'::jsonb, true
            ),
            '{remediation_revision}', '"V512_SEMANTIC_COHERENCE_PROPOSAL_SEPARATION_20260822"'::jsonb, true
          ),
          '{semantic_coherence_contract}',
          '{"validator_pass_requires_candidate_source_compatibility":true,"positive_requirement_forbids_coverage_missing":true,"positive_requirement_forbids_not_applicable":true,"false_missing_blocker_forbidden":true,"direct_source_readback_required":true}'::jsonb,
          true
        ),
        '{not_applicable_positive_authority_contract}',
        '{"absence_only_authority":"DENY","empty_collection_authority":"DENY","explicit_semantic_exclusion_required":true,"unresolved_when_no_positive_exclusion":true}'::jsonb,
        true
      ),
      '{proposal_contract}',
      '{"curator_role":"PROPOSE","validator_role":"INDEPENDENT_VERIFY","proposal_is_canonical_source":false,"auto_promotion":"DENY","evidence_required_for_research_or_best_practice":true,"stale_source_requires_revalidation":true,"allowed_kinds":["RESEARCH_EVIDENCED_PROPOSAL","BEST_PRACTICE_PROPOSAL","HUMAN_DECISION_REQUIRED","RESEARCH_REQUIRED","SOURCE_INCOMPLETE","SOURCE_CONFLICT"]}'::jsonb,
      true
    ),
    '{negative_tests}',
    (especificacion->'negative_tests') || '["POSITIVE_RULE_ASSERTION_WITH_COVERAGE_MISSING","POSITIVE_RULE_ASSERTION_WITH_FALSE_MISSING_BLOCKER","NA_WITH_CAPABILITY_ABSENCE_PLUS_EMPTY_RULE_SET","NA_WITH_EMPTY_STATE_SET","NA_WITH_EXPLICIT_AUTH_EXCLUSION_ACCEPTED","OTP_SOURCE_EXISTS_BUT_MFA_OTP_SSO_NA","PROPOSAL_WITHOUT_REQUIRED_EVIDENCE","PROPOSAL_USED_AS_CANONICAL_SOURCE","CURATOR_SELF_VALIDATES_PROPOSAL","PROPOSAL_STALE_SOURCE_WITHOUT_REVALIDATION","RESEARCH_PROPOSAL_SILENTLY_PROMOTED","CANONICAL_VALUE_ORIGINATES_ONLY_FROM_PROPOSAL"]'::jsonb,
    true
  ) || jsonb_build_object(
    'canon_vs_proposal_separation', jsonb_build_object(
      'proposal_registry','programacion.input_gap_proposals',
      'proposal_source_ref_allowed',false,
      'canonical_write_from_proposal','EXPLICIT_SEPARATE_GOVERNED_ACTION_REQUIRED',
      'automatic_canonicalization','DENY'
    )
  )
where version_id=19 and contrato_codigo='INPUT_READINESS_CONTRACT';

create or replace function programacion.fn_input_na_positive_authority_v512(
  p_family_code text,
  p_pantalla_id integer,
  p_version_id bigint
) returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','programacion'
as $function$
declare
  v_graph jsonb;
  v_rules jsonb;
  v_screen_permissions jsonb;
  v_profile_permissions jsonb;
  v_rule jsonb;
  v_codes jsonb := '[]'::jsonb;
  v_qualified boolean := false;
begin
  v_graph := programacion.fn_input_screen_canonical_graph(p_pantalla_id,p_version_id);
  v_rules := coalesce(v_graph->'canonical_contract'->'rules','[]'::jsonb);
  v_screen_permissions := coalesce(v_graph->'screen_permissions','[]'::jsonb);
  v_profile_permissions := coalesce(v_graph->'profile_permissions','[]'::jsonb);

  if p_family_code='SESSION' then
    for v_rule in select value from jsonb_array_elements(v_rules)
    loop
      if coalesce(v_rule->'config'->>'operational_session_creation','')='DENY' then
        v_qualified := true;
        v_codes := v_codes || jsonb_build_array(v_rule->>'rule_code');
      end if;
    end loop;
  elsif p_family_code='PERMISSIONS'
        and jsonb_array_length(v_screen_permissions)=0
        and jsonb_array_length(v_profile_permissions)=0 then
    for v_rule in select value from jsonb_array_elements(v_rules)
    loop
      if coalesce(v_rule->>'transversal','true')::boolean is false
         and (
           coalesce(v_rule->'config'->>'operational_access_grant','')='DENY'
           or coalesce(v_rule->'config'->>'operational_authorization_before_completion','')='DENY'
           or coalesce(v_rule->'config'->>'mfa_route_full_operational_session_required','')='false'
         ) then
        v_qualified := true;
        v_codes := v_codes || jsonb_build_array(v_rule->>'rule_code');
      end if;
    end loop;
  end if;

  return jsonb_build_object(
    'qualified',v_qualified,
    'family_code',p_family_code,
    'pantalla_id',p_pantalla_id,
    'authority_kind',case when v_qualified then 'EXPLICIT_CANONICAL_EXCLUSION' else 'NO_POSITIVE_EXCLUSION' end,
    'rule_codes',v_codes,
    'screen_permission_count',jsonb_array_length(v_screen_permissions),
    'profile_permission_count',jsonb_array_length(v_profile_permissions)
  );
end;
$function$;
revoke all on function programacion.fn_input_na_positive_authority_v512(text,integer,bigint) from public;
grant execute on function programacion.fn_input_na_positive_authority_v512(text,integer,bigint) to postgres;

create or replace function programacion.fn_guard_input_na_positive_authority_v512()
returns trigger
language plpgsql
security definer
set search_path='pg_catalog','programacion'
as $function$
declare
  v_revision text;
  v_version_id bigint;
  v_pantalla_id integer;
  v_authority jsonb;
begin
  select contract_revision,version_id,pantalla_id
    into v_revision,v_version_id,v_pantalla_id
  from programacion.input_readiness_runs where id=new.run_id;
  if v_revision is distinct from '5.12' or new.applicability<>'NOT_APPLICABLE' then
    return new;
  end if;
  v_authority := programacion.fn_input_na_positive_authority_v512(new.family_code,v_pantalla_id,v_version_id);
  if coalesce((v_authority->>'qualified')::boolean,false) is not true then
    raise exception 'V512_NOT_APPLICABLE_REQUIRES_EXPLICIT_SEMANTIC_EXCLUSION:%:%',v_pantalla_id,new.family_code;
  end if;
  return new;
end;
$function$;
revoke all on function programacion.fn_guard_input_na_positive_authority_v512() from public;
grant execute on function programacion.fn_guard_input_na_positive_authority_v512() to postgres;

drop trigger if exists trg_input_family_assessment_00b_na_authority_insert on programacion.input_family_assessments;
create trigger trg_input_family_assessment_00b_na_authority_insert
before insert on programacion.input_family_assessments
for each row execute function programacion.fn_guard_input_na_positive_authority_v512();

create or replace function programacion.fn_guard_input_validator_semantic_coherence_v512()
returns trigger
language plpgsql
security definer
set search_path='pg_catalog','programacion'
as $function$
declare
  v_revision text;
  v_version_id bigint;
  v_pantalla_id integer;
  v_assertion jsonb;
  v_eval jsonb;
  v_positive_requirement boolean := false;
  v_na_authority jsonb;
  v_blocker jsonb;
  v_false_missing boolean := false;
  v_graph jsonb;
  v_rules jsonb;
  v_otp_present boolean := false;
begin
  if old.validator_outcome<>'PENDING' or new.validator_outcome='PENDING' then
    return new;
  end if;
  select contract_revision,version_id,pantalla_id
    into v_revision,v_version_id,v_pantalla_id
  from programacion.input_readiness_runs where id=old.run_id;
  if v_revision is distinct from '5.12' then return new; end if;

  if jsonb_typeof(new.validator_evidence->'assertions')='array' then
    for v_assertion in select value from jsonb_array_elements(new.validator_evidence->'assertions')
    loop
      if coalesce(v_assertion->>'operator','')='CONTAINS'
         and jsonb_typeof(v_assertion->'expected')='array'
         and jsonb_array_length(v_assertion->'expected')>0
         and coalesce(v_assertion->'source_ref'->>'kind','') in ('SCREEN_CANONICAL_GRAPH','SCREEN_RULE_SET','RULE','SECURITY_POLICY_SET','SCREEN_STATE_SET') then
        v_eval := programacion.fn_input_evaluate_assertion(old.run_id,old.family_code,v_assertion);
        if coalesce((v_eval->>'passed')::boolean,false) is true then
          v_positive_requirement := true;
        end if;
      end if;
    end loop;
  end if;

  if new.validator_outcome='PASS' and v_positive_requirement and old.coverage_status='MISSING' then
    raise exception 'V512_VALIDATOR_SOURCE_CANDIDATE_CONTRADICTION_POSITIVE_REQUIREMENT_WITH_MISSING:%:%',v_pantalla_id,old.family_code;
  end if;

  if new.validator_outcome='PASS' and old.applicability='NOT_APPLICABLE' then
    v_na_authority := programacion.fn_input_na_positive_authority_v512(old.family_code,v_pantalla_id,v_version_id);
    if coalesce((v_na_authority->>'qualified')::boolean,false) is not true then
      raise exception 'V512_VALIDATOR_NA_WITHOUT_POSITIVE_EXCLUSION:%:%',v_pantalla_id,old.family_code;
    end if;
  end if;

  if new.validator_outcome='PASS' and v_positive_requirement then
    for v_blocker in select value from jsonb_array_elements(coalesce(old.blockers,'[]'::jsonb))
    loop
      if (old.family_code='REDUCED_MOTION' and v_blocker->>'code'='REDUCED_MOTION_REQUIREMENT_MISSING')
         or (old.family_code='FORCED_COLORS_CONTRAST' and v_blocker->>'code'='FORCED_COLORS_REQUIREMENT_MISSING')
         or (old.family_code='THEME_LIGHT_DARK_SYSTEM' and v_blocker->>'code'='THEME_REQUIREMENTS_NOT_LINKED') then
        v_false_missing := true;
      end if;
    end loop;
    if v_false_missing then
      raise exception 'V512_VALIDATOR_FALSE_MISSING_BLOCKER_CONTRADICTS_SOURCE:%:%',v_pantalla_id,old.family_code;
    end if;
  end if;

  if new.validator_outcome='PASS' and old.family_code='MFA_OTP_SSO' then
    v_graph := programacion.fn_input_screen_canonical_graph(v_pantalla_id,v_version_id);
    v_rules := coalesce(v_graph->'canonical_contract'->'rules','[]'::jsonb);
    select exists(
      select 1 from jsonb_array_elements(v_rules) r
      where (r->'config' ? 'otp_operation_id')
         or (r->'config' ? 'otp_policy_id')
         or (r->'config' ? 'email_otp_policy_code')
    ) into v_otp_present;
    if v_otp_present and old.applicability='NOT_APPLICABLE' then
      raise exception 'V512_VALIDATOR_OTP_PRESENT_BUT_FAMILY_NOT_APPLICABLE:%',v_pantalla_id;
    end if;
  end if;
  return new;
end;
$function$;
revoke all on function programacion.fn_guard_input_validator_semantic_coherence_v512() from public;
grant execute on function programacion.fn_guard_input_validator_semantic_coherence_v512() to postgres;

drop trigger if exists trg_input_family_assessment_00b_semantic_coherence_update on programacion.input_family_assessments;
create trigger trg_input_family_assessment_00b_semantic_coherence_update
before update on programacion.input_family_assessments
for each row execute function programacion.fn_guard_input_validator_semantic_coherence_v512();

create or replace function programacion.fn_input_v512_assertion_template(
  p_pantalla_id integer,
  p_family_code text,
  p_assertion jsonb
) returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','programacion'
as $function$
declare
  v jsonb;
begin
  v := programacion.fn_input_v58_assertion_template(p_pantalla_id,p_family_code,p_assertion);

  if p_family_code='MFA_OTP_SSO' and p_pantalla_id=52 then
    v := jsonb_build_object(
      'source_ref',jsonb_build_object('kind','SCREEN_CANONICAL_GRAPH','pantalla_id',52),
      'path',jsonb_build_array('observed','canonical_contract','rules'),
      'operator','CONTAINS',
      'expected','[{"rule_code":"B2B-RULE-AUTH-028","config":{"otp_policy_id":2,"otp_operation_id":5,"success_context_scope":"PASSWORD_RECOVERY_CHALLENGE_ONLY","authentication_completion":"DENY","operational_session_creation":"DENY"}}]'::jsonb
    );
  elsif p_family_code='PERMISSIONS' and p_pantalla_id=52 then
    v := jsonb_build_object(
      'source_ref',jsonb_build_object('kind','SCREEN_CANONICAL_GRAPH','pantalla_id',52),
      'path',jsonb_build_array('observed','canonical_contract','rules'),
      'operator','CONTAINS',
      'expected','[{"rule_code":"B2B-RULE-AUTH-028","config":{"operational_access_grant":"DENY","authentication_completion":"DENY","operational_session_creation":"DENY"}}]'::jsonb
    );
  elsif p_family_code='PERMISSIONS' and p_pantalla_id=53 then
    v := jsonb_build_object(
      'source_ref',jsonb_build_object('kind','SCREEN_CANONICAL_GRAPH','pantalla_id',53),
      'path',jsonb_build_array('observed','canonical_contract','rules'),
      'operator','CONTAINS',
      'expected','[{"rule_code":"B2B-RULE-AUTH-029","config":{"recovery_context_scope":"PASSWORD_UPDATE_ONLY","operational_authorization_before_completion":"DENY"}}]'::jsonb
    );
  elsif p_family_code='PERMISSIONS' and p_pantalla_id=54 then
    v := jsonb_build_object(
      'source_ref',jsonb_build_object('kind','SCREEN_CANONICAL_GRAPH','pantalla_id',54),
      'path',jsonb_build_array('observed','canonical_contract','rules'),
      'operator','CONTAINS',
      'expected','[{"rule_code":"B2B-RULE-AUTH-033","config":{"mfa_route_full_operational_session_required":false,"mfa_route_direct_navigation_without_challenge":"DENY"}}]'::jsonb
    );
  elsif p_family_code='PERMISSIONS' and p_pantalla_id=56 then
    v := jsonb_build_object(
      'source_ref',jsonb_build_object('kind','SCREEN_CANONICAL_GRAPH','pantalla_id',56),
      'path',jsonb_build_array('observed','canonical_contract','rules'),
      'operator','CONTAINS',
      'expected','[{"rule_code":"B2B-RULE-AUTH-029","config":{"recovery_context_scope":"PASSWORD_UPDATE_ONLY","operational_authorization_before_completion":"DENY"}},{"rule_code":"B2B-RULE-AUTH-037","config":{"mfa_satisfaction":"DENY","operational_session_creation":"DENY"}}]'::jsonb
    );
  end if;
  return v - 'actual' - 'result' - 'source_observed_sha256';
end;
$function$;
revoke all on function programacion.fn_input_v512_assertion_template(integer,text,jsonb) from public;
grant execute on function programacion.fn_input_v512_assertion_template(integer,text,jsonb) to postgres;

create or replace function programacion.fn_input_v58_build_assertions(p_new_run_id bigint, p_parent_run_id bigint, p_family_code text)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','programacion'
as $function$
declare
  v_pantalla_id integer;
  v_old jsonb;
  v_tpl jsonb;
  v_rebound jsonb;
  v_out jsonb := '[]'::jsonb;
begin
  select pantalla_id into v_pantalla_id
  from programacion.input_readiness_runs where id=p_new_run_id;
  if v_pantalla_id is null then raise exception 'V58_ASSERTION_NEW_RUN_NOT_FOUND:%',p_new_run_id; end if;

  for v_old in
    select x.value
    from programacion.input_family_assessments a
    cross join lateral jsonb_array_elements(a.validator_evidence->'assertions') x(value)
    where a.run_id=p_parent_run_id and a.family_code=p_family_code
  loop
    if v_pantalla_id=51 and p_family_code='VISUAL_EVIDENCE'
       and v_old->'source_ref'->>'kind'='CURRENT_VISUAL_ARTIFACT' then
      v_tpl:=jsonb_build_object(
        'source_ref',jsonb_build_object('kind','CURRENT_VISUAL_ARTIFACT','pantalla_id',51),
        'path',jsonb_build_array('observed'),'operator','CONTAINS',
        'expected',jsonb_build_array(
          jsonb_build_object('artifact',jsonb_build_object('pantalla_id',51,'is_current',true,'status','CANDIDATO_VISUAL','storage_provider','GOOGLE_DRIVE','storage_metadata',jsonb_build_object('variant_code','B2B-AUTH-001-DESKTOP-LIGHT','canonical_canvas',true))),
          jsonb_build_object('artifact',jsonb_build_object('pantalla_id',51,'is_current',true,'status','CANDIDATO_VISUAL','storage_provider','GOOGLE_DRIVE','storage_metadata',jsonb_build_object('variant_code','B2B-AUTH-001-TABLET-LIGHT','canonical_canvas',true))),
          jsonb_build_object('artifact',jsonb_build_object('pantalla_id',51,'is_current',true,'status','CANDIDATO_VISUAL','storage_provider','GOOGLE_DRIVE','storage_metadata',jsonb_build_object('variant_code','B2B-AUTH-001-MOBILE-LIGHT','canonical_canvas',true)))
        )
      );
    else
      v_tpl:=programacion.fn_input_v512_assertion_template(v_pantalla_id,p_family_code,v_old);
    end if;
    v_rebound:=programacion.fn_input_rebind_assertion(p_new_run_id,p_family_code,v_tpl);
    if v_rebound->>'result'<>'PASS' then
      raise exception 'V58_REBOUND_ASSERTION_FAILED screen=% family=% source=% path=%',v_pantalla_id,p_family_code,v_rebound->'source_ref',v_rebound->'path';
    end if;
    v_out:=v_out || jsonb_build_array(v_rebound);
  end loop;

  if jsonb_array_length(v_out)=0 then raise exception 'V58_ASSERTION_SET_EMPTY:%:%',v_pantalla_id,p_family_code; end if;
  return v_out;
end;
$function$;
revoke all on function programacion.fn_input_v58_build_assertions(bigint,bigint,text) from public;
grant execute on function programacion.fn_input_v58_build_assertions(bigint,bigint,text) to postgres;

create table if not exists programacion.input_gap_proposals (
  id bigint generated by default as identity primary key,
  run_id bigint not null references programacion.input_readiness_runs(id),
  assessment_id bigint not null references programacion.input_family_assessments(id),
  family_code text not null,
  gap_code text not null,
  proposal_kind text not null check (proposal_kind in ('RESEARCH_EVIDENCED_PROPOSAL','BEST_PRACTICE_PROPOSAL','HUMAN_DECISION_REQUIRED','RESEARCH_REQUIRED','SOURCE_INCOMPLETE','SOURCE_CONFLICT')),
  proposed_payload jsonb not null check (jsonb_typeof(proposed_payload)='object' and proposed_payload<>'{}'::jsonb),
  canonical_target jsonb not null default '{}'::jsonb check (jsonb_typeof(canonical_target)='object'),
  source_refs jsonb not null default '[]'::jsonb check (jsonb_typeof(source_refs)='array'),
  evidence_refs jsonb not null default '[]'::jsonb check (jsonb_typeof(evidence_refs)='array'),
  confidence numeric(5,4) check (confidence is null or (confidence>=0 and confidence<=1)),
  stage_impact jsonb not null default '{}'::jsonb check (jsonb_typeof(stage_impact)='object'),
  contradictions_checked jsonb not null default '[]'::jsonb check (jsonb_typeof(contradictions_checked)='array'),
  status text not null default 'PROPOSED' check (status in ('PROPOSED','VALIDATED','REJECTED','HUMAN_DECISION_REQUIRED')),
  curator_identity text not null,
  curator_execution_id text not null,
  curator_sha256 text not null,
  validator_identity text,
  validator_outcome text not null default 'PENDING' check (validator_outcome in ('PENDING','PASS','FAIL')),
  validator_evidence jsonb not null default '{}'::jsonb check (jsonb_typeof(validator_evidence)='object'),
  validator_sha256 text,
  created_at timestamptz not null default now(),
  validated_at timestamptz,
  unique(run_id,family_code,gap_code)
);
create index if not exists idx_input_gap_proposals_run on programacion.input_gap_proposals(run_id);
create index if not exists idx_input_gap_proposals_status on programacion.input_gap_proposals(status,validator_outcome);
revoke all on programacion.input_gap_proposals from public, anon, authenticated;
grant select,insert,update on programacion.input_gap_proposals to postgres;

create or replace function programacion.fn_guard_input_gap_proposal_insert_v512()
returns trigger
language plpgsql
security definer
set search_path='pg_catalog','programacion'
as $function$
declare
  v_run record;
  v_assessment record;
  v_payload jsonb;
begin
  select * into v_run from programacion.input_readiness_runs where id=new.run_id;
  if not found then raise exception 'V512_PROPOSAL_RUN_NOT_FOUND:%',new.run_id; end if;
  if v_run.status<>'CURATING' then raise exception 'V512_PROPOSAL_REQUIRES_CURATING_RUN:%',new.run_id; end if;
  select id,run_id,family_code into v_assessment from programacion.input_family_assessments where id=new.assessment_id;
  if not found or v_assessment.run_id<>new.run_id or v_assessment.family_code<>new.family_code then
    raise exception 'V512_PROPOSAL_ASSESSMENT_SCOPE_MISMATCH:%',new.family_code;
  end if;
  if new.curator_identity is distinct from v_run.curator_identity then
    raise exception 'V512_PROPOSAL_CURATOR_IDENTITY_MISMATCH:%',new.family_code;
  end if;
  if jsonb_array_length(new.source_refs)=0 then raise exception 'V512_PROPOSAL_SOURCE_REFS_REQUIRED:%',new.family_code; end if;
  if new.proposal_kind in ('RESEARCH_EVIDENCED_PROPOSAL','BEST_PRACTICE_PROPOSAL') and jsonb_array_length(new.evidence_refs)=0 then
    raise exception 'V512_PROPOSAL_EVIDENCE_REQUIRED:%',new.family_code;
  end if;
  if exists(select 1 from jsonb_array_elements(new.source_refs) s where coalesce(s->>'kind','')='INPUT_GAP_PROPOSAL') then
    raise exception 'V512_PROPOSAL_CANNOT_USE_PROPOSAL_AS_CANONICAL_SOURCE:%',new.family_code;
  end if;
  new.validator_outcome:='PENDING'; new.validator_identity:=null; new.validator_sha256:=null; new.validated_at:=null;
  v_payload:=jsonb_build_object('run_id',new.run_id,'assessment_id',new.assessment_id,'family_code',new.family_code,'gap_code',new.gap_code,'proposal_kind',new.proposal_kind,'proposed_payload',new.proposed_payload,'canonical_target',new.canonical_target,'source_refs',new.source_refs,'evidence_refs',new.evidence_refs,'confidence',new.confidence,'stage_impact',new.stage_impact,'contradictions_checked',new.contradictions_checked,'status',new.status,'curator_identity',new.curator_identity,'curator_execution_id',new.curator_execution_id);
  new.curator_sha256:=programacion.fn_v09_sha256_jsonb(v_payload);
  return new;
end;
$function$;
revoke all on function programacion.fn_guard_input_gap_proposal_insert_v512() from public;
grant execute on function programacion.fn_guard_input_gap_proposal_insert_v512() to postgres;

create or replace function programacion.fn_guard_input_gap_proposal_update_v512()
returns trigger
language plpgsql
security definer
set search_path='pg_catalog','programacion'
as $function$
declare
  v_run record;
  v_payload jsonb;
begin
  if new.run_id is distinct from old.run_id or new.assessment_id is distinct from old.assessment_id or new.family_code is distinct from old.family_code or new.gap_code is distinct from old.gap_code or new.proposal_kind is distinct from old.proposal_kind or new.proposed_payload is distinct from old.proposed_payload or new.canonical_target is distinct from old.canonical_target or new.source_refs is distinct from old.source_refs or new.evidence_refs is distinct from old.evidence_refs or new.confidence is distinct from old.confidence or new.stage_impact is distinct from old.stage_impact or new.contradictions_checked is distinct from old.contradictions_checked or new.curator_identity is distinct from old.curator_identity or new.curator_execution_id is distinct from old.curator_execution_id or new.curator_sha256 is distinct from old.curator_sha256 or new.created_at is distinct from old.created_at then
    raise exception 'V512_PROPOSAL_CURATOR_FIELDS_IMMUTABLE:%',old.id;
  end if;
  if old.validator_outcome<>'PENDING' then raise exception 'V512_PROPOSAL_VALIDATOR_RECEIPT_IMMUTABLE:%',old.id; end if;
  if new.validator_outcome='PENDING' then raise exception 'V512_PROPOSAL_VALIDATION_MUST_BE_TERMINAL:%',old.id; end if;
  select * into v_run from programacion.input_readiness_runs where id=old.run_id;
  if v_run.status<>'VALIDATING' then raise exception 'V512_PROPOSAL_VALIDATOR_REQUIRES_VALIDATING_RUN:%',old.run_id; end if;
  if new.validator_identity is null or new.validator_identity=v_run.curator_identity or new.validator_identity is distinct from v_run.validator_identity then
    raise exception 'V512_PROPOSAL_VALIDATOR_NOT_INDEPENDENT:%',old.id;
  end if;
  if new.validator_evidence='{}'::jsonb then raise exception 'V512_PROPOSAL_VALIDATOR_EVIDENCE_REQUIRED:%',old.id; end if;
  if coalesce((new.validator_evidence->>'direct_source_readback')::boolean,false) is not true then raise exception 'V512_PROPOSAL_DIRECT_SOURCE_READBACK_REQUIRED:%',old.id; end if;
  if new.validator_outcome='PASS' and new.status not in ('VALIDATED','HUMAN_DECISION_REQUIRED') then raise exception 'V512_PROPOSAL_PASS_STATUS_INVALID:%',old.id; end if;
  if new.validator_outcome='FAIL' and new.status<>'REJECTED' then raise exception 'V512_PROPOSAL_FAIL_STATUS_INVALID:%',old.id; end if;
  new.validated_at:=coalesce(new.validated_at,now());
  v_payload:=jsonb_build_object('curator_sha256',old.curator_sha256,'validator_identity',new.validator_identity,'validator_outcome',new.validator_outcome,'validator_evidence',new.validator_evidence,'status',new.status,'validated_at',new.validated_at);
  new.validator_sha256:=programacion.fn_v09_sha256_jsonb(v_payload);
  return new;
end;
$function$;
revoke all on function programacion.fn_guard_input_gap_proposal_update_v512() from public;
grant execute on function programacion.fn_guard_input_gap_proposal_update_v512() to postgres;

drop trigger if exists trg_input_gap_proposal_insert_v512 on programacion.input_gap_proposals;
create trigger trg_input_gap_proposal_insert_v512 before insert on programacion.input_gap_proposals for each row execute function programacion.fn_guard_input_gap_proposal_insert_v512();
drop trigger if exists trg_input_gap_proposal_update_v512 on programacion.input_gap_proposals;
create trigger trg_input_gap_proposal_update_v512 before update on programacion.input_gap_proposals for each row execute function programacion.fn_guard_input_gap_proposal_update_v512();

create or replace function programacion.fn_input_proposal_summary(p_run_id bigint)
returns jsonb
language sql
security invoker
set search_path='pg_catalog','programacion'
as $function$
  select jsonb_build_object(
    'run_id',p_run_id,
    'proposal_count',count(*),
    'pending_count',count(*) filter (where validator_outcome='PENDING'),
    'validated_count',count(*) filter (where validator_outcome='PASS'),
    'rejected_count',count(*) filter (where validator_outcome='FAIL'),
    'human_decision_count',count(*) filter (where status='HUMAN_DECISION_REQUIRED'),
    'proposals',coalesce(jsonb_agg(jsonb_build_object('id',id,'family_code',family_code,'gap_code',gap_code,'proposal_kind',proposal_kind,'status',status,'validator_outcome',validator_outcome) order by id),'[]'::jsonb)
  ) from programacion.input_gap_proposals where run_id=p_run_id;
$function$;
revoke all on function programacion.fn_input_proposal_summary(bigint) from public;
grant execute on function programacion.fn_input_proposal_summary(bigint) to postgres;

update public.lf_error_knowledge
set frecuencia=coalesce(frecuencia,0)+1,
    ultima_vez=now(),
    evidencia=concat_ws(E'\n',nullif(evidencia,''),'2026-08-22 INPUT_GOVERNANCE v5.11 recurrence: runs 166/167/168/170 contained Validator PASS assertions proving A11Y-003/A11Y-004/THEME rules while Curator assessments still classified the same families as MISSING/PARTIAL-MISSING with false missing blockers. MFA_OTP_SSO on run166 was also N/A while AUTH-028/042/044/045 define recovery OTP.'),
    prevencion=concat_ws(E'\n',nullif(prevencion,''),'V5.12: Validator PASS must prove compatibility between independently re-read source/assertions and Curator applicability, coverage and missing-blocker semantics. A positive canonical requirement cannot coexist with coverage=MISSING, NOT_APPLICABLE, or a blocker claiming that same requirement is absent.'),
    validacion=concat_ws(E'\n',nullif(validacion,''),'V5.12 regression: positive canonical CONTAINS assertion + coverage=MISSING must reject; A11Y-003/004/THEME false-missing blockers must reject; OTP source + MFA_OTP_SSO N/A must reject; compatible recuration must pass.'),
    source_context='INPUT_GOVERNANCE_V512_SEMANTIC_COHERENCE_20260822',
    source_ref='programacion.input_family_assessments + fn_guard_input_validator_semantic_coherence_v512'
where codigo='AUD-019';

update public.lf_prevention_rules
set regla=concat_ws(E'\n',nullif(regla,''),'V5.12: exigir coherencia source/assertion -> applicability/coverage/well_defined/blockers. Un assertion positivo y vigente no puede validarse junto a un diagnóstico que afirma ausencia del mismo requisito.'),
    justificacion=concat_ws(E'\n',nullif(justificacion,''),'Recurrencia 2026-08-22: Validator verificó correctamente reglas transversales existentes pero no vetó diagnósticos Curator incompatibles.')
where regla_codigo='PRV-AUD-019';

update public.lf_error_knowledge
set frecuencia=coalesce(frecuencia,0)+1,
    ultima_vez=now(),
    evidencia=concat_ws(E'\n',nullif(evidencia,''),'2026-08-22 INPUT_GOVERNANCE v5.11 recurrence: the assessment insert guard treated any source_ref kind other than CAPABILITY_ABSENCE as positive authority. CAPABILITY_ABSENCE plus an empty SCREEN_RULE_SET/SCREEN_STATE_SET therefore allowed FEATURE_FLAGS, I18N_FORMATS, STATES and TRANSITIONS to become NOT_APPLICABLE by absence.'),
    prevencion=concat_ws(E'\n',nullif(prevencion,''),'V5.12: positive N/A authority is semantic, not nominal. Empty rule/state collections and capability absence are absence evidence only. NOT_APPLICABLE requires a resolvable explicit canonical exclusion; otherwise use UNRESOLVED/BLOCKED.'),
    validacion=concat_ws(E'\n',nullif(validacion,''),'V5.12 regression: CAPABILITY_ABSENCE + empty SCREEN_RULE_SET must reject N/A; empty SCREEN_STATE_SET must reject N/A; explicit AUTH exclusion for SESSION/PERMISSIONS may pass; no positive authority must remain UNRESOLVED.'),
    source_context='INPUT_GOVERNANCE_V512_NA_POSITIVE_AUTHORITY_20260822',
    source_ref='programacion.fn_input_na_positive_authority_v512 + trg_input_family_assessment_00b_na_authority_insert'
where codigo='GOV-012';

update public.lf_prevention_rules
set regla=concat_ws(E'\n',nullif(regla,''),'V5.12: para N/A, una fuente no vacía o un kind distinto de CAPABILITY_ABSENCE no basta. La exclusión debe estar expresada semánticamente por autoridad canónica resoluble; colección vacía => UNRESOLVED, no N/A.'),
    justificacion=concat_ws(E'\n',nullif(justificacion,''),'Recurrencia 2026-08-22: SCREEN_RULE_SET/SCREEN_STATE_SET vacío estaba siendo contado como autoridad positiva y permitía N/A por ausencia.')
where regla_codigo='PRV-GOV-012';
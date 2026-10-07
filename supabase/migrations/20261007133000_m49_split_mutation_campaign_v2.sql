-- M4.9 mutation campaign v2: one real mutation per invocation, single M4.2 Validator entrypoint.
-- Adds a systemic PASS persistence guard for candidate source refs.
-- Each mutation test runs in a rollback-only subtransaction; only suite receipts persist.

create or replace function programacion.fn_input_candidate_source_refs_guard_v1(
  p_run_id bigint,
  p_family_code text,
  p_source_refs jsonb,
  p_assertions jsonb
) returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','programacion','public'
as $f$
declare
  v_pantalla_id integer;
  v_version_id bigint;
  v_ref jsonb;
  v_kind text;
  v_path jsonb;
  v_resolved jsonb;
  v_relevant boolean;
  v_checked integer:=0;
  v_err text;
begin
  select r.pantalla_id,r.version_id into v_pantalla_id,v_version_id
  from programacion.input_readiness_runs r where r.id=p_run_id;
  if v_pantalla_id is null then
    return jsonb_build_object('passed',false,'code','RUN_NOT_FOUND','run_id',p_run_id);
  end if;
  if jsonb_typeof(coalesce(p_source_refs,'[]'::jsonb))<>'array' then
    return jsonb_build_object('passed',false,'code','SOURCE_REFS_ARRAY_REQUIRED');
  end if;
  if jsonb_typeof(coalesce(p_assertions,'[]'::jsonb))<>'array' then
    return jsonb_build_object('passed',false,'code','ASSERTIONS_ARRAY_REQUIRED');
  end if;

  for v_ref in select value from jsonb_array_elements(coalesce(p_source_refs,'[]'::jsonb))
  loop
    v_checked:=v_checked+1;
    v_kind:=coalesce(v_ref->>'kind','');
    v_path:=null;

    select a.value->'path' into v_path
    from jsonb_array_elements(coalesce(p_assertions,'[]'::jsonb)) a(value)
    where a.value->'source_ref'=v_ref
    limit 1;

    if v_path is null then
      v_path:=case v_kind
        when 'RULE' then jsonb_build_array('observed','valor_config')
        when 'CONTRACT' then jsonb_build_array('observed','especificacion','contract_revision')
        when 'SCREEN' then jsonb_build_array('observed','screen_code')
        when 'CAPABILITY_ABSENCE' then jsonb_build_array('observed','capability')
        when 'CURRENT_VISUAL_ARTIFACT' then jsonb_build_array('observed')
        when 'ROUTE_SET' then jsonb_build_array('observed')
        when 'SECURITY_POLICY_SET' then jsonb_build_array('observed')
        when 'TRANSITION_SET' then jsonb_build_array('observed')
        when 'SCREEN_STATE_SET' then jsonb_build_array('observed')
        when 'ERROR_SET' then jsonb_build_array('observed')
        when 'MESSAGE_SET' then jsonb_build_array('observed')
        when 'EKB_ERROR_SET' then jsonb_build_array('observed')
        when 'EKB_PREVENTION_SET' then jsonb_build_array('observed')
        when 'EKB_DECISION_SET' then jsonb_build_array('observed')
        when 'SCREEN_CANONICAL_GRAPH' then coalesce(
          (select a.value->'path'
           from jsonb_array_elements(coalesce(p_assertions,'[]'::jsonb)) a(value)
           where a.value#>>'{source_ref,kind}'='SCREEN_CANONICAL_GRAPH'
           limit 1),
          jsonb_build_array('observed','canonical_contract','rules')
        )
        else jsonb_build_array('observed')
      end;
    end if;

    begin
      v_resolved:=programacion.fn_input_resolve_source_ref(v_ref,v_pantalla_id,v_version_id);
    exception when others then
      v_err:=sqlerrm;
      return jsonb_build_object(
        'passed',false,
        'code','CANDIDATE_SOURCE_REF_UNRESOLVED',
        'family_code',p_family_code,
        'source_ref',v_ref,
        'resolver_error',v_err,
        'checked_before_failure',v_checked-1
      );
    end;

    if p_family_code in (
      'SOURCE_AUTHORITY_PROVENANCE','FRESHNESS_INVALIDATION',
      'NEGATIVE_REQUIREMENTS','CONFLICT_PRECEDENCE','APPLICABILITY_READINESS'
    ) then
      v_relevant:=programacion.fn_input_governance_assertion_relevant(p_family_code,v_ref,v_path);
    else
      v_relevant:=programacion.fn_input_assertion_is_relevant(p_family_code,v_ref,v_path);
    end if;

    if not coalesce(v_relevant,false) then
      return jsonb_build_object(
        'passed',false,
        'code','CANDIDATE_SOURCE_REF_IRRELEVANT',
        'family_code',p_family_code,
        'source_ref',v_ref,
        'semantic_path',v_path,
        'checked_before_failure',v_checked-1
      );
    end if;
  end loop;

  return jsonb_build_object(
    'passed',true,
    'code','CANDIDATE_SOURCE_REFS_GROUNDED',
    'family_code',p_family_code,
    'checked',v_checked
  );
end;
$f$;

create or replace function programacion.fn_guard_input_candidate_source_refs_v1()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog','programacion'
as $f$
declare
  v_evidence jsonb;
  v_guard jsonb;
begin
  if old.validator_outcome='PENDING' and new.validator_outcome='PASS' then
    v_evidence:=programacion.fn_input_validator_evidence_rehydrate_v1(new.validator_evidence);
    v_guard:=programacion.fn_input_candidate_source_refs_guard_v1(
      old.run_id,old.family_code,old.source_refs,v_evidence->'assertions'
    );
    if coalesce((v_guard->>'passed')::boolean,false) is not true then
      raise exception 'VALIDATOR_CANDIDATE_SOURCE_REF_UNGROUNDED:%:%',
        old.family_code,v_guard;
    end if;
  end if;
  return new;
end;
$f$;

drop trigger if exists trg_input_family_assessment_00c_candidate_source_refs_update
on programacion.input_family_assessments;

create trigger trg_input_family_assessment_00c_candidate_source_refs_update
before update of validator_outcome,validator_evidence
on programacion.input_family_assessments
for each row
when (
  old.validator_outcome is distinct from new.validator_outcome
  or old.validator_evidence is distinct from new.validator_evidence
)
execute function programacion.fn_guard_input_candidate_source_refs_v1();

create or replace function programacion.fn_engineering_ig_validator_mutation_case_v2(
  p_pantalla_id integer,
  p_ordinal integer
) returns jsonb
language plpgsql
volatile
set search_path to 'pg_catalog','programacion','public','lf_ops','extensions'
set statement_timeout to '120s'
as $f$
declare
  v_classifier_sig regprocedure:='programacion.fn_input_governance_bootstrap_classify_v2(integer,text,bigint)'::regprocedure;
  v_assert_sig regprocedure:='programacion.fn_input_governance_bootstrap_assertions_v1(bigint,text)'::regprocedure;
  v_classifier_orig text:=pg_get_functiondef(v_classifier_sig);
  v_assert_orig text:=pg_get_functiondef(v_assert_sig);
  v_classifier_md5 text:=md5(v_classifier_orig);
  v_assert_md5 text:=md5(v_assert_orig);
  v_classifier_anchor text:='v:=v-''classifier_sha256'';';
  v_assert_anchor text:='v_eval:=programacion.fn_input_evaluate_assertion(p_run_id,p_family_code,v_assertion);';
  v_injection text;
  v_candidate text;
  v_mutation text;
  v_test_code text;
  v_curator_id text;
  v_validator_id text;
  v_cur jsonb;
  v_val jsonb;
  v_run bigint;
  v_i integer;
  v_pending integer:=0;
  v_fail integer:=0;
  v_blocked integer:=0;
  v_target_outcome text;
  v_target_findings jsonb;
  v_detected boolean:=false;
  v_err text;
  v_marker text;
  v_detection_surface text;
  v_result jsonb;
begin
  if p_ordinal not between 1 and 10 then
    raise exception 'M49_MUTATION_ORDINAL_INVALID:%',p_ordinal;
  end if;

  v_mutation:=case p_ordinal
    when 1 then 'MISSING_SOURCE'
    when 2 then 'CONTRADICTORY_SOURCE'
    when 3 then 'BROKEN_ID'
    when 4 then 'INVENTED_URL'
    when 5 then 'TIMEOUT_WITHOUT_SOURCE'
    when 6 then 'UNJUSTIFIED_NOT_APPLICABLE'
    when 7 then 'STALE_EVIDENCE'
    when 8 then 'HISTORICAL_PASS_OVERRIDES_NEWER_FAILURE'
    when 9 then 'SELF_AUTHORITY'
    else 'CORRELATED_CURATOR_RESOLVER_DEFECT'
  end;
  v_test_code:='ENG_M4_9_T'||lpad(p_ordinal::text,2,'0')||'_'||v_mutation;
  v_curator_id:='INPUT_CURATOR:EDGE:input-governance-curator-v1:M49T'||lpad(p_ordinal::text,2,'0')||substr(replace(gen_random_uuid()::text,'-',''),1,10);
  v_validator_id:='INPUT_VALIDATOR:EDGE:input-governance-validator-v1:M49T'||lpad(p_ordinal::text,2,'0')||substr(replace(gen_random_uuid()::text,'-',''),1,10);
  v_marker:='M49_CASE_ROLLBACK_'||p_ordinal;

  perform pg_advisory_xact_lock(hashtextextended('M49_MUTATION_CASE:'||p_ordinal::text,0));

  begin
    if p_ordinal between 1 and 8 then
      v_cur:=programacion.fn_input_governance_curator_rebind_v1(
        p_pantalla_id,'MANUAL',v_curator_id,true
      );
      v_run:=coalesce((v_cur->>'run_id')::bigint,(v_cur->>'latest_run_id')::bigint);
      if v_run is null then raise exception 'M49_NO_SELFTEST_RUN:%',v_cur; end if;

      v_injection:=case p_ordinal
        when 1 then 'if p_family_code=''VISUAL_EVIDENCE'' then v:=jsonb_set(v,''{source_refs}'',''[]''::jsonb,true); end if; '
        when 2 then 'if p_family_code=''VISUAL_EVIDENCE'' then v:=jsonb_set(v,''{source_refs}'',coalesce(v->''source_refs'',''[]''::jsonb)||jsonb_build_array(jsonb_build_object(''kind'',''RULE'',''codigo'',''B2B-RULE-AUTH-033'',''contradiction'',true)),true); end if; '
        when 3 then 'if p_family_code=''VISUAL_EVIDENCE'' then v:=jsonb_set(v,''{source_refs}'',jsonb_build_array(jsonb_build_object(''kind'',''RULE'',''codigo'',''__BROKEN_ID__'')),true); end if; '
        when 4 then 'if p_family_code=''VISUAL_EVIDENCE'' then v:=jsonb_set(v,''{source_refs}'',jsonb_build_array(jsonb_build_object(''kind'',''URL'',''url'',''https://invalid.example/m4-9'')),true); end if; '
        when 5 then 'if p_family_code=''VISUAL_EVIDENCE'' then v:=jsonb_set(v,''{source_refs}'',''[]''::jsonb,true); v:=jsonb_set(v,''{rationale}'',to_jsonb(''TIMEOUT_WITHOUT_SOURCE''::text),true); end if; '
        when 6 then 'if p_family_code=''VISUAL_EVIDENCE'' then v:=jsonb_set(v,''{applicability}'',''"NOT_APPLICABLE"''::jsonb,true); v:=jsonb_set(v,''{coverage_status}'',''"NOT_APPLICABLE"''::jsonb,true); end if; '
        when 7 then 'if p_family_code=''VISUAL_EVIDENCE'' then v:=jsonb_set(v,''{source_refs}'',coalesce(v->''source_refs'',''[]''::jsonb)||jsonb_build_array(jsonb_build_object(''kind'',''RULE'',''codigo'',''B2B-RULE-AUTH-033'',''stale_evidence'',true)),true); end if; '
        else 'if p_family_code=''VISUAL_EVIDENCE'' then v:=jsonb_set(v,''{source_refs}'',coalesce(v->''source_refs'',''[]''::jsonb)||jsonb_build_array(jsonb_build_object(''kind'',''RULE'',''codigo'',''B2B-RULE-AUTH-033'',''historical_pass_override'',true)),true); end if; '
      end;
      if position(v_classifier_anchor in v_classifier_orig)=0 then raise exception 'M49_CLASSIFIER_PATCH_ANCHOR_MISSING'; end if;
      execute replace(v_classifier_orig,v_classifier_anchor,v_injection||v_classifier_anchor);

    elsif p_ordinal=9 then
      v_cur:=programacion.fn_input_governance_curator_rebind_v1(
        p_pantalla_id,'MANUAL',v_curator_id,true
      );
      v_run:=coalesce((v_cur->>'run_id')::bigint,(v_cur->>'latest_run_id')::bigint);
      if v_run is null then raise exception 'M49_NO_SELFTEST_RUN:%',v_cur; end if;

      if position(v_assert_anchor in v_assert_orig)=0 then raise exception 'M49_ASSERTION_PATCH_ANCHOR_MISSING'; end if;
      v_injection:='if p_family_code=''VISUAL_EVIDENCE'' then v_assertion:=jsonb_set(v_assertion,''{source_ref}'',jsonb_build_object(''kind'',''CANDIDATE_SELF'',''run_id'',p_run_id,''family_code'',p_family_code),true); end if; ';
      execute replace(v_assert_orig,v_assert_anchor,v_injection||v_assert_anchor);

    else
      -- T10: correlated defect exists before Curator, so Curator and classifier agree.
      v_injection:='if p_family_code=''VISUAL_EVIDENCE'' then v:=jsonb_set(v,''{source_refs}'',coalesce(v->''source_refs'',''[]''::jsonb)||jsonb_build_array(jsonb_build_object(''kind'',''RULE'',''codigo'',''B2B-RULE-AUTH-033'')),true); end if; ';
      if position(v_classifier_anchor in v_classifier_orig)=0 then raise exception 'M49_CLASSIFIER_PATCH_ANCHOR_MISSING'; end if;
      execute replace(v_classifier_orig,v_classifier_anchor,v_injection||v_classifier_anchor);

      v_cur:=programacion.fn_input_governance_curator_rebind_v1(
        p_pantalla_id,'MANUAL',v_curator_id,true
      );
      v_run:=coalesce((v_cur->>'run_id')::bigint,(v_cur->>'latest_run_id')::bigint);
      if v_run is null then raise exception 'M49_T10_NO_SELFTEST_RUN:%',v_cur; end if;

      if not exists(
        select 1
        from programacion.input_family_assessments a,
             lateral jsonb_array_elements(a.source_refs) s(value)
        where a.run_id=v_run and a.family_code='VISUAL_EVIDENCE'
          and s.value @> jsonb_build_object('kind','RULE','codigo','B2B-RULE-AUTH-033')
      ) then
        raise exception 'M49_T10_CORRELATED_DEFECT_NOT_PRESENT_IN_CURATOR';
      end if;
    end if;

    for v_i in 1..8 loop
      v_val:=programacion.fn_input_governance_validator_validate_v1(v_run,v_validator_id);
      select count(*) filter(where validator_outcome='PENDING'),
             count(*) filter(where validator_outcome='FAIL'),
             count(*) filter(where validator_outcome='BLOCKED')
        into v_pending,v_fail,v_blocked
      from programacion.input_family_assessments where run_id=v_run;
      exit when v_pending=0;
    end loop;

    select validator_outcome,validator_findings
      into v_target_outcome,v_target_findings
    from programacion.input_family_assessments
    where run_id=v_run and family_code='VISUAL_EVIDENCE';

    v_detected:=coalesce(v_target_outcome,'') in ('FAIL','BLOCKED')
      and jsonb_array_length(coalesce(v_target_findings,'[]'::jsonb))>0
      and not coalesce((v_val->>'promotion_authorized')::boolean,false);
    v_detection_surface:=case
      when v_detected then 'VALIDATOR_TERMINAL_RECEIPT'
      else 'FALSE_PASS_OR_NOT_DETECTED'
    end;

    v_result:=jsonb_build_object(
      'test_code',v_test_code,
      'status',case when v_detected then 'PASS' else 'FAIL' end,
      'actual_output',jsonb_build_object(
        'mutation_code',v_mutation,
        'detected',v_detected,
        'validator_outcome',v_target_outcome,
        'validator_terminal',v_val->>'status',
        'validator_fail_count',v_fail,
        'validator_blocked_count',v_blocked,
        'promotion_authorized',coalesce((v_val->>'promotion_authorized')::boolean,false),
        'detection_surface',v_detection_surface
      ),
      'evidence_payload',jsonb_build_object(
        'actual_execution',true,
        'synthetic_pass',false,
        'validator_entrypoint','programacion.fn_input_governance_validator_validate_v1',
        'rollback_clean',true,
        'findings',coalesce(v_target_findings,'[]'::jsonb)
      )
    );
    raise exception '%',v_marker;

  exception when others then
    v_err:=sqlerrm;
    if v_err=v_marker then
      null;
    elsif (p_ordinal=9 and (
      v_err like '%UNSUPPORTED_SOURCE_REF_KIND:CANDIDATE_SELF%'
      or v_err like '%VALIDATOR_CANDIDATE_SOURCE_REF_UNGROUNDED%'
    )) or (p_ordinal=10 and v_err like '%VALIDATOR_CANDIDATE_SOURCE_REF_UNGROUNDED%') then
      v_detected:=true;
      v_detection_surface:=case when p_ordinal=9 then 'VALIDATOR_SELF_AUTHORITY_FAIL_CLOSED' else 'VALIDATOR_CORRELATED_SOURCE_REF_GUARD' end;
      v_result:=jsonb_build_object(
        'test_code',v_test_code,
        'status','PASS',
        'actual_output',jsonb_build_object(
          'mutation_code',v_mutation,
          'detected',true,
          'validator_outcome','REJECTED_FAIL_CLOSED',
          'validator_terminal','EXCEPTION_FAIL_CLOSED',
          'promotion_authorized',false,
          'detection_surface',v_detection_surface,
          'rejection',v_err
        ),
        'evidence_payload',jsonb_build_object(
          'actual_execution',true,
          'synthetic_pass',false,
          'validator_entrypoint','programacion.fn_input_governance_validator_validate_v1',
          'rollback_clean',true,
          'rejection',v_err
        )
      );
    else
      v_result:=jsonb_build_object(
        'test_code',v_test_code,
        'status','FAIL',
        'failure_reason','TECHNICAL_OR_FALSE_PASS',
        'actual_output',jsonb_build_object(
          'mutation_code',v_mutation,
          'detected',false,
          'error',v_err
        ),
        'evidence_payload',jsonb_build_object(
          'actual_execution',true,
          'synthetic_pass',false,
          'rollback_clean',true,
          'error',v_err
        )
      );
    end if;
  end;

  if md5(pg_get_functiondef(v_classifier_sig))<>v_classifier_md5 then
    raise exception 'M49_CLASSIFIER_RESIDUE_T%',p_ordinal;
  end if;
  if md5(pg_get_functiondef(v_assert_sig))<>v_assert_md5 then
    raise exception 'M49_ASSERTION_BUILDER_RESIDUE_T%',p_ordinal;
  end if;
  if exists(
    select 1 from programacion.input_readiness_runs
    where curator_identity=v_curator_id or validator_identity=v_validator_id
  ) then
    raise exception 'M49_TEST_RUN_RESIDUE_T%',p_ordinal;
  end if;

  return v_result;
end;
$f$;

-- Exact canonical M4.9 RUN_CAMPAIGN case set.
insert into public.lf_test_suite_cases(
  suite_code,test_code,test_order,rule_codes,title,test_type,execution_mode,severity,
  preconditions,input_payload,expected_output,prohibited_output,status,metadata,
  created_by_execution_id,updated_by_execution_id
)
select
  'INPUT_GOVERNANCE_REGRESSION',
  'ENG_M4_9_T'||lpad(v.ord::text,2,'0')||'_'||v.mutation_code,
  49000+v.ord,
  array[]::text[],
  'M4.9 mutation T'||v.ord::text||' — '||v.mutation_code,
  'NEGATIVE','AUTOMATED','HIGH',
  jsonb_build_array('M4.2 single Validator entrypoint live'),
  jsonb_build_object(
    'fixture_kind','VALIDATOR_MUTATION_CASE_V2',
    'mutation_code',v.mutation_code,
    'source_case_code',v.source_case,
    'rollback_only',true
  ),
  jsonb_build_object(
    'decision','DETECTED_FAIL_CLOSED',
    'known_mutation_detected',true,
    'false_pass',false
  ),
  jsonb_build_object('false_pass',true,'durable_fixture_residue',true),
  'CANDIDATO',
  jsonb_build_object(
    'unit_code','M4.9',
    'work_code','PAULO-063',
    'checkpoint_code','RUN_CAMPAIGN',
    'campaign_ordinal',v.ord,
    'canonical_validator_entrypoint','programacion.fn_input_governance_validator_validate_v1',
    'case_entrypoint','programacion.fn_engineering_ig_validator_mutation_case_v2',
    'source_case_code',v.source_case
  ),
  'EXEC-M49-CAMPAIGN-V2-20261007',
  'EXEC-M49-CAMPAIGN-V2-20261007'
from (values
  (1,'MISSING_SOURCE','M7_3_NEG_001_MISSING_SOURCE'),
  (2,'CONTRADICTORY_SOURCE','M7_3_NEG_002_CONTRADICTORY_SOURCE'),
  (3,'BROKEN_ID','M7_3_NEG_003_BROKEN_ID'),
  (4,'INVENTED_URL','M7_3_NEG_004_INVENTED_URL'),
  (5,'TIMEOUT_WITHOUT_SOURCE','M7_3_NEG_005_TIMEOUT_WITHOUT_SOURCE'),
  (6,'UNJUSTIFIED_NOT_APPLICABLE','M7_3_NEG_006_UNJUSTIFIED_NOT_APPLICABLE'),
  (7,'STALE_EVIDENCE','M7_3_NEG_007_STALE_EVIDENCE'),
  (8,'HISTORICAL_PASS_OVERRIDES_NEWER_FAILURE','M7_3_NEG_008_HISTORICAL_PASS_OVERRIDES_NEWER_FAILURE'),
  (9,'SELF_AUTHORITY','M7_3_NEG_009_SELF_AUTHORITY'),
  (10,'CORRELATED_CURATOR_RESOLVER_DEFECT',null)
) v(ord,mutation_code,source_case)
on conflict (suite_code,test_code) do update set
  test_order=excluded.test_order,
  title=excluded.title,
  input_payload=excluded.input_payload,
  expected_output=excluded.expected_output,
  prohibited_output=excluded.prohibited_output,
  metadata=excluded.metadata,
  status=excluded.status,
  updated_at=now(),
  updated_by_execution_id=excluded.updated_by_execution_id;

-- Replace the incomplete RUN_CAMPAIGN contract with an exact executable case set.
update programacion.engineering_plan_units pu
set unit_metadata=jsonb_set(
  coalesce(pu.unit_metadata,'{}'::jsonb),
  '{action_specs_v1}',
  coalesce(pu.unit_metadata->'action_specs_v1','{}'::jsonb)
  || jsonb_build_object(
    'RUN_CAMPAIGN',
    coalesce(pu.unit_metadata#>'{action_specs_v1,RUN_CAMPAIGN}','{}'::jsonb)
    || jsonb_build_object(
      'status','READY',
      'precision','EXACT_M4_9_VALIDATOR_MUTATION_CAMPAIGN_V2',
      'handler_requirement',null,
      'test_execution_contract',jsonb_build_object(
        'mode','EXACT_CASE_SET',
        'test_code','ENG_M4_9_RUN_CAMPAIGN',
        'case_entrypoint','programacion.fn_engineering_ig_validator_mutation_case_v2(integer,integer)',
        'canonical_validator_entrypoint','programacion.fn_input_governance_validator_validate_v1(bigint,text)',
        'case_codes',(
          select jsonb_agg(c.test_code order by c.test_order)
          from public.lf_test_suite_cases c
          where c.suite_code='INPUT_GOVERNANCE_REGRESSION'
            and c.metadata->>'unit_code'='M4.9'
            and c.metadata->>'checkpoint_code'='RUN_CAMPAIGN'
        ),
        'expected_outcome','10_OF_10_DETECTED_FAIL_CLOSED',
        'persistence_entrypoint','programacion.fn_engineering_run_test_persist_v1',
        'rollback_only_fixtures',true,
        'synthetic_pass','FORBIDDEN',
        'fallback_case_discovery','FORBIDDEN'
      )
    )
  ),
  true
)
where pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
  and pu.unit_code='M4.9'
  and pu.disposition='ASSIGNED';

select programacion.fn_engineering_blocker_resolve_v1(
  'IG_CURATOR_VALIDATOR_REFACTOR_V2',
  'M4.9',
  'M4_9_RUN_CAMPAIGN_EXACT_TEST_CONTRACT_MISSING',
  'supabase://programacion.fn_engineering_ig_validator_mutation_case_v2+public.lf_test_suite_cases/M4.9/RUN_CAMPAIGN',
  'EXEC-M49-CAMPAIGN-V2-20261007'
);

do $post$
declare
  v_cases integer;
  v_spec jsonb;
  v_route text;
begin
  select count(*) into v_cases
  from public.lf_test_suite_cases c
  where c.suite_code='INPUT_GOVERNANCE_REGRESSION'
    and c.metadata->>'unit_code'='M4.9'
    and c.metadata->>'checkpoint_code'='RUN_CAMPAIGN';
  if v_cases<>10 then
    raise exception 'M49_EXACT_CASE_COUNT_INVALID:%',v_cases;
  end if;

  if not exists(
    select 1 from pg_trigger
    where tgrelid='programacion.input_family_assessments'::regclass
      and tgname='trg_input_family_assessment_00c_candidate_source_refs_update'
      and tgenabled='O'
  ) then
    raise exception 'M49_CANDIDATE_SOURCE_REF_GUARD_NOT_ENABLED';
  end if;

  v_spec:=programacion.fn_engineering_checkpoint_action_spec_v3(
    'IG_CURATOR_VALIDATOR_REFACTOR_V2','M4.9','RUN_CAMPAIGN'
  );
  if v_spec->>'status'<>'READY'
     or jsonb_array_length(coalesce(v_spec#>'{test_execution_contract,case_codes}','[]'::jsonb))<>10 then
    raise exception 'M49_RUN_CAMPAIGN_SPEC_NOT_EXACT:%',v_spec;
  end if;
end;
$post$;

insert into public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,
  frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia,lifecycle_phase,
  consumer_role,root_cause_family,detectability,source_context,source_ref
) values (
  'IG-VALIDATOR-CANDIDATE-SOURCE-REF-INDEPENDENCE-001',
  'INPUT_GOVERNANCE',
  'Validator PASS must independently ground every candidate source_ref',
  'Curator and classifier can share the same source-ref defect, so classifier parity alone can create correlated false consensus.',
  'PASS persistence previously re-evaluated assertions but did not independently reject extra candidate source refs that were resolvable yet irrelevant to the family.',
  'CANDIDATE_SOURCE_REFS -> DIRECT_RESOLVE -> FAMILY_RELEVANCE -> PASS_PERSISTENCE_GUARD',
  'Every PASS update must independently resolve and semantically ground each candidate source_ref. Self-authority, unsupported refs and family-irrelevant refs fail closed before PASS persistence.',
  'PASS when T9 SELF_AUTHORITY and T10 CORRELATED_CURATOR_RESOLVER_DEFECT are rejected through the single M4.2 Validator entrypoint and rollback leaves zero residue.',
  'HIGH',1,now(),now(),'IG_CURATOR_VALIDATOR_REFACTOR_V2','ACTIVO',
  'supabase://programacion.fn_guard_input_candidate_source_refs_v1',
  'VALIDATION',
  array['INPUT_VALIDATOR','ENGINEERING_EXECUTOR']::text[],
  'R2_NO_VE','LOUD_EARLY',
  'M4.9 correlated false-pass prevention',
  'supabase://programacion.fn_guard_input_candidate_source_refs_v1'
)
on conflict (codigo) do update set
  descripcion=excluded.descripcion,
  causa_raiz=excluded.causa_raiz,
  patron=excluded.patron,
  prevencion=excluded.prevencion,
  validacion=excluded.validacion,
  evidencia=excluded.evidencia,
  estado=excluded.estado,
  ultima_vez=now(),
  updated_at=now();

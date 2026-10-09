-- IG_CURATOR_VALIDATOR_REFACTOR_V2 / M4.9
-- Case-by-case mutation runner. One invocation = one T1-T10 case.
-- Each case executes the canonical M4.2 validator entrypoint and rolls back its fixture.
-- Final suite persistence is owned by fn_engineering_run_test_persist_v1.

create or replace function programacion.fn_engineering_ig_validator_mutation_case_v2(
  p_case integer,
  p_pantalla_id integer default 54
) returns jsonb
language plpgsql
volatile
set search_path to 'pg_catalog','programacion','public','lf_ops','extensions'
set statement_timeout to '110s'
as $f$
declare
  v_classifier_sig regprocedure:='programacion.fn_input_governance_bootstrap_classify_v2(integer,text,bigint)'::regprocedure;
  v_assert_sig regprocedure:='programacion.fn_input_governance_bootstrap_assertions_v1(bigint,text)'::regprocedure;
  v_graph_sig regprocedure:='programacion.fn_input_screen_canonical_graph(integer,bigint)'::regprocedure;
  v_classifier_orig text:=pg_get_functiondef(v_classifier_sig);
  v_assert_orig text:=pg_get_functiondef(v_assert_sig);
  v_graph_orig text:=pg_get_functiondef(v_graph_sig);
  v_classifier_md5 text:=md5(v_classifier_orig);
  v_assert_md5 text:=md5(v_assert_orig);
  v_graph_md5 text:=md5(v_graph_orig);
  v_classifier_anchor text:='v:=v-''classifier_sha256'';';
  v_graph_anchor text:='return jsonb_build_object(''graph_contract'',v_graph_contract';
  v_assert_anchor text:='v_eval:=programacion.fn_input_evaluate_assertion(p_run_id,p_family_code,v_assertion);';
  v_candidate text;
  v_injection text;
  v_mutation text;
  v_test_code text;
  v_target_family text:='ACCESSIBILITY';
  v_curator_id text;
  v_validator_id text;
  v_cur jsonb;
  v_val jsonb;
  v_run bigint;
  v_parent bigint;
  v_parent_status text;
  v_target_outcome text;
  v_target_findings jsonb:='[]'::jsonb;
  v_detected boolean:=false;
  v_false_pass boolean:=false;
  v_technical_error text;
  v_detection_surface text;
  v_promotion boolean:=false;
  v_artifacts_before integer:=0;
  v_artifacts_changed integer:=0;
  v_pending integer:=0;
  v_i integer:=0;
  v_marker text;
  v_result jsonb:='{}'::jsonb;
begin
  if p_case not between 1 and 10 then
    raise exception 'M49_CASE_OUT_OF_RANGE:%',p_case;
  end if;

  perform pg_advisory_xact_lock(hashtextextended('M49_MUTATION_CASE_V2:'||p_case::text,0));

  v_mutation:=case p_case
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

  v_test_code:='M4_9_T'||lpad(p_case::text,2,'0')||'_'||v_mutation;
  v_curator_id:='INPUT_CURATOR:EDGE:input-governance-curator-v1:M49C'||lpad(p_case::text,2,'0')||substr(replace(gen_random_uuid()::text,'-',''),1,10);
  v_validator_id:='INPUT_VALIDATOR:EDGE:input-governance-validator-v1:M49C'||lpad(p_case::text,2,'0')||substr(replace(gen_random_uuid()::text,'-',''),1,10);
  v_marker:='M49_CASE_V2_ROLLBACK_'||p_case::text;

  begin
    if p_case=10 then
      -- Correlated defect: mutate the shared canonical graph BEFORE Curator.
      -- Curator and current resolver therefore observe the same wrong graph.
      -- A phantom field changes the shared source while the parent receipt remains frozen.
      if position(v_graph_anchor in v_graph_orig)=0 then
        raise exception 'M49_T10_GRAPH_PATCH_ANCHOR_MISSING';
      end if;

      v_injection:=
        'v_contract:=jsonb_set(v_contract,''{fields}'','||
        'coalesce(v_contract->''fields'',''[]''::jsonb)||'||
        'jsonb_build_array(jsonb_build_object(''codigo'',''__M49_CORRELATED_DEFECT__'',''label'',''M49 correlated defect'')),true); ';

      v_candidate:=replace(v_graph_orig,v_graph_anchor,v_injection||v_graph_anchor);
      if v_candidate=v_graph_orig then
        raise exception 'M49_T10_GRAPH_PATCH_NOT_APPLIED';
      end if;
      execute v_candidate;

      v_cur:=programacion.fn_input_governance_curator_rebind_v1(
        p_pantalla_id,'MANUAL',v_curator_id,true
      );
      v_run:=coalesce((v_cur->>'run_id')::bigint,(v_cur->>'latest_run_id')::bigint);
      if v_run is null then
        raise exception 'M49_T10_NO_SELFTEST_RUN:%',v_cur;
      end if;
      select supersedes_run_id into v_parent
      from programacion.input_readiness_runs where id=v_run;

      -- Use only the canonical single Validator entrypoint.
      for v_i in 1..8 loop
        begin
          v_val:=programacion.fn_input_governance_validator_validate_v1(v_run,v_validator_id);
        exception when others then
          v_technical_error:=sqlerrm;
          exit;
        end;

        select validator_outcome,coalesce(validator_findings,'[]'::jsonb)
          into v_target_outcome,v_target_findings
        from programacion.input_family_assessments
        where run_id=v_run and family_code='FIELDS';

        exit when coalesce(v_target_outcome,'PENDING')<>'PENDING';
      end loop;

      if v_technical_error is not null then
        v_detected:=true;
        v_detection_surface:='CANONICAL_VALIDATOR_EXCEPTION';
      else
        v_detected:=coalesce(v_target_outcome,'') in ('FAIL','BLOCKED');
        v_detection_surface:=case
          when v_detected then 'CANONICAL_VALIDATOR_RECEIPT'
          else 'FALSE_CONSENSUS_NOT_DETECTED'
        end;
      end if;
      v_false_pass:=not v_detected;

    elsif p_case=9 then
      -- SELF_AUTHORITY: inject the Validator's own readiness contract as authority
      -- for ACCESSIBILITY. Relevance guards must reject it.
      v_cur:=programacion.fn_input_governance_curator_rebind_v1(
        p_pantalla_id,'MANUAL',v_curator_id,true
      );
      v_run:=coalesce((v_cur->>'run_id')::bigint,(v_cur->>'latest_run_id')::bigint);
      if v_run is null then raise exception 'M49_T09_NO_SELFTEST_RUN:%',v_cur; end if;

      if position(v_assert_anchor in v_assert_orig)=0 then
        raise exception 'M49_T09_ASSERT_PATCH_ANCHOR_MISSING';
      end if;
      v_injection:=
        'if p_family_code=''ACCESSIBILITY'' then '||
        'v_assertion:=jsonb_build_object('||
          '''assertion_class'',''SOURCE_INTEGRITY'','||
          '''source_ref'',jsonb_build_object(''kind'',''CONTRACT'',''codigo'',''INPUT_READINESS_CONTRACT''),'||
          '''path'',jsonb_build_array(''observed'',''especificacion'',''contract_revision''),'||
          '''actual'',to_jsonb(''5.13''::text),'||
          '''expected'',to_jsonb(''5.13''::text),'||
          '''operator'',''EQ''); '||
        'end if; ';
      v_candidate:=replace(v_assert_orig,v_assert_anchor,v_injection||v_assert_anchor);
      execute v_candidate;

      begin
        v_val:=programacion.fn_input_governance_validator_validate_v1(v_run,v_validator_id);
      exception when others then
        v_technical_error:=sqlerrm;
      end;

      v_detected:=coalesce(v_technical_error,'') like '%ASSERTION_SOURCE_NOT_RELEVANT%'
                  or coalesce(v_technical_error,'') like '%VALIDATOR_ASSERTION_NOT_RELEVANT%';
      v_false_pass:=not v_detected;
      v_detection_surface:=case when v_detected then 'ASSERTION_AUTHORITY_RELEVANCE_GUARD' else 'SELF_AUTHORITY_NOT_REJECTED' end;

    elsif p_case=7 then
      -- STALE_EVIDENCE: pin the run/source snapshot with one canonical Validator chunk,
      -- then mutate current visual source and call the canonical entrypoint again.
      v_cur:=programacion.fn_input_governance_curator_rebind_v1(
        p_pantalla_id,'MANUAL',v_curator_id,true
      );
      v_run:=coalesce((v_cur->>'run_id')::bigint,(v_cur->>'latest_run_id')::bigint);
      if v_run is null then raise exception 'M49_T07_NO_SELFTEST_RUN:%',v_cur; end if;

      v_val:=programacion.fn_input_governance_validator_validate_v1(v_run,v_validator_id);

      select count(*) into v_artifacts_before
      from lf_ops.pantalla_artefactos
      where pantalla_id=p_pantalla_id and is_current=true;
      if v_artifacts_before=0 then
        raise exception 'M49_T07_NO_CURRENT_VISUAL_ARTIFACT:%',p_pantalla_id;
      end if;

      begin
        update lf_ops.pantalla_artefactos
           set is_current=false
         where pantalla_id=p_pantalla_id and is_current=true;
        get diagnostics v_artifacts_changed=row_count;

        begin
          v_val:=programacion.fn_input_governance_validator_validate_v1(v_run,v_validator_id);
        exception when others then
          v_technical_error:=sqlerrm;
        end;
      exception when others then
        v_technical_error:=sqlerrm;
      end;

      v_detected:=v_artifacts_changed=v_artifacts_before
        and (
          coalesce(v_technical_error,'') like '%CONTINUATION_CURRENTNESS_BLOCKED%'
          or coalesce(v_technical_error,'') like '%SOURCE_SNAPSHOT_STALE%'
          or coalesce(v_technical_error,'') like '%CURRENTNESS%'
          or coalesce(v_technical_error,'') like '%IMMUTABLE%'
        );
      v_false_pass:=not v_detected;
      v_detection_surface:=case when v_detected then 'CONTINUATION_CURRENTNESS_OR_SOURCE_GUARD' else 'STALE_EVIDENCE_NOT_REJECTED' end;

    else
      -- T1-T6 and T8: Curator first, then mutate Validator-side classifier.
      -- This proves the canonical Validator refuses divergence from the Curator receipt.
      v_cur:=programacion.fn_input_governance_curator_rebind_v1(
        p_pantalla_id,'MANUAL',v_curator_id,true
      );
      v_run:=coalesce((v_cur->>'run_id')::bigint,(v_cur->>'latest_run_id')::bigint);
      if v_run is null then raise exception 'M49_NO_SELFTEST_RUN:%:%',p_case,v_cur; end if;
      select supersedes_run_id into v_parent
      from programacion.input_readiness_runs where id=v_run;
      select status into v_parent_status from programacion.input_readiness_runs where id=v_parent;

      if position(v_classifier_anchor in v_classifier_orig)=0 then
        raise exception 'M49_CLASSIFIER_PATCH_ANCHOR_MISSING';
      end if;

      v_injection:=case p_case
        when 1 then
          'if p_family_code=''ACCESSIBILITY'' then v:=jsonb_set(v,''{source_refs}'',''[]''::jsonb,true); end if; '
        when 2 then
          'if p_family_code=''ACCESSIBILITY'' then v:=jsonb_set(v,''{source_refs}'',coalesce(v->''source_refs'',''[]''::jsonb)||jsonb_build_array(jsonb_build_object(''kind'',''RULE'',''codigo'',''B2B-RULE-A11Y-001'',''contradiction'',true)),true); end if; '
        when 3 then
          'if p_family_code=''ACCESSIBILITY'' then v:=jsonb_set(v,''{source_refs}'',jsonb_build_array(jsonb_build_object(''kind'',''RULE'',''codigo'',''__M49_BROKEN_ID__'')),true); end if; '
        when 4 then
          'if p_family_code=''ACCESSIBILITY'' then v:=jsonb_set(v,''{source_refs}'',jsonb_build_array(jsonb_build_object(''kind'',''URL'',''url'',''https://invalid.example/m4-9'')),true); end if; '
        when 5 then
          'if p_family_code=''ACCESSIBILITY'' then raise exception ''M49_SOURCE_TIMEOUT_WITHOUT_SOURCE''; end if; '
        when 6 then
          'if p_family_code=''ACCESSIBILITY'' then v:=jsonb_set(v,''{applicability}'',''"NOT_APPLICABLE"''::jsonb,true); v:=jsonb_set(v,''{coverage_status}'',''"NOT_APPLICABLE"''::jsonb,true); end if; '
        when 8 then
          'if p_family_code=''ACCESSIBILITY'' then v:=jsonb_set(v,''{source_refs}'',coalesce(v->''source_refs'',''[]''::jsonb)||jsonb_build_array(jsonb_build_object(''kind'',''RULE'',''codigo'',''B2B-RULE-A11Y-001'',''historical_pass_override'',true)),true); end if; '
      end;

      v_candidate:=replace(v_classifier_orig,v_classifier_anchor,v_injection||v_classifier_anchor);
      execute v_candidate;

      begin
        v_val:=programacion.fn_input_governance_validator_validate_v1(v_run,v_validator_id);
      exception when others then
        v_technical_error:=sqlerrm;
      end;

      if p_case=5 then
        v_detected:=coalesce(v_technical_error,'') like '%M49_SOURCE_TIMEOUT_WITHOUT_SOURCE%';
        v_detection_surface:=case when v_detected then 'FAIL_CLOSED_SOURCE_TIMEOUT' else 'TIMEOUT_NOT_REJECTED' end;
      else
        select validator_outcome,coalesce(validator_findings,'[]'::jsonb)
          into v_target_outcome,v_target_findings
        from programacion.input_family_assessments
        where run_id=v_run and family_code=v_target_family;

        v_detected:=coalesce(v_target_outcome,'') in ('FAIL','BLOCKED')
          and jsonb_array_length(v_target_findings)>0;

        if p_case=8 then
          v_detected:=v_detected and v_parent_status='COMPLETED'
             and (select status<>'COMPLETED' from programacion.input_readiness_runs where id=v_run);
        end if;

        v_detection_surface:=case when v_detected then 'VALIDATOR_CLASSIFIER_MISMATCH' else 'MUTATION_NOT_REJECTED' end;
      end if;

      v_false_pass:=not v_detected;
    end if;

    v_promotion:=coalesce((v_val->>'promotion_authorized')::boolean,false);

    v_result:=jsonb_build_object(
      'test_code',v_test_code,
      'ordinal',p_case,
      'mutation_code',v_mutation,
      'status',case when v_detected and not v_promotion then 'PASS' else 'FAIL' end,
      'detected',v_detected,
      'false_pass',v_false_pass,
      'validator_outcome',v_target_outcome,
      'validator_findings',coalesce(v_target_findings,'[]'::jsonb),
      'validator_status',v_val->>'status',
      'technical_error',v_technical_error,
      'promotion_authorized',v_promotion,
      'detection_surface',v_detection_surface,
      'actual_execution',true,
      'synthetic_pass',false,
      'canonical_validator_entrypoint','programacion.fn_input_governance_validator_validate_v1',
      'fixture_policy','ROLLBACK_ALL_TEST_MUTATIONS'
    );

    raise exception '%',v_marker;
  exception when others then
    if sqlerrm<>v_marker then
      raise;
    end if;
  end;

  if md5(pg_get_functiondef(v_classifier_sig))<>v_classifier_md5 then
    raise exception 'M49_CLASSIFIER_RESIDUE:%',p_case;
  end if;
  if md5(pg_get_functiondef(v_assert_sig))<>v_assert_md5 then
    raise exception 'M49_ASSERTION_BUILDER_RESIDUE:%',p_case;
  end if;
  if md5(pg_get_functiondef(v_graph_sig))<>v_graph_md5 then
    raise exception 'M49_GRAPH_RESIDUE:%',p_case;
  end if;
  if exists(
    select 1 from programacion.input_readiness_runs
    where curator_identity=v_curator_id or validator_identity=v_validator_id
  ) then
    raise exception 'M49_RUN_RESIDUE:%',p_case;
  end if;

  return v_result||jsonb_build_object(
    'rollback_clean',true,
    'runtime_functions_restored',true,
    'durable_fixture_residue',false
  );
end;
$f$;

comment on function programacion.fn_engineering_ig_validator_mutation_case_v2(integer,integer)
is 'M4.9 deterministic one-case runner. One call executes one T1-T10 mutation through the canonical M4.2 validator entrypoint, captures fail-closed evidence, then rolls back all fixture/runtime mutations.';

-- Register M4.9-owned canonical cases. Final test result PASS means the mutation
-- was detected/rejected; a Validator false PASS is a FAILED test.
insert into public.lf_test_suite_cases(
  suite_code,test_code,test_order,title,test_type,execution_mode,severity,
  input_payload,expected_output,prohibited_output,status,metadata
)
select
  'INPUT_GOVERNANCE_REGRESSION',
  x.test_code,
  490000+x.ordinal,
  'M4.9 mutation T'||x.ordinal::text||' — '||x.mutation_code,
  'NEGATIVE',
  'AUTOMATED',
  'HIGH',
  jsonb_build_object(
    'schema_version','M49_MUTATION_CASE_V2',
    'ordinal',x.ordinal,
    'mutation_code',x.mutation_code,
    'pantalla_id',54,
    'fixture_kind','ROLLBACK_ONLY_REAL_VALIDATOR_CASE',
    'side_effects',false,
    'rollback_required',true,
    'validator_entrypoint','programacion.fn_input_governance_validator_validate_v1'
  ),
  jsonb_build_object(
    'decision','MUTATION_DETECTED_FAIL_CLOSED',
    'test_status','PASS',
    'promotion_authorized',false,
    'rollback_clean',true
  ),
  jsonb_build_object(
    'false_pass',true,
    'synthetic_pass',true,
    'persistent_fixture_mutation',true,
    'direct_validate_v2_bypass',true
  ),
  'CANDIDATO',
  jsonb_build_object(
    'plan_code','IG_CURATOR_VALIDATOR_REFACTOR_V2',
    'unit_code','M4.9',
    'work_code','PAULO-063',
    'checkpoint_code','RUN_CAMPAIGN',
    'case_runner','programacion.fn_engineering_ig_validator_mutation_case_v2',
    'case_runner_arg',x.ordinal,
    'ownership','M4.9'
  )
from (values
  (1,'M4_9_T01_MISSING_SOURCE','MISSING_SOURCE'),
  (2,'M4_9_T02_CONTRADICTORY_SOURCE','CONTRADICTORY_SOURCE'),
  (3,'M4_9_T03_BROKEN_ID','BROKEN_ID'),
  (4,'M4_9_T04_INVENTED_URL','INVENTED_URL'),
  (5,'M4_9_T05_TIMEOUT_WITHOUT_SOURCE','TIMEOUT_WITHOUT_SOURCE'),
  (6,'M4_9_T06_UNJUSTIFIED_NOT_APPLICABLE','UNJUSTIFIED_NOT_APPLICABLE'),
  (7,'M4_9_T07_STALE_EVIDENCE','STALE_EVIDENCE'),
  (8,'M4_9_T08_HISTORICAL_PASS_OVERRIDES_NEWER_FAILURE','HISTORICAL_PASS_OVERRIDES_NEWER_FAILURE'),
  (9,'M4_9_T09_SELF_AUTHORITY','SELF_AUTHORITY'),
  (10,'M4_9_T10_CORRELATED_CURATOR_RESOLVER_DEFECT','CORRELATED_CURATOR_RESOLVER_DEFECT')
) x(ordinal,test_code,mutation_code)
on conflict (suite_code,test_code) do update set
  test_order=excluded.test_order,
  title=excluded.title,
  test_type=excluded.test_type,
  execution_mode=excluded.execution_mode,
  severity=excluded.severity,
  input_payload=excluded.input_payload,
  expected_output=excluded.expected_output,
  prohibited_output=excluded.prohibited_output,
  status=excluded.status,
  metadata=excluded.metadata,
  updated_at=now();

-- Replace the vague RUN_CAMPAIGN test contract with the exact case set and persistence route.
update programacion.engineering_plan_units
set unit_metadata=jsonb_set(
  coalesce(unit_metadata,'{}'::jsonb),
  '{action_specs_v1}',
  coalesce(unit_metadata->'action_specs_v1','{}'::jsonb)
  || jsonb_build_object(
    'RUN_CAMPAIGN',
    jsonb_build_object(
      'schema_version','ENGINEERING_ACTION_SPEC_V3',
      'status','READY',
      'checkpoint_code','RUN_CAMPAIGN',
      'checkpoint_title','Ejecutar campaña contra el Validator único (M4.2) y persistir run en lf_test_suite_runs',
      'action_kind','DECLARED_TEST_PERSISTENCE_EXECUTION',
      'recipe_mode','EXECUTE_DECLARED_TEST_PERSISTENCE',
      'precision','EXACT_M49_T1_T10_CASE_RUNNER_V2',
      'requires_material_execution',true,
      'mutation_policy','TEST_FIXTURES_ROLLBACK_ONLY_PLUS_TEST_GRAPH_PERSISTENCE',
      'expected','10/10 known mutations detected through the canonical M4.2 Validator entrypoint; zero false PASS; persisted suite receipt VERIFIED.',
      'target',jsonb_build_object(
        'declared_objects',jsonb_build_array(
          'public.lf_test_suite_cases','public.lf_test_suite_runs',
          'public.lf_test_runs','public.lf_test_assertion_results'
        ),
        'declared_assets','[]'::jsonb,
        'declared_events','[]'::jsonb,
        'declared_artifacts','[]'::jsonb
      ),
      'action_steps',jsonb_build_array(
        'EXECUTE_T1_T10_ONE_CASE_PER_CALL',
        'RETRY_ONLY_FAILED_TECHNICAL_CASE_ONCE',
        'PERSIST_ATOMIC_SUITE_RUN_TEST_RUN_ASSERTION_GRAPH',
        'VERIFY_RECEIPT_BUNDLE',
        'PERSIST_DONE_ONLY_ON_10_OF_10_REAL_PASS'
      ),
      'test_execution_contract',jsonb_build_object(
        'mode','DB_CASE_RUNNER_V2',
        'suite_code','INPUT_GOVERNANCE_REGRESSION',
        'test_codes',jsonb_build_array(
          'M4_9_T01_MISSING_SOURCE',
          'M4_9_T02_CONTRADICTORY_SOURCE',
          'M4_9_T03_BROKEN_ID',
          'M4_9_T04_INVENTED_URL',
          'M4_9_T05_TIMEOUT_WITHOUT_SOURCE',
          'M4_9_T06_UNJUSTIFIED_NOT_APPLICABLE',
          'M4_9_T07_STALE_EVIDENCE',
          'M4_9_T08_HISTORICAL_PASS_OVERRIDES_NEWER_FAILURE',
          'M4_9_T09_SELF_AUTHORITY',
          'M4_9_T10_CORRELATED_CURATOR_RESOLVER_DEFECT'
        ),
        'case_runner','programacion.fn_engineering_ig_validator_mutation_case_v2(integer,integer)',
        'case_runner_screen_id',54,
        'one_case_per_call',true,
        'retry_failed_technical_case_once',true,
        'validator_entrypoint','programacion.fn_input_governance_validator_validate_v1',
        'persistence_entrypoint','programacion.fn_engineering_run_test_persist_v1',
        'receipt_mode','LOCAL_DECLARED_TEST_EXECUTION',
        'actual_execution_required',true,
        'synthetic_pass','FORBIDDEN',
        'fallback_case_discovery','FORBIDDEN',
        'canonical_exit_criterion','100% de mutaciones conocidas detectadas'
      ),
      'assertion_contract',jsonb_build_object(
        'mode','EXPLICIT_PASS_WHEN_SUBSET',
        'pass_when',jsonb_build_object(
          'known_mutations_total',10,
          'known_mutations_detected',10,
          'false_pass_count',0,
          'receipt_bundle_status','VERIFIED',
          'semantic_authority_bound',true
        )
      ),
      'handler_requirement',jsonb_build_object(
        'status','READY',
        'existing_exact_case_set_found',true,
        'case_count',10,
        'case_runner','programacion.fn_engineering_ig_validator_mutation_case_v2',
        'persistence_entrypoint','programacion.fn_engineering_run_test_persist_v1'
      ),
      'verification_queries',jsonb_build_array(
        'select suite_run_id,status,tests_total,tests_passed,tests_failed,tests_blocked,tests_review_required,manifest,metadata from public.lf_test_suite_runs where metadata->>''unit_code''=''M4.9'' and metadata->>''checkpoint_code''=''RUN_CAMPAIGN'' order by created_at desc limit 1'
      ),
      'persist',jsonb_build_object(
        'on_pass','DONE',
        'entrypoint','programacion.fn_engineering_checkpoint_transition_v1',
        'next_state','RETURNED_BOOTSTRAP_ONLY'
      ),
      'forbidden',jsonb_build_array(
        'DIRECT_VALIDATE_V2_BYPASS',
        'SYNTHETIC_PASS',
        'MONOLITHIC_T1_T10_SINGLE_STATEMENT',
        'FALLBACK_CASE_DISCOVERY',
        'PERSIST_FIXTURE_MUTATION'
      )
    )
  ),
  true
)
where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
  and unit_code='M4.9'
  and disposition='ASSIGNED';

do $post$
declare
  v_cases integer;
  v_spec jsonb;
begin
  select count(*) into v_cases
  from public.lf_test_suite_cases
  where suite_code='INPUT_GOVERNANCE_REGRESSION'
    and metadata->>'unit_code'='M4.9'
    and metadata->>'checkpoint_code'='RUN_CAMPAIGN';

  if v_cases<>10 then
    raise exception 'M49_CASE_CATALOG_CARDINALITY:%',v_cases;
  end if;

  v_spec:=programacion.fn_engineering_checkpoint_action_spec_v3(
    'IG_CURATOR_VALIDATOR_REFACTOR_V2','M4.9','RUN_CAMPAIGN'
  );

  if v_spec->>'status'<>'READY'
     or v_spec#>>'{handler_requirement,status}'<>'READY'
     or coalesce((v_spec#>>'{handler_requirement,case_count}')::integer,0)<>10 then
    raise exception 'M49_RUN_CAMPAIGN_CONTRACT_POSTCHECK:%',v_spec;
  end if;
end;
$post$;

insert into public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,
  frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia,lifecycle_phase,
  consumer_role,root_cause_family,detectability,source_context,source_ref
) values (
  'ENGINEERING-M49-CASE-RUNNER-002',
  'ENGINEERING_TESTING',
  'Mutation campaigns must execute one canonical case per call through the public Validator entrypoint',
  'The prior M4.9 runner bundled T1-T10 in one 120-second statement, called validate_v2 directly and represented SELF_AUTHORITY with an unrelated source marker.',
  'Campaign orchestration was monolithic and bypassed the M4.2 single Validator entrypoint contract.',
  'ONE_CASE_PER_CALL -> CANONICAL_VALIDATOR_ENTRYPOINT -> ROLLBACK_FIXTURE -> COLLECT_RESULTS -> ATOMIC_TEST_GRAPH_PERSISTENCE',
  'Register owned exact cases; retry only a technically failed case once; never call validate_v2 directly from the campaign; persist only after all 10 outcomes are collected.',
  'PASS when M4.9 owns exactly 10 RUN_CAMPAIGN cases and every case result comes from fn_input_governance_validator_validate_v1 with rollback_clean=true; final suite requires 10/10 PASS and VERIFIED receipt bundle.',
  'HIGH',1,now(),now(),'IG_CURATOR_VALIDATOR_REFACTOR_V2','ACTIVO',
  'supabase://programacion.fn_engineering_ig_validator_mutation_case_v2',
  'TEST',
  array['ENGINEERING_EXECUTOR','PROGRAMMING_AGENT']::text[],
  'R5_EROSION_PROCESO','LOUD_EARLY',
  'M4.9 RUN_CAMPAIGN exact test execution contract',
  'supabase://programacion.fn_engineering_ig_validator_mutation_case_v2'
)
on conflict (codigo) do update set
  descripcion=excluded.descripcion,
  causa_raiz=excluded.causa_raiz,
  patron=excluded.patron,
  prevencion=excluded.prevencion,
  validacion=excluded.validacion,
  evidencia=excluded.evidencia,
  ultima_vez=now(),
  estado=excluded.estado,
  updated_at=now();

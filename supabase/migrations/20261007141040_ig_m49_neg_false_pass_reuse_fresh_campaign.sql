
do $repair$
declare
  v_suite uuid;
  v_bundle jsonb;
  v_rows integer;
  v_spec jsonb;
begin
  select s.suite_run_id into v_suite
  from public.lf_test_suite_runs s
  where s.metadata->>'plan_code'='IG_CURATOR_VALIDATOR_REFACTOR_V2'
    and s.metadata->>'unit_code'='M4.9'
    and s.metadata->>'checkpoint_code'='RUN_CAMPAIGN'
    and s.status='PASSED'
    and s.tests_total=10
    and s.tests_passed=10
    and s.tests_failed=0
    and s.tests_blocked=0
    and s.tests_review_required=0
    and coalesce((s.manifest->>'false_pass_count')::integer,-1)=0
  order by s.created_at desc
  limit 1;

  if v_suite is null then
    raise exception 'M49_NEG_FALSE_PASS_REUSE_REQUIRES_FRESH_10_OF_10_SUITE';
  end if;

  v_bundle:=programacion.fn_engineering_run_test_receipt_bundle_v1(v_suite);
  if v_bundle->>'status'<>'VERIFIED' then
    raise exception 'M49_NEG_FALSE_PASS_REUSE_BUNDLE_NOT_VERIFIED:%',v_bundle;
  end if;

  update programacion.engineering_plan_units pu
     set unit_metadata=jsonb_set(
       coalesce(pu.unit_metadata,'{}'::jsonb),
       '{action_specs_v1}',
       coalesce(pu.unit_metadata->'action_specs_v1','{}'::jsonb)
       || jsonb_build_object(
         'NEG_FALSE_PASS',
         jsonb_build_object(
           'schema_version','ENGINEERING_ACTION_SPEC_V3',
           'status','READY',
           'checkpoint_code','NEG_FALSE_PASS',
           'checkpoint_title','Negativo: cada mutación conocida da FAIL; un falso PASS bloquea la unidad',
           'action_kind','VERIFY_QUERY_ONCE',
           'recipe_mode','VERIFY_EXACT',
           'precision','M49_FRESH_CAMPAIGN_RECEIPT_REUSE_V1',
           'requires_material_execution',false,
           'mutation_policy','NO_DOMAIN_MUTATION',
           'target',jsonb_build_object(
             'declared_objects',jsonb_build_array('public.lf_test_suite_runs','public.lf_test_runs','public.lf_test_assertion_results'),
             'declared_assets','[]'::jsonb,
             'declared_events','[]'::jsonb,
             'declared_artifacts','[]'::jsonb
           ),
           'expected','Reuse the fresh M4.9 RUN_CAMPAIGN only when it is PASSED 10/10, false_pass_count=0 and receipt bundle VERIFIED.',
           'verification_queries',jsonb_build_array(
             'with s as (select suite_run_id,status,tests_total,tests_passed,tests_failed,tests_blocked,tests_review_required,manifest from public.lf_test_suite_runs where metadata->>''plan_code''=''IG_CURATOR_VALIDATOR_REFACTOR_V2'' and metadata->>''unit_code''=''M4.9'' and metadata->>''checkpoint_code''=''RUN_CAMPAIGN'' order by created_at desc limit 1) select status,tests_total,tests_passed,tests_failed,tests_blocked,tests_review_required,coalesce((manifest->>''false_pass_count'')::integer,-1) false_pass_count,programacion.fn_engineering_run_test_receipt_bundle_v1(suite_run_id)->>''status'' receipt_bundle_status,''supabase://public.lf_test_suite_runs/''||suite_run_id::text evidence_ref from s'
           ),
           'assertion_contract',jsonb_build_object(
             'mode','EXPLICIT_PASS_WHEN_SUBSET',
             'pass_when',jsonb_build_object(
               'suite_status','PASSED',
               'tests_total',10,
               'tests_passed',10,
               'tests_failed',0,
               'tests_blocked',0,
               'tests_review_required',0,
               'false_pass_count',0,
               'receipt_bundle_status','VERIFIED',
               'semantic_authority_bound',true,
               'adversarial_case_executed',true
             )
           ),
           'persist',jsonb_build_object(
             'on_pass','DONE',
             'entrypoint','programacion.fn_engineering_checkpoint_transition_v1',
             'next_state','RETURNED_BOOTSTRAP_ONLY'
           ),
           'forbidden',jsonb_build_array(
             'RERUN_FRESH_10_OF_10_WITHOUT_DRIFT_TRIGGER',
             'SYNTHETIC_PASS',
             'INVENT_TEST_EXIT_CODE',
             'AUTHOR_REDUNDANT_GIT_TEST'
           ),
           'evidence_reuse_policy','FRESH_EXACT_RUN_CAMPAIGN_RECEIPT_ONLY'
         )
       ),
       true
     )
   where pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
     and pu.unit_code='M4.9'
     and pu.disposition='ASSIGNED'
     and pu.unit_metadata#>>'{action_specs_v1,NEG_FALSE_PASS,precision}'='BOUNDED_CHECKPOINT_TEST_AUTHORING_V1';

  get diagnostics v_rows=row_count;
  if v_rows<>1 then
    raise exception 'M49_NEG_FALSE_PASS_ACTION_SPEC_REPAIR_CARDINALITY:%',v_rows;
  end if;

  v_spec:=programacion.fn_engineering_checkpoint_action_spec_v3(
    'IG_CURATOR_VALIDATOR_REFACTOR_V2','M4.9','NEG_FALSE_PASS'
  );
  if v_spec->>'status'<>'READY'
     or v_spec->>'precision'<>'M49_FRESH_CAMPAIGN_RECEIPT_REUSE_V1' then
    raise exception 'M49_NEG_FALSE_PASS_ACTION_SPEC_POSTCHECK_FAILED:%',v_spec;
  end if;
end;
$repair$;

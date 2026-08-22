create or replace function programacion.fn_agent_task_execution_bundle(p_task_id bigint,p_base_head_sha text,p_source_snapshot_sha256 text)
returns jsonb
language plpgsql
stable
set search_path to 'pg_catalog','public','programacion'
as $function$
declare
  t programacion.agent_tasks%rowtype;
  f public.lf_functional_versions%rowtype;
  s public.lf_user_stories%rowtype;
  tc programacion.test_contracts%rowtype;
  dc programacion.agent_task_delivery_contracts%rowtype;
  r jsonb;
  v_spec jsonb;
  v_preimage jsonb;
  v_bundle_sha text;
  v_dep_ids bigint[];
begin
  if p_base_head_sha!~'^[0-9a-f]{40}$' or p_source_snapshot_sha256!~'^[0-9a-f]{64}$' then raise exception 'invalid source identity';end if;
  r:=programacion.fn_task_readiness(p_task_id);
  if not coalesce((r->>'ready_for_development')::boolean,false)then raise exception 'TASK_NOT_READY: %',r->'blockers';end if;
  if not coalesce((r->>'executable_now')::boolean,false)then raise exception 'TASK_WAITING_DEPENDENCIES: %',r->'waiting_on_task_ids';end if;
  select * into t from programacion.agent_tasks where id=p_task_id;
  select * into f from public.lf_functional_versions where id=t.functional_version_id;
  select * into s from public.lf_user_stories where story_code=f.story_code;
  select * into tc from programacion.test_contracts where task_id=t.id and status='SEALED';
  select * into dc from programacion.agent_task_delivery_contracts where task_id=t.id and status='SEALED';
  select coalesce(array_agg(depends_on_task_id order by depends_on_task_id),'{}'::bigint[]) into v_dep_ids from programacion.task_dependencies where task_id=t.id;

  v_spec:=jsonb_build_object(
    'schema_version',2,
    'task_id',t.task_code||'.v'||t.task_version,
    'objective',t.objective,
    'expected_change',dc.expected_change,
    'human_story',jsonb_build_object(
      'story_code',s.story_code,
      'title',s.title,
      'persona',s.persona,
      'need',s.need_statement,
      'benefit',s.benefit_statement,
      'dependencies',coalesce(s.dependencies,'[]'::jsonb),
      'technical_notes',coalesce(s.technical_notes,'{}'::jsonb)
    ),
    'functional_contract',jsonb_build_object('acceptance_criteria',f.acceptance_criteria,'invariants',f.invariants,'negative_controls',f.negative_controls,'source_rule_codes',to_jsonb(f.source_rule_codes)),
    'scope',jsonb_build_object('in_scope',dc.in_scope,'out_of_scope',dc.out_of_scope,'must_not_change',dc.must_not_change),
    'cases',jsonb_build_object('positive',dc.positive_cases,'edge',dc.edge_cases,'regression',dc.regression_cases),
    'dependency_resolution',dc.dependency_resolution,
    'dependency_task_ids',to_jsonb(v_dep_ids),
    'required_tests',dc.required_tests,
    'required_evidence',dc.required_evidence,
    'blocked_if',dc.blocked_if,
    'base_head_sha',p_base_head_sha,
    'source_snapshot_sha256',p_source_snapshot_sha256,
    'context_path_patterns',to_jsonb(t.context_path_patterns),
    'write_path_patterns',to_jsonb(t.write_path_patterns),
    'protected_path_patterns',to_jsonb(t.protected_path_patterns),
    'files_expected',to_jsonb(t.files_expected),
    'platform_refs',to_jsonb(t.platform_refs),
    'interface_refs',to_jsonb(t.interface_refs),
    'acceptance_commands',tc.visible_commands,
    'hidden_oracle_ref',tc.hidden_oracle_ref,
    'max_attempts',t.max_attempts,
    'max_patch_bytes',t.max_patch_bytes,
    'max_changed_files',t.max_changed_files,
    'max_context_bytes',t.max_context_bytes,
    'allow_deletions',t.allow_deletions
  );
  v_preimage:=jsonb_build_object(
    'request_ref','agent-task://'||t.id,
    'worker_task_spec',v_spec,
    'hidden_oracle_ref',tc.hidden_oracle_ref,
    'hidden_oracle_sha256',tc.hidden_oracle_sha256,
    'functional_version_sha256',f.content_sha256,
    'task_sha256',t.task_sha256,
    'delivery_contract_sha256',dc.contract_sha256,
    'test_contract_sha256',tc.contract_sha256,
    'readiness',r
  );
  v_bundle_sha:=programacion.fn_v09_sha256_jsonb(v_preimage);
  return v_preimage||jsonb_build_object('bundle_sha256',v_bundle_sha);
end;
$function$;
-- IG_CURATOR_VALIDATOR_REFACTOR_V2 / T-PRIVACY / PAULO-189
-- PRIVACY_MINIMALITY_GUARD transversal capability.
-- Scope: GENERIC_CONTRACT only.
-- Owner: SUPER_ADMIN. IG is a consumer.
-- No runtime/production activation. No consent/legal-authority engine.

create or replace function public.lf_privacy_minimality_guard_evaluate_v1(p_request jsonb)
returns jsonb
language plpgsql
immutable
security invoker
set search_path = pg_catalog, public
as $fn$
declare
  v_consumer_ref text;
  v_operation text;
  v_need_state text;
  v_need_ref text;
  v_authority_state text;
  v_authority_ref text;
  v_context_ref text;
  v_requested text[] := '{}'::text[];
  v_necessary text[] := '{}'::text[];
  v_excess text[] := '{}'::text[];
begin
  if p_request is null or jsonb_typeof(p_request) <> 'object' then
    return jsonb_build_object(
      'schema_version','LF_PRIVACY_MINIMALITY_GUARD_RESULT_V1',
      'state','UNKNOWN','code','INVALID_REQUEST',
      'authorized_to_proceed',false
    );
  end if;

  v_consumer_ref := nullif(btrim(coalesce(p_request->>'consumer_ref','')),'');
  v_operation := upper(btrim(coalesce(p_request->>'operation','')));

  if v_consumer_ref is null then
    return jsonb_build_object(
      'schema_version','LF_PRIVACY_MINIMALITY_GUARD_RESULT_V1',
      'state','UNKNOWN','code','CONSUMER_REF_REQUIRED',
      'authorized_to_proceed',false
    );
  end if;

  if v_operation not in ('COLLECT','READ','STORE','USE','SHARE','TRACK','PROCESS') then
    return jsonb_build_object(
      'schema_version','LF_PRIVACY_MINIMALITY_GUARD_RESULT_V1',
      'consumer_ref',v_consumer_ref,
      'state','UNKNOWN','code','OPERATION_INVALID',
      'authorized_to_proceed',false
    );
  end if;

  if jsonb_typeof(p_request->'need') is distinct from 'object' then
    return jsonb_build_object(
      'schema_version','LF_PRIVACY_MINIMALITY_GUARD_RESULT_V1',
      'consumer_ref',v_consumer_ref,'operation',v_operation,
      'state','UNKNOWN','code','NEED_EVIDENCE_REQUIRED',
      'authorized_to_proceed',false
    );
  end if;

  v_need_state := upper(btrim(coalesce(p_request#>>'{need,state}','')));
  v_need_ref := nullif(btrim(coalesce(p_request#>>'{need,ref}','')),'');

  if v_need_state not in ('DECLARED','NOT_DECLARED','UNKNOWN') then
    return jsonb_build_object(
      'schema_version','LF_PRIVACY_MINIMALITY_GUARD_RESULT_V1',
      'consumer_ref',v_consumer_ref,'operation',v_operation,
      'state','UNKNOWN','code','NEED_STATE_INVALID',
      'authorized_to_proceed',false
    );
  end if;

  if v_need_state = 'NOT_DECLARED' then
    return jsonb_build_object(
      'schema_version','LF_PRIVACY_MINIMALITY_GUARD_RESULT_V1',
      'consumer_ref',v_consumer_ref,'operation',v_operation,
      'state','BLOCK','code','NEED_NOT_DECLARED',
      'need_ref',v_need_ref,
      'authorized_to_proceed',false
    );
  end if;

  if v_need_state = 'UNKNOWN' then
    return jsonb_build_object(
      'schema_version','LF_PRIVACY_MINIMALITY_GUARD_RESULT_V1',
      'consumer_ref',v_consumer_ref,'operation',v_operation,
      'state','UNKNOWN','code','NEED_UNKNOWN',
      'need_ref',v_need_ref,
      'authorized_to_proceed',false
    );
  end if;

  if v_need_ref is null then
    return jsonb_build_object(
      'schema_version','LF_PRIVACY_MINIMALITY_GUARD_RESULT_V1',
      'consumer_ref',v_consumer_ref,'operation',v_operation,
      'state','UNKNOWN','code','NEED_REF_REQUIRED',
      'authorized_to_proceed',false
    );
  end if;

  if jsonb_typeof(p_request->'authority') is distinct from 'object' then
    return jsonb_build_object(
      'schema_version','LF_PRIVACY_MINIMALITY_GUARD_RESULT_V1',
      'consumer_ref',v_consumer_ref,'operation',v_operation,
      'state','UNKNOWN','code','AUTHORITY_EVIDENCE_REQUIRED',
      'need_ref',v_need_ref,
      'authorized_to_proceed',false
    );
  end if;

  v_authority_state := upper(btrim(coalesce(p_request#>>'{authority,state}','')));
  v_authority_ref := nullif(btrim(coalesce(p_request#>>'{authority,ref}','')),'');
  v_context_ref := nullif(btrim(coalesce(p_request#>>'{authority,context_ref}','')),'');

  if v_authority_state not in ('VALID','INVALID','UNKNOWN') then
    return jsonb_build_object(
      'schema_version','LF_PRIVACY_MINIMALITY_GUARD_RESULT_V1',
      'consumer_ref',v_consumer_ref,'operation',v_operation,
      'state','UNKNOWN','code','AUTHORITY_STATE_INVALID',
      'need_ref',v_need_ref,
      'authorized_to_proceed',false
    );
  end if;

  if v_authority_state = 'INVALID' then
    return jsonb_build_object(
      'schema_version','LF_PRIVACY_MINIMALITY_GUARD_RESULT_V1',
      'consumer_ref',v_consumer_ref,'operation',v_operation,
      'state','BLOCK','code','AUTHORITY_INVALID',
      'need_ref',v_need_ref,'authority_ref',v_authority_ref,
      'authority_context_ref',v_context_ref,
      'authorized_to_proceed',false
    );
  end if;

  if v_authority_state = 'UNKNOWN' then
    return jsonb_build_object(
      'schema_version','LF_PRIVACY_MINIMALITY_GUARD_RESULT_V1',
      'consumer_ref',v_consumer_ref,'operation',v_operation,
      'state','UNKNOWN','code','AUTHORITY_UNKNOWN',
      'need_ref',v_need_ref,'authority_ref',v_authority_ref,
      'authority_context_ref',v_context_ref,
      'authorized_to_proceed',false
    );
  end if;

  if v_authority_ref is null then
    return jsonb_build_object(
      'schema_version','LF_PRIVACY_MINIMALITY_GUARD_RESULT_V1',
      'consumer_ref',v_consumer_ref,'operation',v_operation,
      'state','UNKNOWN','code','AUTHORITY_REF_REQUIRED',
      'need_ref',v_need_ref,
      'authorized_to_proceed',false
    );
  end if;

  if jsonb_typeof(p_request->'requested_items') is distinct from 'array'
     or jsonb_typeof(p_request->'necessary_items') is distinct from 'array' then
    return jsonb_build_object(
      'schema_version','LF_PRIVACY_MINIMALITY_GUARD_RESULT_V1',
      'consumer_ref',v_consumer_ref,'operation',v_operation,
      'state','UNKNOWN','code','ITEM_ARRAYS_REQUIRED',
      'need_ref',v_need_ref,'authority_ref',v_authority_ref,
      'authorized_to_proceed',false
    );
  end if;

  if exists (
       select 1 from jsonb_array_elements(p_request->'requested_items') e(value)
       where jsonb_typeof(e.value) <> 'string'
     )
     or exists (
       select 1 from jsonb_array_elements(p_request->'necessary_items') e(value)
       where jsonb_typeof(e.value) <> 'string'
     ) then
    return jsonb_build_object(
      'schema_version','LF_PRIVACY_MINIMALITY_GUARD_RESULT_V1',
      'consumer_ref',v_consumer_ref,'operation',v_operation,
      'state','UNKNOWN','code','ITEM_IDENTIFIERS_MUST_BE_STRINGS',
      'need_ref',v_need_ref,'authority_ref',v_authority_ref,
      'authorized_to_proceed',false
    );
  end if;

  if exists (
       select 1 from jsonb_array_elements_text(p_request->'requested_items') t(v)
       where nullif(btrim(v),'') is null
     )
     or exists (
       select 1 from jsonb_array_elements_text(p_request->'necessary_items') t(v)
       where nullif(btrim(v),'') is null
     ) then
    return jsonb_build_object(
      'schema_version','LF_PRIVACY_MINIMALITY_GUARD_RESULT_V1',
      'consumer_ref',v_consumer_ref,'operation',v_operation,
      'state','UNKNOWN','code','ITEM_IDENTIFIER_EMPTY',
      'need_ref',v_need_ref,'authority_ref',v_authority_ref,
      'authorized_to_proceed',false
    );
  end if;

  select coalesce(array_agg(distinct btrim(v) order by btrim(v)),'{}'::text[])
    into v_requested
  from jsonb_array_elements_text(p_request->'requested_items') t(v);

  select coalesce(array_agg(distinct btrim(v) order by btrim(v)),'{}'::text[])
    into v_necessary
  from jsonb_array_elements_text(p_request->'necessary_items') t(v);

  select coalesce(array_agg(x order by x),'{}'::text[])
    into v_excess
  from (
    select unnest(v_requested) x
    except
    select unnest(v_necessary) x
  ) q;

  if cardinality(v_excess) > 0 then
    return jsonb_build_object(
      'schema_version','LF_PRIVACY_MINIMALITY_GUARD_RESULT_V1',
      'consumer_ref',v_consumer_ref,'operation',v_operation,
      'state','BLOCK','code','OVERTRACKING',
      'need_ref',v_need_ref,
      'authority_ref',v_authority_ref,
      'authority_context_ref',v_context_ref,
      'requested_items',to_jsonb(v_requested),
      'necessary_items',to_jsonb(v_necessary),
      'excess_items',to_jsonb(v_excess),
      'requested_count',cardinality(v_requested),
      'necessary_count',cardinality(v_necessary),
      'excess_count',cardinality(v_excess),
      'authorized_to_proceed',false
    );
  end if;

  return jsonb_build_object(
    'schema_version','LF_PRIVACY_MINIMALITY_GUARD_RESULT_V1',
    'consumer_ref',v_consumer_ref,'operation',v_operation,
    'state','PASS',
    'code',case when cardinality(v_requested)=0 then 'NO_DATA_REQUESTED' else 'MINIMALITY_SATISFIED' end,
    'need_ref',v_need_ref,
    'authority_ref',v_authority_ref,
    'authority_context_ref',v_context_ref,
    'requested_items',to_jsonb(v_requested),
    'necessary_items',to_jsonb(v_necessary),
    'excess_items','[]'::jsonb,
    'requested_count',cardinality(v_requested),
    'necessary_count',cardinality(v_necessary),
    'excess_count',0,
    'authorized_to_proceed',true
  );
end
$fn$;

comment on function public.lf_privacy_minimality_guard_evaluate_v1(jsonb)
is 'T-PRIVACY generic need + authority + minimality judge. It does not determine legal authority, consent, or database access permissions.';

create or replace function public.lf_privacy_minimality_guard_result_valid_v1(p_result jsonb)
returns boolean
language sql
immutable
security invoker
set search_path = pg_catalog, public
as $fn$
select
  p_result is not null
  and jsonb_typeof(p_result)='object'
  and p_result->>'schema_version'='LF_PRIVACY_MINIMALITY_GUARD_RESULT_V1'
  and p_result->>'state' in ('PASS','BLOCK','UNKNOWN')
  and jsonb_typeof(p_result->'authorized_to_proceed')='boolean'
  and (
    ((p_result->>'state')='PASS' and (p_result->>'authorized_to_proceed')::boolean is true)
    or
    ((p_result->>'state') in ('BLOCK','UNKNOWN') and (p_result->>'authorized_to_proceed')::boolean is false)
  );
$fn$;

comment on function public.lf_privacy_minimality_guard_result_valid_v1(jsonb)
is 'Structural validator for LF_PRIVACY_MINIMALITY_GUARD_RESULT_V1.';

do $register$
declare
  v_execution_id constant text := 'CHATGPT-T-PRIVACY-PAULO-189-20261006';
  v_manifest jsonb;
  v_manifest_sha text;
  v_existing_sha text;
  v_promote jsonb;
begin
  v_manifest := jsonb_build_object(
    'schema_version','LF_CAPABILITY_MANIFEST_V1',
    'capability_code','PRIVACY_MINIMALITY_GUARD',
    'version','1.0.0',
    'owner','SUPER_ADMIN',
    'contract',jsonb_build_object(
      'input','LF_PRIVACY_MINIMALITY_GUARD_REQUEST_V1',
      'output','LF_PRIVACY_MINIMALITY_GUARD_RESULT_V1',
      'states',jsonb_build_array('PASS','BLOCK','UNKNOWN'),
      'decision_rule','PASS only when need is DECLARED with ref, authority is VALID with ref, and requested_items is a subset of necessary_items',
      'unknown_is_authorization',false,
      'authority_semantics','CALLER_PROVEN; THIS CAPABILITY DOES NOT DETERMINE LEGAL BASIS OR CONSENT',
      'overtracking_negative_contract','requested_items minus necessary_items non-empty => BLOCK/OVERTRACKING'
    ),
    'delivery',jsonb_build_object(
      'mode','SUPABASE_NATIVE_READ_ONLY_JUDGE',
      'evaluate_function','public.lf_privacy_minimality_guard_evaluate_v1',
      'validator_function','public.lf_privacy_minimality_guard_result_valid_v1',
      'runtime_mutation',false
    ),
    'installation',jsonb_build_object(
      'required',false,
      'reinstall_required',false,
      'package_update_mode','DATABASE_NATIVE_CUTOVER'
    ),
    'dependencies',jsonb_build_object(
      'hard','{}'::jsonb,
      'composes_with',jsonb_build_array(
        'DECISION_CONTEXT_ASOF',
        'CURRENTNESS_AUTHORITY',
        'TYPED_EVIDENCE_REGISTRY',
        'TYPED_DATA_ACCESS'
      )
    ),
    'compatibility',jsonb_build_object(
      'domain_agnostic',true,
      'ig_role','CONSUMER',
      'ig_owner',false,
      'direct_legal_authority_decision',false,
      'consent_management',false,
      'database_permission_management',false,
      'duplicates_typed_data_access',false,
      'production_activation',false,
      'runtime_activation',false
    ),
    'migration',jsonb_build_object(
      'plan_code','IG_CURATOR_VALIDATOR_REFACTOR_V2',
      'unit_code','T-PRIVACY',
      'work_code','PAULO-189',
      'checkpoint_code','GENERIC_CONTRACT',
      'mode','CAPABILITY_REGISTRY_CURRENTNESS_PLUS_READ_ONLY_JUDGE'
    ),
    'rollback',jsonb_build_object(
      'supported',true,
      'mode','TRANSACTIONAL_SOURCE_ROLLBACK',
      'rule','remove only PRIVACY_MINIMALITY_GUARD v1/current/registry/functions created by this migration'
    ),
    'usage',jsonb_build_object(
      'entrypoint','public.fn_lf_capability_bind_from_orchestrator_v1',
      'evaluate','public.lf_privacy_minimality_guard_evaluate_v1',
      'validator','public.lf_privacy_minimality_guard_result_valid_v1',
      'input_operations',jsonb_build_array('COLLECT','READ','STORE','USE','SHARE','TRACK','PROCESS'),
      'item_identity','OPAQUE_CANONICAL_ITEM_ID'
    ),
    'currentness',jsonb_build_object(
      'entry_guard_required',true,
      'entry_guard_code','ORCHESTRATOR_EXECUTION_GUARD_V1',
      'history_authorization_forbidden',true,
      'current_pointer_authority','public.lf_capability_current'
    )
  );

  v_manifest_sha := encode(
    extensions.digest(convert_to(v_manifest::text,'UTF8'),'sha256'),
    'hex'
  );

  insert into public.lf_capability_registry(
    capability_code,capability_name,capability_kind,owner_scope,status,description,
    created_by_execution_id,updated_by_execution_id,entry_guard_required,entry_guard_code
  ) values (
    'PRIVACY_MINIMALITY_GUARD',
    'Privacy Minimality Guard',
    'TRANSVERSAL',
    'SUPER_ADMIN',
    'ACTIVE',
    'Domain-agnostic need + authority + minimality judge that blocks unnecessary data/tracking without deciding legal authority.',
    v_execution_id,
    v_execution_id,
    true,
    'ORCHESTRATOR_EXECUTION_GUARD_V1'
  )
  on conflict(capability_code) do update set
    capability_name=excluded.capability_name,
    capability_kind=excluded.capability_kind,
    owner_scope=excluded.owner_scope,
    status=excluded.status,
    description=excluded.description,
    updated_at=clock_timestamp(),
    updated_by_execution_id=excluded.updated_by_execution_id,
    entry_guard_required=excluded.entry_guard_required,
    entry_guard_code=excluded.entry_guard_code;

  select manifest_sha256 into v_existing_sha
  from public.lf_capability_version_registry
  where capability_code='PRIVACY_MINIMALITY_GUARD' and version='1.0.0';

  if v_existing_sha is not null and v_existing_sha <> v_manifest_sha then
    raise exception 'BLOCK_T_PRIVACY_CAPABILITY_VERSION_MANIFEST_CONFLICT';
  end if;

  insert into public.lf_capability_version_registry(
    capability_code,version,version_major,version_minor,version_patch,
    release_state,supersedes_version,manifest,manifest_sha256,
    source_ref,docs_ref,validator_ref,created_by_execution_id
  ) values (
    'PRIVACY_MINIMALITY_GUARD','1.0.0',1,0,0,
    'RELEASED',null,v_manifest,v_manifest_sha,
    'supabase://public/lf_privacy_minimality_guard_evaluate_v1',
    'github://cristhianlujan/claude-persona-lf-patch/sandbox/lf_contract_gate_test/transversal_assets/privacy_minimality_guard/README.md',
    'supabase://public/lf_privacy_minimality_guard_result_valid_v1',
    v_execution_id
  )
  on conflict(capability_code,version) do nothing;

  v_promote := public.fn_lf_capability_promote_v1(
    'PRIVACY_MINIMALITY_GUARD',
    '1.0.0',
    null,
    v_execution_id,
    'T-PRIVACY materializes generic need + authority + minimality guard; no runtime or production activation.'
  );

  if coalesce((v_promote->>'ready')::boolean,false) is not true then
    raise exception 'BLOCK_T_PRIVACY_CURRENT_PROMOTION:%',v_promote::text;
  end if;

  if not exists(
    select 1
    from public.lf_capability_registry r
    join public.lf_capability_current c using(capability_code)
    where r.capability_code='PRIVACY_MINIMALITY_GUARD'
      and r.status='ACTIVE'
      and r.owner_scope='SUPER_ADMIN'
      and r.entry_guard_required=true
      and r.entry_guard_code='ORCHESTRATOR_EXECUTION_GUARD_V1'
      and c.version='1.0.0'
      and c.manifest_sha256=v_manifest_sha
  ) then
    raise exception 'BLOCK_T_PRIVACY_CAPABILITY_READBACK_FAILED';
  end if;
end
$register$;

do $tests$
declare
  v_pass jsonb;
  v_no_need jsonb;
  v_bad_authority jsonb;
  v_unknown jsonb;
  v_overtracking jsonb;
begin
  v_pass := public.lf_privacy_minimality_guard_evaluate_v1(
    jsonb_build_object(
      'consumer_ref','EDGE_FN_INPUT_GOVERNANCE_AGENT_V1',
      'operation','READ',
      'need',jsonb_build_object('state','DECLARED','ref','need://ig/evaluate-input'),
      'authority',jsonb_build_object(
        'state','VALID',
        'ref','authority://policy/input-governance',
        'context_ref','decision-context://ig/current'
      ),
      'requested_items',jsonb_build_array('field_a','field_b'),
      'necessary_items',jsonb_build_array('field_a','field_b','field_c')
    )
  );
  if v_pass->>'state' <> 'PASS'
     or coalesce((v_pass->>'authorized_to_proceed')::boolean,false) is not true
     or public.lf_privacy_minimality_guard_result_valid_v1(v_pass) is not true then
    raise exception 'BLOCK_T_PRIVACY_POSITIVE:%',v_pass::text;
  end if;

  v_no_need := public.lf_privacy_minimality_guard_evaluate_v1(
    jsonb_build_object(
      'consumer_ref','EDGE_FN_INPUT_GOVERNANCE_AGENT_V1',
      'operation','TRACK',
      'need',jsonb_build_object('state','NOT_DECLARED'),
      'authority',jsonb_build_object('state','VALID','ref','authority://policy/input-governance'),
      'requested_items',jsonb_build_array('behavioral_signal'),
      'necessary_items','[]'::jsonb
    )
  );
  if v_no_need->>'state' <> 'BLOCK' or v_no_need->>'code' <> 'NEED_NOT_DECLARED' then
    raise exception 'BLOCK_T_PRIVACY_NEG_NO_NEED_FALSE_GREEN:%',v_no_need::text;
  end if;

  v_bad_authority := public.lf_privacy_minimality_guard_evaluate_v1(
    jsonb_build_object(
      'consumer_ref','EDGE_FN_INPUT_GOVERNANCE_AGENT_V1',
      'operation','USE',
      'need',jsonb_build_object('state','DECLARED','ref','need://ig/evaluate-input'),
      'authority',jsonb_build_object('state','INVALID','ref','authority://denied'),
      'requested_items',jsonb_build_array('field_a'),
      'necessary_items',jsonb_build_array('field_a')
    )
  );
  if v_bad_authority->>'state' <> 'BLOCK' or v_bad_authority->>'code' <> 'AUTHORITY_INVALID' then
    raise exception 'BLOCK_T_PRIVACY_NEG_AUTHORITY_FALSE_GREEN:%',v_bad_authority::text;
  end if;

  v_unknown := public.lf_privacy_minimality_guard_evaluate_v1(
    jsonb_build_object(
      'consumer_ref','GITHUB_CONTRACT_GATE_LF',
      'operation','READ',
      'need',jsonb_build_object('state','DECLARED','ref','need://contract-check/evidence'),
      'authority',jsonb_build_object('state','UNKNOWN'),
      'requested_items',jsonb_build_array('evidence_ref'),
      'necessary_items',jsonb_build_array('evidence_ref')
    )
  );
  if v_unknown->>'state' <> 'UNKNOWN'
     or coalesce((v_unknown->>'authorized_to_proceed')::boolean,true) is not false then
    raise exception 'BLOCK_T_PRIVACY_UNKNOWN_AUTHORIZED:%',v_unknown::text;
  end if;

  v_overtracking := public.lf_privacy_minimality_guard_evaluate_v1(
    jsonb_build_object(
      'consumer_ref','GITHUB_CONTRACT_GATE_LF',
      'operation','TRACK',
      'need',jsonb_build_object('state','DECLARED','ref','need://contract-check/health'),
      'authority',jsonb_build_object('state','VALID','ref','authority://contract-check'),
      'requested_items',jsonb_build_array('required_signal','extra_behavioral_signal'),
      'necessary_items',jsonb_build_array('required_signal')
    )
  );
  if v_overtracking->>'state' <> 'BLOCK'
     or v_overtracking->>'code' <> 'OVERTRACKING'
     or (v_overtracking->'excess_items') <> jsonb_build_array('extra_behavioral_signal') then
    raise exception 'BLOCK_T_PRIVACY_OVERTRACKING_FALSE_GREEN:%',v_overtracking::text;
  end if;
end
$tests$;

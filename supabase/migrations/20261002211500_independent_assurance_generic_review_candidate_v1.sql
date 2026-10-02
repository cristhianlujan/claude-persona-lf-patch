-- INDEPENDENT_ASSURANCE generic review candidate v1
-- owner: SUPER_ADMIN
-- executor unit: T-INDEP / PAULO-035
-- lifecycle: CANDIDATE / READ_ONLY; this migration does NOT cut over or activate routing.
-- existing Strategy specialization remains operational until governed qualification/cutover.

-- -----------------------------------------------------------------------------
-- Candidate operation + route. No active route is created by this migration.
-- -----------------------------------------------------------------------------
insert into public.lf_operation_registry(
  operation_code,version,status,source_model,source_repo,source_paths,notes,
  operation_family,operation_domain,operation_type,applies_to_asset_type,
  created_by_execution_id,lifecycle_state_code
) values (
  'REVISION_INDEPENDIENTE_LF','v1.0','CANDIDATO_READ_ONLY','GIT_FIRST_YAML',
  'cristhianlujan/claude-persona-lf-patch',
  jsonb_build_array('supabase/migrations/20261002211500_independent_assurance_generic_review_candidate_v1.sql'),
  'T-INDEP generic subject candidate for INDEPENDENT_ASSURANCE. No production/runtime cutover.',
  'GOVERNANCE','INDEPENDENT_ASSURANCE','INDEPENDENT_REVIEW','REVIEW_SUBJECT',
  'CHATGPT-T-INDEP-PAULO-035-20261002','OP_CANDIDATE'
)
on conflict (operation_code) do update set
  version=excluded.version,
  status=excluded.status,
  source_model=excluded.source_model,
  source_repo=excluded.source_repo,
  source_paths=excluded.source_paths,
  notes=excluded.notes,
  operation_family=excluded.operation_family,
  operation_domain=excluded.operation_domain,
  operation_type=excluded.operation_type,
  applies_to_asset_type=excluded.applies_to_asset_type,
  lifecycle_state_code=excluded.lifecycle_state_code,
  updated_at=clock_timestamp(),
  updated_by_execution_id='CHATGPT-T-INDEP-PAULO-035-20261002';

insert into public.lf_router_action_registry(
  asset_type,action_code,operation_code,operation_resolution,
  requires_existing_target,requires_missing_target,write_allowed,status,notes,
  created_by_execution_id
) values (
  'REVIEW_SUBJECT','INDEPENDENT_REVIEW','REVISION_INDEPENDIENTE_LF','STATIC',
  false,false,false,'CANDIDATO_READ_ONLY',
  'Candidate generic route for INDEPENDENT_ASSURANCE. Must remain inactive until qualification/cutover.',
  'CHATGPT-T-INDEP-PAULO-035-20261002'
)
on conflict (asset_type,action_code) do update set
  operation_code=excluded.operation_code,
  operation_resolution=excluded.operation_resolution,
  requires_existing_target=excluded.requires_existing_target,
  requires_missing_target=excluded.requires_missing_target,
  write_allowed=excluded.write_allowed,
  status=excluded.status,
  notes=excluded.notes,
  updated_at=clock_timestamp(),
  updated_by_execution_id='CHATGPT-T-INDEP-PAULO-035-20261002';

insert into public.lf_operation_contracts(
  operation_code,contract_code,contract_path,required_before_write,allowed,blocked,
  required_after_write,status,created_by_execution_id
) values (
  'REVISION_INDEPENDIENTE_LF','CONTRACT-REVISION-INDEPENDIENTE-LF-v1',
  'supabase/migrations/20261002211500_independent_assurance_generic_review_candidate_v1.sql',
  jsonb_build_array(
    'exact_verified_subject_receipt','verified_producer_dependency_manifest',
    'verified_reviewer_dependency_manifest','producer_reviewer_separation',
    'material_dependency_measurement'
  ),
  jsonb_build_object(
    'read_only',true,'business_write_allowed',false,'runtime_activation',false,
    'production_activation',false,'qualification_implicit',false,
    'evidence_ledger_subject_binding_required',true,'real_oracle_independence_required',true
  ),
  jsonb_build_array(
    'unverified_subject','stale_subject_binding','producer_equals_reviewer',
    'unmeasurable_dependency_manifest','pass_with_unadjudicated_shared_material_dependency',
    'hardcoded_strategy_fallback','business_write','runtime_activation','production_activation'
  ),
  jsonb_build_array('durable_review_receipt','authority_readback','dependency_set_digests'),
  'CANDIDATO_READ_ONLY','CHATGPT-T-INDEP-PAULO-035-20261002'
)
on conflict (operation_code,contract_code) do update set
  contract_path=excluded.contract_path,
  required_before_write=excluded.required_before_write,
  allowed=excluded.allowed,
  blocked=excluded.blocked,
  required_after_write=excluded.required_after_write,
  status=excluded.status,
  updated_at=clock_timestamp(),
  updated_by_execution_id='CHATGPT-T-INDEP-PAULO-035-20261002';

-- -----------------------------------------------------------------------------
-- Six generic reviewer phases. The mini-judges are deterministic wrappers around
-- server-side trust assertions produced by lf_record_independent_review_step_v2.
-- -----------------------------------------------------------------------------
with s(step_order,step_id,evidence_required) as (values
  (10,'route_bind','router_receipt,operation_code'),
  (20,'target_currentness','subject_receipt_id,subject_type,subject_ref,subject_sha256,source_head_sha'),
  (30,'independence_measure','independence_result,producer_dependency_digest,reviewer_dependency_digest,shared_material_dependencies,unresolved_shared_material_dependencies'),
  (40,'semantic_review','verdict,rationale_summary,evidence_refs,independence_result'),
  (50,'reviewer_readback','subject_receipt_id,subject_sha256,source_head_sha,independence_result,semantic_verdict'),
  (60,'report_output','review_receipt,evidence_refs,authority_readback,next_gate')
)
insert into public.lf_operation_steps(
  operation_code,step_order,step_id,required,evidence_required,source_path,active,
  execution_order,created_by_execution_id
)
select 'REVISION_INDEPENDIENTE_LF',step_order,step_id,true,evidence_required,
       'supabase://public/lf_operation_step_contracts/REVISION_INDEPENDIENTE_LF/'||step_id,
       true,step_order,'CHATGPT-T-INDEP-PAULO-035-20261002'
from s
on conflict (operation_code,step_order) do update set
  step_id=excluded.step_id,required=excluded.required,evidence_required=excluded.evidence_required,
  source_path=excluded.source_path,active=excluded.active,execution_order=excluded.execution_order,
  updated_at=clock_timestamp(),updated_by_execution_id='CHATGPT-T-INDEP-PAULO-035-20261002';

with s(step_order,step_id,purpose,required_keys,next_pass,block_code) as (values
  (10,'route_bind','Bind ACT-0001 candidate route to exact generic reviewer operation.',jsonb_build_array('router_receipt','operation_code'),'target_currentness','BLOCKED_REVISION_INDEPENDIENTE_ROUTE_BIND'),
  (20,'target_currentness','Re-read VERIFIED Evidence Ledger subject/dependency receipts and exact subject revision.',jsonb_build_array('subject_receipt_id','subject_type','subject_ref','subject_sha256','source_head_sha'),'independence_measure','BLOCKED_REVISION_INDEPENDIENTE_TARGET_CURRENTNESS'),
  (30,'independence_measure','Measure material dependency overlap from provider-bound dependency manifests.',jsonb_build_array('independence_result','producer_dependency_digest','reviewer_dependency_digest','shared_material_dependencies','unresolved_shared_material_dependencies'),'semantic_review','BLOCKED_REVISION_INDEPENDIENTE_INDEPENDENCE_MEASURE'),
  (40,'semantic_review','Persist independent semantic verdict bound to exact subject and measured independence.',jsonb_build_array('verdict','rationale_summary','evidence_refs','independence_result'),'reviewer_readback','BLOCKED_REVISION_INDEPENDIENTE_SEMANTIC_REVIEW'),
  (50,'reviewer_readback','Re-read exact subject/dependency receipts and semantic verdict before completion.',jsonb_build_array('subject_receipt_id','subject_sha256','source_head_sha','independence_result','semantic_verdict'),'report_output','BLOCKED_REVISION_INDEPENDIENTE_READBACK'),
  (60,'report_output','Emit durable review receipt plus authority readback; no Qualification transition.',jsonb_build_array('review_receipt','evidence_refs','authority_readback','next_gate'),null::text,'BLOCKED_REVISION_INDEPENDIENTE_REPORT')
)
insert into public.lf_operation_step_contracts(
  operation_code,step_id,step_order,execution_order,contract_code,purpose,input_required,
  resolver_ref,output_payload,pass_condition,block_condition,blocking_code,mini_judge_code,
  required_evidence_keys,next_if_pass,next_if_blocked,status,notes,created_by_execution_id
)
select
  'REVISION_INDEPENDIENTE_LF',step_id,step_order,step_order,'CONTRACT-REVISION-INDEPENDIENTE-LF-v1',purpose,
  '[]'::jsonb,
  case step_id
    when 'route_bind' then 'public.lf_router_resolve_v1'
    when 'target_currentness' then 'private.lf_evidence_ledger_v1'
    when 'independence_measure' then 'public.lf_independent_review_measure_v1'
    when 'semantic_review' then 'GPT_RUNTIME_WITH_BOUND_EVIDENCE_CONTEXT'
    when 'reviewer_readback' then 'public.lf_independent_review_readback_v2'
    else 'public.lf_record_operation_step_core_v1'
  end,
  required_keys,
  jsonb_build_object('fail_closed',true,'required_evidence_present',true,'server_assertions_complete',true),
  jsonb_build_object('server_validation_failed',true),block_code,
  'JUDGE-INDEPENDENT-REVIEW-'||upper(replace(step_id,'_','-'))||'-v1',
  required_keys,next_pass,'RETURN_TO_ROUTER','CANDIDATO_READ_ONLY',
  'Candidate generic reviewer step; no active routing/cutover.',
  'CHATGPT-T-INDEP-PAULO-035-20261002'
from s
on conflict (operation_code,step_id) do update set
  step_order=excluded.step_order,execution_order=excluded.execution_order,contract_code=excluded.contract_code,
  purpose=excluded.purpose,input_required=excluded.input_required,resolver_ref=excluded.resolver_ref,
  output_payload=excluded.output_payload,pass_condition=excluded.pass_condition,block_condition=excluded.block_condition,
  blocking_code=excluded.blocking_code,mini_judge_code=excluded.mini_judge_code,
  required_evidence_keys=excluded.required_evidence_keys,next_if_pass=excluded.next_if_pass,
  next_if_blocked=excluded.next_if_blocked,status=excluded.status,notes=excluded.notes,
  updated_at=clock_timestamp(),updated_by_execution_id='CHATGPT-T-INDEP-PAULO-035-20261002';

with j(step_order,step_id,pass_if,fail_if) as (values
  (10,'route_bind',jsonb_build_array('router_ready','operation_exact'),jsonb_build_array('route_invalid')),
  (20,'target_currentness',jsonb_build_array('subject_verified','producer_dependencies_verified','reviewer_dependencies_verified','subject_binding_current'),jsonb_build_array('target_stale')),
  (30,'independence_measure',jsonb_build_array('independence_measured','dependency_digests_bound'),jsonb_build_array('independence_unmeasurable')),
  (40,'semantic_review',jsonb_build_array('review_shape_valid','verdict_allowed','evidence_refs_present','verdict_consistent_with_independence'),jsonb_build_array('semantic_invalid')),
  (50,'reviewer_readback',jsonb_build_array('subject_still_current','dependencies_still_current','semantic_review_bound'),jsonb_build_array('readback_invalid')),
  (60,'report_output',jsonb_build_array('all_prior_clean','receipt_built','authority_readback_present'),jsonb_build_array('completion_invalid'))
)
insert into public.lf_operation_judges(
  operation_code,judge_code,judge_path,pass_if,fail_if,result_values,status,created_by_execution_id
)
select 'REVISION_INDEPENDIENTE_LF',
       'JUDGE-INDEPENDENT-REVIEW-'||upper(replace(step_id,'_','-'))||'-v1',
       'supabase://REVISION_INDEPENDIENTE_LF/'||step_id,
       pass_if,fail_if,
       jsonb_build_array('STEP_PASS_WITH_EVIDENCE','RETURN_TO_ROUTER','BLOCKED_STEP_NOT_CLEAN'),
       'CANDIDATO_READ_ONLY','CHATGPT-T-INDEP-PAULO-035-20261002'
from j
on conflict (operation_code,judge_code) do update set
  judge_path=excluded.judge_path,pass_if=excluded.pass_if,fail_if=excluded.fail_if,
  result_values=excluded.result_values,status=excluded.status,updated_at=clock_timestamp(),
  updated_by_execution_id='CHATGPT-T-INDEP-PAULO-035-20261002';

with b(step_order,step_id,required_keys) as (values
  (10,'route_bind',jsonb_build_array('router_receipt','operation_code')),
  (20,'target_currentness',jsonb_build_array('subject_receipt_id','subject_type','subject_ref','subject_sha256','source_head_sha')),
  (30,'independence_measure',jsonb_build_array('independence_result','producer_dependency_digest','reviewer_dependency_digest','shared_material_dependencies','unresolved_shared_material_dependencies')),
  (40,'semantic_review',jsonb_build_array('verdict','rationale_summary','evidence_refs','independence_result')),
  (50,'reviewer_readback',jsonb_build_array('subject_receipt_id','subject_sha256','source_head_sha','independence_result','semantic_verdict')),
  (60,'report_output',jsonb_build_array('review_receipt','evidence_refs','authority_readback','next_gate'))
)
insert into public.lf_operation_step_judge_bindings(
  operation_code,step_order,step_id,judge_code,clean_result_value,blocked_result_value,
  return_result_value,required_evidence_keys,status,created_by_execution_id
)
select 'REVISION_INDEPENDIENTE_LF',step_order,step_id,
       'JUDGE-INDEPENDENT-REVIEW-'||upper(replace(step_id,'_','-'))||'-v1',
       'STEP_PASS_WITH_EVIDENCE','BLOCKED_STEP_NOT_CLEAN','RETURN_TO_ROUTER',required_keys,
       'CANDIDATO_READ_ONLY','CHATGPT-T-INDEP-PAULO-035-20261002'
from b
on conflict (operation_code,step_order,step_id) do update set
  judge_code=excluded.judge_code,clean_result_value=excluded.clean_result_value,
  blocked_result_value=excluded.blocked_result_value,return_result_value=excluded.return_result_value,
  required_evidence_keys=excluded.required_evidence_keys,status=excluded.status,
  updated_at=clock_timestamp(),updated_by_execution_id='CHATGPT-T-INDEP-PAULO-035-20261002';

-- -----------------------------------------------------------------------------
-- Material dependency measurement. Caller arrays are never accepted as authority:
-- only VERIFIED Evidence Ledger dependency-manifest receipts are consumed.
-- -----------------------------------------------------------------------------
create or replace function public.lf_independent_review_measure_v1(
  p_producer_dependency_receipt_id uuid,
  p_reviewer_dependency_receipt_id uuid,
  p_exception_receipt_id uuid default null
)
returns jsonb
language plpgsql
stable
set search_path = pg_catalog, public, private, extensions
as $$
declare
  p private.lf_evidence_ledger_v1%rowtype;
  r private.lf_evidence_ledger_v1%rowtype;
  e private.lf_evidence_ledger_v1%rowtype;
  p_deps jsonb;
  r_deps jsonb;
  exceptions jsonb := '[]'::jsonb;
  p_norm jsonb;
  r_norm jsonb;
  shared jsonb;
  adjudicated jsonb;
  unresolved jsonb;
  p_digest text;
  r_digest text;
  bad_count integer;
begin
  select * into p from private.lf_evidence_ledger_v1 where receipt_id=p_producer_dependency_receipt_id;
  select * into r from private.lf_evidence_ledger_v1 where receipt_id=p_reviewer_dependency_receipt_id;
  if p.receipt_id is null or r.receipt_id is null then
    return jsonb_build_object('result','BLOCKED','code','DEPENDENCY_RECEIPT_MISSING');
  end if;
  if p.verification_state<>'VERIFIED' or r.verification_state<>'VERIFIED' then
    return jsonb_build_object('result','BLOCKED','code','DEPENDENCY_RECEIPT_NOT_VERIFIED');
  end if;
  if p.receipt_kind<>'DEPENDENCY_MANIFEST' or r.receipt_kind<>'DEPENDENCY_MANIFEST' then
    return jsonb_build_object('result','BLOCKED','code','DEPENDENCY_RECEIPT_KIND_INVALID');
  end if;
  if p.receipt_payload->>'schema_version'<>'LF_MATERIAL_DEPENDENCY_MANIFEST_V1'
     or r.receipt_payload->>'schema_version'<>'LF_MATERIAL_DEPENDENCY_MANIFEST_V1' then
    return jsonb_build_object('result','BLOCKED','code','DEPENDENCY_MANIFEST_SCHEMA_INVALID');
  end if;
  p_deps:=p.receipt_payload->'dependencies';
  r_deps:=r.receipt_payload->'dependencies';
  if jsonb_typeof(p_deps)<>'array' or jsonb_typeof(r_deps)<>'array' then
    return jsonb_build_object('result','BLOCKED','code','DEPENDENCY_MANIFEST_SHAPE_INVALID');
  end if;

  select count(*) into bad_count
  from jsonb_array_elements(p_deps) d
  where jsonb_typeof(d)<>'object'
     or nullif(btrim(coalesce(d->>'ref','')),'') is null
     or coalesce(d->>'digest','') !~ '^[0-9a-f]{64}$'
     or jsonb_typeof(d->'material') is distinct from 'boolean';
  if bad_count>0 then return jsonb_build_object('result','BLOCKED','code','PRODUCER_DEPENDENCY_MANIFEST_INVALID'); end if;
  select count(*) into bad_count
  from jsonb_array_elements(r_deps) d
  where jsonb_typeof(d)<>'object'
     or nullif(btrim(coalesce(d->>'ref','')),'') is null
     or coalesce(d->>'digest','') !~ '^[0-9a-f]{64}$'
     or jsonb_typeof(d->'material') is distinct from 'boolean';
  if bad_count>0 then return jsonb_build_object('result','BLOCKED','code','REVIEWER_DEPENDENCY_MANIFEST_INVALID'); end if;

  select coalesce(jsonb_agg(x order by x->>'ref'),'[]'::jsonb) into p_norm
  from (
    select distinct on (d->>'ref')
      jsonb_build_object('ref',d->>'ref','digest',d->>'digest') x
    from jsonb_array_elements(p_deps) d
    where (d->>'material')::boolean is true
    order by d->>'ref',d->>'digest'
  ) q;
  select coalesce(jsonb_agg(x order by x->>'ref'),'[]'::jsonb) into r_norm
  from (
    select distinct on (d->>'ref')
      jsonb_build_object('ref',d->>'ref','digest',d->>'digest') x
    from jsonb_array_elements(r_deps) d
    where (d->>'material')::boolean is true
    order by d->>'ref',d->>'digest'
  ) q;

  p_digest:=encode(extensions.digest(convert_to(p_norm::text,'UTF8'),'sha256'),'hex');
  r_digest:=encode(extensions.digest(convert_to(r_norm::text,'UTF8'),'sha256'),'hex');

  select coalesce(jsonb_agg(jsonb_build_object(
    'ref',pd->>'ref','producer_digest',pd->>'digest','reviewer_digest',rd->>'digest'
  ) order by pd->>'ref'),'[]'::jsonb) into shared
  from jsonb_array_elements(p_norm) pd
  join jsonb_array_elements(r_norm) rd on rd->>'ref'=pd->>'ref';

  if p_exception_receipt_id is not null then
    select * into e from private.lf_evidence_ledger_v1 where receipt_id=p_exception_receipt_id;
    if e.receipt_id is null or e.verification_state<>'VERIFIED' or e.receipt_kind<>'INDEPENDENCE_EXCEPTION_MANIFEST' then
      return jsonb_build_object('result','BLOCKED','code','INDEPENDENCE_EXCEPTION_RECEIPT_INVALID');
    end if;
    if e.receipt_payload->>'schema_version'<>'LF_INDEPENDENCE_EXCEPTION_MANIFEST_V1'
       or e.receipt_payload->>'adjudicated_by'<>'SUPER_ADMIN'
       or jsonb_typeof(e.receipt_payload->'exceptions')<>'array' then
      return jsonb_build_object('result','BLOCKED','code','INDEPENDENCE_EXCEPTION_MANIFEST_INVALID');
    end if;
    exceptions:=e.receipt_payload->'exceptions';
    select count(*) into bad_count from jsonb_array_elements(exceptions) x
    where nullif(btrim(coalesce(x->>'ref','')),'') is null
       or nullif(btrim(coalesce(x->>'reason','')),'') is null
       or nullif(btrim(coalesce(x->>'evidence_ref','')),'') is null;
    if bad_count>0 then return jsonb_build_object('result','BLOCKED','code','INDEPENDENCE_EXCEPTION_EVIDENCE_INCOMPLETE'); end if;
  end if;

  select coalesce(jsonb_agg(s order by s->>'ref'),'[]'::jsonb) into adjudicated
  from jsonb_array_elements(shared) s
  where exists(select 1 from jsonb_array_elements(exceptions) x where x->>'ref'=s->>'ref');

  select coalesce(jsonb_agg(s order by s->>'ref'),'[]'::jsonb) into unresolved
  from jsonb_array_elements(shared) s
  where not exists(select 1 from jsonb_array_elements(exceptions) x where x->>'ref'=s->>'ref');

  return jsonb_build_object(
    'result',case when jsonb_array_length(unresolved)=0 then 'PASS' else 'FAIL' end,
    'producer_dependency_receipt_id',p_producer_dependency_receipt_id,
    'reviewer_dependency_receipt_id',p_reviewer_dependency_receipt_id,
    'exception_receipt_id',p_exception_receipt_id,
    'producer_dependency_digest',p_digest,
    'reviewer_dependency_digest',r_digest,
    'shared_material_dependencies',shared,
    'adjudicated_exceptions',adjudicated,
    'unresolved_shared_material_dependencies',unresolved
  );
end;
$$;

comment on function public.lf_independent_review_measure_v1(uuid,uuid,uuid) is
'T-INDEP deterministic independence measurement from VERIFIED Evidence Ledger dependency manifests. Shared material dependency identity is compared by ref; exceptions require a VERIFIED SUPER_ADMIN-adjudicated manifest.';

-- -----------------------------------------------------------------------------
-- Begin candidate review. Exact subject identity comes from VERIFIED Evidence
-- Ledger binding; the caller cannot substitute an unverified subject hash.
-- -----------------------------------------------------------------------------
create or replace function public.lf_independent_review_begin_v2(
  p_execution_id text,
  p_subject_receipt_id uuid,
  p_producer_dependency_receipt_id uuid,
  p_reviewer_dependency_receipt_id uuid,
  p_exception_receipt_id uuid,
  p_producer_execution_id text,
  p_request_sha256 text,
  p_idempotency_key text,
  p_actor_execution_id text,
  p_manifest jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
set search_path = pg_catalog, public, private
as $$
declare
  s private.lf_evidence_ledger_v1%rowtype;
  route jsonb;
  measure jsonb;
  manifest jsonb;
  reserved jsonb;
begin
  if btrim(coalesce(p_execution_id,''))=''
     or p_subject_receipt_id is null
     or p_producer_dependency_receipt_id is null
     or p_reviewer_dependency_receipt_id is null
     or btrim(coalesce(p_producer_execution_id,''))=''
     or coalesce(p_request_sha256,'') !~ '^[0-9a-f]{64}$'
     or btrim(coalesce(p_idempotency_key,''))=''
     or btrim(coalesce(p_actor_execution_id,''))=''
     or p_manifest is null or jsonb_typeof(p_manifest)<>'object' then
    return jsonb_build_object('result','BLOCKED','code','INDEPENDENT_REVIEW_BEGIN_INPUT_INVALID');
  end if;
  if p_execution_id=p_producer_execution_id then
    return jsonb_build_object('result','BLOCKED','code','INDEPENDENT_REVIEW_PRODUCER_EQUALS_REVIEWER');
  end if;

  select * into s from private.lf_evidence_ledger_v1 where receipt_id=p_subject_receipt_id;
  if not found or s.verification_state<>'VERIFIED' or s.receipt_kind<>'SUBJECT_BINDING' then
    return jsonb_build_object('result','BLOCKED','code','INDEPENDENT_REVIEW_SUBJECT_RECEIPT_NOT_VERIFIED');
  end if;
  if s.execution_id is distinct from p_producer_execution_id then
    return jsonb_build_object('result','BLOCKED','code','INDEPENDENT_REVIEW_SUBJECT_PRODUCER_BINDING_MISMATCH');
  end if;

  measure:=public.lf_independent_review_measure_v1(
    p_producer_dependency_receipt_id,p_reviewer_dependency_receipt_id,p_exception_receipt_id
  );
  if measure->>'result'='BLOCKED' then
    return jsonb_build_object('result','BLOCKED','code',measure->>'code','independence_measure',measure);
  end if;

  route:=public.lf_router_resolve_v1(
    'revision independiente de sujeto',null,'INDEPENDENT_REVIEW','REVIEW_SUBJECT','ROUTER'
  );
  if route->>'status'<>'READY_TO_EXECUTE' or route->>'operation_code'<>'REVISION_INDEPENDIENTE_LF' then
    return jsonb_build_object('result','BLOCKED','code','INDEPENDENT_REVIEW_ROUTER_NOT_READY','router_receipt',route);
  end if;

  manifest:=p_manifest||jsonb_build_object(
    'capability_code','INDEPENDENT_ASSURANCE',
    'contract_version','lf-independent-review-boundary/v2',
    'subject_receipt_id',p_subject_receipt_id::text,
    'subject_type',s.subject_type,
    'subject_ref',s.subject_ref,
    'subject_sha256',s.subject_sha256,
    'source_head_sha',s.source_head_sha,
    'authority_ref',s.authority_ref,
    'producer_execution_id',p_producer_execution_id,
    'producer_dependency_receipt_id',p_producer_dependency_receipt_id::text,
    'reviewer_dependency_receipt_id',p_reviewer_dependency_receipt_id::text,
    'exception_receipt_id',case when p_exception_receipt_id is null then null else p_exception_receipt_id::text end,
    'independence_measure_at_begin',measure,
    'runtime_activation',false,
    'production_activation',false,
    'business_effect_allowed',false
  );

  reserved:=public.fn_lf_operation_reserve_execution_v1(
    p_execution_id,'REVISION_INDEPENDIENTE_LF','REVIEW_SUBJECT',s.subject_ref,
    p_idempotency_key,p_request_sha256,p_actor_execution_id,null,null,manifest
  );
  if reserved->>'status'<>'IN_PROGRESS' then
    return jsonb_build_object('result','BLOCKED','code','INDEPENDENT_REVIEW_RESERVATION_NOT_IN_PROGRESS','reservation',reserved);
  end if;
  return reserved||jsonb_build_object(
    'result','INDEPENDENT_REVIEW_RESERVED',
    'router_receipt',route,
    'subject_receipt_id',p_subject_receipt_id,
    'subject_type',s.subject_type,
    'subject_ref',s.subject_ref,
    'subject_sha256',s.subject_sha256,
    'source_head_sha',s.source_head_sha,
    'independence_measure',measure,
    'next_step','route_bind'
  );
end;
$$;

-- -----------------------------------------------------------------------------
-- Operation-specific recorder. All closure-relevant assertions are recomputed
-- from durable authority; caller-provided assertion arrays are ignored by core.
-- -----------------------------------------------------------------------------
create or replace function public.lf_record_independent_review_step_v2(
  p_execution_id text,
  p_step_id text,
  p_evidence_ref text,
  p_evidence_payload jsonb,
  p_actor_execution_id text
)
returns jsonb
language plpgsql
set search_path = pg_catalog, public, private
as $$
declare
  x public.lf_operation_execution%rowtype;
  s private.lf_evidence_ledger_v1%rowtype;
  pd private.lf_evidence_ledger_v1%rowtype;
  rd private.lf_evidence_ledger_v1%rowtype;
  measure jsonb;
  route jsonb;
  semantic public.lf_operation_execution_steps%rowtype;
  trust jsonb;
  assertions jsonb:='[]'::jsonb;
  hard_fails jsonb:='[]'::jsonb;
  valid boolean:=true;
  code text:='OK';
  payload jsonb;
  verdict text;
  review_receipt jsonb;
  authority_readback jsonb;
  contract_status text;
  binding_status text;
  judge_status text;
  qid uuid;
  pdid uuid;
  rdid uuid;
  exid uuid;
begin
  if p_evidence_payload is null or jsonb_typeof(p_evidence_payload)<>'object' then
    return jsonb_build_object('outcome','BLOCKED','code','EVIDENCE_PAYLOAD_INVALID','durable',false);
  end if;
  select * into x from public.lf_operation_execution where execution_id=p_execution_id;
  if not found or x.operation_code<>'REVISION_INDEPENDIENTE_LF' or x.target_type<>'REVIEW_SUBJECT' or x.status<>'IN_PROGRESS' then
    return jsonb_build_object('outcome','BLOCKED','code','EXECUTION_IDENTITY_INVALID','durable',false);
  end if;
  begin
    qid:=(x.manifest->>'subject_receipt_id')::uuid;
    pdid:=(x.manifest->>'producer_dependency_receipt_id')::uuid;
    rdid:=(x.manifest->>'reviewer_dependency_receipt_id')::uuid;
    if nullif(x.manifest->>'exception_receipt_id','') is not null then exid:=(x.manifest->>'exception_receipt_id')::uuid; end if;
  exception when others then
    return jsonb_build_object('outcome','BLOCKED','code','EXECUTION_MANIFEST_BINDING_INVALID','durable',false);
  end;

  select status into contract_status from public.lf_operation_step_contracts where operation_code='REVISION_INDEPENDIENTE_LF' and step_id=p_step_id;
  select status into binding_status from public.lf_operation_step_judge_bindings where operation_code='REVISION_INDEPENDIENTE_LF' and step_id=p_step_id;
  select j.status into judge_status
  from public.lf_operation_step_judge_bindings b
  join public.lf_operation_judges j on j.operation_code=b.operation_code and j.judge_code=b.judge_code
  where b.operation_code='REVISION_INDEPENDIENTE_LF' and b.step_id=p_step_id;
  if contract_status is null or binding_status is null or judge_status is null then
    return jsonb_build_object('outcome','BLOCKED','code','CANDIDATE_GOVERNANCE_BINDING_MISSING','durable',false);
  end if;

  select * into s from private.lf_evidence_ledger_v1 where receipt_id=qid;
  select * into pd from private.lf_evidence_ledger_v1 where receipt_id=pdid;
  select * into rd from private.lf_evidence_ledger_v1 where receipt_id=rdid;
  measure:=public.lf_independent_review_measure_v1(pdid,rdid,exid);
  payload:=p_evidence_payload;

  if p_step_id='route_bind' then
    route:=public.lf_router_resolve_v1('revision independiente de sujeto',null,'INDEPENDENT_REVIEW','REVIEW_SUBJECT','ROUTER');
    payload:=payload||jsonb_build_object('router_receipt',route,'operation_code',route->>'operation_code');
    if route->>'status'='READY_TO_EXECUTE' then assertions:=assertions||'"router_ready"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"route_invalid"'::jsonb; code:='ROUTE_NOT_READY'; end if;
    if route->>'operation_code'='REVISION_INDEPENDIENTE_LF' then assertions:=assertions||'"operation_exact"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"route_invalid"'::jsonb; code:='OPERATION_MISMATCH'; end if;

  elsif p_step_id='target_currentness' then
    payload:=payload||jsonb_build_object(
      'subject_receipt_id',qid::text,'subject_type',s.subject_type,'subject_ref',s.subject_ref,
      'subject_sha256',s.subject_sha256,'source_head_sha',s.source_head_sha
    );
    if s.receipt_id=qid and s.verification_state='VERIFIED' and s.receipt_kind='SUBJECT_BINDING' then assertions:=assertions||'"subject_verified"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"target_stale"'::jsonb; code:='SUBJECT_NOT_VERIFIED'; end if;
    if s.execution_id=x.manifest->>'producer_execution_id' and s.subject_ref=x.manifest->>'subject_ref' and s.subject_sha256=x.manifest->>'subject_sha256' and s.source_head_sha=x.manifest->>'source_head_sha' then assertions:=assertions||'"subject_binding_current"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"target_stale"'::jsonb; code:='SUBJECT_BINDING_STALE'; end if;
    if pd.receipt_id=pdid and pd.verification_state='VERIFIED' and pd.receipt_kind='DEPENDENCY_MANIFEST' then assertions:=assertions||'"producer_dependencies_verified"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"target_stale"'::jsonb; code:='PRODUCER_DEPENDENCIES_NOT_VERIFIED'; end if;
    if rd.receipt_id=rdid and rd.verification_state='VERIFIED' and rd.receipt_kind='DEPENDENCY_MANIFEST' then assertions:=assertions||'"reviewer_dependencies_verified"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"target_stale"'::jsonb; code:='REVIEWER_DEPENDENCIES_NOT_VERIFIED'; end if;

  elsif p_step_id='independence_measure' then
    payload:=payload||jsonb_build_object(
      'independence_result',measure->>'result',
      'producer_dependency_digest',measure->>'producer_dependency_digest',
      'reviewer_dependency_digest',measure->>'reviewer_dependency_digest',
      'shared_material_dependencies',coalesce(measure->'shared_material_dependencies','[]'::jsonb),
      'unresolved_shared_material_dependencies',coalesce(measure->'unresolved_shared_material_dependencies','[]'::jsonb)
    );
    if measure->>'result' in ('PASS','FAIL') then assertions:=assertions||'"independence_measured"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"independence_unmeasurable"'::jsonb; code:=coalesce(measure->>'code','INDEPENDENCE_UNMEASURABLE'); end if;
    if coalesce(measure->>'producer_dependency_digest','')~'^[0-9a-f]{64}$' and coalesce(measure->>'reviewer_dependency_digest','')~'^[0-9a-f]{64}$' then assertions:=assertions||'"dependency_digests_bound"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"independence_unmeasurable"'::jsonb; code:='DEPENDENCY_DIGEST_MISSING'; end if;

  elsif p_step_id='semantic_review' then
    verdict:=upper(coalesce(payload->>'verdict',''));
    payload:=payload||jsonb_build_object('independence_result',measure->>'result');
    if verdict in ('PASS','FAIL') and nullif(btrim(coalesce(payload->>'rationale_summary','')),'') is not null then assertions:=assertions||'"review_shape_valid"'::jsonb||'"verdict_allowed"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"semantic_invalid"'::jsonb; code:='SEMANTIC_REVIEW_SHAPE_INVALID'; end if;
    if jsonb_typeof(payload->'evidence_refs')='array' and jsonb_array_length(payload->'evidence_refs')>0 then assertions:=assertions||'"evidence_refs_present"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"semantic_invalid"'::jsonb; code:='SEMANTIC_EVIDENCE_MISSING'; end if;
    if measure->>'result'='PASS' or verdict='FAIL' then assertions:=assertions||'"verdict_consistent_with_independence"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"semantic_invalid"'::jsonb; code:='PASS_WITH_FAILED_INDEPENDENCE_FORBIDDEN'; end if;

  elsif p_step_id='reviewer_readback' then
    select * into semantic from public.lf_operation_execution_steps where execution_id=p_execution_id and step_id='semantic_review';
    verdict:=upper(coalesce(semantic.evidence_payload->>'verdict',''));
    payload:=payload||jsonb_build_object(
      'subject_receipt_id',qid::text,'subject_sha256',s.subject_sha256,'source_head_sha',s.source_head_sha,
      'independence_result',measure->>'result','semantic_verdict',verdict
    );
    if s.verification_state='VERIFIED' and s.subject_sha256=x.manifest->>'subject_sha256' and s.source_head_sha=x.manifest->>'source_head_sha' then assertions:=assertions||'"subject_still_current"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"readback_invalid"'::jsonb; code:='SUBJECT_STALE_AT_READBACK'; end if;
    if pd.verification_state='VERIFIED' and rd.verification_state='VERIFIED' and measure->>'result' in ('PASS','FAIL') then assertions:=assertions||'"dependencies_still_current"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"readback_invalid"'::jsonb; code:='DEPENDENCIES_STALE_AT_READBACK'; end if;
    if semantic.step_id='semantic_review' and semantic.status='STEP_PASS_WITH_EVIDENCE' and verdict in ('PASS','FAIL') then assertions:=assertions||'"semantic_review_bound"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"readback_invalid"'::jsonb; code:='SEMANTIC_REVIEW_NOT_BOUND'; end if;

  elsif p_step_id='report_output' then
    select * into semantic from public.lf_operation_execution_steps where execution_id=p_execution_id and step_id='semantic_review';
    verdict:=upper(coalesce(semantic.evidence_payload->>'verdict',''));
    authority_readback:=jsonb_build_object(
      'subject_receipt_id',qid::text,'subject_verification_state',s.verification_state,
      'subject_sha256',s.subject_sha256,'source_head_sha',s.source_head_sha,
      'producer_dependency_receipt_id',pdid::text,'producer_dependency_verification_state',pd.verification_state,
      'reviewer_dependency_receipt_id',rdid::text,'reviewer_dependency_verification_state',rd.verification_state,
      'independence_result',measure->>'result','readback_at',clock_timestamp()
    );
    review_receipt:=jsonb_build_object(
      'schema_version','LF_INDEPENDENT_REVIEW_RECEIPT_V2',
      'capability_code','INDEPENDENT_ASSURANCE',
      'reviewer_execution_id',p_execution_id,
      'producer_execution_id',x.manifest->>'producer_execution_id',
      'subject_type',s.subject_type,'subject_ref',s.subject_ref,'subject_sha256',s.subject_sha256,
      'source_head_sha',s.source_head_sha,'authority_ref',s.authority_ref,
      'verdict',verdict,'independence_result',measure->>'result',
      'producer_dependency_digest',measure->>'producer_dependency_digest',
      'reviewer_dependency_digest',measure->>'reviewer_dependency_digest',
      'shared_material_dependencies',measure->'shared_material_dependencies',
      'adjudicated_exceptions',measure->'adjudicated_exceptions',
      'unresolved_shared_material_dependencies',measure->'unresolved_shared_material_dependencies',
      'semantic_evidence_refs',semantic.evidence_payload->'evidence_refs'
    );
    payload:=payload||jsonb_build_object(
      'review_receipt',review_receipt,
      'evidence_refs',semantic.evidence_payload->'evidence_refs',
      'authority_readback',authority_readback,
      'next_gate',case when verdict='PASS' and measure->>'result'='PASS' then 'CONSUMER_CLOSURE' else 'RETURN_TO_CONSUMER_BLOCKED' end
    );
    if not exists(
      select 1 from public.lf_operation_steps rs
      left join public.lf_operation_execution_steps es on es.execution_id=p_execution_id and es.step_order=rs.step_order and es.step_id=rs.step_id
      where rs.operation_code='REVISION_INDEPENDIENTE_LF' and rs.required and rs.active and rs.step_id<>'report_output'
        and (es.step_id is null or es.status<>'STEP_PASS_WITH_EVIDENCE')
    ) then assertions:=assertions||'"all_prior_clean"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"completion_invalid"'::jsonb; code:='PRIOR_STEPS_NOT_CLEAN'; end if;
    if jsonb_typeof(review_receipt)='object' and review_receipt->>'verdict' in ('PASS','FAIL') then assertions:=assertions||'"receipt_built"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"completion_invalid"'::jsonb; code:='REVIEW_RECEIPT_INVALID'; end if;
    if jsonb_typeof(authority_readback)='object' and authority_readback->>'subject_verification_state'='VERIFIED' then assertions:=assertions||'"authority_readback_present"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"completion_invalid"'::jsonb; code:='AUTHORITY_READBACK_INVALID'; end if;
  else
    return jsonb_build_object('outcome','BLOCKED','code','STEP_NOT_SUPPORTED','durable',false);
  end if;

  trust:=jsonb_build_object(
    'valid',valid,'code',code,'server_assertions',assertions,'server_hard_fails',hard_fails,
    'details',jsonb_build_object('subject_receipt_id',qid,'independence_measure',measure)
  );

  return public.lf_record_operation_step_core_v1(
    p_execution_id,p_step_id,p_evidence_ref,payload,p_actor_execution_id,
    'REVISION_INDEPENDIENTE_LF','REVIEW_SUBJECT',
    contract_status,binding_status,judge_status,trust,true,'lf_record_independent_review_step_v2'
  );
end;
$$;

create or replace function public.lf_independent_review_readback_v2(p_execution_id text)
returns jsonb
language plpgsql
stable
set search_path = pg_catalog, public
as $$
declare
  x public.lf_operation_execution%rowtype;
  report public.lf_operation_execution_steps%rowtype;
begin
  select * into x from public.lf_operation_execution where execution_id=p_execution_id;
  if not found or x.operation_code<>'REVISION_INDEPENDIENTE_LF' then
    return jsonb_build_object('result','BLOCKED','code','INDEPENDENT_REVIEW_EXECUTION_NOT_FOUND');
  end if;
  select * into report from public.lf_operation_execution_steps where execution_id=p_execution_id and step_id='report_output';
  if x.status<>'COMPLETED' or x.completed_at is null or report.status<>'STEP_PASS_WITH_EVIDENCE' then
    return jsonb_build_object('result','BLOCKED','code','INDEPENDENT_REVIEW_NOT_COMPLETED','execution_status',x.status);
  end if;
  return jsonb_build_object(
    'result','INDEPENDENT_REVIEW_READBACK',
    'execution_id',p_execution_id,
    'operation_code',x.operation_code,
    'subject_type',x.manifest->>'subject_type',
    'subject_ref',x.manifest->>'subject_ref',
    'subject_sha256',x.manifest->>'subject_sha256',
    'source_head_sha',x.manifest->>'source_head_sha',
    'review_receipt',report.evidence_payload->'review_receipt',
    'authority_readback',report.evidence_payload->'authority_readback',
    'next_gate',report.evidence_payload->'next_gate'
  );
end;
$$;

comment on function public.lf_independent_review_begin_v2(text,uuid,uuid,uuid,uuid,text,text,text,text,jsonb) is
'T-INDEP candidate generic independent-review entrypoint. Requires VERIFIED exact subject and dependency receipts; no runtime/production activation.';
comment on function public.lf_record_independent_review_step_v2(text,text,text,jsonb,text) is
'T-INDEP generic independent-review recorder. Recomputes authority/currentness/independence server-side and delegates durable step recording to the operation-neutral core.';
comment on function public.lf_independent_review_readback_v2(text) is
'T-INDEP durable terminal readback for generic independent review candidate.';

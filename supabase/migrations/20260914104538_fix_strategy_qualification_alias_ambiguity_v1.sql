create or replace function public.lf_run_strategy_qualification_v1(p_snapshot_id bigint, p_execution_id text)
returns jsonb
language plpgsql
set search_path to 'pg_catalog', 'public'
as $function$
declare
  s public.lf_strategy_snapshots%rowtype;
  rev text;
  cf text;
  qid uuid;
  qstate text;
  b public.lf_test_requirement_bindings%rowtype;
  rr jsonb;
  ids uuid[] := '{}'::uuid[];
  any_fail boolean := false;
  any_review boolean := false;
  fp text;
begin
  select * into s from public.lf_strategy_snapshots where id=p_snapshot_id;
  if not found then raise exception 'LF_STRATEGY_QUALIFICATION_TARGET_MISSING:%',p_snapshot_id; end if;

  rev:=public.lf_strategy_revision_sha256_v1(p_snapshot_id);
  cf:=public.lf_strategy_classification_fingerprint_v1(p_snapshot_id);
  fp:=public.lf_required_test_suite_fingerprint_v1('STRATEGY',s.snapshot_code);

  insert into public.lf_qualification_receipts(
    subject_type,subject_code,subject_ref,revision_sha256,classification_fingerprint,
    lifecycle_state_code,suite_set_fingerprint,created_by_execution_id
  ) values(
    'STRATEGY',s.snapshot_code,format('supabase://public/lf_strategy_snapshots/%s',s.id),
    rev,cf,null,fp,p_execution_id
  ) returning qualification_id into qid;

  qstate:=public.lf_lifecycle_resolve_transition_v1(
    'QUALIFICATION_LIFECYCLE',
    public.lf_lifecycle_initial_state_v1('QUALIFICATION_LIFECYCLE'),
    'START_QUALIFICATION'
  );
  update public.lf_qualification_receipts
     set lifecycle_state_code=qstate,updated_by_execution_id=p_execution_id
   where qualification_id=qid;

  for b in
    select trb.*
      from public.lf_test_requirement_bindings as trb
     where trb.subject_type='STRATEGY'
       and (trb.subject_code='*' or trb.subject_code=s.snapshot_code)
       and trb.status='ACTIVE'
       and trb.required
       and trb.effective_from<=clock_timestamp()
       and public.lf_test_requirement_applies_v1(trb.binding_code,'STRATEGY',s.snapshot_code)
     order by trb.binding_code
  loop
    rr:=public.lf_run_strategy_matrix_suite_v1(
      b.suite_code,'STRATEGY',s.snapshot_code,rev,p_execution_id
    );
    ids:=array_append(ids,(rr->>'suite_run_id')::uuid);
    if rr->>'status'='FAILED' then
      any_fail:=true;
    elsif rr->>'status'='REVIEW_REQUIRED' then
      any_review:=true;
    end if;
  end loop;

  update public.lf_qualification_receipts
     set suite_run_ids=ids,updated_at=clock_timestamp(),updated_by_execution_id=p_execution_id
   where qualification_id=qid;

  if any_fail then
    update public.lf_qualification_receipts
       set lifecycle_state_code=public.lf_lifecycle_resolve_transition_v1(
             'QUALIFICATION_LIFECYCLE',lifecycle_state_code,'FAIL_QUALIFICATION'
           ),
           findings=findings||jsonb_build_array(jsonb_build_object('type','MATRIX_FAILED')),
           updated_at=clock_timestamp(),updated_by_execution_id=p_execution_id
     where qualification_id=qid;
  elsif not any_review then
    update public.lf_qualification_receipts
       set lifecycle_state_code=public.lf_lifecycle_resolve_transition_v1(
             'QUALIFICATION_LIFECYCLE',lifecycle_state_code,'PASS_QUALIFICATION'
           ),
           qualified_at=clock_timestamp(),updated_at=clock_timestamp(),updated_by_execution_id=p_execution_id
     where qualification_id=qid;
  end if;

  return (
    select jsonb_build_object(
      'qualification_id',qualification_id,
      'subject_code',subject_code,
      'revision_sha256',revision_sha256,
      'classification_fingerprint',classification_fingerprint,
      'lifecycle_state_code',lifecycle_state_code,
      'suite_run_ids',suite_run_ids,
      'suite_set_fingerprint',suite_set_fingerprint
    )
      from public.lf_qualification_receipts
     where qualification_id=qid
  );
end
$function$;

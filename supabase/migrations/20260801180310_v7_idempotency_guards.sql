-- Stable idempotency for V7 reconciliation and gate writers.
-- A nonce is still consumed for every authenticated request, but a retry for the same
-- immutable source workflow returns the existing row instead of creating new evidence.

begin;

create unique index if not exists uq_lf_github_reconciliation_v7_source
  on private.lf_github_reconciliation_runs_v3(
    artifact_id,workflow_run_id,merge_commit_sha,writer_authentication
  )
  where writer_authentication='GITHUB_OIDC_HMAC_NONCE_V7';

create or replace function public.record_external_ci_verification_v7(
  p_payload jsonb,
  p_execution_id text,
  p_writer_signature text,
  p_writer_nonce text
)
returns bigint
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_artifact private.lf_skill_artifacts%rowtype;
  v_payload jsonb;
  v_hash text;
  v_signature_hash text;
  v_nonce_hash text;
  v_proof_expires_at timestamptz;
  v_preimage text;
  v_preimage_hash text;
  v_event_id bigint;
  v_run_id bigint;
  v_existing_preimage_hash text;
begin
  if jsonb_typeof(p_payload)<>'object'
     or nullif(btrim(coalesce(p_execution_id,'')),'') is null
     or jsonb_typeof(p_payload->'artifact_id')<>'number'
     or jsonb_typeof(p_payload->'workflow_run_id')<>'number'
     or coalesce(p_payload->>'merge_commit_sha','') !~ '^[0-9a-f]{40}$'
     or coalesce(p_payload->>'audit_manifest_sha256','') !~ '^[0-9a-f]{64}$'
     or p_payload->>'result' not in ('PASS','FAIL') then
    raise exception using errcode='23514',message='external reconciliation payload is incomplete';
  end if;

  select * into v_artifact
  from private.lf_skill_artifacts
  where id=(p_payload->>'artifact_id')::bigint;
  if not found then
    raise exception using errcode='P0002',message='artifact not found';
  end if;

  -- This ordering is shared with the Edge V7 implementation. Every PASS field is
  -- non-null; FAIL rows are evidence only and cannot satisfy promotion.
  v_preimage:=concat_ws(':',
    'reconciliation-v7',p_execution_id,p_payload->>'artifact_id',p_payload->>'workflow_run_id',
    p_payload->>'merge_commit_sha',p_payload->>'artifact_sha256',p_payload->>'branch_protection_status',
    p_payload->>'result',p_payload->>'audit_manifest_sha256'
  );
  v_preimage_hash:=encode(
    extensions.digest(convert_to(v_preimage,'UTF8'),'sha256'),'hex'
  );

  if not private.fn_consume_writer_proof_v7(
    v_preimage,lower(p_writer_signature),p_writer_nonce
  ) then
    raise exception using errcode='42501',message='OIDC HMAC nonce reconciliation writer failed';
  end if;

  if p_payload->>'target_branch'<>'main'
     or p_payload->>'workflow_event'<>'push'
     or p_payload->>'workflow_conclusion'<>'success'
     or p_payload->>'workflow_head_sha' is distinct from p_payload->>'merge_commit_sha'
     or coalesce((p_payload->>'merged')::boolean,false) is not true
     or p_payload->>'pr_state'<>'MERGED'
     or (p_payload->>'observed_at')::timestamptz<clock_timestamp()-interval '24 hours'
     or (p_payload->>'observed_at')::timestamptz>clock_timestamp()+interval '5 minutes' then
    raise exception using errcode='23514',message='external reconciliation source is not current post-merge evidence';
  end if;

  if p_payload->>'result'='PASS' and (
       p_payload->>'branch_protection_status'<>'VERIFIED'
       or coalesce(p_payload#>>'{details,actual_branch_protection_status}','')<>'VERIFIED'
       or not coalesce((p_payload->>'artifact_exercised_by_workflow')::boolean,false)
       or coalesce(p_payload->>'artifact_sha256','') !~ '^[0-9a-f]{64}$'
       or coalesce(p_payload->>'artifact_git_blob','') !~ '^[0-9a-f]{40}$'
     ) then
    raise exception using errcode='23514',message='PASS requires native protection and complete workflow evidence';
  end if;

  if p_payload->>'artifact_path' is distinct from v_artifact.relative_path then
    raise exception using errcode='23514',message='external reconciliation artifact path mismatch';
  end if;
  if p_payload->>'result'='PASS' and (
    not v_artifact.is_current
    or p_payload->>'artifact_sha256' is distinct from v_artifact.content_sha256
  ) then
    raise exception using errcode='23514',message='external reconciliation PASS does not match current artifact content';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('lf-github-v7:'||v_artifact.id::text,0));

  select g.id,g.details->>'signed_preimage_sha256'
    into v_run_id,v_existing_preimage_hash
  from private.lf_github_reconciliation_runs_v3 g
  where g.artifact_id=v_artifact.id
    and g.workflow_run_id=(p_payload->>'workflow_run_id')::bigint
    and g.merge_commit_sha=p_payload->>'merge_commit_sha'
    and g.writer_authentication='GITHUB_OIDC_HMAC_NONCE_V7';

  if found then
    if v_existing_preimage_hash is distinct from v_preimage_hash then
      raise exception using errcode='23505',message='conflicting V7 reconciliation already exists for source workflow';
    end if;
    return v_run_id;
  end if;

  v_signature_hash:=encode(
    extensions.digest(convert_to(lower(p_writer_signature),'UTF8'),'sha256'),'hex'
  );
  v_nonce_hash:=encode(
    extensions.digest(convert_to(p_writer_nonce,'UTF8'),'sha256'),'hex'
  );
  v_proof_expires_at:=to_timestamp(split_part(p_writer_nonce,'.',2)::bigint);
  v_payload:=(p_payload-'verification_payload_sha256')||jsonb_build_object(
    'evidence_schema_version','external-ci-verification/v3',
    'execution_id',p_execution_id,
    'verification_mode','GITHUB_ACTIONS_OIDC_HMAC_V7',
    'writer_authentication','GITHUB_OIDC_HMAC_NONCE_V7',
    'writer_signature_sha256',v_signature_hash,
    'writer_nonce_sha256',v_nonce_hash,
    'writer_proof_expires_at',v_proof_expires_at
  );
  v_hash:=encode(
    extensions.digest(convert_to(v_payload::text,'UTF8'),'sha256'),'hex'
  );
  v_payload:=v_payload||jsonb_build_object('verification_payload_sha256',v_hash);

  insert into public.lf_eventos(
    evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,payload,created_by_execution_id
  ) values (
    'EXTERNAL_CI_VERIFICATION_COMPLETED','LF_SKILL_ARTIFACT',v_artifact.artifact_code,
    'Authoritative OIDC HMAC nonce post-merge GitHub reconciliation recorded',
    case when v_payload->>'result'='PASS' then 'INFO' else 'WARN' end,
    v_payload,p_execution_id
  ) returning id into v_event_id;

  insert into private.lf_github_reconciliation_runs_v3(
    artifact_id,repository,target_branch,artifact_path,pr_number,pr_state,merged,merge_commit_sha,
    workflow_run_id,workflow_name,workflow_event,workflow_head_sha,workflow_conclusion,
    artifact_git_blob,artifact_sha256,file_touched_by_merge,artifact_exercised_by_workflow,
    audit_artifact_name,audit_manifest_sha256,branch_protection_status,result,authoritative,
    failure_reasons,details,verification_payload_sha256,source_external_event_id,evidence_event_id,
    reconciled_by_execution_id,observed_at,writer_authentication,writer_signature_sha256
  ) values (
    v_artifact.id,v_payload->>'repository',v_payload->>'target_branch',v_payload->>'artifact_path',
    case when v_payload->'pr_number'='null'::jsonb or not(v_payload?'pr_number')
      then null else (v_payload->>'pr_number')::integer end,
    v_payload->>'pr_state',(v_payload->>'merged')::boolean,v_payload->>'merge_commit_sha',
    (v_payload->>'workflow_run_id')::bigint,v_payload->>'workflow_name',v_payload->>'workflow_event',
    v_payload->>'workflow_head_sha',v_payload->>'workflow_conclusion',v_payload->>'artifact_git_blob',
    v_payload->>'artifact_sha256',(v_payload->>'file_touched_by_merge')::boolean,
    (v_payload->>'artifact_exercised_by_workflow')::boolean,v_payload->>'audit_artifact_name',
    v_payload->>'audit_manifest_sha256',v_payload->>'branch_protection_status',v_payload->>'result',true,
    v_payload->'failure_reasons',coalesce(v_payload->'details','{}'::jsonb)||jsonb_build_object(
      'writer_authentication_v7','GITHUB_OIDC_HMAC_NONCE_V7',
      'writer_nonce_sha256',v_nonce_hash,
      'writer_proof_expires_at',v_proof_expires_at,
      'signed_preimage_sha256',v_preimage_hash
    ),v_hash,v_event_id,v_event_id,p_execution_id,(v_payload->>'observed_at')::timestamptz,
    'GITHUB_OIDC_HMAC_NONCE_V7',v_signature_hash
  ) returning id into v_run_id;

  return v_run_id;
end;
$function$;

alter function public.record_external_ci_verification_v7(jsonb,text,text,text)
  owner to lf_governance_owner_v3;
revoke all on function public.record_external_ci_verification_v7(jsonb,text,text,text)
  from public,anon,authenticated;
grant execute on function public.record_external_ci_verification_v7(jsonb,text,text,text)
  to service_role;

create or replace function public.record_lf_gate_test_v7(
  p_payload jsonb,
  p_execution_id text,
  p_writer_signature text,
  p_writer_nonce text
)
returns bigint
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_artifact private.lf_skill_artifacts%rowtype;
  v_payload jsonb;
  v_probe_hash text;
  v_effect_hash text;
  v_payload_hash text;
  v_signature_hash text;
  v_nonce_hash text;
  v_proof_expires_at timestamptz;
  v_preimage text;
  v_preimage_hash text;
  v_persisted_effects jsonb;
  v_event_id bigint;
  v_id bigint;
  v_reconciliation_id bigint;
  v_existing_writer text;
  v_existing_preimage_hash text;
begin
  if jsonb_typeof(p_payload)<>'object'
     or jsonb_typeof(p_payload->'artifact_id')<>'number'
     or jsonb_typeof(p_payload->'source_workflow_run_id')<>'number'
     or coalesce(p_payload->>'source_commit_sha','') !~ '^[0-9a-f]{40}$'
     or nullif(p_payload->>'test_code','') is null then
    raise exception using errcode='23514',message='gate test payload is incomplete';
  end if;

  select * into v_artifact
  from private.lf_skill_artifacts
  where id=(p_payload->>'artifact_id')::bigint;
  if not found then
    raise exception using errcode='P0002',message='artifact not found';
  end if;

  v_preimage:=concat_ws(':',
    'gate-v7',p_execution_id,p_payload->>'artifact_id',p_payload->>'test_code',
    p_payload->>'source_workflow_run_id',p_payload->>'source_commit_sha',p_payload->>'passed',
    p_payload->>'target_relation',p_payload->>'gate_code',
    p_payload->'probe_preimage'->>'expected_sha256',
    p_payload->'observed_outcome'->>'artifact_sha256',
    p_payload->'observed_outcome'->>'audit_covered',
    p_payload->'persisted_effects'->>'github_reconciliation_run_id'
  );
  v_preimage_hash:=encode(
    extensions.digest(convert_to(v_preimage,'UTF8'),'sha256'),'hex'
  );

  if not private.fn_consume_writer_proof_v7(
    v_preimage,lower(p_writer_signature),p_writer_nonce
  ) then
    raise exception using errcode='42501',message='OIDC HMAC nonce gate writer failed';
  end if;

  v_reconciliation_id:=nullif(
    p_payload#>>'{persisted_effects,github_reconciliation_run_id}',''
  )::bigint;
  if coalesce((p_payload->>'passed')::boolean,false) and not exists (
    select 1
    from private.lf_github_reconciliation_runs_v3 g
    where g.id=v_reconciliation_id
      and g.artifact_id=v_artifact.id
      and g.result='PASS'
      and g.authoritative
      and g.branch_protection_status='VERIFIED'
      and coalesce(g.details->>'actual_branch_protection_status','')='VERIFIED'
      and g.workflow_run_id=(p_payload->>'source_workflow_run_id')::bigint
      and g.merge_commit_sha=p_payload->>'source_commit_sha'
      and g.writer_authentication='GITHUB_OIDC_HMAC_NONCE_V7'
      and private.fn_reconciliation_nonce_v7_valid(g.id)
  ) then
    raise exception using errcode='23514',message='passing gate test requires matching V7 reconciliation';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    'lf-gate-v7:'||v_artifact.id::text||':'||coalesce(p_payload->>'test_code',''),0
  ));

  select t.id,t.writer_authentication,t.persisted_effects->>'signed_preimage_sha256'
    into v_id,v_existing_writer,v_existing_preimage_hash
  from private.lf_gate_test_runs_v3 t
  where t.test_code=p_payload->>'test_code'
    and t.artifact_id=v_artifact.id
    and t.source_workflow_run_id=(p_payload->>'source_workflow_run_id')::bigint
    and t.source_commit_sha=p_payload->>'source_commit_sha';

  if found then
    if v_existing_writer<>'GITHUB_OIDC_HMAC_NONCE_V7'
       or v_existing_preimage_hash is distinct from v_preimage_hash then
      raise exception using errcode='23505',message='conflicting gate evidence already exists for source workflow';
    end if;
    return v_id;
  end if;

  v_signature_hash:=encode(
    extensions.digest(convert_to(lower(p_writer_signature),'UTF8'),'sha256'),'hex'
  );
  v_nonce_hash:=encode(
    extensions.digest(convert_to(p_writer_nonce,'UTF8'),'sha256'),'hex'
  );
  v_proof_expires_at:=to_timestamp(split_part(p_writer_nonce,'.',2)::bigint);
  v_probe_hash:=encode(
    extensions.digest(convert_to((p_payload->'probe_preimage')::text,'UTF8'),'sha256'),'hex'
  );
  v_persisted_effects:=coalesce(p_payload->'persisted_effects','{}'::jsonb)
    ||jsonb_build_object('signed_preimage_sha256',v_preimage_hash);
  v_effect_hash:=encode(
    extensions.digest(convert_to(v_persisted_effects::text,'UTF8'),'sha256'),'hex'
  );
  v_payload:=(p_payload-'evidence_payload_sha256')||jsonb_build_object(
    'evidence_schema_version','gate-test-run/v3',
    'execution_id',p_execution_id,
    'probe_sha256',v_probe_hash,
    'persisted_effects',v_persisted_effects,
    'persisted_effects_sha256',v_effect_hash,
    'writer_authentication','GITHUB_OIDC_HMAC_NONCE_V7',
    'writer_signature_sha256',v_signature_hash,
    'writer_nonce_sha256',v_nonce_hash,
    'writer_proof_expires_at',v_proof_expires_at
  );
  v_payload_hash:=encode(
    extensions.digest(convert_to(v_payload::text,'UTF8'),'sha256'),'hex'
  );
  v_payload:=v_payload||jsonb_build_object('evidence_payload_sha256',v_payload_hash);

  insert into public.lf_eventos(
    evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,payload,created_by_execution_id
  ) values (
    'GATE_TEST_RUN_RECORDED','LF_SKILL_ARTIFACT',v_artifact.artifact_code,
    'OIDC HMAC nonce reproducible architecture gate test recorded',
    case when coalesce((v_payload->>'passed')::boolean,false) then 'INFO' else 'WARN' end,
    v_payload,p_execution_id
  ) returning id into v_event_id;

  insert into private.lf_gate_test_runs_v3(
    test_code,artifact_id,gate_code,test_kind,target_relation,probe_preimage,probe_sha256,
    expected_outcome,observed_outcome,persisted_effects,persisted_effects_sha256,passed,
    runner_type,runner_identity,source_workflow_run_id,source_commit_sha,evidence_event_id,
    executed_by_execution_id,executed_at,writer_authentication,writer_signature_sha256
  ) values (
    v_payload->>'test_code',v_artifact.id,v_payload->>'gate_code',v_payload->>'test_kind',
    v_payload->>'target_relation',v_payload->'probe_preimage',v_probe_hash,
    v_payload->'expected_outcome',v_payload->'observed_outcome',
    v_persisted_effects,v_effect_hash,(v_payload->>'passed')::boolean,
    v_payload->>'runner_type',v_payload->>'runner_identity',
    (v_payload->>'source_workflow_run_id')::bigint,v_payload->>'source_commit_sha',
    v_event_id,p_execution_id,(v_payload->>'executed_at')::timestamptz,
    'GITHUB_OIDC_HMAC_NONCE_V7',v_signature_hash
  ) returning id into v_id;

  return v_id;
end;
$function$;

alter function public.record_lf_gate_test_v7(jsonb,text,text,text)
  owner to lf_governance_owner_v3;
revoke all on function public.record_lf_gate_test_v7(jsonb,text,text,text)
  from public,anon,authenticated;
grant execute on function public.record_lf_gate_test_v7(jsonb,text,text,text)
  to service_role;

commit;

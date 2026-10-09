-- F07-X03: Negative contract tests. Run in disposable DB after candidate migration.
begin;
do $$
declare r jsonb; h text:=repeat('a',40);
begin
r:=jsonb_build_object('exact_head',h,'source_revision',h,'runtime_sha','abc','receipt_sha','abc','attestation_ref','attestation:trusted:'||repeat('f',64),'release_path','/release/new','previous_release_path','/release/old','release_manifest_matches',true,'health_status','HEALTHY','service_active_after',true,'changed_paths',jsonb_build_array('services/profile_runtime_api/worker.py'),'runtime_code_delta_count',1,'worker_only_delta',true,'restart_unit','lf-profile-runtime-queue-worker','mitigation_action','PRESERVE','next_gate','POST_DEPLOY_WORKER_QUEUE_REAL_JOB_CANARY');
if public.lf_runtime_impl_deploy_receipt_check_v1(r)<>'VERIFICATION_VERIFIED' then raise exception 'baseline'; end if;
if public.lf_runtime_impl_deploy_receipt_check_v1(jsonb_set(r,'{receipt_sha}','"bad"'))<>'GOVERNANCE_DRIFT' then raise exception 'SHA mismatch'; end if;
if public.lf_runtime_impl_deploy_receipt_check_v1(jsonb_set(r,'{changed_paths}','["outside/worker.py"]'::jsonb))<>'BLOCKED_RUNTIME_DELTA_SCOPE' then raise exception 'scope'; end if;
if public.lf_runtime_impl_deploy_receipt_check_v1(jsonb_set(r,'{release_manifest_matches}','false'::jsonb))<>'BLOCKED_WRONG_RELEASE_OR_ROLLBACK' then raise exception 'release'; end if;
if public.lf_runtime_impl_deploy_receipt_check_v1(jsonb_set(r,'{health_status}','"UNHEALTHY"'))<>'BLOCKED_HEALTH_READBACK' then raise exception 'health'; end if;
if public.lf_runtime_impl_deploy_receipt_check_v1(r-'previous_release_path')<>'BLOCKED_WRONG_RELEASE_OR_ROLLBACK' then raise exception 'rollback'; end if;
if public.lf_runtime_impl_deploy_receipt_check_v1(jsonb_set(r,'{restart_unit}','"wrong"'))<>'BLOCKED_WRONG_RESTART_UNIT' then raise exception 'worker unit'; end if;
if public.lf_runtime_impl_deploy_receipt_check_v1(jsonb_set(r,'{mitigation_action}','"REMOVE"'))<>'BLOCKED_MITIGATION_HUMAN_GATE' then raise exception 'T3.2 gate'; end if;

-- D7: neither deploy-actor receipt nor unauthenticated forged read-only observer can certify runtime.
if public.lf_runtime_impl_deploy_verification_binding_v1(jsonb_set(r,'{attestation}',jsonb_build_object('schema_version','LF_RUNTIME_INDEPENDENT_READBACK_V1','producer','DEPLOY_EXECUTOR','origin_role','DEPLOY_EXECUTOR','credential_role','DEPLOY_WRITE'))) ->> 'reason' <> 'INDEPENDENT_READBACK_RECEIPT_NOT_AUTHENTICATED' then raise exception 'D7 deploy actor receipt must be rejected'; end if;
if public.lf_runtime_impl_deploy_verification_binding_v1(jsonb_set(r,'{attestation}',jsonb_build_object('schema_version','LF_RUNTIME_INDEPENDENT_READBACK_V1','producer','GITHUB_ACTIONS_VPS_READ_ONLY','origin_role','INDEPENDENT_OBSERVER','credential_role','VPS_READ_ONLY','observer_execution_id','claimed-run','workflow_run_id','1','exact_head',h,'runtime_sha','abc','release_path','/release/new','manifest_digest',repeat('f',64)))) ->> 'reason' <> 'INDEPENDENT_READBACK_RECEIPT_NOT_AUTHENTICATED' then raise exception 'D7 unauthenticated observer claim must be rejected'; end if;
end $$;
-- Verify the unauthenticated role cannot insert an authenticated receipt.
set local role authenticated;
do $unauthorized$
begin
 begin
  insert into private.lf_runtime_readback_oidc_receipts
   (execution_id,exact_head,release_path,runtime_sha,manifest_digest,receipt,claims,
    workflow_run_id,workflow_run_attempt,token_sha256)
  values ('EXEC-test',repeat('a',40),'/opt/lf-profile-runtime-api/releases/'||repeat('a',40),
    repeat('a',40),repeat('b',64),'{}'::jsonb,'{}'::jsonb,'1','1',repeat('c',64));
  raise exception 'UNAUTHORIZED_INSERT_WAS_ACCEPTED';
 exception when insufficient_privilege or check_violation then
  null;
 end;
end $unauthorized$;
reset role;

-- I7: role membership is TEST-ONLY and rolled back with this transaction.
grant lf_runtime_readback_oidc_writer to postgres with set true;
set local role lf_runtime_readback_oidc_writer;
do $positive$
declare id bigint; h text:=repeat('a',40); d text:=repeat('b',64);
 declare_claims jsonb;
begin
 declare_claims:=jsonb_build_object('repository','cristhianlujan/claude-persona-lf-patch','repository_id','1244397752',
  'ref','refs/heads/main','event_name','workflow_dispatch',
  'workflow_ref','cristhianlujan/claude-persona-lf-patch/.github/workflows/lf-runtime-independent-readback-dispatch.yml@refs/heads/main',
  'job_workflow_ref','cristhianlujan/claude-persona-lf-patch/.github/workflows/lf-runtime-independent-readback.yml@refs/heads/main',
  'run_id','12345678','run_attempt','1');
 insert into private.lf_runtime_readback_oidc_receipts
  (execution_id,exact_head,release_path,runtime_sha,manifest_digest,receipt,claims,
   workflow_run_id,workflow_run_attempt,token_sha256)
 values ('EXEC-D7-positive',h,'/opt/lf-profile-runtime-api/releases/'||h,h,d,
  jsonb_build_object('exact_head',h,'source_sha',h,'runtime_sha',h,'manifest_matches',true,
   'process_release_matches',true,'health_ok',true,'files_verified',true,
   'release_path','/opt/lf-profile-runtime-api/releases/'||h),
  declare_claims,'12345678','1',repeat('c',64))
 returning receipt_id into id;
 if id is null then raise exception 'I7_POSITIVE_RETURNING_MISSING'; end if;
 raise notice 'I7_POSITIVE_RETURNING_OK receipt_id=%',id;
 begin
  insert into private.lf_runtime_readback_oidc_receipts
  (execution_id,exact_head,release_path,runtime_sha,manifest_digest,receipt,claims,
   workflow_run_id,workflow_run_attempt,token_sha256)
  values('EXEC-D7-duplicate',h,'/opt/lf-profile-runtime-api/releases/'||h,h,repeat('e',64),
   jsonb_build_object('exact_head',h,'runtime_sha',h,'release_path','/opt/lf-profile-runtime-api/releases/'||h),
   declare_claims,'12345678','1',repeat('d',64));
  raise exception 'I7_DUPLICATE_ACCEPTED';
 exception when unique_violation then
  raise notice 'I7_DUPLICATE_REJECTED';
 end;
 begin
  insert into private.lf_runtime_readback_oidc_receipts
  (execution_id,exact_head,release_path,runtime_sha,manifest_digest,receipt,claims,
   workflow_run_id,workflow_run_attempt,token_sha256)
  values('EXEC-D7-token-repeat',h,'/opt/lf-profile-runtime-api/releases/'||h,h,d,
   jsonb_build_object('exact_head',h,'runtime_sha',h,'release_path','/opt/lf-profile-runtime-api/releases/'||h),
   jsonb_set(declare_claims,'{run_id}','"12345680"'::jsonb),'12345680','1',repeat('c',64));
  raise exception 'I7_TOKEN_SHA_DUPLICATE_ACCEPTED';
 exception when unique_violation then
  raise notice 'I7_TOKEN_SHA_DUPLICATE_REJECTED';
 end;
 begin
  insert into private.lf_runtime_readback_oidc_receipts
  (execution_id,exact_head,release_path,runtime_sha,manifest_digest,receipt,claims,
   workflow_run_id,workflow_run_attempt,token_sha256)
  values('EXEC-D7-invalid',h,'/opt/lf-profile-runtime-api/releases/'||h,h,d,
   jsonb_build_object('exact_head',h,'runtime_sha',h,'release_path','/opt/lf-profile-runtime-api/releases/'||h),
   jsonb_set(declare_claims,'{event_name}','"push"'::jsonb),'12345679','1',repeat('e',64));
  raise exception 'I7_INVALID_CLAIM_ACCEPTED';
 exception when insufficient_privilege or check_violation then
  raise notice 'I7_RLS_CLAIM_REJECTED';
 end;
end $positive$;
reset role;
-- Positive binding is checked with source-aligned fixture and an authenticated row.
do $binding_test$
declare h text:=repeat('a',40); v bigint; p jsonb; verdict jsonb;
begin
 select receipt_id into v from private.lf_runtime_readback_oidc_receipts where workflow_run_id='12345678';
 p:=jsonb_build_object('execution_id','EXEC-D7-positive','exact_head',h,'source_revision',h,
 'runtime_sha',h,'receipt_sha',h,'attestation_ref','attestation:trusted:'||repeat('f',64),
 'release_path','/opt/lf-profile-runtime-api/releases/'||h,'previous_release_path','/opt/lf-profile-runtime-api/releases/old',
 'release_manifest_matches',true,'health_status','HEALTHY','service_active_after',true,
 'changed_paths',jsonb_build_array('services/profile_runtime_api/worker.py'),'runtime_code_delta_count',1,
 'worker_only_delta',true,'restart_unit','lf-profile-runtime-queue-worker','mitigation_action','PRESERVE',
 'next_gate','POST_DEPLOY_WORKER_QUEUE_REAL_JOB_CANARY','attestation',jsonb_build_object('receipt_id',v));
 verdict:=public.lf_runtime_impl_deploy_verification_binding_v1(p);
 if verdict->>'decision' <> 'VERIFICATION_VERIFIED' then raise exception 'I7_BINDING_NOT_VERIFIED:%',verdict; end if;
 raise notice 'I7_BINDING_VERIFIED';
end $binding_test$;
rollback;

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
end $;
-- Verify that privileged SQL context cannot insert an authenticated receipt.
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
rollback;

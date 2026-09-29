-- Run only after loading s31_currentness_hardening_v1.sql inside the same transaction.
-- Expected: PASS notices only; transaction must be rolled back by the caller.

do $test$
declare
  v_rev text := repeat('a',40);
  v_sha text := repeat('b',64);
  v_receipt jsonb;
  v_dep jsonb;
  v_ctx jsonb;
  v_result jsonb;
  v_pass integer := 0;
begin
  v_receipt := jsonb_build_object(
    'schema_version','LF_CURRENTNESS_AUTHORITY_RECEIPT_V1',
    'authority_layer','CURRENTNESS_AUTHORITY',
    'decision','CURRENT',
    'ready',true,
    'dependency_completeness','COMPLETE',
    'authority_ref','refs/heads/main',
    'bound_revision',v_rev,
    'current_revision',v_rev,
    'receipt_sha256',v_sha
  );
  v_dep := jsonb_build_object(
    'kind','MIGRATION_SOURCE_AUTHORITY',
    'provider','LF_MIGRATION_SOURCE_PARITY',
    'state','EXACT',
    'evidence_sha256',repeat('c',64),
    'existing_exact_parity',true,
    'remote_ahead',false,
    'pending_count',0,
    'pending_version',''
  );
  v_ctx := jsonb_build_object(
    'operation_kind','MATERIAL_WRITE',
    'target_ref','asset://PERFIL/TEST',
    'authority_ref','refs/heads/main',
    'effective_revision',v_rev
  );

  -- 1. Exact parity + CURRENT is allowed.
  v_result := public.lf_currentness_material_prewrite_guard_v1(v_receipt,v_dep,v_ctx);
  if coalesce((v_result->>'ready')::boolean,false) is not true or v_result->>'decision' <> 'CURRENT' then
    raise exception 'CASE_01_EXACT_CURRENT_FAILED:%',v_result;
  end if;
  v_pass := v_pass + 1;

  -- 2. Irrelevant Git drift already resolved upstream as CURRENT_REBOUND remains allowed.
  v_receipt := jsonb_set(v_receipt,'{decision}','"CURRENT_REBOUND"'::jsonb);
  v_result := public.lf_currentness_material_prewrite_guard_v1(v_receipt,v_dep,v_ctx);
  if coalesce((v_result->>'ready')::boolean,false) is not true or v_result->>'decision' <> 'CURRENT_REBOUND' then
    raise exception 'CASE_02_REBOUND_FAILED:%',v_result;
  end if;
  v_pass := v_pass + 1;

  -- 3. Remote-only/ledger-ahead cannot yield CURRENT/CURRENT_REBOUND.
  v_dep := jsonb_set(v_dep,'{state}','"REMOTE_ONLY"'::jsonb);
  v_dep := jsonb_set(v_dep,'{remote_ahead}','true'::jsonb);
  v_result := public.lf_currentness_material_prewrite_guard_v1(v_receipt,v_dep,v_ctx);
  if v_result->>'decision' <> 'UNKNOWN_FAIL_CLOSED' or coalesce((v_result->>'ready')::boolean,true) is not false then
    raise exception 'CASE_03_REMOTE_ONLY_FAILED:%',v_result;
  end if;
  v_pass := v_pass + 1;

  -- 4. Mixed/unknown parity fails closed.
  v_dep := jsonb_set(v_dep,'{state}','"MIXED"'::jsonb);
  v_result := public.lf_currentness_material_prewrite_guard_v1(v_receipt,v_dep,v_ctx);
  if v_result->>'decision' <> 'UNKNOWN_FAIL_CLOSED' then raise exception 'CASE_04_MIXED_FAILED:%',v_result; end if;
  v_pass := v_pass + 1;

  -- 5. Exact one source-first pending migration may apply itself, and only itself.
  v_dep := jsonb_build_object(
    'kind','MIGRATION_SOURCE_AUTHORITY','provider','LF_MIGRATION_SOURCE_PARITY',
    'state','SOURCE_FIRST_PENDING','evidence_sha256',repeat('d',64),
    'existing_exact_parity',true,'remote_ahead',false,'pending_count',1,
    'pending_version','20260915023000'
  );
  v_ctx := jsonb_build_object(
    'operation_kind','MIGRATION_APPLY','target_ref','supabase/migrations/20260915023000',
    'migration_version','20260915023000','authority_ref','refs/heads/main',
    'effective_revision',v_rev
  );
  v_result := public.lf_currentness_material_prewrite_guard_v1(v_receipt,v_dep,v_ctx);
  if coalesce((v_result->>'ready')::boolean,false) is not true or coalesce((v_result->>'source_first_exact_apply')::boolean,false) is not true then
    raise exception 'CASE_05_SOURCE_FIRST_POSITIVE_FAILED:%',v_result;
  end if;
  v_pass := v_pass + 1;

  -- 6. Source-first pending cannot authorize an unrelated material write.
  v_ctx := jsonb_set(v_ctx,'{operation_kind}','"MATERIAL_WRITE"'::jsonb);
  v_result := public.lf_currentness_material_prewrite_guard_v1(v_receipt,v_dep,v_ctx);
  if v_result->>'decision' <> 'UNKNOWN_FAIL_CLOSED' then raise exception 'CASE_06_SOURCE_FIRST_SCOPE_FAILED:%',v_result; end if;
  v_pass := v_pass + 1;

  -- 7. Source-first pending cannot authorize a different migration target.
  v_ctx := jsonb_build_object(
    'operation_kind','MIGRATION_APPLY','target_ref','supabase/migrations/20260915023001',
    'migration_version','20260915023001','authority_ref','refs/heads/main',
    'effective_revision',v_rev
  );
  v_result := public.lf_currentness_material_prewrite_guard_v1(v_receipt,v_dep,v_ctx);
  if v_result->>'decision' <> 'UNKNOWN_FAIL_CLOSED' then raise exception 'CASE_07_SOURCE_FIRST_TARGET_FAILED:%',v_result; end if;
  v_pass := v_pass + 1;

  -- Restore exact dependency/context.
  v_dep := jsonb_build_object(
    'kind','MIGRATION_SOURCE_AUTHORITY','provider','LF_MIGRATION_SOURCE_PARITY',
    'state','EXACT','evidence_sha256',repeat('c',64),
    'existing_exact_parity',true,'remote_ahead',false,'pending_count',0,'pending_version',''
  );
  v_ctx := jsonb_build_object(
    'operation_kind','MATERIAL_WRITE','target_ref','asset://PERFIL/TEST',
    'authority_ref','refs/heads/main','effective_revision',v_rev
  );

  -- 8. STALE_AFFECTED is blocked before write.
  v_receipt := jsonb_set(v_receipt,'{decision}','"STALE_AFFECTED"'::jsonb);
  v_receipt := jsonb_set(v_receipt,'{ready}','false'::jsonb);
  v_result := public.lf_currentness_material_prewrite_guard_v1(v_receipt,v_dep,v_ctx);
  if v_result->>'decision' <> 'STALE_AFFECTED' or coalesce((v_result->>'ready')::boolean,true) is not false then
    raise exception 'CASE_08_STALE_FAILED:%',v_result;
  end if;
  v_pass := v_pass + 1;

  -- 9. UNKNOWN_FAIL_CLOSED is blocked before write.
  v_receipt := jsonb_set(v_receipt,'{decision}','"UNKNOWN_FAIL_CLOSED"'::jsonb);
  v_result := public.lf_currentness_material_prewrite_guard_v1(v_receipt,v_dep,v_ctx);
  if v_result->>'decision' <> 'UNKNOWN_FAIL_CLOSED' then raise exception 'CASE_09_UNKNOWN_FAILED:%',v_result; end if;
  v_pass := v_pass + 1;

  -- Restore ready CURRENT.
  v_receipt := jsonb_set(v_receipt,'{decision}','"CURRENT"'::jsonb);
  v_receipt := jsonb_set(v_receipt,'{ready}','true'::jsonb);

  -- 10. Incomplete dependency graph is never allowed to rebind/write.
  v_receipt := jsonb_set(v_receipt,'{dependency_completeness}','"UNKNOWN"'::jsonb);
  v_result := public.lf_currentness_material_prewrite_guard_v1(v_receipt,v_dep,v_ctx);
  if v_result->>'decision' <> 'UNKNOWN_FAIL_CLOSED' then raise exception 'CASE_10_COMPLETENESS_FAILED:%',v_result; end if;
  v_pass := v_pass + 1;
  v_receipt := jsonb_set(v_receipt,'{dependency_completeness}','"COMPLETE"'::jsonb);

  -- 11. Effective revision spoof/mismatch fails closed.
  v_ctx := jsonb_set(v_ctx,'{effective_revision}',to_jsonb(repeat('e',40)));
  v_result := public.lf_currentness_material_prewrite_guard_v1(v_receipt,v_dep,v_ctx);
  if v_result->>'decision' <> 'UNKNOWN_FAIL_CLOSED' then raise exception 'CASE_11_REVISION_MISMATCH_FAILED:%',v_result; end if;
  v_pass := v_pass + 1;
  v_ctx := jsonb_set(v_ctx,'{effective_revision}',to_jsonb(v_rev));

  -- 12. Authority ref spoof/mismatch fails closed.
  v_ctx := jsonb_set(v_ctx,'{authority_ref}','"refs/heads/other"'::jsonb);
  v_result := public.lf_currentness_material_prewrite_guard_v1(v_receipt,v_dep,v_ctx);
  if v_result->>'decision' <> 'UNKNOWN_FAIL_CLOSED' then raise exception 'CASE_12_AUTHORITY_MISMATCH_FAILED:%',v_result; end if;
  v_pass := v_pass + 1;

  raise notice 'PASS_S31_CURRENTNESS_HARDENING=%/12',v_pass;
end;
$test$;

do $migration$
declare
  v_sha256 text;
  v_git_blob text;
  v_count bigint;
  v_mismatch bigint;
begin
  select expected_sha256, expected_git_blob
    into v_sha256, v_git_blob
  from public.get_lf_repository_governance_bundle_v4()
  where path = 'scripts/lf_contract_check.py';

  if (v_sha256, v_git_blob) is not distinct from
     ('ed6cdba7db6db43d3906be48abda82b4328aa8b0d5a865543ea57721160cabde','d9e9d1f4955229f97b8f60aaa0eeedb0d0827cdf') then
    null;
  elsif (v_sha256, v_git_blob) is not distinct from
        ('545b7516c9862610367bb52a60905efcc7c6be66105b0fc03425accf6e027aff','ed4d81bcbb0f1e570983bc3c8f04f61fc2f40d6a') then
    insert into private.lf_repository_governance_bundle_v4(
      path, expected_sha256, expected_git_blob, control_kind, active,
      approved_commit_sha, approved_by_execution_id, approved_at
    ) values (
      'scripts/lf_contract_check.py',
      'ed6cdba7db6db43d3906be48abda82b4328aa8b0d5a865543ea57721160cabde',
      'd9e9d1f4955229f97b8f60aaa0eeedb0d0827cdf',
      'VALIDATOR', true,
      'c3410f3a3e538ae40e866bf227cf2324f82f1335',
      'EXEC-S26-CI-402-POOLER-FALLBACK-20260913-001',
      clock_timestamp()
    );
  else
    raise exception 'S26_CI_402_CONTRACT_VALIDATOR_REPIN_STATE_MISMATCH sha256=% git_blob=%',
      coalesce(v_sha256,'<NULL>'), coalesce(v_git_blob,'<NULL>');
  end if;

  select count(*) into v_count
  from public.get_lf_repository_governance_bundle_v4();
  if v_count <> 7 then
    raise exception 'S26_CI_402_CONTRACT_VALIDATOR_GOVERNANCE_COUNT expected=7 observed=%', v_count;
  end if;

  with expected(path, sha256, git_blob, kind) as (
    values
      ('.github/workflows/lf-contract-check.yml','2585742ce2427401004c0e191181c270b9f80fa0cad746d203480fe7ad3fe064','58dbf14df29524b6f85fa04213377c8657df4bb3','SOURCE_WORKFLOW'),
      ('.github/workflows/lf-github-reconcile-v3.yml','dd3febd8a6de892fcffc52deee8c4479cb01dd4e701607427a9696d6594b952a','8d1b2a025a3a3334817d6ea548c32c0b6c41bc36','RECONCILIATION_WORKFLOW'),
      ('sandbox/lf_contract_gate_test/lf_validation_engine_v0_10_2_selftest.py','8f444fdf3e5484aa9843aa8dbd8d9fc790f7d389d9f8ce126b1ef0d8a689cb54','8dd685fb910931ff1eee13b025dde01cbd6b5d0c','VALIDATOR'),
      ('sandbox/lf_contract_gate_test/pass_evidence_gate.py','24dde3dfcc2356770686ac63f4afb5f9e7e30ab75c4a1f8bed5bb03a3ae32579','641947ef209e1e86d5b720b01f6590d68d1965b0','VALIDATOR'),
      ('sandbox/lf_contract_gate_test/r8_continuous_audit.py','bed17e3e4f89dd68ba93872a03123236eef9d101b5c8ead85ff1dfa8193c1973','3e8a5bc0ce6dd9851591fa63378cdb104e4f9a2e','VALIDATOR'),
      ('sandbox/no_bypass_judge_profile_card_skill/no_bypass_judge_selftest.py','86cfac16d1a46f5325c3423acbaee1f8782b9c11e32cd0025ac0b7c9c461fa9f','9aa79e714fd6e0bc56bca850f88447e6ffd7b2e7','VALIDATOR'),
      ('scripts/lf_contract_check.py','ed6cdba7db6db43d3906be48abda82b4328aa8b0d5a865543ea57721160cabde','d9e9d1f4955229f97b8f60aaa0eeedb0d0827cdf','VALIDATOR')
  ), actual as (
    select path, expected_sha256 as sha256, expected_git_blob as git_blob, control_kind as kind
    from public.get_lf_repository_governance_bundle_v4()
  )
  select count(*) into v_mismatch
  from expected e
  left join actual a using (path)
  where (a.sha256, a.git_blob, a.kind) is distinct from (e.sha256, e.git_blob, e.kind);

  if v_mismatch <> 0 then
    raise exception 'S26_CI_402_CANONICAL_GOVERNANCE_BUNDLE_MISMATCH count=%', v_mismatch;
  end if;
end;
$migration$;

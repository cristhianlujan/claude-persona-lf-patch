-- IG M7.11 CI50 qualification / exact-source observable activation.
-- R16 Git-first only; downstream, parser, production and scoped PASS remain forbidden.
-- Source evidence: PR #2083 merged 121208a1dc6bf0966228a47b42ac716a8f62bfd7.
-- GitHub Actions #37916720118, head 61db64d381dce529b5c2429f71cc889e0ddd073c: 50/50 and 10/10 adversarial.
-- This does not touch assurance append-only catalog or any runtime semantic hash.
DO $ig_ci50_activation$
DECLARE v_candidates integer;
DECLARE v_active integer;
BEGIN
  SELECT count(*) INTO v_candidates
  FROM public.lf_test_suite_cases c
  WHERE c.suite_code='INPUT_GOVERNANCE_REGRESSION'
    AND c.test_code LIKE 'CI-%'
    AND c.status='CANDIDATO'
    AND c.metadata->>'source_commit_sha'='5fa5e98d0c8400d4d685c378043557d8f1f308a0'
    AND c.metadata->>'source_base_blob_sha'='cfe2731c872e334d95523a3c7f085c31f92a6f70'
    AND c.metadata->>'source_adjudicated_blob_sha'='32ec59b23a70e09b77245579145233a5ee462c11'
    AND c.metadata#>>'{authorization,scoped_pass_authorized}'='false'
    AND c.metadata#>>'{authorization,downstream_authorized}'='false'
    AND c.metadata#>>'{authorization,production_authorized}'='false';
  IF v_candidates<>50 THEN
    RAISE EXCEPTION 'IG_CI50_ACTIVATION_BOUND_CANDIDATE_COUNT:%',v_candidates;
  END IF;
  UPDATE public.lf_test_suite_cases c
  SET status='ACTIVE',
      metadata=c.metadata || jsonb_build_object('activation',jsonb_build_object(
        'basis','GITHUB_ACTIONS_REAL_CI50_EXACT_SOURCE_PASS',
        'runner','sandbox/lf_contract_gate_test/input_governance_incremental/qualify_ci50_git_v1.py',
        'workflow','.github/workflows/ig_ci50_change_impact_qualification.yml',
        'github_run_id',37916720118,
        'github_exact_head_sha','61db64d381dce529b5c2429f71cc889e0ddd073c',
        'github_merge_sha','121208a1dc6bf0966228a47b42ac716a8f62bfd7',
        'report_archive_sha256','124a6ffe9902aee6bfc7310f4b25476e448e26b37523a5dc33e661def3d8c3fb',
        'observed_case_count',50,
        'observed_pass_count',50,
        'observed_adversarial_pass',10,
        'claim_scope','READ_ONLY_STRUCTURED_INPUT_CHANGE_IMPACT_QUALIFICATION_ONLY',
        'natural_language_parser_certified',false,
        'semantic_runtime_authority',false,
        'downstream_authorized',false,
        'migration','supabase/migrations/20261009133000_ig_ci50_qualification_activation_v1.sql'))
  WHERE c.suite_code='INPUT_GOVERNANCE_REGRESSION' AND c.test_code LIKE 'CI-%' AND c.status='CANDIDATO';
  SELECT count(*) INTO v_active FROM public.lf_test_suite_cases
  WHERE suite_code='INPUT_GOVERNANCE_REGRESSION' AND test_code LIKE 'CI-%'
    AND status='ACTIVE' AND metadata#>>'{activation,observed_pass_count}'='50';
  IF v_active<>50 THEN RAISE EXCEPTION 'IG_CI50_ACTIVATION_READBACK_FAILED:%',v_active; END IF;
END
$ig_ci50_activation$;

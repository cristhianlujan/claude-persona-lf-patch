-- T-DECCTX / PAULO-187 rollback-only proof.
-- Requires DECISION_CONTEXT_ASOF v1 installed.
-- Leaves zero canary decision contexts and zero canary authority state after ROLLBACK.

BEGIN;

CREATE TEMP TABLE t_decctx_latest_authority(
  authority_kind text PRIMARY KEY,
  authority_ref text NOT NULL,
  authority_version text NOT NULL,
  authority_sha256 text NOT NULL
) ON COMMIT DROP;

INSERT INTO t_decctx_latest_authority(authority_kind,authority_ref,authority_version,authority_sha256)
VALUES
  ('AUTHORITY','canary://t-decctx/authority','1.0.0',encode(extensions.digest(convert_to('AUTHORITY_V1','UTF8'),'sha256'),'hex')),
  ('POLICY','canary://t-decctx/policy','1.0.0',encode(extensions.digest(convert_to('POLICY_V1','UTF8'),'sha256'),'hex')),
  ('TERMS','canary://t-decctx/terms','1.0.0',encode(extensions.digest(convert_to('TERMS_V1','UTF8'),'sha256'),'hex'));

DO $proof$
DECLARE
  v_auth_refs jsonb;
  v_auth_ref text; v_auth_version text; v_auth_sha text;
  v_policy_ref text; v_policy_version text; v_policy_sha text;
  v_terms_ref text; v_terms_version text; v_terms_sha text;
  v_ig_context jsonb;
  v_non_ig_context jsonb;
  v_record jsonb;
  v_resolve jsonb;
BEGIN
  SELECT jsonb_agg(
           jsonb_build_object(
             'capability_code',capability_code,
             'version',version,
             'manifest_sha256',manifest_sha256,
             'authority_ref','supabase://public/lf_capability_current/'||capability_code||'@'||version||'#'||manifest_sha256
           ) ORDER BY capability_code
         )
    INTO v_auth_refs
  FROM public.lf_capability_current
  WHERE capability_code IN ('CURRENTNESS_AUTHORITY','CAPABILITY_VERSION_COMPATIBILITY','TYPED_EVIDENCE_REGISTRY');

  IF jsonb_array_length(coalesce(v_auth_refs,'[]'::jsonb))<>3 THEN
    RAISE EXCEPTION 'T_DECCTX_PROOF_REQUIRED_AUTHORITIES_MISSING';
  END IF;

  SELECT authority_ref,authority_version,authority_sha256 INTO v_auth_ref,v_auth_version,v_auth_sha
  FROM t_decctx_latest_authority WHERE authority_kind='AUTHORITY';
  SELECT authority_ref,authority_version,authority_sha256 INTO v_policy_ref,v_policy_version,v_policy_sha
  FROM t_decctx_latest_authority WHERE authority_kind='POLICY';
  SELECT authority_ref,authority_version,authority_sha256 INTO v_terms_ref,v_terms_version,v_terms_sha
  FROM t_decctx_latest_authority WHERE authority_kind='TERMS';

  v_ig_context := jsonb_build_object(
    'evidence_schema_version','decision-context-asof/v1',
    'decision_ref','canary://t-decctx/decision/ig/001',
    'consumer_code','IG_CURATOR_VALIDATOR_REFACTOR_V2:N-16',
    'subject',jsonb_build_object('ref','canary://t-decctx/subject/shared','version','S1'),
    'actor_authority',jsonb_build_object(
      'actor_ref','actor://SUPER_ADMIN/test',
      'authority_ref',v_auth_ref,'authority_version',v_auth_version,'authority_sha256',v_auth_sha
    ),
    'governing',jsonb_build_object(
      'policy_ref',v_policy_ref,'policy_version',v_policy_version,'policy_sha256',v_policy_sha,
      'terms_ref',v_terms_ref,'terms_version',v_terms_version,'terms_sha256',v_terms_sha
    ),
    'times',jsonb_build_object('decided_at','2026-10-04T14:30:00Z','effective_at','2026-10-04T14:30:00Z'),
    'authority_refs',v_auth_refs,
    'extensions',jsonb_build_object('proof_case','NEG_LATEST_MUTATION','authoritative',false)
  );

  v_record := public.fn_lf_decision_context_asof_record_v1(v_ig_context,'CHATGPT-T-DECCTX-NEGATIVE-PROOF');
  IF v_record->>'state'<>'RECORDED' THEN
    RAISE EXCEPTION 'T_DECCTX_IG_CONTEXT_RECORD_FAILED:%',v_record;
  END IF;

  -- Mutate latest authority/policy/terms after the decision context was recorded.
  UPDATE t_decctx_latest_authority
  SET authority_version='2.0.0',
      authority_sha256=encode(extensions.digest(convert_to(authority_kind||'_V2','UTF8'),'sha256'),'hex');

  v_resolve := public.fn_lf_decision_context_asof_resolve_v1(
    'IG_CURATOR_VALIDATOR_REFACTOR_V2:N-16','canary://t-decctx/subject/shared','2026-10-04T14:31:00Z'::timestamptz
  );

  IF v_resolve->>'state'<>'RESOLVED'
     OR v_resolve->>'latest_reinterpreted'<>'false'
     OR v_resolve#>>'{context,actor_authority,authority_version}'<>'1.0.0'
     OR v_resolve#>>'{context,actor_authority,authority_sha256}'<>v_auth_sha
     OR v_resolve#>>'{context,governing,policy_version}'<>'1.0.0'
     OR v_resolve#>>'{context,governing,policy_sha256}'<>v_policy_sha
     OR v_resolve#>>'{context,governing,terms_version}'<>'1.0.0'
     OR v_resolve#>>'{context,governing,terms_sha256}'<>v_terms_sha THEN
    RAISE EXCEPTION 'T_DECCTX_NEGATIVE_ASOF_FAILED:%',v_resolve;
  END IF;

  IF EXISTS (SELECT 1 FROM t_decctx_latest_authority WHERE authority_version<>'2.0.0') THEN
    RAISE EXCEPTION 'T_DECCTX_NEGATIVE_LATEST_MUTATION_NOT_APPLIED';
  END IF;

  -- Second consumer: same exact input contract, no IG-specific branch or column.
  SELECT authority_ref,authority_version,authority_sha256 INTO v_auth_ref,v_auth_version,v_auth_sha
  FROM t_decctx_latest_authority WHERE authority_kind='AUTHORITY';
  SELECT authority_ref,authority_version,authority_sha256 INTO v_policy_ref,v_policy_version,v_policy_sha
  FROM t_decctx_latest_authority WHERE authority_kind='POLICY';
  SELECT authority_ref,authority_version,authority_sha256 INTO v_terms_ref,v_terms_version,v_terms_sha
  FROM t_decctx_latest_authority WHERE authority_kind='TERMS';

  v_non_ig_context := jsonb_build_object(
    'evidence_schema_version','decision-context-asof/v1',
    'decision_ref','canary://t-decctx/decision/story-creator/001',
    'consumer_code','STORY_CREATOR',
    'subject',jsonb_build_object('ref','canary://t-decctx/subject/story','version','SPEC-1'),
    'actor_authority',jsonb_build_object(
      'actor_ref','actor://SUPER_ADMIN/test',
      'authority_ref',v_auth_ref,'authority_version',v_auth_version,'authority_sha256',v_auth_sha
    ),
    'governing',jsonb_build_object(
      'policy_ref',v_policy_ref,'policy_version',v_policy_version,'policy_sha256',v_policy_sha,
      'terms_ref',v_terms_ref,'terms_version',v_terms_version,'terms_sha256',v_terms_sha
    ),
    'times',jsonb_build_object('decided_at','2026-10-04T14:32:00Z','effective_at','2026-10-04T14:32:00Z'),
    'authority_refs',v_auth_refs,
    'extensions',jsonb_build_object('proof_case','NON_IG_CONSUMER','authoritative',false)
  );

  v_record := public.fn_lf_decision_context_asof_record_v1(v_non_ig_context,'CHATGPT-T-DECCTX-NON-IG-PROOF');
  IF v_record->>'state'<>'RECORDED' OR v_record->>'consumer_code'<>'STORY_CREATOR' THEN
    RAISE EXCEPTION 'T_DECCTX_NON_IG_RECORD_FAILED:%',v_record;
  END IF;

  v_resolve := public.fn_lf_decision_context_asof_resolve_v1(
    'STORY_CREATOR','canary://t-decctx/subject/story','2026-10-04T14:33:00Z'::timestamptz
  );
  IF v_resolve->>'state'<>'RESOLVED'
     OR v_resolve#>>'{context,evidence_schema_version}'<>'decision-context-asof/v1'
     OR v_resolve->>'consumer_code'<>'STORY_CREATOR' THEN
    RAISE EXCEPTION 'T_DECCTX_NON_IG_RESOLVE_FAILED:%',v_resolve;
  END IF;

  RAISE NOTICE 'T_DECCTX_PROOF_PASS negative=PASS non_ig=PASS schema=decision-context-asof/v1';
END
$proof$;

ROLLBACK;

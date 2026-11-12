-- LOTE 13 incremental PG18 sandbox: family birth proposal + expiry/review states.
\set ON_ERROR_STOP on
SET search_path = rule_quality_l13, public;

-- T24: SUPER_ADMIN denied even if can_approve flag is true.
DO $$
DECLARE blocked boolean:=false;err text:='';
BEGIN
 BEGIN
  PERFORM propose_family_birth('lf','NUEVA_FAMILIA','Distinct regulatory scope','lf-super',
   '{"scope_difference":"distinct","owner_impact":"reviewed","decision_ref":"SBX-24","source_ref":"test"}'::jsonb);
 EXCEPTION WHEN insufficient_privilege THEN blocked:=true;err:=SQLERRM;
 END;
 PERFORM assert_l13('T24_ADMIN_FAMILY_BIRTH_REJECTED',blocked,
 '42501 BLOCK_SUPER_ADMIN_APPROVAL',jsonb_build_object('rejected',blocked,'error',err));
END $$;

-- T25: missing semantic evidence forbids new-family proposal.
DO $$
DECLARE blocked boolean:=false;err text:='';
BEGIN
 BEGIN
  PERFORM propose_family_birth('lf','NUEVA_FAMILIA','Distinct regulatory scope','lf-owner','{}'::jsonb);
 EXCEPTION WHEN check_violation THEN blocked:=true;err:=SQLERRM;
 END;
 PERFORM assert_l13('T25_FAMILY_BIRTH_WITHOUT_EVIDENCE_REJECTED',blocked,
 '23514 BLOCK_BIRTH_EVIDENCE_MISSING',jsonb_build_object('rejected',blocked,'error',err));
END $$;

-- T26: proposal recorded, mapping and family catalog remain unchanged.
DO $$
DECLARE v_id bigint;family_total int;proposal_state text;
BEGIN
 v_id:=propose_family_birth('lf','NUEVA_FAMILIA','Distinct regulatory scope','lf-owner',
  '{"scope_difference":"subject and consumers distinguish the category",
     "owner_impact":"downstream mappings and rules assessed in sandbox",
     "decision_ref":"SBX-OWNER-PROPOSAL-26","source_ref":"L12-map"}'::jsonb);
 SELECT count(*) INTO family_total FROM families WHERE project_code='lf';
 SELECT status INTO proposal_state FROM family_birth_requests WHERE request_id=v_id;
 PERFORM assert_l13('T26_FAMILY_BIRTH_PROPOSED_NOT_APPLIED',
 v_id IS NOT NULL AND family_total=15 AND proposal_state='PROPOSED',
 'proposal only, LF family count stays 15',
 jsonb_build_object('request_id',v_id,'families_unchanged',family_total,'status',proposal_state));
END $$;

-- T27: CADUCADA occurs only when owner expressly decides EXPIRE.
DO $$
DECLARE v_id bigint;v_state text;v_to timestamptz;v_due timestamptz;
BEGIN
 v_id:=decide_rule_review('lf','LF-SYN-0010','lf-owner','EXPIRE',
 '{"source_ref":"SBX-27","rationale":"explicit owner-approved expiry"}'::jsonb,
 '2026-11-12T00:00:00Z');
 SELECT state,effective_to,next_review_at INTO v_state,v_to,v_due
 FROM rules WHERE project_code='lf' AND rule_code='LF-SYN-0010';
 PERFORM assert_l13('T27_OWNER_CADUCADA_TRANSITION',
 v_id IS NOT NULL AND v_state='CADUCADA' AND v_to='2026-11-12T00:00:00Z'::timestamptz
 AND v_due IS NULL,
 'owner EXPIRE => CADUCADA, effective_to set, next_review_at cleared',
 jsonb_build_object('decision_id',v_id,'state',v_state,'effective_to',v_to,'next_review_at',v_due));
END $$;

-- T28: EN_REVISION is not auto-caducada; SALY owner can revalidate it.
DO $$
DECLARE due_count int;v_id bigint;st text;
BEGIN
 UPDATE rules SET state='EN_REVISION',next_review_at='2026-10-01T00:00:00Z'
 WHERE project_code='saly' AND rule_code='SALY-SYN-0006';
 SELECT count(*) INTO due_count FROM list_review_due('saly','2026-11-12T00:00:00Z');
 v_id:=decide_rule_review('saly','SALY-SYN-0006','saly-owner','KEEP_VIGENTE',
 '{"source_ref":"SBX-28","rationale":"owner approved SALY rule after review"}'::jsonb,
 '2026-11-12T00:00:00Z');
 SELECT state INTO st FROM rules WHERE project_code='saly' AND rule_code='SALY-SYN-0006';
 PERFORM assert_l13('T28_REVIEW_STATE_OWNER_DECISION',
 due_count=0 AND v_id IS NOT NULL AND st='VIGENTE',
 'EN_REVISION not auto-due, owner restores VIGENTE',
 jsonb_build_object('due_before_decision',due_count,'decision_id',v_id,'state_after',st));
END $$;

-- Final: 28 raw cases. Fail if any missing.
DO $$
DECLARE n int;
BEGIN
 SELECT count(*) INTO n FROM sandbox_test_results WHERE status='PASS';
 IF n<>28 THEN RAISE EXCEPTION 'L13_FINAL_TEST_COUNT_MISMATCH: %',n; END IF;
END $$;
SELECT jsonb_build_object('status','SANDBOX_TESTS_OK',
  'test_count',count(*),'cases',jsonb_agg(jsonb_build_object(
    'id',test_id,'status',status,'expected',expected,'observed',observed) ORDER BY test_id))
FROM sandbox_test_results;

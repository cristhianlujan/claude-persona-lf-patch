-- LF IG 07:07: source-bound diagnosis, NOT a change to the promotion policy.
-- PG17 BEGIN/ROLLBACK, no artificial tests, judge, approval, or pending-state edits.
-- Existing pilot CANDIDATO ...002 must remain untouched; old ...001 remains VIGENTE.
BEGIN;
DO $lf_b2b_002_promotion_guard_audit_pg17$
DECLARE
  v_old CONSTANT text:='B2B-RULE-VALIDATION-VALID-ONLY-001';
  v_new CONSTANT text:='B2B-RULE-VALIDATION-VALID-ONLY-002';
  v_parent CONSTANT text:='EXEC-PROFILE-GATE2-258A773626E5527875866440';
  v_child CONSTANT text:='EXEC-SKILL-F491C7DCB572ED08';
  v_rules_before text;
  v_rules_after text;
  v_hist_before text;
  v_hist_after text;
  v_old_status text;
  v_new_status text;
  v_cat text;
  v_pending boolean;
  v_score jsonb;
  v_src_score text;
  v_src_create text;
  v_src_writer text;
  v_raw_sha text;
  v_judge text;
  v_ref boolean;
  v_a integer;
  v_b integer;
  v_c integer;
  v_d integer;
  v_max_score integer;
  v_tests integer;
  v_links integer;
  v_cites integer;
BEGIN
  IF current_setting('server_version_num')::integer/10000<>17 THEN
    RAISE EXCEPTION 'LF_B2B_PROMOTION_PG17_REQUIRED'; END IF;
  SELECT md5(coalesce(jsonb_agg(to_jsonb(r) ORDER BY codigo)::text,'[]'))
    INTO v_rules_before FROM lf_ops.reglas r;
  SELECT md5(coalesce(jsonb_agg(to_jsonb(h) ORDER BY codigo,version)::text,'[]'))
    INTO v_hist_before FROM lf_ops.reglas_versiones h;
  SELECT estado,categoria,pendiente_decision INTO STRICT v_new_status,v_cat,v_pending
    FROM lf_ops.reglas WHERE codigo=v_new;
  SELECT estado INTO STRICT v_old_status
    FROM lf_ops.reglas WHERE codigo=v_old;
  IF v_old_status<>'VIGENTE' OR v_new_status<>'CANDIDATO'
     OR v_cat<>'VALIDATION' OR v_pending IS DISTINCT FROM TRUE THEN
    RAISE EXCEPTION 'LF_B2B_PROMOTION_PILOT_STATE_DRIFT'; END IF;
  v_score:=public.lf_rule_promotion_score_v1(v_parent,v_new);
  IF v_score->>'decision' IS DISTINCT FROM 'BLOCKED'
    OR v_score->>'hard_block' IS DISTINCT FROM 'true'
    OR (v_score->>'score')::integer<>0
  THEN RAISE EXCEPTION 'LF_B2B_PROMOTION_SCORE_NOT_EXPECTED:%',v_score; END IF;

  SELECT evidence_payload#>>'{semantic_judge_result,verdict}' INTO STRICT v_judge
    FROM public.lf_operation_execution_steps
    WHERE execution_id=v_parent AND step_id='semantic_judge'
      AND status='STEP_PASS_WITH_EVIDENCE';
  IF v_judge IS DISTINCT FROM 'PASS_TRAIN_EVIDENCE_AUTOMATICO'
  THEN RAISE EXCEPTION 'LF_B2B_PROMOTION_STEP70_VERDICT_DRIFT:%',v_judge; END IF;
  SELECT evidence_payload->>'raw_output_sha256' INTO STRICT v_raw_sha
    FROM public.lf_operation_execution_steps
    WHERE execution_id=v_parent AND step_id='execute_profile'
      AND status='STEP_PASS_WITH_EVIDENCE';
  IF v_raw_sha !~ '^[0-9a-f]{64}$' THEN RAISE EXCEPTION 'LF_B2B_PROMOTION_STEP50_SHA_MISSING'; END IF;

  SELECT EXISTS(
    SELECT 1 FROM public.lf_operation_execution_steps s,
      jsonb_array_elements(s.evidence_payload#>'{profile_output,deliverable_created,product_decision,source_refs}') x
    WHERE s.execution_id=v_parent AND s.step_id='execute_profile'
      AND x->>'source_ref'='supabase://lf_ops.reglas/'||v_new)
    INTO v_ref;
  IF v_ref THEN RAISE EXCEPTION 'LF_B2B_PROMOTION_SOURCE_REF_UNEXPECTEDLY_PRESENT'; END IF;
  SELECT count(*) INTO v_tests FROM lf_ops.regla_behavior_tests WHERE regla_codigo=v_new;
  SELECT count(*) INTO v_links FROM lf_ops.reglas_pantallas rp
     JOIN lf_ops.reglas r ON r.id=rp.regla_id WHERE r.codigo=v_new;
  SELECT count(*) INTO v_cites FROM lf_ops.reglas r
    WHERE r.codigo<>v_old AND r.codigo<>v_new AND r.valor_config::text LIKE '%'||v_old||'%';
  IF v_tests<>0 OR v_links<>0 OR v_cites<>3
    OR NOT EXISTS(SELECT 1 FROM public.lf_ig_rule_change_v2 ch
       WHERE ch.parent_execution_id=v_parent
       AND ch.child_execution_id=v_child AND ch.rule_code=v_new
       AND ch.kind='CREATE' AND ch.state='CANDIDATE_VERIFIED')
  THEN RAISE EXCEPTION 'LF_B2B_PROMOTION_ACTUAL_EVIDENCE_DRIFT'; END IF;

  v_src_score:=pg_get_functiondef('public.lf_rule_promotion_score_v1(text,text)'::regprocedure);
  v_src_create:=pg_get_functiondef('public.lf_skill_o_rule_create_v2(text,jsonb,text,text,text)'::regprocedure);
  v_src_writer:=pg_get_functiondef('public.lf_regla_candidate_write_v1(text,text,text,text,text,text,text,jsonb,boolean,text)'::regprocedure);
  -- The deployed contracts, not hypothetical scores, force the conflict:
  -- CREATE requires pending_decision TRUE; scorer sets hard_block TRUE for TRUE.
  IF position('after_row->>''pendiente_decision''<>''true''' in v_src_create)=0
    OR position('''CANDIDATO'',p_origen,true,v_review,p_execution_id' in v_src_writer)=0
    OR position('hard_block:=coalesce(r.pendiente_decision,true) OR' in v_src_score)=0
    OR position('PASS_INDEPENDENT_SEMANTIC' in v_src_score)=0
    OR position('PASS_REVIEWED_CURRENT_CONTEXT' in v_src_score)=0
    OR position('PASS_TRAIN_EVIDENCE_AUTOMATICO' in v_src_score)>0
  THEN RAISE EXCEPTION 'LF_B2B_PROMOTION_SOURCE_CONTRACT_CHANGED_REEVALUATE'; END IF;

  -- This is an upper bound on the EXISTING score terms, NOT fabricated PG evidence:
  -- even perfect source-bound V3 (B=30,D=10), dual PG behavior test (A=40),
  -- but legitimate CREATE pending TRUE (C=0), total maximum 80, AUTO >=85
  -- AND hard_block=false are jointly impossible until authorized resolution.
  v_a:=40; v_b:=30; v_c:=0; v_d:=10;
  v_max_score:=v_a+v_b+v_c+v_d;
  IF v_max_score<>80
    OR v_max_score>=85
    OR NOT v_pending
  THEN RAISE EXCEPTION 'LF_B2B_PROMOTION_DESIGN_BOUND_NOT_PROVEN'; END IF;
  RAISE NOTICE 'LF_B2B_PG17_GUARD_DIAG_PASS:CURRENT score=% hard_block=% pending_decision=% category=% native_step70=% new_tests=% new_links=%',
    v_score->>'score',v_score->>'hard_block',v_pending,v_cat,v_judge,v_tests,v_links;
  RAISE NOTICE 'LF_B2B_PG17_GUARD_DESIGN_INCOMPATIBILITY:CREATE_PENDING_TRUE+PROMOTION_AUTO_REQUIRES_FALSE;A40+B30+C0+D10=80_LT_85;manual_review_needed_if_new_PROMOTION_RUN_VALID';
  SELECT md5(coalesce(jsonb_agg(to_jsonb(r) ORDER BY codigo)::text,'[]'))
    INTO v_rules_after FROM lf_ops.reglas r;
  SELECT md5(coalesce(jsonb_agg(to_jsonb(h) ORDER BY codigo,version)::text,'[]'))
    INTO v_hist_after FROM lf_ops.reglas_versiones h;
  IF v_rules_after IS DISTINCT FROM v_rules_before
    OR v_hist_after IS DISTINCT FROM v_hist_before
    OR EXISTS(SELECT 1 FROM public.lf_rule_promotion_v1 WHERE rule_code=v_new)
  THEN RAISE EXCEPTION 'LF_B2B_PG17_GUARD_PROOF_CAUSED_SIDE_EFFECTS'; END IF;
  RAISE NOTICE 'LF_B2B_PG17_GUARD_READBACK_PASS:old=VIGENTE:new=CANDIDATO:rules_unchanged:versions_unchanged:promotion_absent';
END;
$lf_b2b_002_promotion_guard_audit_pg17$;
ROLLBACK;

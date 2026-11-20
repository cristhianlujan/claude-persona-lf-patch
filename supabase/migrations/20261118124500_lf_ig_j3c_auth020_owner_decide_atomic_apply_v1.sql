-- PR-J3C: owner 2026-11-18 12:00, exact approved functional AUTH-020.
-- Sequential AFTER PR-J3B; official owner decide_v2 calls skill child and
-- PR-H finalize_v2 in the SAME transaction. Parent RUN stays IN_PROGRESS
-- until the separately governed Step80/report closure.
-- No changes to PR-H code, AUTH-018/019, policy20, permission38, RLS or rulesets.
BEGIN;
-- EKB ACTIVE LF-OWNER-OVERRIDE-NO_PROMOTION-MANIFEST-20261115-001:
-- A documentary no_promotion flag is NOT an authorization veto.
-- Keep parent EXECUTION, exact request SHA, invoker, source and owner guards.
DO $j3c_guard$
DECLARE d text; d0 text;
BEGIN
 d:=pg_get_functiondef('public.lf_ig_rule_child_guard_v2(text,jsonb,text,text,text,text)'::regprocedure);
 IF md5(d) <> 'ce5d02fc728ec18fc0ab1963364c392c'
 THEN RAISE EXCEPTION 'PR_J3C_CHILD_GUARD_PREIMAGE_DRIFT'; END IF;
 d0:=d;
 d:=replace(d,
   $from_j3c$ AND manifest->>'no_promotion'='true';$from_j3c$,
   $to_j3c$;$to_j3c$);
 IF d=d0 OR position($no_promotion_j3c$manifest->>'no_promotion'='true'$no_promotion_j3c$ IN d)>0
 THEN RAISE EXCEPTION 'PR_J3C_CHILD_GUARD_REPLACEMENT_FAILED'; END IF;
 IF position($sha_j3c$p_request_sha IS DISTINCT FROM v_par.request_sha256$sha_j3c$ IN d)=0
    OR position($write_j3c$manifest->>'read_only'='true' AND manifest->>'no_write'='true'$write_j3c$ IN d)=0
 THEN RAISE EXCEPTION 'PR_J3C_CHILD_GUARD_SECURITY_GATES_MISSING'; END IF;
 EXECUTE d;
END $j3c_guard$;

-- Keep canonical handoff trigger unchanged: child V2 opener must place
-- source snapshot SHA inside manifest.profile_handoff, not only at root.
DO $j3c_handoff$
DECLARE d text; d0 text;
BEGIN
 d:=pg_get_functiondef('public.lf_skill_o_rule_update_v2(text,jsonb,text,text,text)'::regprocedure);
 IF md5(d) <> 'ee2d52efc6c93327e1d585c73b71e0bc'
 THEN RAISE EXCEPTION 'PR_J3C_CHILD_OPENER_PREIMAGE_DRIFT'; END IF;
 d0:=d;
 d:=replace(d,
   $from_j3c$'source_execution_id',p_parent,'skill_run_id',p_run,'via','SKILL_INVOKER'),
   'analysis_snapshot_sha256',v_source$from_j3c$,
   $to_j3c$'source_execution_id',p_parent,'skill_run_id',p_run,'via','SKILL_INVOKER',
    'analysis_snapshot_sha256',v_source),
   'analysis_snapshot_sha256',v_source$to_j3c$);
 IF d=d0 THEN RAISE EXCEPTION 'PR_J3C_CHILD_OPENER_HANDOFF_REPLACEMENT_FAILED'; END IF;
 IF position($check_j3c$'source_execution_id',p_parent,'skill_run_id',p_run,'via','SKILL_INVOKER',
    'analysis_snapshot_sha256',v_source$check_j3c$ IN d)=0
 THEN RAISE EXCEPTION 'PR_J3C_CHILD_OPENER_HANDOFF_SNAPSHOT_NOT_BOUND'; END IF;
 EXECUTE d;
END $j3c_handoff$;

DO $j3c$
DECLARE parent_run CONSTANT text:='EXEC-PROFILE-GATE2-D53B143BD852CB33AB25257F';
        rule CONSTANT text:='B2B-RULE-AUTH-020';
        src CONSTANT text:='8cec17753d80d2df4d40bb1ed3b5e7d5bb81b9942787cde667b3aae79e750df8';
        patch_sha CONSTANT text:='adaffe6a15e705fc4ec48fa809135088736915cd0d4446691ede078899704a02';
        candidate_sha CONSTANT text:='16729473fcfc98cb04a04d2489cfa6338cb59f1c1cace12ce9443a4c24bee061';
        old_md5 CONSTANT text:='7588d5a7de4d94a864fca9e63cd10ebe';
        new_md5 CONSTANT text:='9d558e62bd85cefe6dbe0f4147e59056';
        before18 text; before19 text; before20 text; before38 text;
        after18 text; after19 text; after20 text; after38 text;
        before_rule text; after_rule text;
        verify jsonb; approval jsonb;
        v_hold jsonb;
BEGIN
 -- In the PG17 schema-only rehearsal there is no live parent RUN; the
 -- migration still compiles under BEGIN/ROLLBACK without fake receipts.
 -- The live Train lane must find the same actual admitted parent and will
 -- roll back ALL effects if any binding/readback below differs.
 IF EXISTS (
   SELECT 1 FROM public.lf_operation_execution
   WHERE execution_id=parent_run AND status='IN_PROGRESS'
 ) THEN
   SELECT md5((to_jsonb(r)-'updated_at')::text) INTO before_rule
   FROM lf_ops.reglas r WHERE codigo=rule AND estado='VIGENTE';
   IF before_rule IS DISTINCT FROM old_md5
   THEN RAISE EXCEPTION 'PR_J3C_AUTH020_PREIMAGE_MD5_DRIFT:%',before_rule; END IF;

   IF (SELECT count(*) FROM lf_ops.reglas)<>579
   THEN RAISE EXCEPTION 'PR_J3C_RULE_INVENTORY_DRIFT'; END IF;
   IF EXISTS(SELECT 1 FROM public.lf_ig_owner_decision_v2
      WHERE parent_execution_id=parent_run AND rule_code=rule)
   THEN RAISE EXCEPTION 'PR_J3C_OWNER_DECISION_ALREADY_EXISTS'; END IF;

   SELECT md5((to_jsonb(r)-'updated_at')::text) INTO before18
     FROM lf_ops.reglas r WHERE codigo='B2B-RULE-AUTH-018';
   SELECT md5((to_jsonb(r)-'updated_at')::text) INTO before19
     FROM lf_ops.reglas r WHERE codigo='B2B-RULE-AUTH-019';
   SELECT md5((to_jsonb(p)-'updated_at')::text) INTO before20
     FROM lf_ops.politicas_seguridad p WHERE security_policy_id=20;
   SELECT md5(coalesce(jsonb_agg(to_jsonb(p) ORDER BY p.profile_code,p.permission_code)::text,'[]'))
     INTO before38 FROM lf_ops.perfiles_permisos p WHERE permission_id=38;

   verify:=public.lf_ig_step70_functional_train_auto_v1(parent_run);
   IF verify->>'status' IS DISTINCT FROM 'PASS'
      OR verify->>'verdict' IS DISTINCT FROM 'PASS_TRAIN_EVIDENCE_AUTOMATICO'
      OR verify#>>'{train_evidence,rule_code}' IS DISTINCT FROM rule
      OR verify#>>'{train_evidence,source_snapshot_sha256}' IS DISTINCT FROM src
      OR verify#>>'{train_evidence,proposal_sha256}' IS DISTINCT FROM patch_sha
      OR verify#>>'{train_evidence,candidate_snapshot_sha256}' IS DISTINCT FROM candidate_sha
      OR NOT EXISTS(
        SELECT 1 FROM public.lf_operation_execution_steps
        WHERE execution_id=parent_run AND step_id='semantic_judge'
          AND status='STEP_PASS_WITH_EVIDENCE'
          AND evidence_payload->'semantic_judge_result' IS NOT DISTINCT FROM verify
      )
   THEN RAISE EXCEPTION 'PR_J3C_STEP70_AUTO_OR_RECEIPT_DRIFT:%',verify->>'blocking_code'; END IF;

   -- The official owner entry point is the sole effect path. It invokes
   -- RULE_UPDATE_APPLY child (7 steps) and finalize_v2 atomically.
   approval:=public.lf_ig_rule_owner_decide_v2(
      parent_run,rule,src,
      '{"usuario":"Cristhian Lujan","veredicto":"APROBAR"}'::jsonb);
   IF approval->>'status' IS DISTINCT FROM 'APPROVED_AND_VIGENTE_VERIFIED'
      OR approval->>'kind' IS DISTINCT FROM 'CORRECT_VIGENTE'
      OR approval->>'proposal_sha256' IS DISTINCT FROM patch_sha
      OR approval->>'finalized_snapshot_sha256' IS DISTINCT FROM candidate_sha
      OR approval->>'write_performed' IS DISTINCT FROM 'true'
   THEN RAISE EXCEPTION 'PR_J3C_OFFICIAL_OWNER_DECIDE_FINALIZE_FAILED:%',approval; END IF;

   SELECT md5((to_jsonb(r)-'updated_at')::text),r.valor_config
     INTO after_rule,v_hold FROM lf_ops.reglas r WHERE codigo=rule AND estado='VIGENTE';
   IF after_rule IS DISTINCT FROM new_md5
     OR v_hold ? 'hold_hours'
     OR v_hold ? 'human_approval_count_required'
   THEN RAISE EXCEPTION 'PR_J3C_AUTH020_POSTIMAGE_OR_HOLD_APPROVAL_DRIFT:%',after_rule; END IF;
   IF (SELECT count(*) FROM lf_ops.reglas)<>579
   THEN RAISE EXCEPTION 'PR_J3C_RULE_COUNT_CHANGED'; END IF;
   SELECT md5((to_jsonb(r)-'updated_at')::text) INTO after18
     FROM lf_ops.reglas r WHERE codigo='B2B-RULE-AUTH-018';
   SELECT md5((to_jsonb(r)-'updated_at')::text) INTO after19
     FROM lf_ops.reglas r WHERE codigo='B2B-RULE-AUTH-019';
   SELECT md5((to_jsonb(p)-'updated_at')::text) INTO after20
     FROM lf_ops.politicas_seguridad p WHERE security_policy_id=20;
   SELECT md5(coalesce(jsonb_agg(to_jsonb(p) ORDER BY p.profile_code,p.permission_code)::text,'[]'))
     INTO after38 FROM lf_ops.perfiles_permisos p WHERE permission_id=38;
   IF after18 IS DISTINCT FROM before18
      OR after19 IS DISTINCT FROM before19
      OR after20 IS DISTINCT FROM before20
      OR after38 IS DISTINCT FROM before38
   THEN RAISE EXCEPTION 'PR_J3C_PROTECTED_ADJACENT_ASSET_DRIFT'; END IF;
 END IF;
END $j3c$;
COMMIT;

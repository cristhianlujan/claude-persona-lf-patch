-- PG17 isolated skill child 10..60 adapter positive and negatives.
DO $test$
DECLARE
 v_parent constant text:='EXEC-PROFILE-GATE2-8DC96C01CF8C81DEEAB067DA';
 v_child constant text:='EXEC-SKILL-49797550002EE84C';
 v_path constant text:='skills/profile_creator/validators/compare_s26_profile_evolution_v1.py';
 v_repo constant text:='cristhianlujan/claude-persona-lf-patch';
 v_context jsonb;
 v_changed_main jsonb;
 v_plan jsonb;
 v_p10 jsonb;
 v_p20 jsonb;
 v_p30 jsonb;
 v_p40 jsonb;
 v_p50 jsonb;
 v_p60 jsonb;
 v_result jsonb;
BEGIN
 v_context:=jsonb_build_object(
   'main_sha',repeat('a',40),'target_blob_sha',repeat('b',40),
   'github_owner',jsonb_build_object(
     'asset_code','ACT-0045','root_path','skills/profile_creator',
     'readme_blob_sha',repeat('d',40),'main_sha',repeat('a',40)),
   'caller',jsonb_build_object(
     'method','GITHUB_ACTIONS_OIDC_GOVERNED_NATIVE_PROFILE_CONTINUATION_V1',
     'repository',v_repo,'run_id','12345678900',
     'workflow_sha',repeat('e',40),
     'workflow_ref',v_repo||'/.github/workflows/lf-edge-deploy-credential-readback.yml@refs/heads/main')
 );
 v_p10:=jsonb_build_object(
   'router_read',repeat('c',64),'action','SKILL_UPDATE','blocking_codes','[]'::jsonb);
 v_p20:=jsonb_build_object('codigo_activo','ACT-0045','repo_path','skills/profile_creator',
   'skill_identity','PROFILE_CREATOR','exact_skill_resolved',true,'blocking_codes','[]'::jsonb);
 v_p30:=jsonb_build_object('baseline_revision',repeat('a',40),
   'baseline_files',jsonb_build_array(jsonb_build_object('path',v_path,'blob_sha',repeat('b',40))),
   'before_evidence','Git exact frozen main ref and missing canonical_validator.transport',
   'blocking_codes','[]'::jsonb);
 v_p40:=jsonb_build_object(
   'defect','Runtime validator transport is undeclared for the Repair profile',
   'root_cause','The S26 measurer does not detect absent canonical_validator transport',
   'minimal_patch_scope',jsonb_build_array(v_path),
   'preserved_constraints',jsonb_build_array('Router unchanged','No untested production promotion'),
   'evidence_ceiling','Local synthetic validation is not actual current runtime evidence',
   'blocking_codes','[]'::jsonb);
 v_p50:=jsonb_build_object(
   'positive_cases',jsonb_build_array('missing transport detected'),
   'negative_cases',jsonb_build_array('valid binding unchanged','missing validator path rejected'),
   'adversarial_cases',jsonb_build_array('no caller PASS injection','source main drift rejected'),
   'holdout','Falsified profile owner and changed binding blob must remain blocked',
   'blocking_codes','[]'::jsonb);

 -- Parent impersonation: even valid-looking payload cannot create a step.
 v_result:=public.lf_skill_update_child_step_v1('EXEC-PROFILE-GATE2-UNRELATED',
   v_child,'router','git:fixture',v_p10,v_context);
 IF v_result->>'code'<>'SKILL_UPDATE_STEP_PARENT_CHILD_BINDING_INVALID'
 THEN RAISE EXCEPTION 'FAIL_PARENT_IMPERSONATION:%',v_result; END IF;
 RAISE NOTICE 'PASS_WRONG_PARENT_BLOCKED';

 -- Direct PASS/derived assertions are never accepted from model or issue.
 v_result:=public.lf_skill_update_child_step_v1(v_parent,v_child,'router','git:fixture',
   v_p10||jsonb_build_object('server_assertions',jsonb_build_array('fake_pass')),v_context);
 IF v_result->>'code'<>'SKILL_UPDATE_CALLER_JUDGE_FIELDS_FORBIDDEN'
 THEN RAISE EXCEPTION 'FAIL_ASSERTION_INJECTION:%',v_result; END IF;
 RAISE NOTICE 'PASS_CALLER_ASSERTION_BLOCKED';

 -- Future gate 60 cannot leap over required predecessors.
 v_result:=public.lf_skill_update_child_step_v1(v_parent,v_child,
   'pre_write_execution_binding_gate','git:fixture','{"blocking_codes":[]}'::jsonb,v_context);
 IF v_result->>'code'<>'SKILL_UPDATE_PREWRITE_BINDING_NOT_PROVEN'
 THEN RAISE EXCEPTION 'FAIL_EARLY_PREWRITE:%',v_result; END IF;
 RAISE NOTICE 'PASS_EARLY_PREWRITE_BLOCKED';

 -- Wrong authenticated workflow, missing and tampered GitHub blob.
 v_result:=public.lf_skill_update_child_step_v1(v_parent,v_child,'router','git:fixture',
   v_p10,jsonb_set(v_context,'{caller,method}','"FORGED"'::jsonb));
 IF v_result->>'code'<>'SKILL_UPDATE_STEP_SERVER_CONTEXT_OR_DRIFT_INVALID'
 THEN RAISE EXCEPTION 'FAIL_FORGED_OIDC:%',v_result; END IF;
 RAISE NOTICE 'PASS_FORGED_CALLER_BLOCKED';
 v_result:=public.lf_skill_update_child_step_v1(v_parent,v_child,'router','git:fixture',
   v_p10,jsonb_set(v_context,'{target_blob_sha}',to_jsonb(repeat('f',40))));
 IF v_result->>'code'<>'SKILL_UPDATE_STEP_SERVER_CONTEXT_OR_DRIFT_INVALID'
 THEN RAISE EXCEPTION 'FAIL_SOURCE_DRIFT:%',v_result; END IF;
 RAISE NOTICE 'PASS_CHANGED_TARGET_BLOB_BLOCKED';

 -- Only this exact code/target and existing step chain can receive a PASS.
  v_result:=public.lf_skill_update_child_step_v1(v_parent,v_child,'router','git:fixture',v_p10,v_context);
 IF v_result->>'outcome'<>'STEP_RECORDED' THEN RAISE EXCEPTION 'FAIL_ROUTER:%',v_result; END IF;
 v_result:=public.lf_skill_update_child_step_v1(v_parent,v_child,'skill_resolve','git:fixture',v_p20,v_context);
 IF v_result->>'outcome'<>'STEP_RECORDED' THEN RAISE EXCEPTION 'FAIL_RESOLVE:%',v_result; END IF;
 v_result:=public.lf_skill_update_child_step_v1(v_parent,v_child,'baseline_read','git:fixture',v_p30,v_context);
 IF v_result->>'outcome'<>'STEP_RECORDED' THEN RAISE EXCEPTION 'FAIL_BASELINE:%',v_result; END IF;
 v_result:=public.lf_skill_update_child_step_v1(v_parent,v_child,'change_scope','git:fixture',v_p40,v_context);
 IF v_result->>'outcome'<>'STEP_RECORDED' THEN RAISE EXCEPTION 'FAIL_SCOPE:%',v_result; END IF;
 v_result:=public.lf_skill_update_child_step_v1(v_parent,v_child,'regression_plan','git:fixture',v_p50,v_context);
 IF v_result->>'outcome'<>'STEP_RECORDED' THEN RAISE EXCEPTION 'FAIL_PLAN:%',v_result; END IF;
 RAISE NOTICE 'PASS_STEPS_10_20_30_40_50_BOUND';

 -- Refresh new main with unchanged target blob and README: no stale plan may pass.
 v_changed_main:=jsonb_set(
   jsonb_set(v_context,'{main_sha}',to_jsonb(repeat('9',40))),
   '{github_owner,main_sha}',to_jsonb(repeat('9',40)));
 v_plan:=jsonb_build_array(jsonb_build_object('path',v_path,'content_sha256',repeat('6',64)));
 v_p60:=jsonb_build_object(
   'execution_id',v_child,'target_code','ACT-0045','target_path',v_path,
   'write_plan',v_plan,'write_plan_hash',
      encode(extensions.digest(convert_to(v_plan::text,'UTF8'),'sha256'),'hex'),
   'pre_write_gate_passed',true,'source_blob_sha',repeat('b',40),
   'bound_revision',repeat('a',40),'blocking_codes','[]'::jsonb);
 v_result:=public.lf_skill_update_child_step_v1(v_parent,v_child,
   'pre_write_execution_binding_gate','git:fixture',v_p60,v_changed_main);
 IF v_result->>'code'<>'SKILL_UPDATE_PREWRITE_BINDING_NOT_PROVEN'
 THEN RAISE EXCEPTION 'FAIL_STALE_GATE:%',v_result; END IF;
 RAISE NOTICE 'PASS_STALE_GATE_BLOCKED';

 v_p60:=jsonb_set(v_p60,'{bound_revision}',to_jsonb(repeat('9',40)));
 v_result:=public.lf_skill_update_child_step_v1(v_parent,v_child,
   'pre_write_execution_binding_gate','git:fixture',v_p60,v_changed_main);
 IF v_result->>'outcome'<>'STEP_RECORDED'
 THEN RAISE EXCEPTION 'FAIL_GATE:%',v_result; END IF;
 IF (SELECT manifest->>'pre_write_bound_main_revision' FROM public.lf_operation_execution
       WHERE execution_id=v_child) IS DISTINCT FROM repeat('9',40)
 THEN RAISE EXCEPTION 'FAIL_PREWRITE_READBACK'; END IF;
 IF (SELECT COUNT(*) FROM public.lf_operation_execution_steps
      WHERE execution_id=v_child AND status='STEP_PASS_WITH_EVIDENCE')<>7
 THEN RAISE EXCEPTION 'FAIL_STEP_COUNT'; END IF;
 RAISE NOTICE 'PASS_FRESH_REBIND_GATE_60_SEVEN_CLEAN_STEPS';

 -- This adapter NEVER accepts post-write operations (those require real GH/CI receipts).
 v_result:=public.lf_skill_update_child_step_v1(v_parent,v_child,'github_write',
    'git:fixture',v_p60,v_changed_main);
 IF v_result->>'code'<>'SKILL_UPDATE_STEP_REQUEST_INVALID'
 THEN RAISE EXCEPTION 'FAIL_POSTWRITE_ELEVATION:%',v_result; END IF;
 RAISE NOTICE 'PASS_NO_POSTWRITE_ELEVATION';
END $test$;

-- No privileges to invoke from anon or authenticated even with known IDs.
DO $acl$
BEGIN
 IF has_function_privilege('anon',
  'public.lf_skill_update_child_step_v1(text,text,text,text,jsonb,jsonb)','EXECUTE')
  OR has_function_privilege('authenticated',
  'public.lf_skill_update_child_step_v1(text,text,text,text,jsonb,jsonb)','EXECUTE')
 THEN RAISE EXCEPTION 'FAIL_PUBLIC_SKILL_STEP_EXECUTE_ACL'; END IF;
 RAISE NOTICE 'PASS_ONLY_SERVICE_ROLE_EXECUTE';
END $acl$;

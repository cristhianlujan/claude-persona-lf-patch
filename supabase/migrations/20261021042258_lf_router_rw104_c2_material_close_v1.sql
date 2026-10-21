-- RW1-04_C2 final material closure.
-- Consumes exact merged implementation evidence from PR #2996; no domain implementation occurs here.
BEGIN;
DO $rw104_c2_close$
DECLARE
  v_plan constant text := 'LF_ROUTER_ARCHITECTURE_WAVE_V1';
  v_unit constant text := 'RW1-04';
  v_cp constant text := 'RW1-04_C2';
  v_wi constant bigint := 1130;
  v_prior_md5 constant text := 'b84ab474cce2b8ca895c3fc3ef2d0b0e';
  v_actor constant text := 'LF_ROUTER_RW104_C2_MATERIAL_CLOSE_20261020';
  v_main constant text := '8ab8ae565803212c4b800c8f55b85c6ab960de32';
  v_run constant text := '39525468715';
  v_job constant text := '118978933270';
  v_merge_job constant text := '118979198556';
  v_exec constant text := 'EXEC-DB-TRAIN-PR2996-20261021010500-R39525468715';
  v_evidence constant text := 'https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/39525468715/job/118978933270';

  v_source jsonb := $source$
{
  "inputs":{
    "assets":["ACT-0001","ROUTER_DOWNSTREAM_AUTHORITY","OPERATION_EFFECT_GUARD","OPERATION_MATERIALIZATION_GUARD"],
    "events":[21263],
    "queries":[
      "SELECT p.proname,pg_get_function_identity_arguments(p.oid) args,p.proacl,md5(pg_get_functiondef(p.oid)) def_md5 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname IN ('lf_router_resolve_v1','lf_router_intent_handoff_v1','lf_router_intent_handoff_v2','lf_router_semantic_resume_validate_v1') ORDER BY p.proname",
      "SELECT (length(pg_get_functiondef('public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure))-length(replace(pg_get_functiondef('public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure),'lf_router_intent_handoff_v1(','')))/length('lf_router_intent_handoff_v1(') v1_sites,(length(pg_get_functiondef('public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure))-length(replace(pg_get_functiondef('public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure),'lf_router_intent_handoff_v2(','')))/length('lf_router_intent_handoff_v2(') v2_sites,md5(pg_get_functiondef('programacion.fn_lf_router_input_governance_resolve_v1(text,jsonb,text)'::regprocedure)) ig_md5,(SELECT count(*) FROM public.lf_router_action_registry WHERE status='ACTIVE') active_routes",
      "SELECT version,name FROM supabase_migrations.schema_migrations WHERE version='20261021010500' AND name='lf_router_rw104_c2_semantic_v2_implementation_v1'",
      "SELECT checkpoint_code,status,evidence_ref,assertion_receipt_sha256 FROM programacion.engineering_work_checkpoints WHERE work_item_id=1130 ORDER BY sequence_no"
    ],
    "db_objects":[
      "public.lf_router_resolve_v1",
      "public.lf_router_intent_handoff_v1",
      "public.lf_router_intent_handoff_v2",
      "public.lf_router_semantic_resume_validate_v1",
      "public.lf_router_action_registry",
      "programacion.fn_lf_router_input_governance_resolve_v1",
      "programacion.engineering_work_checkpoints",
      "supabase_migrations.schema_migrations"
    ],
    "artifacts":[
      "docs/programming-agent/router_wave/RW1_04_C1_SOURCE_REGRESSION_DIFF_BASELINE_V1.md",
      "docs/programming-agent/router_wave/RW1_04_C1_ERRATUM_HANDOFF_SITE_COUNT_V1.md",
      "docs/programming-agent/router_wave/RW1_03_C2_SEMANTIC_ABI_TRANSITION_V1.json",
      "supabase/migrations/20261021010500_lf_router_rw104_c2_semantic_v2_implementation_v1.sql",
      "sandbox/lf_contract_gate_test/router_wave/test_rw104_semantic_v2_source_v1.py"
    ]
  },
  "missing":[],
  "missing_typed":[],
  "expected_result":"Exact-main implemented semantic handoff V2 plus fail-closed resume validator, six V1 + six V2 Router emission sites, preserved legacy V1 and authority boundaries, semantic runtime still shadow/disabled.",
  "evidence_ref":"https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/39525468715/job/118978933270",
  "verification_boundary":"RW104_C2_IMPLEMENTATION_ONLY_SHADOW_DISABLED_NOT_E2E_OR_PRODUCTION",
  "source_snapshot_commit":"b7ec44a04d5e99d18884f26f3dddc85f86d0abf9",
  "source_git_blobs":{
    "c1_baseline":"ab2f5232ad429b5d78fd8a943ac94be76830b943",
    "c1_erratum":"d52489462ee0319a60f64dc797698d3934b5262b",
    "rw103_contract":"bfd571d5e7c7d1d80c5ed39414a822b4096c20d6",
    "implementation_migration":"14619e0a883d42db1e9b25f471e85a5800f970d7",
    "source_test":"ed6461d6f1d45b75e02692994f0c4a8a85517cb9"
  },
  "db_source_md5":{
    "lf_router_resolve_v1":"8cffdd7403c0ae40d5db19890ea4f944",
    "lf_router_intent_handoff_v1":"540bc1b60caf2e3f9d81461f99c509ef",
    "lf_router_intent_handoff_v2":"e6c5df658f322e0c67ee7a2bb5972410",
    "lf_router_semantic_resume_validate_v1":"4dc0dad03d7259009583e2f77f5930fb",
    "fn_lf_router_input_governance_resolve_v1":"72e153a7fbfe7b10a8c9ae694a61b334"
  },
  "runner_receipt":{
    "provider":"GITHUB_ACTIONS",
    "pr":2996,
    "run_id":"39525468715",
    "job_id":"118978933270",
    "merge_job_id":"118979198556",
    "conclusion":"success",
    "merged_main_sha":"8ab8ae565803212c4b800c8f55b85c6ab960de32",
    "execution_id":"EXEC-DB-TRAIN-PR2996-20261021010500-R39525468715"
  }
}
$source$::jsonb;

  v_material jsonb := jsonb_build_object(
    'schema','RW104_C2_MATERIAL_RESULT_V1',
    'implementation_written',true,
    'git_merged',true,
    'db_applied',true,
    'readback_passed',true,
    'pr',2996,
    'train_run_id',v_run,
    'train_job_id',v_job,
    'merge_job_id',v_merge_job,
    'execution_id',v_exec,
    'main_sha',v_main,
    'migration_version','20261021010500',
    'migration_blob','14619e0a883d42db1e9b25f471e85a5800f970d7',
    'source_test_blob','ed6461d6f1d45b75e02692994f0c4a8a85517cb9',
    'router_md5','8cffdd7403c0ae40d5db19890ea4f944',
    'handoff_v1_md5','540bc1b60caf2e3f9d81461f99c509ef',
    'handoff_v2_md5','e6c5df658f322e0c67ee7a2bb5972410',
    'resume_validator_md5','4dc0dad03d7259009583e2f77f5930fb',
    'router_v1_sites',6,
    'router_v2_sites',6,
    'negative_contract_probes',12,
    'semantic_runtime_activated',false
  );

  v_old jsonb;
  v_new jsonb;
  v_spec jsonb;
  v_contract jsonb;
  v_ready jsonb;
  v_obs jsonb;
  v_bad jsonb;
  v_assertion jsonb;
  v_transition jsonb;
  v_receipt text;
  v_negative_rejected boolean:=false;
  v_count int;
  v_src text;
  v_v1 int;
  v_v2 int;
  v_q jsonb;
  v_r jsonb;
  v_out jsonb;
BEGIN
  SELECT unit_metadata INTO STRICT v_old
  FROM programacion.engineering_plan_units
  WHERE plan_code=v_plan AND unit_code=v_unit AND work_item_id=v_wi
    AND disposition='ASSIGNED' AND md5(unit_metadata::text)=v_prior_md5
  FOR UPDATE;

  IF (SELECT count(*) FROM programacion.engineering_work_items
      WHERE id=v_wi AND status='IN_PROGRESS')<>1
     OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
         WHERE work_item_id=v_wi AND checkpoint_code='RW1-04_C1' AND status='DONE')<>1
     OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
         WHERE work_item_id=v_wi AND checkpoint_code=v_cp AND status='PENDING'
           AND evidence_ref IS NULL AND assertion_receipt IS NULL)<>1
     OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
         WHERE work_item_id=v_wi AND checkpoint_code='RW1-04_C3'
           AND status='PENDING' AND evidence_ref IS NULL)<>1
  THEN RAISE EXCEPTION 'RW104_C2_CLOSE_LIFECYCLE_DRIFT'; END IF;

  IF md5(pg_get_functiondef('public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure))
       IS DISTINCT FROM '8cffdd7403c0ae40d5db19890ea4f944'
     OR md5(pg_get_functiondef('public.lf_router_intent_handoff_v1(text,jsonb,text)'::regprocedure))
       IS DISTINCT FROM '540bc1b60caf2e3f9d81461f99c509ef'
     OR md5(pg_get_functiondef('public.lf_router_intent_handoff_v2(text,jsonb,text,jsonb,jsonb)'::regprocedure))
       IS DISTINCT FROM 'e6c5df658f322e0c67ee7a2bb5972410'
     OR md5(pg_get_functiondef('public.lf_router_semantic_resume_validate_v1(jsonb,jsonb)'::regprocedure))
       IS DISTINCT FROM '4dc0dad03d7259009583e2f77f5930fb'
     OR md5(pg_get_functiondef('programacion.fn_lf_router_input_governance_resolve_v1(text,jsonb,text)'::regprocedure))
       IS DISTINCT FROM '72e153a7fbfe7b10a8c9ae694a61b334'
  THEN RAISE EXCEPTION 'RW104_C2_CLOSE_FUNCTION_DRIFT'; END IF;

  v_src:=pg_get_functiondef('public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure);
  v_v1:=(length(v_src)-length(replace(v_src,'lf_router_intent_handoff_v1(','')))/length('lf_router_intent_handoff_v1(');
  v_v2:=(length(v_src)-length(replace(v_src,'lf_router_intent_handoff_v2(','')))/length('lf_router_intent_handoff_v2(');
  IF v_v1<>6 OR v_v2<>6 THEN
    RAISE EXCEPTION 'RW104_C2_CLOSE_SITE_DRIFT:v1=% v2=%',v_v1,v_v2;
  END IF;

  IF (SELECT count(*) FROM public.lf_router_action_registry WHERE status='ACTIVE')<>35
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations
         WHERE version='20261021010500'
           AND name='lf_router_rw104_c2_semantic_v2_implementation_v1')<>1
     OR has_function_privilege('anon','public.lf_router_intent_handoff_v2(text,jsonb,text,jsonb,jsonb)','EXECUTE')
     OR has_function_privilege('authenticated','public.lf_router_intent_handoff_v2(text,jsonb,text,jsonb,jsonb)','EXECUTE')
     OR has_function_privilege('anon','public.lf_router_semantic_resume_validate_v1(jsonb,jsonb)','EXECUTE')
     OR has_function_privilege('authenticated','public.lf_router_semantic_resume_validate_v1(jsonb,jsonb)','EXECUTE')
     OR NOT has_function_privilege('service_role','public.lf_router_intent_handoff_v2(text,jsonb,text,jsonb,jsonb)','EXECUTE')
     OR NOT has_function_privilege('supabase_read_only_user','public.lf_router_intent_handoff_v2(text,jsonb,text,jsonb,jsonb)','EXECUTE')
  THEN RAISE EXCEPTION 'RW104_C2_CLOSE_BOUNDARY_OR_LEDGER_FAILED'; END IF;

  v_q:=public.lf_router_intent_handoff_v2(
    'Actualizar ACT-0053 pero no ACT-0052',
    jsonb_build_array(
      jsonb_build_object('asset_code','ACT-0053','asset_type','SKILL'),
      jsonb_build_object('asset_code','ACT-0052','asset_type','SKILL')
    ),
    'CANONICAL_ASSET',
    jsonb_build_array(jsonb_build_object('kind','ONLY_IF','value','CURRENT')),
    NULL
  );
  v_r:=jsonb_build_object(
    'schema_version','LF_ROUTER_SEMANTIC_RESULT_V1',
    'request_sha256',v_q->>'request_sha256',
    'decision','RESOLVED',
    'positive_target_refs',jsonb_build_array('ACT-0053'),
    'excluded_target_refs',jsonb_build_array('ACT-0052'),
    'allowed_scope',jsonb_build_array('ACT-0053'),
    'forbidden_scope',jsonb_build_array('ACT-0052'),
    'conditions',v_q->'conditions',
    'material_ambiguities','[]'::jsonb,
    'clarification_question',NULL,
    'semantic_receipt_sha256',repeat('c',64)
  );
  v_out:=public.lf_router_semantic_resume_validate_v1(v_q,v_r);
  IF v_out->>'status' IS DISTINCT FROM 'VALID'
     OR v_out->>'next_action' IS DISTINCT FROM 'ACT0001_REDERIVE_ROUTE_AND_AUTHORITY'
     OR public.lf_router_semantic_resume_validate_v1(
          v_q,v_r||jsonb_build_object('operation_code','ACTUALIZACION_DB_LF')
        )->>'status' IS DISTINCT FROM 'BLOCKED'
     OR public.lf_router_semantic_resume_validate_v1(
          v_q,v_r||jsonb_build_object('effect_authority',true)
        )->>'status' IS DISTINCT FROM 'BLOCKED'
     OR public.lf_router_semantic_resume_validate_v1(
          v_q,jsonb_set(v_r,'{positive_target_refs}',jsonb_build_array('ACT-9999'),true)
        )->>'status' IS DISTINCT FROM 'BLOCKED'
     OR public.lf_router_semantic_resume_validate_v1(
          jsonb_set(v_q,'{source_currentness,router_source_md5}',to_jsonb(repeat('0',32)),true),v_r
        )->>'status' IS DISTINCT FROM 'BLOCKED'
  THEN RAISE EXCEPTION 'RW104_C2_CLOSE_VALIDATOR_READBACK_FAILED'; END IF;

  v_new:=jsonb_set(v_old,'{source_pack_v2,checkpoint_inputs,RW1-04_C2}',v_source,true);
  v_new:=jsonb_set(
    v_new,'{material_results_v1}',
    coalesce(v_new->'material_results_v1','{}'::jsonb)||jsonb_build_object(v_cp,v_material),true
  );

  UPDATE programacion.engineering_plan_units
     SET unit_metadata=v_new
   WHERE plan_code=v_plan AND unit_code=v_unit AND work_item_id=v_wi
     AND md5(unit_metadata::text)=v_prior_md5;
  GET DIAGNOSTICS v_count=ROW_COUNT;
  IF v_count<>1 THEN RAISE EXCEPTION 'RW104_C2_CLOSE_METADATA_COUNT:%',v_count; END IF;

  v_spec:=programacion.fn_engineering_checkpoint_action_spec_v3(v_plan,v_unit,v_cp);
  v_contract:=programacion.fn_engineering_action_spec_assertion_contract_v1(v_plan,v_unit,v_cp,v_spec);
  v_ready:=programacion.fn_engineering_checkpoint_execution_readiness_v1(v_plan,v_unit,v_cp);

  IF v_spec->>'status' IS DISTINCT FROM 'READY'
     OR v_spec->>'action_kind' IS DISTINCT FROM 'MATERIALIZE_DECLARED_DELIVERABLE'
     OR v_contract->>'status' IS DISTINCT FROM 'READY'
     OR v_contract->>'mode' IS DISTINCT FROM 'EXPLICIT_PASS_WHEN_SUBSET'
     OR v_ready->>'status' IS DISTINCT FROM 'READY'
     OR coalesce((v_ready->>'execution_ready')::boolean,false) IS NOT TRUE
     OR v_ready#>>'{source_currentness,status}' IS DISTINCT FROM 'CURRENT'
  THEN RAISE EXCEPTION 'RW104_C2_CLOSE_CONTRACT_NOT_READY:spec=% contract=% ready=%',
       v_spec::text,v_contract::text,v_ready::text; END IF;

  v_obs:=jsonb_build_object(
    'implementation_written',true,
    'git_merged',true,
    'db_applied',true,
    'readback_passed',true,
    'handoff_v2_installed',true,
    'resume_validator_installed',true,
    'router_v1_sites_preserved',6,
    'router_v2_sites',6,
    'positive_contract_probes_passed',true,
    'negative_contract_probes_passed_at_least',10,
    'actual_negative_contract_probes',12,
    'rollback_fail_closed_verified',true,
    'legacy_v1_preserved',true,
    'acl_not_widened',true,
    'semantic_runtime_activated',false,
    'operation_registry_changed',false,
    'input_governance_changed',false,
    'merge_train_changed',false,
    'pr',2996,
    'train_run_id',v_run,
    'train_job_id',v_job,
    'merge_job_id',v_merge_job,
    'execution_id',v_exec,
    'resolved_main_sha',v_main,
    'migration_blob','14619e0a883d42db1e9b25f471e85a5800f970d7',
    'source_test_blob','ed6461d6f1d45b75e02692994f0c4a8a85517cb9'
  );

  IF (v_obs @> (v_contract->'pass_when')) IS DISTINCT FROM true
  THEN RAISE EXCEPTION 'RW104_C2_CLOSE_OBSERVED_NOT_PASS'; END IF;

  v_bad:=jsonb_set(v_obs,'{router_v2_sites}','5'::jsonb,true);
  BEGIN
    PERFORM programacion.fn_engineering_checkpoint_assertion_record_v1(
      v_plan,v_unit,v_cp,
      jsonb_build_object(
        'status','PASS','test_code','ENG_RW104_C2_SEMANTIC_V2_IMPLEMENTATION',
        'evidence_ref',v_evidence,'observed',v_bad
      ),
      v_actor||'_NEGATIVE'
    );
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE 'ENGINEERING_ASSERTION_RESULT_FAILED:%' THEN RAISE; END IF;
    v_negative_rejected:=true;
  END;
  IF NOT v_negative_rejected THEN
    RAISE EXCEPTION 'RW104_C2_CLOSE_NEGATIVE_ASSERTION_FALSE_PASS';
  END IF;

  IF (SELECT assertion_receipt FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=v_wi AND checkpoint_code=v_cp) IS NOT NULL
  THEN RAISE EXCEPTION 'RW104_C2_CLOSE_NEGATIVE_LEFT_RECEIPT'; END IF;

  v_assertion:=programacion.fn_engineering_checkpoint_assertion_record_v1(
    v_plan,v_unit,v_cp,
    jsonb_build_object(
      'status','PASS','test_code','ENG_RW104_C2_SEMANTIC_V2_IMPLEMENTATION',
      'evidence_ref',v_evidence,'observed',v_obs
    ),
    v_actor
  );

  IF v_assertion->>'passed' IS DISTINCT FROM 'true'
     OR coalesce(v_assertion->>'assertion_receipt_sha256','') !~ '^[a-f0-9]{64}$'
  THEN RAISE EXCEPTION 'RW104_C2_CLOSE_ASSERTION_FAILED:%',coalesce(v_assertion::text,'NULL'); END IF;
  v_receipt:=v_assertion->>'assertion_receipt_sha256';

  v_transition:=programacion.fn_engineering_checkpoint_transition_v1(
    v_plan,v_unit,v_cp,'DONE',v_evidence,v_actor,
    'RW1-04_C2 material PASS: semantic handoff V2 and fail-closed resume validator merged/applied; six V1 + six V2 sites; 12 negative probes; ACL closed; V1/IG/route registry preserved; semantic runtime remains shadow/disabled; no C3/E2E/production claim.'
  );

  IF v_transition#>>'{transition,status}' IS DISTINCT FROM 'APPLIED'
  THEN RAISE EXCEPTION 'RW104_C2_CLOSE_TRANSITION_FAILED:%',coalesce(v_transition::text,'NULL'); END IF;

  IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=v_wi
        AND ((checkpoint_code='RW1-04_C1' AND status='DONE')
          OR (checkpoint_code='RW1-04_C2' AND status='DONE'
              AND evidence_ref=v_evidence
              AND assertion_receipt_sha256=v_receipt
              AND assertion_receipt->>'passed'='true')
          OR (checkpoint_code='RW1-04_C3' AND status='PENDING' AND evidence_ref IS NULL)))<>3
     OR (SELECT count(*) FROM programacion.engineering_work_items
         WHERE id=v_wi AND status='IN_PROGRESS')<>1
  THEN RAISE EXCEPTION 'RW104_C2_CLOSE_POST_READBACK_FAILED'; END IF;
END
$rw104_c2_close$;
COMMIT;

-- CP4 is Edge-vs-Git readback, not deployment.
DO $cp4$
DECLARE
 p text:='IG_CURATOR_VALIDATOR_REFACTOR_V2'; m jsonb; a jsonb; r jsonb;
 e text:='supabase://edge-functions/input-governance-agent-v1@17+input-governance-curator-v1@14+input-governance-validator-v1@18;github://cristhianlujan/claude-persona-lf-patch/tree/main/supabase/functions';
BEGIN
 a:=programacion.fn_engineering_unit_bootstrap_v3(p,'M10.2');
 IF a#>>'{current_checkpoint,checkpoint_code}'<>'RUNTIME_PREFLIGHT' THEN RAISE EXCEPTION 'CP4_NOT_CURRENT'; END IF;
 SELECT unit_metadata INTO m FROM programacion.engineering_plan_units WHERE plan_code=p AND unit_code='M10.2' FOR UPDATE;
 IF m#>>'{action_specs_v1,RUNTIME_PREFLIGHT,action_kind}'<>'READBACK_ONCE'
 OR m#>>'{action_specs_v1,RUNTIME_PREFLIGHT,runtime_source_parity_preflight,verification}'<>'DEPLOYED_INDEX_TS_EXACTLY_EQUALS_GITHUB_MAIN'
 OR m#>>'{action_specs_v1,RUNTIME_PREFLIGHT,runtime_source_parity_preflight,items,0,git_blob_sha}'<>'326a5c492c84cceccb45ea8d6a0f39a1d5305637'
 OR m#>>'{action_specs_v1,RUNTIME_PREFLIGHT,runtime_source_parity_preflight,items,1,git_blob_sha}'<>'bd43f469d5d508f64dbee21eea7be611e7d2e780'
 OR m#>>'{action_specs_v1,RUNTIME_PREFLIGHT,runtime_source_parity_preflight,items,2,git_blob_sha}'<>'31a77e43c02f714479e5ed2f1fdb615fbe38eead'
 THEN RAISE EXCEPTION 'CP4_EDGE_PARITY_NOT_VERIFIED'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.lf_capability_current WHERE capability_code='INPUT_GOVERNANCE' AND version='1.0.0') THEN RAISE EXCEPTION 'CP4_BASELINE_DRIFT'; END IF;
 -- Align governance and action spec: no-deployment source readback must not run a deployment-effect verifier.
 IF m#>>'{transversal_execution_v1,RUNTIME_PREFLIGHT,activation}'<>'ACTIVE'
 OR m#>>'{transversal_execution_v1,RUNTIME_PREFLIGHT,capabilities,0,capability_code}'<>'RUNTIME_DEPLOY_VERIFICATION'
 THEN RAISE EXCEPTION 'CP4_HANDLER_PRESTATE_DRIFT'; END IF;
 m:=jsonb_set(m,'{m10_2_cp4_inapplicable_deploy_handler_v1}',m#>'{transversal_execution_v1,RUNTIME_PREFLIGHT}',true);
 m:=m#-'{transversal_execution_v1,RUNTIME_PREFLIGHT}';
 m:=jsonb_set(m,'{m10_2_cp4_nature_alignment_v1}',jsonb_build_object(
 'nature','READBACK_ONCE','deployment_verification','NOT_APPLICABLE_NO_DEPLOY',
 'historical_handler_preserved_in_metadata',true,'operational_activation',false),true);
 UPDATE programacion.engineering_plan_units SET unit_metadata=m
 WHERE plan_code=p AND unit_code='M10.2' AND work_item_id=199;
 a:=programacion.fn_engineering_checkpoint_action_spec_v3(p,'M10.2','RUNTIME_PREFLIGHT');
 IF a->>'action_kind'<>'READBACK_ONCE' OR a->>'requires_material_execution'<>'false'
 THEN RAISE EXCEPTION 'CP4_WRONG_COMPILED_NATURE:%',a; END IF;
 r:=programacion.fn_engineering_checkpoint_execution_readiness_v1(p,'M10.2','RUNTIME_PREFLIGHT');
 IF r->>'status'<>'READY' THEN RAISE EXCEPTION 'CP4_READINESS'; END IF;
 r:=programacion.fn_engineering_checkpoint_transition_v1(p,'M10.2','RUNTIME_PREFLIGHT','DONE',e,'IG_M102_CP4_TRAIN','3/3 deployed Edge index.ts match Git main; no deployment or cutover; existing deployment verifier is inapplicable to source readback');
 IF r#>>'{transition,status}'<>'APPLIED' THEN RAISE EXCEPTION 'CP4_TRANSITION_FAIL'; END IF;
 IF (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=199 AND status='DONE')<>4 THEN RAISE EXCEPTION 'CP4_POSTSTATE_FAIL'; END IF;
END $cp4$;
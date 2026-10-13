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
 r:=programacion.fn_engineering_checkpoint_execution_readiness_v1(p,'M10.2','RUNTIME_PREFLIGHT');
 IF r->>'status'<>'READY' THEN RAISE EXCEPTION 'CP4_READINESS'; END IF;
 r:=programacion.fn_engineering_checkpoint_transition_v1(p,'M10.2','RUNTIME_PREFLIGHT','DONE',e,'IG_M102_CP4_TRAIN','3/3 deployed Edge index.ts match Git main; no deployment or cutover; existing deployment verifier is inapplicable to source readback');
 IF r#>>'{transition,status}'<>'APPLIED' THEN RAISE EXCEPTION 'CP4_TRANSITION_FAIL'; END IF;
 IF (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=199 AND status='DONE')<>4 THEN RAISE EXCEPTION 'CP4_POSTSTATE_FAIL'; END IF;
END $cp4$;
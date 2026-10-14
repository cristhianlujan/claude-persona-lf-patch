-- M10.5 CP2 only. Authenticated canonical dispatch inputs and exact run readback.
-- Never registers/releases/promotes a capability or invents any Edge receipt.
CREATE OR REPLACE FUNCTION public.fn_ig_m105_cp2_dispatch_context_v1()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = pg_catalog, public, programacion
AS $cp2$
DECLARE v_scope jsonb; v_release record; v_cohort integer; v_pass boolean;
BEGIN
 IF auth.role() IS DISTINCT FROM 'service_role' THEN
   RAISE EXCEPTION 'IG_M105_CP2_SERVICE_ROLE_REQUIRED';
 END IF;
 SELECT u.unit_metadata#>'{m105_scope_v1}' INTO STRICT v_scope
 FROM programacion.engineering_plan_units u
 WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND u.unit_code='M10.5';
 IF v_scope->>'schema_version' IS DISTINCT FROM 'M105_SCOPE_SNAPSHOT_V1'
 OR jsonb_typeof(v_scope->'screen_ids') IS DISTINCT FROM 'array'
 OR jsonb_array_length(v_scope->'screen_ids')<>13
 OR (SELECT count(DISTINCT value) FROM jsonb_array_elements_text(v_scope->'screen_ids'))<>13
 THEN RAISE EXCEPTION 'IG_M105_CP2_COHORT_DRIFT'; END IF;
 SELECT c.version,c.previous_version,c.manifest_sha256,r.release_state
 INTO STRICT v_release FROM public.lf_capability_current c
 JOIN public.lf_capability_version_registry r
 ON r.capability_code=c.capability_code AND r.version=c.version
 WHERE c.capability_code='INPUT_GOVERNANCE';
 v_pass:=v_release.previous_version IS NOT NULL
   AND v_release.version IS DISTINCT FROM v_release.previous_version
   AND v_release.release_state='RELEASED'
   AND v_release.manifest_sha256 ~ '^[0-9a-f]{64}$';
 RETURN jsonb_build_object(
   'status','AUTHORIZED_CONTEXT','scope',v_scope,
   'release',jsonb_build_object('version',v_release.version,
      'previous_version',v_release.previous_version,
      'manifest_sha256',v_release.manifest_sha256),
   'dispatch_permitted',v_pass,
   'reason',CASE WHEN v_pass THEN 'AUTHENTIC_CURRENT_RELEASE_READBACK'
                 ELSE 'CURRENT_VNEXT_RELEASE_NOT_PROMOTED' END,
   'no_promotion',true,'no_receipt_fabrication',true);
END $cp2$;

CREATE OR REPLACE FUNCTION public.fn_ig_m105_cp2_screen_readback_v1(p_pantalla_id integer)
RETURNS TABLE(pantalla_id integer,run_id bigint,cp2_verdict text,technical_verdict text)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = pg_catalog, public, programacion
AS $cp2$
BEGIN
 IF auth.role() IS DISTINCT FROM 'service_role' THEN
   RAISE EXCEPTION 'IG_M105_CP2_SERVICE_ROLE_REQUIRED';
 END IF;
 IF NOT EXISTS(
 SELECT 1 FROM programacion.engineering_plan_units u,
 LATERAL jsonb_array_elements_text(u.unit_metadata#>'{m105_scope_v1,screen_ids}') x
 WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND u.unit_code='M10.5'
 AND x.value=p_pantalla_id::text
 ) THEN RAISE EXCEPTION 'IG_M105_CP2_SCREEN_OUT_OF_SCOPE'; END IF;
 RETURN QUERY SELECT v.pantalla_id,v.run_id,v.cp2_verdict,v.technical_verdict
 FROM programacion.v_ig_m105_cp2_verdict_v1 v
 WHERE v.pantalla_id=p_pantalla_id;
END $cp2$;

REVOKE ALL ON FUNCTION public.fn_ig_m105_cp2_dispatch_context_v1() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.fn_ig_m105_cp2_screen_readback_v1(integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.fn_ig_m105_cp2_dispatch_context_v1() TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_ig_m105_cp2_screen_readback_v1(integer) TO service_role;

DO $cp2_govern$
DECLARE m jsonb; wid bigint; path text:='cristhianlujan/claude-persona-lf-patch:sandbox/lf_contract_gate_test/engineering_checkpoints/m10_5/dispatch_vnext_cohort.py';
BEGIN
 SELECT work_item_id,unit_metadata INTO STRICT wid,m
 FROM programacion.engineering_plan_units
 WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M10.5' FOR UPDATE;
 IF (SELECT status FROM programacion.engineering_work_checkpoints
     WHERE work_item_id=wid AND checkpoint_code='NEW_RUNS_VNEXT')<>'PENDING'
 OR m#>>'{m105_cp2_governance_v1,schema_version}'
 IS DISTINCT FROM 'M105_CP2_EVALUATION_IS_NOT_ENGINE_FAILURE_V1'
 THEN RAISE EXCEPTION 'IG_M105_CP2_PRODUCER_PRESTATE_DRIFT'; END IF;
 m:=jsonb_set(m,'{m105_cp2_producer_v1}',jsonb_build_object(
 'schema_version','IG_M105_CP2_CANONICAL_DISPATCH_PRODUCER_V1',
 'phase','OPERATIONAL_POST_CUTOVER',
 'runtime','SUPABASE_EDGE_FUNCTION:input-governance-agent-v1',
 'cohort_source','programacion.engineering_plan_units.M10.5.m105_scope_v1',
 'release_source','public.lf_capability_current',
 'dispatch_context_rpc','public.fn_ig_m105_cp2_dispatch_context_v1',
 'readback_rpc','public.fn_ig_m105_cp2_screen_readback_v1',
 'executor_path',path,
 'execution_status','PREPARED_NOT_EXECUTED',
 'requires_real_promotion',true,
 'no_release_promotion_here',true,'no_synthetic_receipts',true,
 'verify_each_run',true,'semantic_decisions_are_not_errors',true),true);
 m:=jsonb_set(m,'{action_specs_v1,NEW_RUNS_VNEXT,test_execution_contract,producer_path}',to_jsonb(path),true);
 m:=jsonb_set(m,'{action_specs_v1,NEW_RUNS_VNEXT,test_execution_contract,execution_required}','true'::jsonb,true);
 m:=jsonb_set(m,'{action_specs_v1,NEW_RUNS_VNEXT,test_execution_contract,producer_status}',to_jsonb('PREPARED_NOT_EXECUTED'::text),true);
 m:=jsonb_set(m,'{action_specs_v1,NEW_RUNS_VNEXT,target,declared_objects}',
   m#>'{action_specs_v1,NEW_RUNS_VNEXT,target,declared_objects}'
   || jsonb_build_array('public.fn_ig_m105_cp2_dispatch_context_v1',
                        'public.fn_ig_m105_cp2_screen_readback_v1'),true);
 m:=jsonb_set(m,'{action_specs_v1,NEW_RUNS_VNEXT,target,mutation_artifacts}',
  coalesce(m#>'{action_specs_v1,NEW_RUNS_VNEXT,target,mutation_artifacts}','[]'::jsonb)
  || jsonb_build_array(jsonb_build_object('path',path,
  'role','MUTATION_TARGET','purpose','EDGE_DISPATCH_PRODUCER',
  'target_kind','EXACT_NEW_OR_UPDATE_FILE')),true);
 UPDATE programacion.engineering_plan_units SET unit_metadata=m
 WHERE work_item_id=wid AND unit_code='M10.5' AND plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2';
 IF (SELECT unit_metadata#>>'{m105_cp2_producer_v1,schema_version}'
 FROM programacion.engineering_plan_units WHERE work_item_id=wid)
 <> 'IG_M105_CP2_CANONICAL_DISPATCH_PRODUCER_V1'
 THEN RAISE EXCEPTION 'IG_M105_CP2_PRODUCER_READBACK_FAIL'; END IF;
END $cp2_govern$;

INSERT INTO transversal.error_knowledge
(codigo,categoria,titulo,descripcion,causa_raiz,prevencion,validacion,evidencia,source_ref,lote_origen,estado,lifecycle_phase,consumer_role)
SELECT 'IG-M105-CP2-DISPATCH-PRODUCER-ABSENT-006','INPUT_GOVERNANCE',
'M10.5 CP2: checkpoint authoring spec did not provide governed runtime dispatcher',
'CP2 compiler READY only meant the test file existed; live 13 Edge dispatches never ran.',
'The action spec declared a test artifact without a canonical release/scope-reading Edge cohort runner and readback.',
'Provide service-role-only canonical RPCs, no local scope/release selection, real Edge caller, exact per-run readback, preserve operational cutover control and distinguish evaluation hold from technical error.',
'Before execution release remains 1.0.0 with no previous version, so preflight must reject actual Edge dispatch; no fake run/receipt and no CP2 DONE.',
'github://cristhianlujan/claude-persona-lf-patch/ig/m105-cp2-real-edge-dispatch-20261013',
'programacion.engineering_plan_units/M10.5/NEW_RUNS_VNEXT',
'IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.5','ACTIVO','CONTRACT_PREFLIGHT',
ARRAY['Architect','Builder','Judge','Auditor']::text[]
WHERE NOT EXISTS (SELECT 1 FROM transversal.error_knowledge
 WHERE codigo='IG-M105-CP2-DISPATCH-PRODUCER-ABSENT-006');

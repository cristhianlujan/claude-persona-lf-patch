-- M9.13 contract and governance repair: ledger-owned manifest, independently verified handoff.
-- No events emitted, no checkpoint transitions and no runtime/production cutover.
DO $m913$
DECLARE u bigint; m jsonb; specs jsonb; bundle jsonb; independent jsonb;
        pack jsonb; manifest_query jsonb; handoff_query jsonb; check_queries jsonb;
        trans jsonb;
BEGIN
 SELECT work_item_id,unit_metadata INTO u,m FROM programacion.engineering_plan_units
 WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M9.13' FOR UPDATE;
 IF u IS NULL OR m#>>'{action_specs_v1,M9_INDEPENDENT_READBACK,recipe_mode}'
 IS DISTINCT FROM 'EXECUTE_CANONICAL_CLOSURE_EVENT'
 OR m#>>'{transversal_execution_v1,M9_EVIDENCE_BUNDLE,activation}'
 IS DISTINCT FROM 'DECLARED_ONLY'
 THEN RAISE EXCEPTION 'M913_CONTRACT_PRESTATE_DRIFT'; END IF;
 IF (SELECT count(*) FROM programacion.fn_engineering_effective_dependencies_v1(u) WHERE is_unmet)<>3
 THEN RAISE EXCEPTION 'M913_DEPENDENCY_DRIFT'; END IF;
 specs:=m->'action_specs_v1';
 bundle:=specs->'M9_EVIDENCE_BUNDLE';
 manifest_query:=bundle#>'{verification_queries,0}';
 IF jsonb_typeof(manifest_query)<>'string' OR length(manifest_query#>>'{}')<100
 THEN RAISE EXCEPTION 'M913_MANIFEST_SOURCE_NOT_FOUND'; END IF;
 pack:=m->'source_pack_v1';
 pack:=jsonb_set(pack,'{checkpoint_inputs,M9_EVIDENCE_BUNDLE,inputs,queries}',jsonb_build_array(manifest_query),true);
 pack:=jsonb_set(pack,'{checkpoint_inputs,M9_EVIDENCE_BUNDLE,inputs,artifacts}','[]'::jsonb,true);
 pack:=jsonb_set(pack,'{checkpoint_inputs,M9_EVIDENCE_BUNDLE,inputs,events}','[]'::jsonb,true);
 pack:=jsonb_set(pack,'{checkpoint_inputs,M9_EVIDENCE_BUNDLE,inputs,db_objects}',
 jsonb_build_array('programacion.engineering_plan_units','programacion.engineering_work_items','programacion.engineering_work_checkpoints'),true);
 bundle:=bundle||jsonb_build_object('expected',
  'Compute canonical M9 peer-unit/checkpoint evidence SHA256 directly from IG ledger after all peer units are DONE; no external FINAL_EVIDENCE, no new evidence store',
  'governance_ref','IG_LEDGER_MANIFEST_REUSE_NO_EXTERNAL_WORKSTREAM_V1');
 specs:=jsonb_set(specs,'{M9_EVIDENCE_BUNDLE}',bundle,true);
 -- The first closure HANDOFF is still emitted through existing guarded transversal function.
 -- Independent checkpoint must separately verify that handoff and ledger match, by another executor.
 handoff_query:=to_jsonb(
  'select e.id,e.created_by_execution_id,e.evento_tipo,e.payload->>''all_dependencies_done'' dependencies_done,e.payload->>''dependency_count'' dependency_count,e.payload->>''dependencies_done'' completed_count,e.payload->''units'' unit_proofs from public.lf_eventos e join programacion.engineering_plan_units u on e.entidad_codigo=u.plan_code||''.''||u.unit_code||''.CLOSE.HANDOFF'' where u.plan_code=''IG_CURATOR_VALIDATOR_REFACTOR_V2'' and u.unit_code=''M9.13'' and e.evento_tipo=''HANDOFF_DEEP_CONTEXT'' order by e.id desc limit 1'::text);
 check_queries:=jsonb_build_array(manifest_query,handoff_query);
 independent:=specs->'M9_INDEPENDENT_READBACK';
 independent:=independent||jsonb_build_object(
  'action_kind','BOUNDED_CHECKPOINT_TEST_AUTHORING',
  'recipe_mode','AUTHOR_AND_RUN_CHECKPOINT_TEST',
  'precision','INDEPENDENT_ACTOR_SIGNED_RECONCILIATION_V1',
  'contract_family','BOUNDED_CHECKPOINT_TEST','mutation_policy','TEST_ARTIFACT_ONLY',
  'expected','Separate executor independently recomputes M9 ledger SHA, compares all 13 peer units against HANDOFF payload and M9_EVIDENCE_BUNDLE checkpoint evidence_ref, proves actor differs from HANDOFF writer and signs zero discrepancies. Existing INDEPENDENT_READBACK event by same closure producer is insufficient.',
  'forbidden',jsonb_build_array('REUSE_HANDOFF_PRODUCER_AS_INDEPENDENT','ASSUME_INDEPENDENT_IDENTITY_FROM_PAYLOAD_FLAG','ACCEPT_EVENT_EXISTENCE_AS_READBACK_PROOF','USE_FINAL_EVIDENCE_FROM_DISABLED_POST_PASE','WRITE_DOMAIN_STATE_OR_RELEASE_POINTER','SYNTHETIC_PASS_WITHOUT_MACHINE_ASSERTION'),
  'verification_queries',check_queries,
  'assertion_contract',jsonb_build_object('mode','EXPLICIT_PASS_WHEN_SUBSET','pass_when',
    jsonb_build_object('status','PASS','test_passed',true,'test_exit_code',0,'independent_executor_verified',true,'manifest_parity_verified',true,'handoff_evidence_verified',true,'discrepancy_count',0)),
  'test_execution_contract',jsonb_build_object('mode','AUTHORED_NEGATIVE','test_code','ENG_M9_13_INDEPENDENT_READBACK',
   'test_path','cristhianlujan/claude-persona-lf-patch:sandbox/lf_contract_gate_test/engineering_checkpoints/m9_13/independent_readback.py',
   'declared_queries',check_queries,
   'declared_objects',jsonb_build_array('public.lf_eventos','programacion.engineering_plan_units','programacion.engineering_work_items','programacion.engineering_work_checkpoints'),
   'negative_required',true,'authoring_required',true,'synthetic_pass','FORBIDDEN',
   'semantic_authority','CANONICAL_PLAN_EXIT_CRITERION','fallback_case_discovery','FORBIDDEN'),
  'independent_verifier_contract_v1',jsonb_build_object('producer','EXTERNAL_INDEPENDENT_EXECUTOR','proof','SIGNED_DISTINCT_ACTOR_AND_LEDGER_MANIFEST_DIFF','allow_same_producer',false,'crosscheck_handoff_event',true,'crosscheck_ledger_manifest',true,'required_units','ALL_M9_PEERS_EXCEPT_SELF','require_zero_missing_evidence',true,'require_zero_discrepancies',true,'no_production_activation',true));
 independent:=jsonb_set(independent,'{target}',jsonb_build_object(
  'checkpoint','M9_INDEPENDENT_READBACK','declared_assets','[]'::jsonb,'declared_events','[]'::jsonb,
  'declared_objects',jsonb_build_array('public.lf_eventos','programacion.engineering_plan_units','programacion.engineering_work_items','programacion.engineering_work_checkpoints'),
  'declared_artifacts',jsonb_build_array(jsonb_build_object('path','cristhianlujan/claude-persona-lf-patch:sandbox/lf_contract_gate_test/engineering_checkpoints/m9_13/independent_readback.py',
  'role','MUTATION_TARGET','purpose','INDEPENDENT_CHECKPOINT_TEST_ARTIFACT','target_kind','EXACT_NEW_OR_UPDATE_FILE')),
  'mutation_artifacts',jsonb_build_array(jsonb_build_object('path','cristhianlujan/claude-persona-lf-patch:sandbox/lf_contract_gate_test/engineering_checkpoints/m9_13/independent_readback.py',
  'role','MUTATION_TARGET','purpose','INDEPENDENT_CHECKPOINT_TEST_ARTIFACT','target_kind','EXACT_NEW_OR_UPDATE_FILE'))),true);
 independent:=independent-'closure_event_contract';
 specs:=jsonb_set(specs,'{M9_INDEPENDENT_READBACK}',independent,true);
 m:=jsonb_set(m,'{action_specs_v1}',specs,true);
 pack:=jsonb_set(pack,'{checkpoint_inputs,M9_INDEPENDENT_READBACK,inputs,queries}',check_queries,true);
 pack:=jsonb_set(pack,'{checkpoint_inputs,M9_INDEPENDENT_READBACK,inputs,events}','[]'::jsonb,true);
 pack:=jsonb_set(pack,'{checkpoint_inputs,M9_INDEPENDENT_READBACK,inputs,db_objects}',
 jsonb_build_array('public.lf_eventos','programacion.engineering_plan_units','programacion.engineering_work_items','programacion.engineering_work_checkpoints'),true);
 m:=jsonb_set(m,'{source_pack_v1}',pack,true);
 trans:=coalesce(m->'transversal_execution_v1','{}'::jsonb)-'M9_EVIDENCE_BUNDLE';
 m:=jsonb_set(m,'{transversal_execution_v1}',trans,true);
 m:=jsonb_set(m,'{m9_13_ledger_handoff_governance_v1}',jsonb_build_object(
  'schema_version','IG_M9_13_LEDGER_HANDOFF_GOVERNANCE_V1',
  'transversal_governance_change','REUSE_EXISTING_GUARDED_HANDOFF_REMOVE_DISABLED_POST_PASE_ROUTE',
  'handoff_entrypoint','programacion.fn_engineering_closure_event_guarded_v2',
  'manifest_source','IG_ENGINEERING_CHECKPOINT_LEDGER',
  'independent_check','SIGNED_DISTINCT_EXECUTOR_MANIFEST_AND_EVENT_COMPARISON',
  'independent_check_owner','CHECKPOINT_EXECUTION_NOT_ASSET_OWNER',
  'runtime_activation',false,'release_switch_authorized',false),true);
 UPDATE programacion.engineering_plan_units SET unit_metadata=m
 WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M9.13';
 UPDATE programacion.engineering_work_checkpoints
 SET title='Readback independiente firmado por otro ejecutor: ledger, handoff y SHA sin discrepancias'
 WHERE work_item_id=u AND checkpoint_code='M9_INDEPENDENT_READBACK';
 IF NOT FOUND THEN RAISE EXCEPTION 'M913_CHECKPOINT_TITLE_MISSING'; END IF;
END $m913$;
-- M9.12: reconcile local SOURCE_PACK with current IG ledger instead of stale dependency narrative/POST_PASE.
DO $m$
DECLARE m jsonb; specs jsonb; s jsonb; pack jsonb; prereq jsonb; proof jsonb; negative jsonb;
BEGIN
 SELECT unit_metadata INTO m FROM programacion.engineering_plan_units
 WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M9.12' FOR UPDATE;
 IF m#>>'{cutover_readiness_governance_v1,transversal_change}' IS DISTINCT FROM 'NOT_APPLICABLE_REUSE_GOVERNED_PROVENANCE'
 THEN RAISE EXCEPTION 'M912_OWNER_CONTRACT_NOT_APPLIED'; END IF;
 prereq:=jsonb_build_array(
 'select w.work_code,w.status,c.checkpoint_code,c.status cp_status,c.evidence_ref from programacion.engineering_work_items w join programacion.engineering_work_checkpoints c on c.work_item_id=w.id where w.work_code in (''PAULO-148'',''PAULO-156'',''PAULO-150'',''PAULO-151'') order by w.work_code,c.sequence_no',
 'select programacion.fn_ig_m98_checkpoint_bound_readback_v2(''IG_CURATOR_VALIDATOR_REFACTOR_V2'',''M9.8'') current_governed_readback');
 proof:=jsonb_build_array(
 'select id,receipt_kind,subject_type,subject_ref,subject_sha256,issuer_channel,payload->>''verification_status'' verified,payload->>''bundle_sha256'' bundle,payload->>''readiness_status'' readiness from programacion.provenance_receipts where subject_type=''IG_CUTOVER_READINESS'' order by id desc limit 30',
 'select capability_code,version,manifest_sha256 from public.lf_capability_current where capability_code=''INPUT_GOVERNANCE''');
 negative:=jsonb_build_array(
 'select count(*) filter(where status=''PRODUCTION_ACTIVE'') production_active from programacion.promotions',
 'select count(*) verified_receipts from programacion.provenance_receipts where subject_type=''IG_CUTOVER_READINESS'' and receipt_kind=''EVIDENCE_VERIFICATION'' and issuer_channel=''EVIDENCE_VERIFIER_V1'' and payload->>''verification_status''=''VERIFIED''');
 specs:=m->'action_specs_v1';
 s:=specs->'CLOSURE_GATE_CONSUME';
 s:=s||jsonb_build_object('verification_queries',proof);
 s:=jsonb_set(s,'{test_execution_contract,declared_queries}',proof,true);
 s:=jsonb_set(s,'{test_execution_contract,declared_objects}',jsonb_build_array('programacion.provenance_receipts','public.lf_capability_current'),true);
 specs:=jsonb_set(specs,'{CLOSURE_GATE_CONSUME}',s,true);
 s:=specs->'NOT_PRODUCTION_NEGATIVE';
 s:=s||jsonb_build_object('verification_queries',negative,
 'expected','Verify zero PRODUCTION_ACTIVE and reject missing/stale M9.0 bundle SHA. No verified receipt means NOT READY, not PASS',
 'negative_contract_v1',jsonb_build_object('zero_production_active',true,'reject_missing_bundle_sha',true,'reject_stale_bundle_sha',true,'require_verified_issuer',true));
 s:=jsonb_set(s,'{test_execution_contract,declared_queries}',negative,true);
 specs:=jsonb_set(specs,'{NOT_PRODUCTION_NEGATIVE}',s,true);
 m:=jsonb_set(m,'{action_specs_v1}',specs,true);
 pack:=m->'source_pack_v1';
 IF jsonb_typeof(pack#>'{checkpoint_inputs,PREREQ_RECEIPTS}') IS DISTINCT FROM 'object'
 THEN RAISE EXCEPTION 'M912_PREREQ_SOURCE_PACK_MISSING'; END IF;
 pack:=jsonb_set(pack,'{checkpoint_inputs,PREREQ_RECEIPTS,inputs,queries}',prereq,true);
 pack:=jsonb_set(pack,'{checkpoint_inputs,PREREQ_RECEIPTS,inputs,db_objects}',jsonb_build_array('programacion.engineering_work_items','programacion.engineering_work_checkpoints','programacion.provenance_receipts'),true);
 pack:=jsonb_set(pack,'{checkpoint_inputs,PREREQ_RECEIPTS,missing}','[]'::jsonb,true);
 pack:=jsonb_set(pack,'{checkpoint_inputs,PREREQ_RECEIPTS,missing_typed}','[]'::jsonb,true);
 pack:=jsonb_set(pack,'{checkpoint_inputs,CLOSURE_GATE_CONSUME,inputs,queries}',proof,true);
 pack:=jsonb_set(pack,'{checkpoint_inputs,CLOSURE_GATE_CONSUME,inputs,db_objects}',jsonb_build_array('programacion.provenance_receipts','public.lf_capability_current'),true);
 pack:=jsonb_set(pack,'{checkpoint_inputs,CLOSURE_GATE_CONSUME,inputs,artifacts}','[]'::jsonb,true);
 pack:=jsonb_set(pack,'{checkpoint_inputs,CUTOVER_READY_READBACK,inputs,queries}',proof,true);
 pack:=jsonb_set(pack,'{checkpoint_inputs,CUTOVER_READY_READBACK,inputs,db_objects}',jsonb_build_array('programacion.provenance_receipts','public.lf_capability_current'),true);
 pack:=jsonb_set(pack,'{checkpoint_inputs,NOT_PRODUCTION_NEGATIVE,inputs,queries}',negative,true);
 pack:=jsonb_set(pack,'{checkpoint_inputs,NOT_PRODUCTION_NEGATIVE,inputs,db_objects}',jsonb_build_array('programacion.promotions','programacion.provenance_receipts'),true);
 IF pack IS NULL THEN RAISE EXCEPTION 'M912_NULL_PACK'; END IF;
 m:=jsonb_set(m,'{source_pack_v1}',pack,true);
 UPDATE programacion.engineering_plan_units SET unit_metadata=m
 WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M9.12';
END $m$;
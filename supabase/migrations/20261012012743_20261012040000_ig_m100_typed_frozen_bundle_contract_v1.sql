-- M10.0: bundle sha256 and Git commit SHA are distinct typed identities.
-- Fail closed on pre-existing signed M9.0 readback/manifest disparity; never select latest by time.
DO $m100$
DECLARE m jsonb;s jsonb;specs jsonb;src jsonb;w bigint; bundle_query jsonb;ready_query jsonb;
BEGIN
 SELECT work_item_id,unit_metadata INTO w,m FROM programacion.engineering_plan_units
 WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M10.0' FOR UPDATE;
 IF w IS NULL OR m#>>'{action_specs_v1,BUNDLE_M9_BINDING,status}' IS DISTINCT FROM 'BLOCK_UPSTREAM_OWNER_BINDING_PENDING'
 OR m#>>'{action_specs_v1,CUTOVER_READY_PRECONDITION,status}' IS DISTINCT FROM 'BLOCK_UPSTREAM_RECEIPT_PENDING'
 THEN RAISE EXCEPTION 'M100_PRESTATE_DRIFT'; END IF;
 IF NOT EXISTS(SELECT 1 FROM programacion.fn_engineering_effective_dependencies_v1(w) WHERE effective_work_code='PAULO-152' AND is_unmet)
 THEN RAISE EXCEPTION 'M100_M912_DEPENDENCY_DRIFT'; END IF;
 bundle_query:=jsonb_build_array('select m.evidence_ref manifest_checkpoint_ref,c.evidence_ref frozen_readback_ref, r.id signed_receipt_id,r.head_sha frozen_git_head_sha,r.subject_sha256 frozen_bundle_sha256,r.payload->>''verification_status'' verifier_state,r.payload#>>''{manifest,bundle_sha256}'' canonical_bundle_sha256, 
(r.id is not null and r.payload->>''verification_status''=''VERIFIED'' and r.subject_sha256=r.payload#>>''{manifest,bundle_sha256}'' and r.head_sha=r.payload->>''head_sha'') verifier_consistent,
(m.evidence_ref like ''%''||r.subject_sha256||''%'') manifest_artifact_matches_signed_bundle
from programacion.engineering_plan_units u
join programacion.engineering_work_checkpoints c on c.work_item_id=u.work_item_id and c.checkpoint_code=''BUNDLE_READBACK''
join programacion.engineering_work_checkpoints m on m.work_item_id=u.work_item_id and m.checkpoint_code=''BUNDLE_MANIFEST_SHA''
left join programacion.provenance_receipts r on c.evidence_ref like ''supabase://programacion.provenance_receipts/''||r.id::text||'' %''
where u.plan_code=''IG_CURATOR_VALIDATOR_REFACTOR_V2'' and u.unit_code=''M9.0''');
 ready_query:=jsonb_build_array('select id,head_sha,subject_sha256,payload->>''verification_status'' verifier_state,payload->>''bundle_sha256'' as bound_bundle_sha,payload->>''readiness_status'' as readiness from programacion.provenance_receipts where subject_type=''IG_CUTOVER_READINESS'' and receipt_kind=''EVIDENCE_VERIFICATION'' order by id desc limit 20');
 specs:=m->'action_specs_v1';
 s:=specs->'BUNDLE_M9_BINDING';
 s:=s||jsonb_build_object(
 'status','READY','action_kind','READBACK_ONCE','recipe_mode','READBACK_EXACT',
 'precision','FROZEN_BUNDLE_TYPED_IDENTITY_CONTRACT_V1',
 'contract_family','CANONICAL_LEDGER_READBACK',
 'mutation_policy','NO_DOMAIN_MUTATION',
 'expected','Read the pinned M9.0 signed bundle receipt from its DONE checkpoint. Git head_sha is 40 hex and bundle_sha256 is 64 hex: they MUST NOT be equated. Fail closed on differing manifest artifact and verified receipt, without rebuilding or picking latest.',
 'verification_queries',bundle_query,
 'binding_contract',jsonb_build_object('producer','M9.0','authority','SIGNED_PINNED_PROVENANCE_RECEIPT','head_sha_type','GIT_COMMIT_SHA1_40','bundle_sha_type','MANIFEST_SHA256_64','head_sha_equals_bundle_sha',false,'manifest_must_match_receipt',true,'no_latest_receipt_selection',true,'no_bundle_rebuild',true,'no_promotion_execution',true),
 'assertion_contract',jsonb_build_object('mode','EXPLICIT_PASS_WHEN_SUBSET','pass_when',jsonb_build_object('receipt_verified',true,'manifest_sha_parity',true,'head_bound',true,'provenance_pinned',true)));
 s:=s-'required_contract';
 s:=jsonb_set(s,'{target,declared_objects}',jsonb_build_array('programacion.engineering_plan_units','programacion.engineering_work_checkpoints','programacion.provenance_receipts'),true);
 s:=jsonb_set(s,'{target,declared_artifacts}','[]'::jsonb,true);
 s:=jsonb_set(s,'{source_pack_missing_typed}','[]'::jsonb,true);
 specs:=jsonb_set(specs,'{BUNDLE_M9_BINDING}',s,true);
 s:=specs->'CUTOVER_READY_PRECONDITION';
 s:=s||jsonb_build_object(
 'expected','CUTOVER_READY is emitted by M9.12 in programacion.provenance_receipts with verified issuer and exact frozen M9.0 bundle SHA; no qualification_receipt substitute',
 'verification_queries',ready_query,
 'upstream_receipt_contract',jsonb_build_object('producer_unit','M9.12','subject_type','IG_CUTOVER_READINESS','receipt_table','programacion.provenance_receipts','receipt_kind','EVIDENCE_VERIFICATION','verified_issuer','EVIDENCE_VERIFIER_V1','bundle_sha_source','M9.0_PINNED_SIGNED_RECEIPT','head_sha_is_bundle_sha',false,'must_be_current',true));
 s:=jsonb_set(s,'{target,declared_objects}',jsonb_build_array('programacion.provenance_receipts','programacion.engineering_work_dependencies'),true);
 s:=jsonb_set(s,'{source_pack_missing_typed}','[]'::jsonb,true);
 specs:=jsonb_set(specs,'{CUTOVER_READY_PRECONDITION}',s,true);
 m:=jsonb_set(m,'{action_specs_v1}',specs,true);
 src:=m->'source_pack_v1';
 src:=jsonb_set(src,'{checkpoint_inputs,BUNDLE_M9_BINDING,inputs,queries}',bundle_query,true);
 src:=jsonb_set(src,'{checkpoint_inputs,BUNDLE_M9_BINDING,inputs,artifacts}','[]'::jsonb,true);
 src:=jsonb_set(src,'{checkpoint_inputs,BUNDLE_M9_BINDING,inputs,db_objects}',jsonb_build_array('programacion.engineering_plan_units','programacion.engineering_work_checkpoints','programacion.provenance_receipts'),true);
 src:=jsonb_set(src,'{checkpoint_inputs,BUNDLE_M9_BINDING,missing}','[]'::jsonb,true);
 src:=jsonb_set(src,'{checkpoint_inputs,BUNDLE_M9_BINDING,missing_typed}','[]'::jsonb,true);
 src:=jsonb_set(src,'{checkpoint_inputs,CUTOVER_READY_PRECONDITION,inputs,queries}',ready_query,true);
 src:=jsonb_set(src,'{checkpoint_inputs,CUTOVER_READY_PRECONDITION,inputs,db_objects}',jsonb_build_array('programacion.provenance_receipts'),true);
 src:=jsonb_set(src,'{checkpoint_inputs,CUTOVER_READY_PRECONDITION,missing}','[]'::jsonb,true);
 src:=jsonb_set(src,'{checkpoint_inputs,CUTOVER_READY_PRECONDITION,missing_typed}','[]'::jsonb,true);
 m:=jsonb_set(m,'{source_pack_v1}',src,true);
 m:=jsonb_set(m,'{m10_0_contract_governance_v1}',jsonb_build_object('schema','M10_0_PROMOTION_AUTHORITY_CONTRACT_V1','transversal_change','NOT_APPLICABLE_REUSE_EXISTING_HUMAN_DECISION_GUARDS','human_authority','RECEIPT_BACKED_APPROVAL_ONLY','no_automatic_approval',true,'no_production_activation',true,'freeze_bundle_to_m90_signed_receipt',true,'sha_types_distinct',true,'fail_closed_on_m90_bundle_drift',true),true);
 UPDATE programacion.engineering_plan_units SET unit_metadata=m
 WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M10.0';
END $m100$;
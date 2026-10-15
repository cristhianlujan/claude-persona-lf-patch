-- IG M10.0: governed human approval is APPROVE + typed metadata, not invalid SQL enum.
-- Keep runtime activation and the approval itself strictly outside this contract migration.
DO $m$
DECLARE m jsonb; s jsonb; src jsonb; w bigint; p jsonb;q_auth jsonb;q_guard jsonb;q_read jsonb;
BEGIN
 SELECT work_item_id,unit_metadata INTO w,m FROM programacion.engineering_plan_units
 WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M10.0' FOR UPDATE;
 IF w IS NULL OR m#>>'{m10_0_contract_governance_v1,schema}' IS DISTINCT FROM 'M10_0_PROMOTION_AUTHORITY_CONTRACT_V1'
 OR m#>>'{action_specs_v1,HUMAN_DECISION_RECORD,status}' IS DISTINCT FROM 'BLOCK_OWNER_DECISION_REQUIRED'
 THEN RAISE EXCEPTION 'M100_AUTHORITY_CONTRACT_PRESTATE_DRIFT'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='programacion.human_decisions'::regclass
 AND conname='human_decisions_decision_check' AND pg_get_constraintdef(oid) LIKE '%APPROVE%REJECT%')
 THEN RAISE EXCEPTION 'M100_HUMAN_DECISION_DOMAIN_CHANGED'; END IF;
 q_auth:=jsonb_build_array('select programacion.fn_engineering_current_capability_set_assert_v1(array[''AUTHORITY_READBACK'',''PLAN_AUTHORITY_DRIFT_GUARD'',''WAIVER_AUTHORITY'']::text[]) authority_capabilities','select conname,pg_get_constraintdef(oid) constraint_def from pg_constraint where conrelid=''programacion.human_decisions''::regclass and conname in (''human_decisions_decision_check'',''human_decisions_head_sha_check'') order by conname');
 q_guard:=jsonb_build_array('select conname,pg_get_constraintdef(oid) constraint_def from pg_constraint where conrelid=''programacion.human_decisions''::regclass and conname in (''human_decisions_decision_check'',''human_decisions_head_sha_check'') order by conname');
 q_read:=jsonb_build_array('select hd.id,hd.decision,hd.head_sha,hd.metadata->>''decision_class'' decision_class,hd.metadata->>''bundle_sha256'' bundle_sha,hd.metadata->>''cutover_readiness_receipt_id'' cutover_id,hd.authority_receipt_id,hd.actor_identity,hd.approval_ref, pr.subject_sha256 cutover_subject_sha,pr.payload->>''verification_status'' readiness_verified from programacion.human_decisions hd left join programacion.provenance_receipts pr on pr.id=nullif(hd.metadata->>''cutover_readiness_receipt_id'','''')::bigint and pr.subject_type=''IG_CUTOVER_READINESS'' where hd.metadata->>''decision_class''=''CUTOVER_AUTHORIZED'' order by hd.id desc limit 25');
 s:=m#>'{action_specs_v1,REUSE_SADM_AUTHORITY}';
 s:=s||jsonb_build_object('expected','Reuse existing current AUTHORITY_READBACK, PLAN_AUTHORITY_DRIFT_GUARD and WAIVER_AUTHORITY. Disabled SADM-PP project is not a prerequisite and does not issue promotion decisions.',
 'verification_queries',q_auth,'authority_reuse_scope','REGISTERED_TRANSVERSAL_CAPABILITIES_NOT_POST_PASE_RUNTIME');
 s:=jsonb_set(s,'{target,declared_objects}',jsonb_build_array('public.lf_capability_registry','public.lf_capability_current','pg_constraint'),true);
 m:=jsonb_set(m,'{action_specs_v1,REUSE_SADM_AUTHORITY}',s,true);
 s:=m#>'{action_specs_v1,HUMAN_DECISION_RECORD}';
 s:=s||jsonb_build_object('expected','Human authority must explicitly approve release; store decision=APPROVE and metadata.decision_class=CUTOVER_AUTHORIZED, not unsupported decision literal. Bind head_sha 40 to Git execution, bundle_sha256 64 to M9.0 frozen signed receipt and CUTOVER_READY  M9.12; require authority_receipt_id verified.',
 'verification_queries',q_read,
 'decision_authority_contract',jsonb_build_object('owner','GOVERNED_HUMAN_AUTHORITY','record_table','programacion.human_decisions','db_decision','APPROVE','metadata_decision_class','CUTOVER_AUTHORIZED','required_fields',jsonb_build_array('execution_id','head_sha','actor_identity','approval_ref','authority_receipt_id','metadata.bundle_sha256','metadata.cutover_readiness_receipt_id','metadata.decision_class'),'head_sha_type','GIT_COMMIT_SHA1_40','bundle_sha_type','MANIFEST_SHA256_64','require_m90_signed_frozen_bundle',true,'require_m912_verified_cutover_receipt',true,'require_authority_provenance_receipt',true,'automatic_decision','FORBIDDEN','production_activation',false));
 m:=jsonb_set(m,'{action_specs_v1,HUMAN_DECISION_RECORD}',s,true);
 s:=m#>'{action_specs_v1,NEG_SHA_MISMATCH}';
 s:=s||jsonb_build_object('expected','Real negative checks: reject wrong 40-hex execution Git head; missing/mismatched 64-hex signed bundle; absent/stale M9.12 CUTOVER_READY; forged/missing authority receipt; reject invalid decision literal CUTOVER_AUTHORIZED in decision column.',
 'negative_contract_v1',jsonb_build_object('forged_authority_receipt_rejected',true,'invalid_decision_literal_rejected',true,'wrong_head_rejected',true,'missing_cutover_receipt_rejected',true,'bundle_sha_mismatch_rejected',true,'require_transaction_rollback_no_residue',true));
 m:=jsonb_set(m,'{action_specs_v1,NEG_SHA_MISMATCH}',s,true);
 m:=jsonb_set(m,'{exit_criterion_v2}',jsonb_build_object('governed_decision','APPROVE','decision_class','CUTOVER_AUTHORIZED','approval_source','REAL_HUMAN_AUTHORITY_RECEIPT','head_sha_identity','GIT_HEAD_SHA40','bundle_identity','FROZEN_M9_0_SIGNED_SHA256_64','release_receipt','M9.12_IG_CUTOVER_READINESS','release_activation',false,'no_approval_until_prerequisites',true),true);
 src:=m->'source_pack_v1';
 src:=jsonb_set(src,'{checkpoint_inputs,REUSE_SADM_AUTHORITY,inputs,queries}',q_auth,true);
 src:=jsonb_set(src,'{checkpoint_inputs,REUSE_SADM_AUTHORITY,inputs,db_objects}',jsonb_build_array('public.lf_capability_registry','public.lf_capability_current','pg_constraint'),true);
 src:=jsonb_set(src,'{checkpoint_inputs,HUMAN_DECISION_RECORD,inputs,queries}',q_read,true);
 src:=jsonb_set(src,'{checkpoint_inputs,HUMAN_DECISION_RECORD,inputs,db_objects}',jsonb_build_array('programacion.human_decisions','programacion.provenance_receipts'),true);
 src:=jsonb_set(src,'{checkpoint_inputs,AUTHORITY_READBACK,inputs,queries}',q_read,true);
 src:=jsonb_set(src,'{checkpoint_inputs,AUTHORITY_READBACK,inputs,db_objects}',jsonb_build_array('programacion.human_decisions','programacion.provenance_receipts'),true);
 m:=jsonb_set(m,'{source_pack_v1}',src,true);
 UPDATE programacion.engineering_plan_units SET unit_metadata=m,
 exit_criterion='Existe una decisión humana verificada en programacion.human_decisions con decision=APPROVE y metadata.decision_class=CUTOVER_AUTHORIZED, head_sha igual al Git head de la ejecución, metadata.bundle_sha256 igual al digest SHA-256 del recibo congelado M9.0, metadata.cutover_readiness_receipt_id ligado al recibo M9.12 verificado, approval_ref y authority_receipt_id presentes; ningún aprobado sin coincidencia o sin recibos. Sin autorización automática ni activación de producción.'
 WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M10.0';
END $m$;
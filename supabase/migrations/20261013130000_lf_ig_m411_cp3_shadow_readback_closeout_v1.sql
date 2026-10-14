-- IG M4.11 / PAULO-143: CP3 SHADOW ENGINEERING ONLY.
-- Governed single checkpoint transition through LF Migration Merge Train.
-- No CP4-CP6 transition, no domain/function/production/release/capability changes.
-- EKB: IG-M411-CONSTRUCTION-VS-DECISIONAL-SCOPE-CONFLATION-001,
-- IG-M99-SANDBOX-LIVE-ADMISSION-CONFLATION-001,
-- IG-ENGINEERING-TRANSITION-EMPTY-EVIDENCE-001, AUD-045.
DO $m411cp3$
DECLARE
 v_u record; v_cp record; v_boot jsonb; v_spec jsonb; v_sql text;
 v_pass jsonb; v_negative jsonb; v_neg_rejected boolean:=false;
 v_out jsonb; v_after jsonb; v_ready int; v_receipt int;
 v_evidence text :=
  'supabase://programacion.engineering_plan_units/267'
  || '#checkpoint=DECISIONAL_BINDING_VIA_RELEASE'
  || ';readback=IG_M411_ENGINEERING_SCOPE_V3:PASS_ENGINEERING_BOUNDARY'
  || ';M9.2=M4.12:DONE'
  || ';novated_R11_event=20635'
  || ';families=47/47_SHADOW_ONLY'
  || ';signed_cutover_receipt=1667'
  || ';scope=ENGINEERING_QUALIFICATION_SHADOW_COMPARISON_ONLY'
  || ';semantic_independence_proven=false'
  || ';decisional_oracle_authorized=false'
  || ';production_authorized=false';
BEGIN
 SELECT u.id,u.work_item_id,w.status,u.unit_metadata INTO STRICT v_u
 FROM programacion.engineering_plan_units u
 JOIN programacion.engineering_work_items w ON w.id=u.work_item_id
 WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
 AND u.unit_code='M4.11' AND u.disposition='ASSIGNED'
 FOR UPDATE OF u,w;
 IF v_u.status IS DISTINCT FROM 'IN_PROGRESS'
 OR v_u.unit_metadata#>>'{m411_admission_boundary_v1,version}' IS DISTINCT FROM '3.0.0'
 OR v_u.unit_metadata#>>'{m411_admission_boundary_v1,cp3_scope}' IS DISTINCT FROM
 'HISTORICAL_BEHAVIORAL_AND_MECHANISM_READBACK'
 OR v_u.unit_metadata#>>'{m411_admission_boundary_v1,decisional_promotion}' IS DISTINCT FROM 'NOT_AUTHORIZED'
 OR v_u.unit_metadata#>>'{m411_admission_boundary_v1,production_activation}' IS DISTINCT FROM 'NOT_AUTHORIZED'
 THEN RAISE EXCEPTION 'M411_CP3_GOVERNANCE_V3_DRIFT'; END IF;
 SELECT c.status,c.evidence_ref INTO STRICT v_cp
 FROM programacion.engineering_work_checkpoints c
 WHERE c.work_item_id=v_u.work_item_id
 AND c.checkpoint_code='DECISIONAL_BINDING_VIA_RELEASE' FOR UPDATE;
 IF v_cp.status IS DISTINCT FROM 'PENDING'
 OR v_cp.evidence_ref IS NOT NULL
 OR EXISTS(SELECT 1 FROM programacion.engineering_work_checkpoints
 WHERE work_item_id=v_u.work_item_id AND sequence_no>=4
 AND (status<>'PENDING' OR evidence_ref IS NOT NULL))
 THEN RAISE EXCEPTION 'M411_CP3_NOT_CURRENT_OR_DOWNSTREAM_MUTATED'; END IF;

 v_boot:=programacion.fn_engineering_unit_bootstrap_v3(
 'IG_CURATOR_VALIDATOR_REFACTOR_V2','M4.11');
 IF v_boot->>'terminal_action' IS DISTINCT FROM 'CONTINUE_CURRENT_CHECKPOINT'
 OR v_boot#>>'{current_checkpoint,checkpoint_code}' IS DISTINCT FROM 'DECISIONAL_BINDING_VIA_RELEASE'
 OR (v_boot#>>'{state,done_checkpoint_count}')::integer<>2
 OR (v_boot#>>'{state,checkpoint_count}')::integer<>6
 OR (v_boot#>>'{state,open_blockers}')::integer<>0
 OR (v_boot#>>'{state,unmet_deps}')::integer<>0
 THEN RAISE EXCEPTION 'M411_CP3_BOOTSTRAP_DRIFT'; END IF;
 v_spec:=programacion.fn_engineering_checkpoint_action_spec_v3(
 'IG_CURATOR_VALIDATOR_REFACTOR_V2','M4.11','DECISIONAL_BINDING_VIA_RELEASE');
 IF v_spec->>'status' IS DISTINCT FROM 'READY'
 OR v_spec->>'precision' IS DISTINCT FROM 'M411_ENGINEERING_SCOPE_ONLY_V3'
 OR v_spec->>'action_kind' IS DISTINCT FROM 'READBACK_ONCE'
 OR v_spec->>'requires_material_execution' IS DISTINCT FROM 'false'
 OR v_spec#>>'{required_evidence_contract,phase}' IS DISTINCT FROM 'SHADOW_ENGINEERING_QUALIFICATION'
 OR v_spec#>>'{required_evidence_contract,semantic_independence_proven}' IS DISTINCT FROM 'false'
 OR v_spec#>>'{required_evidence_contract,decisional_promotion_authorized}' IS DISTINCT FROM 'false'
 OR v_spec#>>'{required_evidence_contract,production_activation_authorized}' IS DISTINCT FROM 'false'
 OR jsonb_array_length(coalesce(v_spec->'verification_queries','[]'::jsonb))<>1
 THEN RAISE EXCEPTION 'M411_CP3_ACTION_SPEC_DRIFT'; END IF;

 v_sql:=v_spec->'verification_queries'->>0;
 -- Execute the exact source-pack readback; reject anything other than the
 -- known canonical readback SQL shape (no arbitrary mutation here).
 IF left(ltrim(v_sql),9) IS DISTINCT FROM 'WITH u AS'
 OR v_sql NOT LIKE '%IG_M411_ENGINEERING_SCOPE_V3%'
 OR v_sql NOT LIKE '%PASS_ENGINEERING_BOUNDARY%'
 OR v_sql NOT LIKE '%FROM programacion.provenance_receipts%'
 OR v_sql NOT LIKE '%WHERE id=1667%'
 THEN RAISE EXCEPTION 'M411_CP3_READBACK_QUERY_NOT_CANONICAL'; END IF;
 EXECUTE v_sql INTO STRICT v_pass;
 IF v_pass->>'status' IS DISTINCT FROM 'PASS_ENGINEERING_BOUNDARY'
 OR v_pass->>'contract' IS DISTINCT FROM 'IG_M411_ENGINEERING_SCOPE_V3'
 OR (v_pass->>'m92_m412_done')::integer<>2
 OR (v_pass->>'shadow_strategies')::integer<>47
 OR (v_pass->>'m412_novation_event')::integer<>20635
 OR (v_pass->>'m912_cutover_receipt')::integer<>1667
 OR v_pass->>'semantic_independence_proven' IS DISTINCT FROM 'false'
 OR v_pass->>'decisional_oracle_authorized' IS DISTINCT FROM 'false'
 OR v_pass->>'production_authorized' IS DISTINCT FROM 'false'
 THEN RAISE EXCEPTION 'M411_CP3_POSITIVE_READBACK_INVALID'; END IF;
 SELECT count(*) INTO v_ready
 FROM programacion.engineering_work_items w
 JOIN programacion.engineering_plan_units u ON u.work_item_id=w.id
 WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
 AND u.unit_code IN ('M9.2','M4.12') AND w.status='DONE';
 IF v_ready<>2 THEN RAISE EXCEPTION 'M411_CP3_DEPENDENCY_READBACK_DRIFT'; END IF;
 SELECT count(*) INTO v_receipt FROM programacion.provenance_receipts
 WHERE id=1667 AND receipt_kind='EVIDENCE_VERIFICATION'
 AND subject_ref='plan://IG_CURATOR_VALIDATOR_REFACTOR_V2/M9.12/CUTOVER_READY'
 AND receipt_sha256='b4b8174360d8478c122340ca25973ba54cdcd7785d2d168ae8271840fc0c7fc5'
 AND payload->>'verification_status'='VERIFIED'
 AND payload->>'bundle_sha256'='db84f4ab3cdcc0fe3dcdd463be70ad9b4c96ec7beb9be9cc56b9d344793e7f2f'
 AND payload#>>'{manifest,production_activation}'='false';
 IF v_receipt<>1 THEN RAISE EXCEPTION 'M411_CP3_RECEIPT_NOT_EXACT'; END IF;

 -- Negative: a tampered receipt makes the same readback fail closed.
 EXECUTE replace(v_sql,'WHERE id=1667','WHERE id=-1667') INTO STRICT v_negative;
 IF v_negative->>'status' IS DISTINCT FROM 'BLOCKED'
 OR v_negative->>'decisional_oracle_authorized' IS DISTINCT FROM 'false'
 OR v_negative->>'production_authorized' IS DISTINCT FROM 'false'
 THEN RAISE EXCEPTION 'M411_CP3_TAMPERED_RECEIPT_FALSE_PASS'; END IF;

 -- Negative: canonical transition refuses empty evidence; PL/pgSQL
 -- exception subtransaction guarantees zero residue.
 BEGIN
  PERFORM programacion.fn_engineering_checkpoint_transition_v1(
   'IG_CURATOR_VALIDATOR_REFACTOR_V2','M4.11','DECISIONAL_BINDING_VIA_RELEASE',
   'DONE','','IG_M411_CP3_NEGATIVE_EMPTY',NULL);
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM LIKE '%Terminal checkpoint transition requires evidence%'
  OR SQLERRM LIKE '%ENGINEERING_EXPLICIT_EVIDENCE_REF_REQUIRED%'
  THEN v_neg_rejected:=true;
  ELSE RAISE; END IF;
 END;
 IF NOT v_neg_rejected THEN RAISE EXCEPTION 'M411_CP3_EMPTY_EVIDENCE_FALSE_PASS'; END IF;
 IF NOT EXISTS(SELECT 1 FROM programacion.engineering_work_checkpoints
 WHERE work_item_id=v_u.work_item_id AND checkpoint_code='DECISIONAL_BINDING_VIA_RELEASE'
 AND status='PENDING' AND evidence_ref IS NULL)
 THEN RAISE EXCEPTION 'M411_CP3_NEGATIVE_LEFT_RESIDUE'; END IF;

 -- One governed transition only: no release/candidate switch.
 v_out:=programacion.fn_engineering_checkpoint_transition_v1(
  'IG_CURATOR_VALIDATOR_REFACTOR_V2','M4.11','DECISIONAL_BINDING_VIA_RELEASE',
  'DONE',v_evidence,'IG_M411_CP3_TRAIN_CANONICAL',
  'CP3 engineering shadow qualification PASS on declared source readback; '
  || 'R11 event 20635, M9.2 6/6, M9.12 receipt 1667, 47 declared shadow strategies; '
  || 'negative tampered receipt BLOCKED; empty evidence refused. '
  || 'No semantic independent oracle claim and NO release or production activation.');
 IF v_out#>>'{transition,status}' IS DISTINCT FROM 'APPLIED'
 OR v_out#>>'{transition,checkpoint_code}' IS DISTINCT FROM 'DECISIONAL_BINDING_VIA_RELEASE'
 THEN RAISE EXCEPTION 'M411_CP3_TRANSITION_NOT_APPLIED'; END IF;
 IF NOT EXISTS(SELECT 1 FROM programacion.engineering_work_checkpoints
 WHERE work_item_id=v_u.work_item_id AND checkpoint_code='DECISIONAL_BINDING_VIA_RELEASE'
 AND status='DONE' AND evidence_ref=v_evidence AND completed_at IS NOT NULL)
 THEN RAISE EXCEPTION 'M411_CP3_POSTREADBACK_MISMATCH'; END IF;
 IF EXISTS(SELECT 1 FROM programacion.engineering_work_checkpoints
 WHERE work_item_id=v_u.work_item_id AND sequence_no>3
 AND (status<>'PENDING' OR evidence_ref IS NOT NULL))
 THEN RAISE EXCEPTION 'M411_CP3_DOWNSTREAM_UNAUTHORIZED_MUTATION'; END IF;
 v_after:=programacion.fn_engineering_unit_bootstrap_v3(
 'IG_CURATOR_VALIDATOR_REFACTOR_V2','M4.11');
 IF (v_after#>>'{state,done_checkpoint_count}')::integer<>3
 OR (v_after#>>'{state,checkpoint_count}')::integer<>6
 OR v_after#>>'{current_checkpoint,checkpoint_code}' IS DISTINCT FROM 'NO_PASS_WITHOUT_ORACLE_NEG'
 OR v_after#>>'{state,status}' IS DISTINCT FROM 'IN_PROGRESS'
 THEN RAISE EXCEPTION 'M411_CP3_POST_BOOTSTRAP_DRIFT'; END IF;
 IF v_u.unit_metadata#>>'{m411_admission_boundary_v1,decisional_promotion}' IS DISTINCT FROM 'NOT_AUTHORIZED'
 OR (SELECT version FROM public.lf_capability_current
     WHERE capability_code='INPUT_GOVERNANCE') IS DISTINCT FROM '1.0.0'
 THEN RAISE EXCEPTION 'M411_CP3_RUNTIME_OR_CUTOVER_DRIFT'; END IF;
END;
$m411cp3$;

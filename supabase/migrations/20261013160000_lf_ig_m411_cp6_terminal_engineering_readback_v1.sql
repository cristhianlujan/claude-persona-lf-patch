-- IG M4.11 / CP6: terminal SHADOW engineering qualification ONLY.
-- Governed via LF Migration Merge Train; no semantic or production authorization.
-- EKB: IG-M411-CONSTRUCTION-VS-DECISIONAL-SCOPE-CONFLATION-001;
-- IG-M99-SANDBOX-LIVE-ADMISSION-CONFLATION-001;
-- IG-ENGINEERING-TRANSITION-EMPTY-EVIDENCE-001.
DO $cp6$
DECLARE
 u record; b jsonb; s jsonb; p jsonb; n jsonb; t jsonb;
 q text; neg_rejected boolean:=false;
 evidence text:='supabase://programacion.engineering_plan_units/267#M4.11/CP6;readback=IG_M411_TERMINAL_ENGINEERING_V3:PASS_ENGINEERING_ONLY;prior_checkpoints=5/5;negative_missing_r11_event=BLOCKED;governance=3.1.0;scope=SHADOW_ENGINEERING_ONLY;semantic_independence_proven=false;decisional_promotion=false;production_activation=false';
BEGIN
 SELECT x.id,x.work_item_id,x.unit_metadata,w.status work_status INTO STRICT u
 FROM programacion.engineering_plan_units x JOIN programacion.engineering_work_items w
 ON w.id=x.work_item_id WHERE x.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
 AND x.unit_code='M4.11' AND x.disposition='ASSIGNED' FOR UPDATE OF x,w;
 IF u.work_status IS DISTINCT FROM 'IN_PROGRESS'
 OR u.unit_metadata#>>'{m411_admission_boundary_v1,version}' IS DISTINCT FROM '3.1.0'
 OR u.unit_metadata#>>'{m411_admission_boundary_v1,cp6_scope}' IS DISTINCT FROM 'ENGINEERING_TERMINAL_NOT_ACTIVATION'
 OR u.unit_metadata#>>'{m411_admission_boundary_v1,decisional_promotion}' IS DISTINCT FROM 'NOT_AUTHORIZED'
 OR u.unit_metadata#>>'{m411_admission_boundary_v1,production_activation}' IS DISTINCT FROM 'NOT_AUTHORIZED'
 THEN RAISE EXCEPTION 'M411_CP6_GOVERNANCE_DRIFT'; END IF;
 IF (SELECT count(*) FROM programacion.engineering_work_checkpoints c
 WHERE c.work_item_id=u.work_item_id AND c.sequence_no<=5
 AND c.status='DONE' AND nullif(btrim(c.evidence_ref),'') IS NOT NULL
 AND c.completed_at IS NOT NULL)<>5
 OR NOT EXISTS(SELECT 1 FROM programacion.engineering_work_checkpoints
 WHERE work_item_id=u.work_item_id AND checkpoint_code='NO_PASS_WITHOUT_ORACLE_NEG'
 AND assertion_receipt->>'passed'='true')
 OR NOT EXISTS(SELECT 1 FROM programacion.engineering_work_checkpoints
 WHERE work_item_id=u.work_item_id AND checkpoint_code='ORACLE_ACTIVATION_READBACK'
 AND status='PENDING' AND evidence_ref IS NULL)
 THEN RAISE EXCEPTION 'M411_CP6_CHECKPOINT_PRESTATE_DRIFT'; END IF;
 b:=programacion.fn_engineering_unit_bootstrap_v3('IG_CURATOR_VALIDATOR_REFACTOR_V2','M4.11');
 IF b->>'terminal_action' IS DISTINCT FROM 'CONTINUE_CURRENT_CHECKPOINT'
 OR b#>>'{current_checkpoint,checkpoint_code}' IS DISTINCT FROM 'ORACLE_ACTIVATION_READBACK'
 OR (b#>>'{state,done_checkpoint_count}')::int<>5
 OR (b#>>'{state,checkpoint_count}')::int<>6
 OR (b#>>'{state,unmet_deps}')::int<>0
 OR (b#>>'{state,open_blockers}')::int<>0
 THEN RAISE EXCEPTION 'M411_CP6_BOOTSTRAP_NOT_CURRENT'; END IF;
 s:=programacion.fn_engineering_checkpoint_action_spec_v3('IG_CURATOR_VALIDATOR_REFACTOR_V2','M4.11','ORACLE_ACTIVATION_READBACK');
 IF s->>'status' IS DISTINCT FROM 'READY'
 OR s->>'action_kind' IS DISTINCT FROM 'READBACK_ONCE'
 OR s->>'precision' IS DISTINCT FROM 'M411_ENGINEERING_TERMINAL_READBACK_V3'
 OR s#>>'{required_evidence_contract,phase}' IS DISTINCT FROM 'ENGINEERING_TERMINAL_READBACK'
 OR s#>>'{required_evidence_contract,decisional_promotion_authorized}' IS DISTINCT FROM 'false'
 OR s#>>'{required_evidence_contract,production_activation_authorized}' IS DISTINCT FROM 'false'
 OR jsonb_array_length(s->'verification_queries')<>1
 THEN RAISE EXCEPTION 'M411_CP6_ACTION_SPEC_DRIFT'; END IF;
 q:=s->'verification_queries'->>0;
 IF q NOT LIKE '%IG_M411_TERMINAL_ENGINEERING_V3%'
 OR q NOT LIKE '%WHERE id=20635%'
 OR q NOT LIKE '%PASS_ENGINEERING_ONLY%'
 THEN RAISE EXCEPTION 'M411_CP6_QUERY_DRIFT'; END IF;
 EXECUTE q INTO STRICT p;
 IF p->>'contract' IS DISTINCT FROM 'IG_M411_TERMINAL_ENGINEERING_V3'
 OR p->>'status' IS DISTINCT FROM 'PASS_ENGINEERING_ONLY'
 OR (p->>'prior_checkpoints_done')::int<>5
 OR p->>'decisional_oracle_authorized' IS DISTINCT FROM 'false'
 OR p->>'production_authorized' IS DISTINCT FROM 'false'
 THEN RAISE EXCEPTION 'M411_CP6_POSITIVE_FAILED'; END IF;
 EXECUTE replace(q,'WHERE id=20635','WHERE id=-20635') INTO STRICT n;
 IF n->>'status' IS DISTINCT FROM 'BLOCKED'
 OR n->>'decisional_oracle_authorized' IS DISTINCT FROM 'false'
 OR n->>'production_authorized' IS DISTINCT FROM 'false'
 THEN RAISE EXCEPTION 'M411_CP6_NEGATIVE_FALSE_PASS'; END IF;
 -- Fail-closed negative: no blank evidence; subtransaction auto-reverts.
 BEGIN
  PERFORM programacion.fn_engineering_checkpoint_transition_v1(
   'IG_CURATOR_VALIDATOR_REFACTOR_V2','M4.11','ORACLE_ACTIVATION_READBACK',
   'DONE','','M411_CP6_EMPTY_EVIDENCE_NEG',NULL);
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM LIKE '%Terminal checkpoint transition requires evidence%'
  OR SQLERRM LIKE '%ENGINEERING_EXPLICIT_EVIDENCE_REF_REQUIRED%'
  THEN neg_rejected:=true; ELSE RAISE; END IF;
 END;
 IF NOT neg_rejected
 OR NOT EXISTS(SELECT 1 FROM programacion.engineering_work_checkpoints
 WHERE work_item_id=u.work_item_id AND checkpoint_code='ORACLE_ACTIVATION_READBACK'
 AND status='PENDING' AND evidence_ref IS NULL)
 THEN RAISE EXCEPTION 'M411_CP6_BLANK_EVIDENCE_FALSE_PASS'; END IF;
 t:=programacion.fn_engineering_checkpoint_transition_v1(
 'IG_CURATOR_VALIDATOR_REFACTOR_V2','M4.11','ORACLE_ACTIVATION_READBACK',
 'DONE',evidence,'IG_M411_CP6_TRAIN_CANONICAL',
 'CP1-CP5 genuine evidence and CP4 assertion; terminal positive PASS_ENGINEERING_ONLY; negative event BLOCKED. No decisional release or production activation.');
 IF t#>>'{transition,status}' IS DISTINCT FROM 'APPLIED'
 OR t#>>'{transition,checkpoint_code}' IS DISTINCT FROM 'ORACLE_ACTIVATION_READBACK'
 THEN RAISE EXCEPTION 'M411_CP6_CANONICAL_TRANSITION_FAILED'; END IF;
 IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
 WHERE work_item_id=u.work_item_id AND status='DONE'
 AND nullif(btrim(evidence_ref),'') IS NOT NULL
 AND completed_at IS NOT NULL)<>6
 OR NOT EXISTS(SELECT 1 FROM programacion.engineering_work_checkpoints
 WHERE work_item_id=u.work_item_id AND checkpoint_code='ORACLE_ACTIVATION_READBACK'
 AND status='DONE' AND evidence_ref=evidence)
 THEN RAISE EXCEPTION 'M411_CP6_CHECKPOINT_POSTREADBACK_FAILED'; END IF;
 b:=programacion.fn_engineering_unit_bootstrap_v3('IG_CURATOR_VALIDATOR_REFACTOR_V2','M4.11');
 IF b#>>'{state,status}' IS DISTINCT FROM 'DONE'
 OR (b#>>'{state,done_checkpoint_count}')::int<>6
 OR (b#>>'{state,checkpoint_count}')::int<>6
 OR (b#>>'{state,progress_pct}')::numeric<>100
 OR b->>'terminal_action' IS DISTINCT FROM 'STOP_TERMINAL_DONE'
 OR (SELECT version FROM public.lf_capability_current WHERE capability_code='INPUT_GOVERNANCE') IS DISTINCT FROM '1.0.0'
 OR (SELECT payload->>'promotion_authorized' FROM public.lf_eventos WHERE id=20635) IS DISTINCT FROM 'false'
 THEN RAISE EXCEPTION 'M411_CP6_TERMINAL_100_READBACK_FAILED'; END IF;
END;
$cp6$;

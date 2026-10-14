-- M4.11 CP5 only, Train-governed. Declarative shadow, never release.
-- EKB: IG-M411-CONSTRUCTION-VS-DECISIONAL-SCOPE-CONFLATION-001.
DO $cp5$
DECLARE
 s jsonb; p jsonb; n jsonb; b jsonb; t jsonb; q text;
 e text:='supabase://programacion.contratos/46#M4.11/CP5;47/47=SHADOW_ONLY;positive=PASS_DECLARATIVE_ONLY;negative=BLOCKED;semantic_independence_certified=false;promotion=false;production=false';
BEGIN
 b:=programacion.fn_engineering_unit_bootstrap_v3('IG_CURATOR_VALIDATOR_REFACTOR_V2','M4.11');
 IF b->>'terminal_action' IS DISTINCT FROM 'CONTINUE_CURRENT_CHECKPOINT'
 OR b#>>'{current_checkpoint,checkpoint_code}' IS DISTINCT FROM 'FAMILY_COVERAGE_47'
 OR (b#>>'{state,done_checkpoint_count}')::int<>4
 OR (b#>>'{state,open_blockers}')::int<>0
 OR (b#>>'{state,unmet_deps}')::int<>0
 THEN RAISE EXCEPTION 'CP5_NOT_CURRENT'; END IF;
 IF NOT EXISTS (SELECT 1 FROM programacion.engineering_plan_units
 WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M4.11'
 AND unit_metadata#>>'{m411_admission_boundary_v1,version}'='3.1.0'
 AND unit_metadata#>>'{m411_admission_boundary_v1,decisional_promotion}'='NOT_AUTHORIZED'
 AND unit_metadata#>>'{m411_admission_boundary_v1,production_activation}'='NOT_AUTHORIZED')
 THEN RAISE EXCEPTION 'CP5_GOVERNANCE_CHANGED'; END IF;
 s:=programacion.fn_engineering_checkpoint_action_spec_v3('IG_CURATOR_VALIDATOR_REFACTOR_V2','M4.11','FAMILY_COVERAGE_47');
 IF s->>'status'<>'READY' OR s->>'action_kind'<>'READBACK_ONCE'
 OR s->>'precision'<>'M411_DECLARATIVE_SHADOW_COVERAGE_47_V3'
 OR jsonb_array_length(s->'verification_queries')<>1
 THEN RAISE EXCEPTION 'CP5_SPEC_CHANGED'; END IF;
 q:=s->'verification_queries'->>0;
 IF q NOT LIKE '%WHERE c.id=46 AND c.contrato_codigo=%'
 THEN RAISE EXCEPTION 'CP5_QUERY_CHANGED'; END IF;
 EXECUTE q INTO STRICT p;
 IF p->>'status'<>'PASS_DECLARATIVE_ONLY'
 OR (p->>'families')::int<>47
 OR p->>'semantic_independence_certified'<>'false'
 THEN RAISE EXCEPTION 'CP5_POSITIVE_FAILED'; END IF;
 EXECUTE replace(q,'WHERE c.id=46','WHERE c.id=-46') INTO STRICT n;
 IF n->>'status'<>'BLOCKED' OR (n->>'families')::int<>0
 THEN RAISE EXCEPTION 'CP5_NEGATIVE_FAILED'; END IF;
 t:=programacion.fn_engineering_checkpoint_transition_v1(
 'IG_CURATOR_VALIDATOR_REFACTOR_V2','M4.11','FAMILY_COVERAGE_47',
 'DONE',e,'IG_M411_CP5_MIGRATION_TRAIN',
 '47 declared shadow strategies, no semantic independence or activation');
 IF t#>>'{transition,status}'<>'APPLIED'
 THEN RAISE EXCEPTION 'CP5_NOT_APPLIED'; END IF;
 IF NOT EXISTS(SELECT 1 FROM programacion.engineering_work_checkpoints c
 JOIN programacion.engineering_plan_units u ON u.work_item_id=c.work_item_id
 WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND u.unit_code='M4.11'
 AND c.checkpoint_code='FAMILY_COVERAGE_47' AND c.status='DONE' AND c.evidence_ref=e)
 THEN RAISE EXCEPTION 'CP5_NO_LEDGER_EVIDENCE'; END IF;
 b:=programacion.fn_engineering_unit_bootstrap_v3('IG_CURATOR_VALIDATOR_REFACTOR_V2','M4.11');
 IF (b#>>'{state,done_checkpoint_count}')::int<>5
 OR b#>>'{current_checkpoint,checkpoint_code}'<>'ORACLE_ACTIVATION_READBACK'
 THEN RAISE EXCEPTION 'CP5_POSTREADBACK_FAILED'; END IF;
END;
$cp5$;
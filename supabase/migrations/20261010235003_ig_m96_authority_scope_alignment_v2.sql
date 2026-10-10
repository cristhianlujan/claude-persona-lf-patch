BEGIN;
DO $align$
DECLARE
 old_exit constant text:='Toda divergencia D1–D5 del shadow adjudicada por la autoridad de M1.7 con decisión persistida; 0 UNRESOLVED (UNRESOLVED bloquea el Shadow Gate)';
 new_exit constant text:='M9.6: mecanismo tecnico de observacion dinamica por campo y barrera de adjudicacion fail-closed implementados y probados; M1.7 solo gobierna drift de plan/currentness. Cobertura y decisiones reales de divergencias shadow siguen UNVERIFIED y requieren recibos verificados, politica D0-D5 actual, 0 UNRESOLVED y cutover del consumidor. Cero recibos NO es PASS.';
 m jsonb;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM transversal.decision_log WHERE adr='DEC-INPUT-GOV-M1.7-DIVERGENCE-ADJUDICATION-001' AND estado='VIGENTE' AND decision LIKE '%plan/currentness%')
 THEN RAISE EXCEPTION 'M96_PLAN_DRIFT_ADR_NOT_CURRENT'; END IF;
 IF NOT EXISTS(SELECT 1 FROM programacion.engineering_plan_units
 WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M9.5'
 AND unit_metadata#>>'{m9_5_scope_alignment_v1,historical_shadow_divergence_coverage,status}'='UNVERIFIED')
 THEN RAISE EXCEPTION 'M96_M95_RUNTIME_HOLD_MISSING'; END IF;
 IF to_regprocedure('programacion.fn_ig_m96_shadow_field_probe_v1(integer,bigint)') IS NULL
 OR to_regprocedure('programacion.fn_ig_m96_adjudication_live_gate_v1(uuid)') IS NULL
 THEN RAISE EXCEPTION 'M96_TECHNICAL_GATES_MISSING'; END IF;
 SELECT unit_metadata INTO m FROM programacion.engineering_plan_units
 WHERE id=279 AND plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M9.6'
 AND work_item_id=468 AND exit_criterion=old_exit FOR UPDATE;
 IF m IS NULL THEN RAISE EXCEPTION 'M96_ORIGINAL_CONTRACT_DRIFT'; END IF;
 m:=jsonb_set(m,'{m9_6_scope_alignment_v2}',jsonb_build_object(
   'schema_version','M96_ENGINEERING_VS_RUNTIME_SCOPE_V2',
   'original_exit_criterion',old_exit,'engineering_exit_criterion',new_exit,
   'reason','M17_AUTHORITY_IS_FOR_PLAN_DRIFT_NOT_SHADOW_SEMANTICS',
   'canonical_observation','programacion.fn_ig_m96_shadow_field_probe_v1',
   'technical_gate','programacion.fn_ig_m96_adjudication_live_gate_v1',
   'consumer_policy','INPUT_GOVERNANCE_DIVERGENCE_LEVELS_CONTRACT',
   'plan_drift_authority','DEC-INPUT-GOV-M1.7-DIVERGENCE-ADJUDICATION-001',
   'runtime_obligation',jsonb_build_object('status','UNVERIFIED',
      'owned_by','CONTROL_EQUIVALENCE_JUDGE_CONSUMER_CUTOVER','required_before','RUNTIME_CUTOVER',
      'acceptance','CURRENT_TYPED_FIELD_RECEIPTS_AND_CURRENT_ORACLE_COVERAGE_AND_ZERO_UNRESOLVED',
      'zero_receipts_is_pass',false,'unknown_oracle_is_pass',false),
   'production_authorized',false),true);
 m:=jsonb_set(m,'{action_specs_v1,ADJUDICATE_EACH,expected}',
  to_jsonb('Comprobar implementacion y fallos negativos del gate por campo. No materializar decisiones humanas ni afirmar 0 divergencias reales.'::text),true);
 m:=jsonb_set(m,'{action_specs_v1,ADJUDICATE_EACH,adjudication_contract}',jsonb_build_object(
  'source_authority','CONTROL_EQUIVALENCE_JUDGE','dynamic_contract','INPUT_GOVERNANCE_DIVERGENCE_LEVELS_CONTRACT',
  'plan_drift_authority','DEC-INPUT-GOV-M1.7-DIVERGENCE-ADJUDICATION-001',
  'runtime_cutover_owner','CONTROL_EQUIVALENCE_JUDGE_CONSUMER_CUTOVER','runtime_cutover_unverified',true,
  'D4_always_blocks',true,'zero_receipts_is_pass',false),true);
 UPDATE programacion.engineering_plan_units SET exit_criterion=new_exit,unit_metadata=m WHERE id=279;
 UPDATE programacion.engineering_work_items SET
 title='M9.6 — Gate tecnico de adjudicacion shadow; cutover condicionado',
 objective='Demostrar observacion por campo y politica dinamica; M1.7 solo gobierna drift de plan.',
 expected_result='Gate fail-closed implementado; divergencias reales no adjudicadas permanecen UNVERIFIED.',
 acceptance_criteria='["Adaptador canonico por campo instalado","Gate rechaza recibos solo digest","D4 y UNRESOLVED son bloqueantes","Cero recibos no es PASS","Cutover real sigue UNVERIFIED"]'::jsonb
 WHERE id=468 AND work_code='PAULO-155';
 UPDATE programacion.engineering_work_checkpoints SET title=CASE checkpoint_code
 WHEN 'ADJUDICATE_EACH' THEN 'Implementacion de gate de adjudicacion; runtime no autorizado'
 WHEN 'UNRESOLVED_NEGATIVE' THEN 'Negativo: UNRESOLVED mantiene BLOCKED'
 WHEN 'ADJUDICATION_READBACK' THEN 'Readback tecnico; cutover sigue UNVERIFIED'
 ELSE title END WHERE work_item_id=468
 AND checkpoint_code IN ('ADJUDICATE_EACH','UNRESOLVED_NEGATIVE','ADJUDICATION_READBACK');
 IF programacion.fn_ig_m96_adjudication_live_gate_v1('0a091836-f8db-4063-965d-a02fa2fbd6d5')->>'status'<>'BLOCKED'
 OR programacion.fn_ig_m96_adjudication_live_gate_v1('00000000-0000-4000-8000-000000000099')->>'status'<>'BLOCKED'
 THEN RAISE EXCEPTION 'M96_GATE_FALSE_PASS'; END IF;
END $align$;
COMMIT;

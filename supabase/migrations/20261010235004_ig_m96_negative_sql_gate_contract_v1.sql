BEGIN;
DO $fix$
DECLARE m jsonb; n jsonb; r jsonb; v_exit text;
BEGIN
 SELECT unit_metadata,exit_criterion INTO m,v_exit FROM programacion.engineering_plan_units
 WHERE id=279 AND plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M9.6' FOR UPDATE;
 IF m#>>'{m9_6_scope_alignment_v2,runtime_obligation,status}' IS DISTINCT FROM 'UNVERIFIED'
 OR v_exit IS DISTINCT FROM m#>>'{m9_6_scope_alignment_v2,engineering_exit_criterion}'
 THEN RAISE EXCEPTION 'M96_SCOPE_CURRENTNESS_MISSING'; END IF;
 n:=m#>'{action_specs_v1,UNRESOLVED_NEGATIVE}';
 IF n->>'status'<>'READY' OR n->>'action_kind'<>'BOUNDED_CHECKPOINT_TEST_AUTHORING'
 THEN RAISE EXCEPTION 'M96_NEGATIVE_CONTRACT_PREIMAGE_DRIFT'; END IF;
 n:=n||jsonb_build_object(
  'action_kind','READBACK_ONCE','recipe_mode','NEGATIVE_SQL_GATE_READBACK_V1',
  'precision','EXPLICIT_ADJUDICATION_NEGATIVE_SQL_READBACK_V1',
  'mutation_policy','NO_DOMAIN_MUTATION','requires_material_execution',false,
  'expected','SQL negativo real: recibo digest-only y recibo ausente mantienen BLOCKED; no se concede cutover.',
  'target',jsonb_build_object('declared_objects',jsonb_build_array(
    'programacion.fn_ig_m96_adjudication_live_gate_v1','programacion.fn_ig_m96_adjudication_structure_v1',
    'private.lf_evidence_ledger_v1','programacion.engineering_plan_units'),
    'declared_assets','[]'::jsonb,'declared_events','[]'::jsonb,'declared_artifacts','[]'::jsonb),
  'test_execution_contract',jsonb_build_object(
   'mode','SQL_READBACK_NEGATIVE','test_code','ENG_M9_6_UNRESOLVED_NEGATIVE',
   'synthetic_pass','FORBIDDEN','negative_required',true,'authoring_required',false,
   'semantic_authority','CURRENT_M96_SCOPE_AND_CANONICAL_LEDGER',
   'declared_objects',jsonb_build_array('programacion.fn_ig_m96_adjudication_live_gate_v1','private.lf_evidence_ledger_v1'),
   'canonical_exit_criterion',v_exit),
  'verification_queries',jsonb_build_array(
    'select programacion.fn_ig_m96_adjudication_live_gate_v1(''0a091836-f8db-4063-965d-a02fa2fbd6d5'')',
    'select programacion.fn_ig_m96_adjudication_live_gate_v1(''00000000-0000-4000-8000-000000000099'')'));
 m:=jsonb_set(m,'{action_specs_v1,UNRESOLVED_NEGATIVE}',n,true);
 r:=jsonb_build_object(
 'schema_version','ENGINEERING_ACTION_SPEC_V3','checkpoint_code','ADJUDICATION_READBACK',
 'status','READY','action_kind','READBACK_ONCE','recipe_mode','READBACK_EXACT',
 'contract_source','EXPLICIT_ACTION_SPEC','mutation_policy','NO_DOMAIN_MUTATION',
 'expected','Verificar dos migraciones Git=ledger=DB, negativo real BLOCKED y cutover UNVERIFIED.',
 'target',jsonb_build_object('declared_objects',jsonb_build_array(
  'programacion.engineering_plan_units','programacion.engineering_work_checkpoints',
  'supabase_migrations.schema_migrations','programacion.fn_ig_m96_adjudication_live_gate_v1'),
  'declared_assets','[]'::jsonb,'declared_events','[]'::jsonb,'declared_artifacts','[]'::jsonb),
 'assertion_contract',jsonb_build_object('mode','EXPLICIT_PASS_WHEN_SUBSET','pass_when',
  jsonb_build_object('source_parity',true,'negative_gate_blocked',true,'cutover_unverified',true)),
 'requires_material_execution',false,
 'verification_queries',jsonb_build_array(
 'select version,name from supabase_migrations.schema_migrations where version in (''20261010235002'',''20261010235003'')',
 'select unit_metadata#>>''{m9_6_scope_alignment_v2,runtime_obligation,status}'' from programacion.engineering_plan_units where id=279'));
 m:=jsonb_set(m,'{action_specs_v1,ADJUDICATION_READBACK}',r,true);
 UPDATE programacion.engineering_plan_units SET unit_metadata=m WHERE id=279;
 IF (programacion.fn_engineering_checkpoint_action_spec_v3('IG_CURATOR_VALIDATOR_REFACTOR_V2','M9.6','UNRESOLVED_NEGATIVE')->>'action_kind')<>'READBACK_ONCE'
 OR (programacion.fn_engineering_checkpoint_action_spec_v3('IG_CURATOR_VALIDATOR_REFACTOR_V2','M9.6','ADJUDICATION_READBACK')->>'status')<>'READY'
 THEN RAISE EXCEPTION 'M96_ACTION_SPEC_REBIND_FAILED'; END IF;
 IF programacion.fn_ig_m96_adjudication_live_gate_v1('0a091836-f8db-4063-965d-a02fa2fbd6d5')->>'reason'<>'PRODUCER_ONLY_BUNDLE_DIGEST_OR_UNVERIFIED'
 OR programacion.fn_ig_m96_adjudication_live_gate_v1('00000000-0000-4000-8000-000000000099')->>'reason'<>'PRODUCER_RECEIPT_MISSING'
 THEN RAISE EXCEPTION 'M96_REAL_NEGATIVE_FALSE_PASS'; END IF;
END $fix$;
COMMIT;
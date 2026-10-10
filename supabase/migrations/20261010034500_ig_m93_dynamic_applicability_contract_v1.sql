-- IG M9.3; governed dynamic selection, transaction-safe, sandbox-only after merge
DO $m93$
DECLARE spec jsonb; acquisition jsonb; measure jsonb; criterion text;
BEGIN
 SELECT unit_metadata#>'{action_specs_v1,FULL_PIPELINE_CANDIDATE}' INTO STRICT spec
 FROM programacion.engineering_plan_units
 WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M9.3' FOR UPDATE;
 IF spec#>>'{evidence_acquisition_contract,cohort_authority}' <> 'programacion.v_input_governance_representative_cohort_v1'
 OR spec#>>'{evidence_acquisition_contract,baseline}' <> '5.13'
 THEN RAISE EXCEPTION 'M93_SELECTION_CONTRACT_SOURCE_DRIFT'; END IF;
 criterion := 'Shadow no decisional del pipeline vNext vs 5.13 con seleccion dinamica de casos aplicables desde M9.4; por alcance ALL_ACTIVE, SCREEN o TYPE; comparacion T-EQUIV tipada; cero escrituras autoritativas persistentes; recibos reales y readback; N/A justificado.';
 acquisition := spec#>'{evidence_acquisition_contract}';
 measure := acquisition->'measurement_contract';
 measure := jsonb_set(measure,'{terminal_pass_when}',
    (measure->'terminal_pass_when')-'seven_independently_proven_receipts' ||
    jsonb_build_object('all_and_only_selected_memberships_verified',true,'governed_selection_snapshot_required',true,'selection_nonempty',true,'nonapplicable_justified',true),true);
 measure := measure || jsonb_build_object('terminal_unit','DYNAMIC_GOVERNED_SELECTION','selection_is_data_driven',true,'historical_seven_types_not_per_screen_required',true);
 acquisition := (acquisition-'required_cohort_count') || jsonb_build_object(
    'selection_source','programacion.v_input_governance_representative_cohort_v1',
    'selection_scopes',jsonb_build_array('ALL_ACTIVE','SCREEN','TYPE'),
    'selection_cardinality','RUNTIME_GOVERNED_MEMBERSHIPS',
    'literal_type_set_forbidden',true,'literal_screen_ids_forbidden',true,
    'measurement_contract',measure);
 spec := jsonb_set(spec,'{evidence_acquisition_contract}',acquisition,true);
 spec := spec || jsonb_build_object('required_scope','M9_4_DYNAMIC_APPLICABLE_COHORTS','expected',criterion);
 spec := jsonb_set(spec,'{test_execution_contract,canonical_exit_criterion}',to_jsonb(criterion),true);
 UPDATE programacion.engineering_plan_units SET
  exit_criterion=criterion,
  unit_metadata=jsonb_set(unit_metadata,'{action_specs_v1,FULL_PIPELINE_CANDIDATE}',spec,true)
 WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M9.3';
END $m93$;

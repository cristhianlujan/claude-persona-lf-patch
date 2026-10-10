DO $m95$
DECLARE
  old_exit constant text := 'IG declara la tabla de niveles D0–D5 por campo (D4 = riesgo de falso PASS, bloqueante) como configuración consumida por el motor de T-EQUIV; 100% de divergencias del shadow clasificadas';
  new_exit constant text := 'M9.5: unidad DECLARATIVA, contrato versionado D0-D5 dinamico por campo, T-EQUIV CURRENT RELEASED, y D4 negativo con evidencia real. Clasificacion historica shadow queda UNVERIFIED, no se infiere 100% de ausencia de recibos; exige cutover del consumidor.';
  new_title constant text := 'Readback de declaraciones y evidencia D4; runtime shadow UNVERIFIED';
  p programacion.engineering_plan_units%ROWTYPE;
BEGIN
  SELECT * INTO p FROM programacion.engineering_plan_units
  WHERE id=77 AND plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M9.5' AND work_item_id=265
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'M95_UNIT_NOT_FOUND'; END IF;
  IF p.exit_criterion=new_exit THEN RETURN; END IF;
  IF p.exit_criterion IS DISTINCT FROM old_exit OR p.remap_action<>'MUEVE motor a T-EQUIV; IG solo declara niveles' THEN RAISE EXCEPTION 'M95_SCOPE_CHANGED'; END IF;
  IF NOT EXISTS(SELECT 1 FROM programacion.engineering_work_checkpoints
    WHERE work_item_id=265 AND checkpoint_code='CLASSIFIED_READBACK' AND status IN ('PENDING','IN_PROGRESS')) THEN RAISE EXCEPTION 'M95_CP_NOT_CURRENT'; END IF;
  UPDATE programacion.engineering_plan_units
  SET exit_criterion=new_exit,
      unit_metadata=jsonb_set(unit_metadata,'{m9_5_scope_alignment_v1}',
        jsonb_build_object('schema_version','M95_DECLARATIVE_SCOPE_V1',
          'original_exit_criterion',old_exit,
          'declarative_exit_criterion',new_exit,
          'reason','REMAPPED_DECLARATION_ONLY_NO_SHADOW_TYPED_RECEIPTS',
          'terminal_sources',jsonb_build_array('programacion.contratos/50','CONTROL_EQUIVALENCE_JUDGE/1.0.0','D4_BLOCKS_NEGATIVE'),
          'historical_shadow_divergence_coverage',jsonb_build_object(
            'status','UNVERIFIED','owned_by','CONTROL_EQUIVALENCE_JUDGE_CONSUMER_CUTOVER',
            'required_before','RUNTIME_CUTOVER',
            'acceptance','CLASSIFIED_COUNT_EQUALS_DIVERGENCE_COUNT_WITH_CURRENT_TYPED_RECEIPTS',
            'zero_receipts_is_pass',false),'production_authorized',false),true)
  WHERE id=77;
  UPDATE programacion.engineering_work_checkpoints
  SET title=new_title, updated_at=now(), updated_by_execution_id='CHATGPT-M95-SCOPEALIGN-20261010'
  WHERE work_item_id=265 AND checkpoint_code='CLASSIFIED_READBACK';
  IF (SELECT exit_criterion FROM programacion.engineering_plan_units WHERE id=77)<>new_exit THEN RAISE EXCEPTION 'M95_POSTCHECK'; END IF;
END $m95$;

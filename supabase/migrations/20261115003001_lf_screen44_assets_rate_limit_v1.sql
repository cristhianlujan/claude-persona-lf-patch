-- Screen 44 / IG run 956. Candidate-only data bindings; no state promotion.
-- Canonical source: SELECT element 148, rate policy 2, rule 418.
BEGIN;
DO $repair$
DECLARE
  v_token_id bigint;
BEGIN
  IF (SELECT count(*) FROM lf_ops.pantallas WHERE id=44 AND codigo='B2B-CARGA-002')<>1 THEN
    RAISE EXCEPTION 'SCREEN44_ASSET_RATE_SCREEN_DRIFT';
  END IF;
  IF (SELECT count(*) FROM lf_ops.pantalla_elementos
      WHERE pantalla_id=44 AND required_for_implementation=true AND status<>'DEPRECATED')<>27
    OR (SELECT count(*) FROM lf_ops.pantalla_elementos
      WHERE element_id=148 AND pantalla_id=44
      AND element_code='B2B_CARGA002_WIZARD_LOCAL_NAV'
      AND element_role='WIZARD_NAVIGATION'
      AND required_for_implementation=true)<>1 THEN
    RAISE EXCEPTION 'SCREEN44_ASSET_RATE_ELEMENT_SOURCE_DRIFT';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM lf_design.component_tokens
      WHERE component_token_id=11 AND component_token_code='upload_six_step_stepper'
      AND component_state='six_step') THEN
    RAISE EXCEPTION 'SCREEN44_ASSET_RATE_LEGACY_STEPPER_DRIFT';
  END IF;
  IF EXISTS (SELECT 1 FROM lf_design.component_tokens
      WHERE component_token_code='b2b_upload_wizard_local_nav_3step'
      AND (component_name<>'b2b_upload_wizard_navigation'
        OR component_state<>'three_step' OR design_system_id<>1)) THEN
    RAISE EXCEPTION 'SCREEN44_ASSET_RATE_COMPONENT_CONFLICT';
  END IF;
  IF (SELECT count(*) FROM lf_ops.politicas_rate_limit
      WHERE rate_limit_policy_id=2 AND policy_code='RATE-B2B-UPLOAD'
        AND status='CANDIDATO' AND resource_code='FILE_UPLOAD'
        AND window_seconds=3600 AND max_requests=20 AND scope_key='TENANT_USER')<>1
    OR (SELECT count(*) FROM lf_ops.reglas WHERE id=418 AND estado='VIGENTE')<>1 THEN
    RAISE EXCEPTION 'SCREEN44_ASSET_RATE_POLICY_SOURCE_DRIFT';
  END IF;

  INSERT INTO lf_design.component_tokens (
    component_token_code,design_system_code,component_name,component_state,
    token_bindings,allowed_usage,blocked_usage,status,notes,design_system_id
  )
  VALUES (
    'b2b_upload_wizard_local_nav_3step','LF_DS_V1',
    'b2b_upload_wizard_navigation','three_step',
    jsonb_build_object('screen_code','B2B-CARGA-002','source_rule_id',581,
      'ui_states',jsonb_build_array('OFFER_TYPE_AND_TEMPLATE',
      'UPLOAD_AND_PREPARE_DATA','VALIDATE')),
    'Navegacion local del wizard B2B de tres pasos; conservar autoridad de transiciones server-side.',
    'No usar stepper legado de seis pasos ni componentes de Cliente. No inventar estado de dominio.',
    'CANDIDATO','Binding candidato trazado a pantalla 44, regla 581 y run IG 956.',1
  )
  ON CONFLICT (component_token_code) DO NOTHING;

  SELECT component_token_id INTO STRICT v_token_id
  FROM lf_design.component_tokens
  WHERE component_token_code='b2b_upload_wizard_local_nav_3step'
    AND component_name='b2b_upload_wizard_navigation'
    AND component_state='three_step' AND design_system_id=1
    AND status='CANDIDATO';

  IF EXISTS (SELECT 1 FROM lf_ops.pantalla_elementos
     WHERE element_id=148 AND component_token_id IS NOT NULL
       AND component_token_id<>v_token_id) THEN
    RAISE EXCEPTION 'SCREEN44_ASSET_RATE_ELEMENT_ALREADY_BOUND_OTHER';
  END IF;
  UPDATE lf_ops.pantalla_elementos
     SET component_token_id=v_token_id,
         semantic_binding_status='RESOLVED_ID',
         source_refs=source_refs || '["component_token:b2b_upload_wizard_local_nav_3step"]'::jsonb,
         updated_at=now()
   WHERE element_id=148 AND pantalla_id=44
     AND component_token_id IS NULL
     AND semantic_binding_status='PENDING_SEMANTIC_COMPONENT';

  INSERT INTO lf_ops.pantallas_politicas (
    pantalla_id,policy_kind,reference_role,rate_limit_policy_id,status
  ) VALUES (44,'RATE_LIMIT','upload_rate_limit_policy_id',2,'CANDIDATO')
  ON CONFLICT (pantalla_id,reference_role) DO NOTHING;

  IF (SELECT count(*) FROM lf_ops.pantallas_politicas
      WHERE pantalla_id=44 AND policy_kind='RATE_LIMIT'
        AND reference_role='upload_rate_limit_policy_id'
        AND rate_limit_policy_id=2 AND status='CANDIDATO')<>1 THEN
    RAISE EXCEPTION 'SCREEN44_ASSET_RATE_LINK_CONFLICT';
  END IF;

  INSERT INTO lf_ops.pantallas_politicas_reglas(pantalla_politica_id,regla_id)
  SELECT pp.pantalla_politica_id,418
  FROM lf_ops.pantallas_politicas pp
  WHERE pp.pantalla_id=44 AND pp.reference_role='upload_rate_limit_policy_id'
    AND pp.rate_limit_policy_id=2 AND pp.status='CANDIDATO'
  ON CONFLICT DO NOTHING;
END $repair$;

DO $readback$
BEGIN
  IF (SELECT count(*) FROM lf_ops.pantalla_elementos
      WHERE pantalla_id=44 AND required_for_implementation=true AND status<>'DEPRECATED'
        AND component_token_id IS NOT NULL
        AND semantic_binding_status='RESOLVED_ID')<>27
    OR (SELECT count(*) FROM lf_ops.pantallas_politicas
      WHERE pantalla_id=44 AND reference_role='upload_rate_limit_policy_id'
      AND rate_limit_policy_id=2 AND status='CANDIDATO')<>1
    OR (SELECT count(*) FROM lf_ops.pantallas_politicas_reglas pr
      JOIN lf_ops.pantallas_politicas pp USING(pantalla_politica_id)
      WHERE pp.pantalla_id=44 AND pp.reference_role='upload_rate_limit_policy_id'
        AND pr.regla_id=418)<>1
    OR (SELECT status FROM lf_ops.politicas_rate_limit
      WHERE rate_limit_policy_id=2)<>'CANDIDATO' THEN
    RAISE EXCEPTION 'SCREEN44_ASSET_RATE_READBACK_FAILED';
  END IF;
END $readback$;
COMMIT;

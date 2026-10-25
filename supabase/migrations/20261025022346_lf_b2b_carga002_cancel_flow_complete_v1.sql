BEGIN;

DO $complete$
DECLARE
  v_screen_id integer;
  v_element_id bigint;
  v_error_hex text;
  v_color_id bigint;
  v_visual_id bigint;
  v_component_id bigint;
BEGIN
  SELECT id INTO v_screen_id
  FROM lf_ops.pantallas
  WHERE codigo='B2B-CARGA-002' AND activa
  LIMIT 1;

  IF v_screen_id IS NULL THEN
    RAISE EXCEPTION 'B2B_CARGA002_SCREEN_NOT_FOUND';
  END IF;

  SELECT pe.element_id,pe.component_token_id
    INTO v_element_id,v_component_id
  FROM lf_ops.pantalla_elementos pe
  WHERE pe.pantalla_id=v_screen_id
    AND pe.element_code='B2B_CARGA002_CANCEL_ACTION'
  LIMIT 1;

  IF v_element_id IS NULL OR v_component_id IS NULL THEN
    RAISE EXCEPTION 'B2B_CARGA002_CANCEL_ELEMENT_NOT_REPAIRED';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM lf_design.component_tokens
    WHERE component_token_id=v_component_id
      AND component_token_code='cta_destructive_default'
      AND status='CANDIDATO'
  ) THEN
    RAISE EXCEPTION 'CTA_DESTRUCTIVE_EXPECTED_CANDIDATE_NOT_FOUND';
  END IF;

  SELECT hex_value INTO v_error_hex
  FROM lf_design.color_tokens
  WHERE token_name='error_text'
    AND status='VIGENTE'
  LIMIT 1;

  IF v_error_hex IS DISTINCT FROM '#991B1B' THEN
    RAISE EXCEPTION 'CRITICAL_ACTION_BASE_COLOR_UNEXPECTED:%',v_error_hex;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM lf_design.visual_decisions
    WHERE visual_decision_code='VD_B2B_CARGA002_CANCEL_ACTION_20261024'
  ) THEN
    SELECT coalesce(max(visual_decision_id),0)+1 INTO v_visual_id
    FROM lf_design.visual_decisions;

    INSERT INTO lf_design.visual_decisions(
      visual_decision_code,
      design_system_code,
      decision_title,
      decision_detail,
      decision_status,
      complexity_level,
      source_decision_id,
      impact_scope,
      pending_reason,
      owner_name,
      decided_at,
      visual_decision_id,
      design_system_id
    )
    VALUES(
      'VD_B2B_CARGA002_CANCEL_ACTION_20261024',
      'LF_DS_V1',
      'Acción destructiva canónica para cancelar una carga B2B',
      'Owner aprobó el ejemplo visual de cancelación de B2B-CARGA-002. La acción visible queda como "Anular carga". La confirmación exige el campo canónico B2B_FLD_LOAD_CANCEL_COMMENT de UPLOAD_BATCH antes de ejecutar CANCEL. El patrón destructivo usa un token semántico critical_action con el mismo valor cromático vigente de error_text (#991B1B), pero con autoridad de uso específica para CTA destructivo; texto card_surface. Se preservan B2B_LOAD_CANCEL, transiciones 15/16, requires_comment, idempotencia y auditoría. Esta decisión no promueve toda la pantalla B2B-CARGA-002 ni cambia otros estados del wizard.',
      'VIGENTE',
      'MEDIA',
      'OWNER_APPROVAL_2026-10-24_B2B_CARGA002_CANCEL',
      jsonb_build_array(
        'LF_DS_V1',
        'B2B_APP_SHELL',
        'B2B-CARGA-002',
        'B2B_CARGA002_CANCEL_ACTION',
        'CANCEL_CONFIRMATION',
        'DESTRUCTIVE_ACTION'
      ),
      NULL,
      'Cristhian',
      DATE '2026-10-24',
      v_visual_id,
      1
    );
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM lf_design.color_tokens
    WHERE token_name='critical_action'
  ) THEN
    SELECT coalesce(max(color_token_id),0)+1 INTO v_color_id
    FROM lf_design.color_tokens;

    INSERT INTO lf_design.color_tokens(
      token_name,
      design_system_code,
      hex_value,
      rgb_value,
      token_group,
      semantic_role,
      allowed_usage,
      blocked_usage,
      status,
      source_decision_id,
      affected_components,
      propagation_scope,
      requires_qa,
      notes,
      color_token_id,
      design_system_id
    )
    VALUES(
      'critical_action',
      'LF_DS_V1',
      v_error_hex,
      '153,27,27',
      'semantic_action',
      'Acción crítica o destructiva confirmada',
      'CTA destructivo o acción crítica que cambia estado de forma irreversible/relevante y requiere confirmación gobernada.',
      'No usar para texto informativo, errores inline, CTA principal normal ni estados positivos. No usar sin confirmación cuando la regla funcional la exige.',
      'VIGENTE',
      'VD_B2B_CARGA002_CANCEL_ACTION_20261024',
      jsonb_build_array('cta_destructive_default'),
      jsonb_build_array('LF_DS_V1','B2B_APP_SHELL'),
      true,
      'Alias semántico de #991B1B separado de error_text para evitar reutilizar un token de texto como fondo de acción. Aprobado para patrón destructivo B2B.',
      v_color_id,
      1
    );
  ELSE
    UPDATE lf_design.color_tokens
       SET hex_value=v_error_hex,
           rgb_value='153,27,27',
           token_group='semantic_action',
           semantic_role='Acción crítica o destructiva confirmada',
           allowed_usage='CTA destructivo o acción crítica que cambia estado de forma irreversible/relevante y requiere confirmación gobernada.',
           blocked_usage='No usar para texto informativo, errores inline, CTA principal normal ni estados positivos. No usar sin confirmación cuando la regla funcional la exige.',
           status='VIGENTE',
           source_decision_id='VD_B2B_CARGA002_CANCEL_ACTION_20261024',
           affected_components=jsonb_build_array('cta_destructive_default'),
           propagation_scope=jsonb_build_array('LF_DS_V1','B2B_APP_SHELL'),
           requires_qa=true,
           updated_at=now()
     WHERE token_name='critical_action';
  END IF;

  UPDATE lf_design.component_tokens
     SET token_bindings=jsonb_build_object(
           'text','card_surface',
           'border','critical_action',
           'radius','radius_12',
           'background','critical_action',
           'typography','text_button_primary'
         ),
         allowed_usage='Acciones destructivas confirmadas y gobernadas que cambian estado o invalidan una entidad.',
         blocked_usage='No usar como CTA principal normal. No usar sin confirmación cuando la regla funcional la exige. No hardcodear color ni semántica por pantalla.',
         status='VIGENTE',
         source_decision_id='VD_B2B_CARGA002_CANCEL_ACTION_20261024',
         notes='Patrón destructivo VIGENTE. Usa critical_action como semántica de acción, no error_text directamente. Primer consumidor: B2B-CARGA-002 CANCEL.',
         updated_at=now()
   WHERE component_token_id=v_component_id
     AND component_token_code='cta_destructive_default';

  UPDATE lf_ops.campos
     SET estado='ACTIVO',
         source_decision_id='VD_B2B_CARGA002_CANCEL_ACTION_20261024',
         updated_at=now()
   WHERE codigo='B2B_FLD_LOAD_CANCEL_COMMENT'
     AND entity_code='UPLOAD_BATCH';

  UPDATE lf_ops.pantalla_elementos
     SET label_visible='Anular carga',
         status='VIGENTE',
         semantic_binding_status='RESOLVED_ID',
         source_refs=(
           SELECT jsonb_agg(DISTINCT x)
           FROM jsonb_array_elements(
             coalesce(source_refs,'[]'::jsonb)
             || jsonb_build_array(
               'visual_decision:VD_B2B_CARGA002_CANCEL_ACTION_20261024',
               'product_label:Anular carga',
               'color_token:critical_action',
               'product_currentness:CANONICAL_UPDATED'
             )
           ) x
         ),
         updated_at=now()
   WHERE element_id=v_element_id
     AND component_token_id=v_component_id;

  IF NOT EXISTS (
    SELECT 1
    FROM lf_design.visual_decisions
    WHERE visual_decision_code='VD_B2B_CARGA002_CANCEL_ACTION_20261024'
      AND decision_status='VIGENTE'
  ) THEN
    RAISE EXCEPTION 'FINAL_VISUAL_DECISION_NOT_VIGENTE';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM lf_design.color_tokens
    WHERE token_name='critical_action'
      AND status='VIGENTE'
      AND hex_value='#991B1B'
      AND source_decision_id='VD_B2B_CARGA002_CANCEL_ACTION_20261024'
  ) THEN
    RAISE EXCEPTION 'FINAL_CRITICAL_ACTION_TOKEN_NOT_VIGENTE';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM lf_design.component_tokens
    WHERE component_token_id=v_component_id
      AND component_token_code='cta_destructive_default'
      AND status='VIGENTE'
      AND token_bindings->>'background'='critical_action'
      AND token_bindings->>'text'='card_surface'
  ) THEN
    RAISE EXCEPTION 'FINAL_DESTRUCTIVE_COMPONENT_NOT_VIGENTE';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM lf_ops.campos
    WHERE codigo='B2B_FLD_LOAD_CANCEL_COMMENT'
      AND entity_code='UPLOAD_BATCH'
      AND es_requerido
      AND estado='ACTIVO'
  ) THEN
    RAISE EXCEPTION 'FINAL_CANCEL_FIELD_NOT_ACTIVE';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM lf_ops.pantalla_elementos
    WHERE element_id=v_element_id
      AND label_visible='Anular carga'
      AND status='VIGENTE'
      AND semantic_binding_status='RESOLVED_ID'
      AND component_token_id=v_component_id
  ) THEN
    RAISE EXCEPTION 'FINAL_CANCEL_ELEMENT_NOT_VIGENTE';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM lf_ops.estados_transiciones
    WHERE transition_id IN (15,16)
      AND (
        action_code<>'CANCEL'
        OR required_permission_code<>'B2B_LOAD_CANCEL'
        OR requires_comment IS NOT TRUE
        OR requires_idempotency_key IS NOT TRUE
        OR audit_required IS NOT TRUE
      )
  ) THEN
    RAISE EXCEPTION 'FINAL_CANCEL_TRANSITIONS_CHANGED';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM lf_ops.pantallas
    WHERE id=v_screen_id
      AND estado='CANDIDATO_VISUAL'
  ) THEN
    RAISE EXCEPTION 'SCREEN_WIDE_STATUS_MUST_REMAIN_UNCHANGED';
  END IF;
END
$complete$;

COMMIT;

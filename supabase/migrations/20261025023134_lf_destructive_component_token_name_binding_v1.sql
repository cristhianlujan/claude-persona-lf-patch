BEGIN;

DO $fix$
DECLARE
  v_component_id bigint;
BEGIN
  SELECT component_token_id INTO v_component_id
  FROM lf_design.component_tokens
  WHERE component_token_code='cta_destructive_default'
  LIMIT 1;

  IF v_component_id IS NULL THEN
    RAISE EXCEPTION 'CTA_DESTRUCTIVE_DEFAULT_NOT_FOUND';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM lf_design.component_tokens
    WHERE component_token_id<>v_component_id
      AND token_bindings::text ilike '%critical_action%'
  ) THEN
    RAISE EXCEPTION 'CRITICAL_ACTION_HAS_OTHER_COMPONENT_CONSUMERS';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM lf_design.theme_bindings
    WHERE token_overrides::text ilike '%critical_action%'
  ) THEN
    RAISE EXCEPTION 'CRITICAL_ACTION_HAS_THEME_CONSUMERS';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM lf_design.color_tokens
    WHERE token_name='error_bg' AND status='VIGENTE'
  ) OR NOT EXISTS (
    SELECT 1 FROM lf_design.color_tokens
    WHERE token_name='error_text' AND status='VIGENTE'
  ) THEN
    RAISE EXCEPTION 'CANONICAL_ERROR_TOKENS_NOT_VIGENTE';
  END IF;

  UPDATE lf_design.component_tokens
  SET token_bindings=jsonb_build_object(
        'text','error_text',
        'border','error_text',
        'radius','radius_12',
        'background','error_bg',
        'typography','text_button_primary'
      ),
      source_decision_id='VD_B2B_CARGA002_CANCEL_ACTION_20261024',
      notes='Patrón destructivo VIGENTE usando exclusivamente nombres de tokens canónicos existentes: error_bg y error_text. Sin duplicación de HEX.',
      updated_at=now()
  WHERE component_token_id=v_component_id;

  UPDATE lf_design.visual_decisions
  SET decision_detail=
      'Owner aprobó el ejemplo visual de cancelación de B2B-CARGA-002. La acción visible queda como "Anular carga". La confirmación exige B2B_FLD_LOAD_CANCEL_COMMENT de UPLOAD_BATCH antes de ejecutar CANCEL. El componente destructivo referencia tokens canónicos por nombre: background=error_bg, border=error_text, text=error_text; no duplica valores HEX. Se preservan B2B_LOAD_CANCEL, transiciones 15/16, requires_comment, idempotencia y auditoría. Esta decisión no promueve toda la pantalla B2B-CARGA-002 ni cambia otros estados del wizard.',
      updated_at=now()
  WHERE visual_decision_code='VD_B2B_CARGA002_CANCEL_ACTION_20261024'
    AND decision_status='VIGENTE';

  DELETE FROM lf_design.color_tokens
  WHERE token_name='critical_action';

  IF EXISTS (
    SELECT 1 FROM lf_design.color_tokens WHERE token_name='critical_action'
  ) THEN
    RAISE EXCEPTION 'CRITICAL_ACTION_DUPLICATE_TOKEN_REMAINS';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM lf_design.component_tokens
    WHERE component_token_id=v_component_id
      AND component_token_code='cta_destructive_default'
      AND status='VIGENTE'
      AND token_bindings->>'background'='error_bg'
      AND token_bindings->>'border'='error_text'
      AND token_bindings->>'text'='error_text'
      AND token_bindings->>'radius'='radius_12'
      AND token_bindings->>'typography'='text_button_primary'
  ) THEN
    RAISE EXCEPTION 'CTA_DESTRUCTIVE_TOKEN_NAME_BINDING_READBACK_FAILED';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM lf_design.component_tokens
    WHERE token_bindings::text ~ '#[0-9A-Fa-f]{6}'
      AND component_token_id=v_component_id
  ) THEN
    RAISE EXCEPTION 'CTA_DESTRUCTIVE_HARDCODED_HEX_REMAINS';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM lf_ops.pantalla_elementos pe
    JOIN lf_ops.pantallas p ON p.id=pe.pantalla_id
    WHERE p.codigo='B2B-CARGA-002'
      AND p.activa
      AND pe.element_code='B2B_CARGA002_CANCEL_ACTION'
      AND pe.label_visible='Anular carga'
      AND pe.status='VIGENTE'
      AND pe.semantic_binding_status='RESOLVED_ID'
      AND pe.component_token_id=v_component_id
  ) THEN
    RAISE EXCEPTION 'B2B_CARGA002_CANCEL_ELEMENT_REGRESSION';
  END IF;
END
$fix$;

COMMIT;

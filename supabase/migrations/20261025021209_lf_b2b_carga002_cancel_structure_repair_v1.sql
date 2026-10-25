BEGIN;

DO $repair$
DECLARE
  v_screen_id integer;
  v_input_token_id bigint;
  v_destructive_token_id bigint;
  v_field_id integer;
  v_element_id bigint;
  v_before jsonb;
  v_after jsonb;
BEGIN
  SELECT id INTO v_screen_id
  FROM lf_ops.pantallas
  WHERE codigo='B2B-CARGA-002' AND activa
  LIMIT 1;

  IF v_screen_id IS NULL THEN
    RAISE EXCEPTION 'B2B_CARGA002_SCREEN_NOT_FOUND';
  END IF;

  SELECT component_token_id INTO v_input_token_id
  FROM lf_design.component_tokens
  WHERE component_token_code='input_default'
    AND status='VIGENTE'
  LIMIT 1;

  IF v_input_token_id IS NULL THEN
    RAISE EXCEPTION 'INPUT_DEFAULT_TOKEN_NOT_FOUND';
  END IF;

  SELECT element_id INTO v_element_id
  FROM lf_ops.pantalla_elementos
  WHERE pantalla_id=v_screen_id
    AND element_code='B2B_CARGA002_CANCEL_ACTION'
  LIMIT 1;

  IF v_element_id IS NULL THEN
    RAISE EXCEPTION 'B2B_CARGA002_CANCEL_ACTION_NOT_FOUND';
  END IF;

  SELECT jsonb_build_object(
    'element',to_jsonb(pe),
    'transitions',(
      select jsonb_agg(to_jsonb(t) order by transition_id)
      from lf_ops.estados_transiciones t
      where transition_id in (15,16)
    )
  )
  INTO v_before
  FROM lf_ops.pantalla_elementos pe
  WHERE pe.element_id=v_element_id;

  IF v_before#>>'{element,semantic_binding_status}' <> 'PENDING_SEMANTIC_COMPONENT'
     OR v_before#>>'{element,component_token_id}' IS NOT NULL
  THEN
    RAISE EXCEPTION 'B2B_CARGA002_CANCEL_ACTION_NOT_IN_EXPECTED_PRESTATE:%',
      left(v_before::text,1800);
  END IF;

  IF EXISTS (
    SELECT 1
    FROM lf_ops.estados_transiciones
    WHERE transition_id in (15,16)
      AND (
        action_code<>'CANCEL'
        OR required_permission_code<>'B2B_LOAD_CANCEL'
        OR requires_comment IS NOT TRUE
        OR requires_idempotency_key IS NOT TRUE
        OR audit_required IS NOT TRUE
      )
  ) THEN
    RAISE EXCEPTION 'B2B_CARGA002_CANCEL_TRANSITIONS_PRESTATE_INVALID';
  END IF;

  INSERT INTO lf_design.component_tokens(
    component_token_code,
    design_system_code,
    component_name,
    component_state,
    token_bindings,
    allowed_usage,
    blocked_usage,
    status,
    source_decision_id,
    notes,
    design_system_id
  )
  VALUES(
    'cta_destructive_default',
    'LF_DS_V1',
    'cta_destructive',
    'default',
    jsonb_build_object(
      'text','card_surface',
      'border','error_text',
      'radius','radius_12',
      'background','error_text',
      'typography','text_button_primary'
    ),
    'Acciones destructivas confirmadas y gobernadas que cambian estado o invalidan una entidad.',
    'No usar como CTA principal normal. No usar sin confirmación cuando la regla funcional la exige. No hardcodear color ni semántica por pantalla.',
    'CANDIDATO',
    'SRCR-B2B-CARGA002-CANCEL-STRUCTURE-001',
    'Creado por reparación estructural gobernada para resolver la clase PENDING_SEMANTIC_COMPONENT de acciones destructivas. No implica promoción a VIGENTE.',
    1
  )
  ON CONFLICT (component_token_code) DO UPDATE
  SET updated_at=now()
  RETURNING component_token_id INTO v_destructive_token_id;

  IF v_destructive_token_id IS NULL THEN
    SELECT component_token_id INTO v_destructive_token_id
    FROM lf_design.component_tokens
    WHERE component_token_code='cta_destructive_default';
  END IF;

  INSERT INTO lf_ops.campos(
    codigo,nombre,tipo_dato,descripcion,es_requerido,es_sensible,estado,
    entity_code,source_type,pii_classification,masking_rule,retention_class,
    analytics_allowed,logs_allowed,source_decision_id,updated_at
  )
  VALUES(
    'B2B_FLD_LOAD_CANCEL_COMMENT',
    'Motivo de cancelación',
    'textarea',
    'Motivo/comentario obligatorio requerido para cancelar un UPLOAD_BATCH.',
    true,false,'CANDIDATO',
    'UPLOAD_BATCH','USER','INTERNAL','REDACT_FREE_TEXT','AUDIT',
    false,false,'SRCR-B2B-CARGA002-CANCEL-STRUCTURE-001',now()
  )
  ON CONFLICT (codigo) DO UPDATE
  SET nombre=excluded.nombre,
      tipo_dato=excluded.tipo_dato,
      descripcion=excluded.descripcion,
      es_requerido=true,
      entity_code='UPLOAD_BATCH',
      source_type='USER',
      pii_classification='INTERNAL',
      masking_rule='REDACT_FREE_TEXT',
      retention_class='AUDIT',
      updated_at=now()
  RETURNING id INTO v_field_id;

  IF v_field_id IS NULL THEN
    SELECT id INTO v_field_id
    FROM lf_ops.campos
    WHERE codigo='B2B_FLD_LOAD_CANCEL_COMMENT';
  END IF;

  INSERT INTO lf_ops.campos_pantallas(
    campo_id,pantalla_id,orden_visual,placeholder,label_visible,nota,
    visibility_mode,editable_by,required_override,component_token_code,
    help_text,context_key,component_token_id,updated_at
  )
  VALUES(
    v_field_id,v_screen_id,900,
    'Describe brevemente el motivo de la cancelación',
    'Motivo de cancelación',
    'Campo estructural requerido por CANCEL / requires_comment=true.',
    'VISIBLE',
    jsonb_build_array('B2B_ADMIN_LF','B2B_OPERADOR','B2B_OPERADOR_INTEGRAL'),
    true,
    'input_default',
    'Obligatorio antes de confirmar la cancelación.',
    'CANCEL_CONFIRMATION',
    v_input_token_id,
    now()
  )
  ON CONFLICT (campo_id,pantalla_id,context_key) DO UPDATE
  SET placeholder=excluded.placeholder,
      label_visible=excluded.label_visible,
      nota=excluded.nota,
      visibility_mode='VISIBLE',
      editable_by=excluded.editable_by,
      required_override=true,
      component_token_code='input_default',
      help_text=excluded.help_text,
      component_token_id=v_input_token_id,
      updated_at=now();

  UPDATE lf_ops.pantalla_elementos
  SET component_token_id=v_destructive_token_id,
      semantic_binding_status='RESOLVED_ID',
      source_refs=(
        SELECT jsonb_agg(DISTINCT x)
        FROM jsonb_array_elements(
          coalesce(source_refs,'[]'::jsonb) ||
          jsonb_build_array(
            'field:B2B_FLD_LOAD_CANCEL_COMMENT',
            'field_context:CANCEL_CONFIRMATION',
            'component_token:cta_destructive_default',
            'repair:SRCR-B2B-CARGA002-CANCEL-STRUCTURE-001'
          )
        ) x
      ),
      updated_at=now()
  WHERE element_id=v_element_id;

  SELECT jsonb_build_object(
    'element',to_jsonb(pe),
    'field',(
      select jsonb_build_object(
        'codigo',c.codigo,
        'nombre',c.nombre,
        'tipo_dato',c.tipo_dato,
        'entity_code',c.entity_code,
        'es_requerido',c.es_requerido,
        'label_visible',cp.label_visible,
        'context_key',cp.context_key,
        'required_override',cp.required_override,
        'component_token_code',cp.component_token_code,
        'component_token_id',cp.component_token_id
      )
      from lf_ops.campos c
      join lf_ops.campos_pantallas cp on cp.campo_id=c.id
      where c.codigo='B2B_FLD_LOAD_CANCEL_COMMENT'
        and cp.pantalla_id=v_screen_id
        and cp.context_key='CANCEL_CONFIRMATION'
    ),
    'action_token',(
      select jsonb_build_object(
        'component_token_code',ct.component_token_code,
        'status',ct.status,
        'component_name',ct.component_name
      )
      from lf_design.component_tokens ct
      where ct.component_token_id=pe.component_token_id
    ),
    'transitions',(
      select jsonb_agg(to_jsonb(t) order by transition_id)
      from lf_ops.estados_transiciones t
      where transition_id in (15,16)
    )
  )
  INTO v_after
  FROM lf_ops.pantalla_elementos pe
  WHERE pe.element_id=v_element_id;

  IF v_after#>>'{element,semantic_binding_status}'<>'RESOLVED_ID'
     OR v_after#>>'{action_token,component_token_code}'<>'cta_destructive_default'
     OR v_after#>>'{field,codigo}'<>'B2B_FLD_LOAD_CANCEL_COMMENT'
     OR v_after#>>'{field,entity_code}'<>'UPLOAD_BATCH'
     OR coalesce((v_after#>>'{field,es_requerido}')::boolean,false) IS NOT TRUE
     OR coalesce((v_after#>>'{field,required_override}')::boolean,false) IS NOT TRUE
     OR v_after#>>'{field,context_key}'<>'CANCEL_CONFIRMATION'
     OR v_after#>>'{field,component_token_code}'<>'input_default'
  THEN
    RAISE EXCEPTION 'B2B_CARGA002_CANCEL_REPAIR_READBACK_FAILED:%',
      left(v_after::text,2200);
  END IF;

  IF EXISTS (
    SELECT 1
    FROM lf_ops.estados_transiciones
    WHERE transition_id in (15,16)
      AND (
        action_code<>'CANCEL'
        OR required_permission_code<>'B2B_LOAD_CANCEL'
        OR requires_comment IS NOT TRUE
        OR requires_idempotency_key IS NOT TRUE
        OR audit_required IS NOT TRUE
      )
  ) THEN
    RAISE EXCEPTION 'B2B_CARGA002_CANCEL_CONSTRAINT_PRESERVATION_FAILED';
  END IF;
END
$repair$;

COMMIT;

-- LF B2B-CARGA-002 · reparación textual acotada de una regla CANDIDATO.
-- Producto: tres pasos UI (pantalla 44), sin cuarto paso y sin cambiar el dominio UPLOAD_BATCH.
-- Origen gobernado: Product Director EXEC-PROFILE-GATE2-7D8A0D0F933807A4C8826727
-- Reparador: EXEC-PROFILE-GATE2-100EAF5F03DA504596AC0706 (ACT-0001).
-- No promueve reglas, no modifica permisos, transiciones, valor_config ni producción.
BEGIN;
DO $lf_b2b_wizard_three_steps$
DECLARE
  v_row_count integer;
  v_description text;
  v_config jsonb;
  v_new_description text := $desc$
B2B-CARGA-002 organiza la preparación de cartera en tres pasos UI: seleccionar tipo y formato, subir y preparar datos, y validar con resultado. «Cartera preparada» no constituye un cuarto paso UI ni afirma procesamiento definitivo: el resultado del paso 3 conserva la transición de dominio a B2B_LOAD_VALIDADO y ofrece salida a detalle o historial. El mapeo de columnas es condicional: se omite para formato LF y puede omitirse cuando existe un mapeo gobernado previamente para la empresa. Los estados UI no sustituyen estados de UPLOAD_BATCH; las mutaciones siguen gobernadas por lf_ops.estados_transiciones.
$desc$;
BEGIN
  v_new_description := btrim(v_new_description);
  SELECT count(*) INTO v_row_count
  FROM lf_ops.reglas
  WHERE codigo='B2B-RULE-LOAD-WIZARD-001' AND estado='CANDIDATO';
  IF v_row_count <> 1 THEN
    RAISE EXCEPTION 'LF_B2B_WIZARD_RULE_CURRENTNESS_OR_STATUS_DRIFT: %',v_row_count;
  END IF;

  SELECT descripcion,valor_config INTO STRICT v_description,v_config
  FROM lf_ops.reglas
  WHERE codigo='B2B-RULE-LOAD-WIZARD-001' AND estado='CANDIDATO'
  FOR UPDATE;

  -- Fuente canónica actual: tres UI steps; cuarto paso prohibido y dominio separado.
  IF v_config->>'screen_code' <> 'B2B-CARGA-002'
     OR v_config->>'ui_state_count' <> '3'
     OR jsonb_typeof(v_config->'ui_states') <> 'array'
     OR jsonb_array_length(v_config->'ui_states') <> 3
     OR v_config#>>'{wizard_completion,fourth_ui_step}' <> 'DENY'
     OR v_config#>>'{wizard_completion,domain_state_after_completion}' <> 'B2B_LOAD_VALIDADO'
  THEN
    RAISE EXCEPTION 'LF_B2B_WIZARD_CONFIG_AUTHORITY_DRIFT';
  END IF;

  IF v_description <> v_new_description THEN
    IF md5(v_description) <> '289f5579f9570815fd3d7580f5743dee' THEN
      RAISE EXCEPTION 'LF_B2B_WIZARD_DESCRIPTION_PREIMAGE_DRIFT';
    END IF;

    UPDATE lf_ops.reglas
       SET descripcion=v_new_description,
           updated_at=now()
     WHERE codigo='B2B-RULE-LOAD-WIZARD-001'
       AND estado='CANDIDATO'
       AND md5(descripcion)='289f5579f9570815fd3d7580f5743dee';
    GET DIAGNOSTICS v_row_count = ROW_COUNT;
    IF v_row_count <> 1 THEN
      RAISE EXCEPTION 'LF_B2B_WIZARD_MUTATION_CAS_FAILED';
    END IF;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM lf_ops.reglas
    WHERE codigo='B2B-RULE-LOAD-WIZARD-001'
      AND estado='CANDIDATO'
      AND descripcion=v_new_description
      AND valor_config=v_config
  ) THEN
    RAISE EXCEPTION 'LF_B2B_WIZARD_POST_READBACK_FAILED';
  END IF;
END $lf_b2b_wizard_three_steps$;
COMMIT;

-- B2B-AUTH-001 (pantalla 51) composition v1, read from current mockups 46/47/48 (v0.5-r3).
-- Requires 20261120170000_lf_design_screen_composition_v1.
-- Not included, pending owner decision:
--   * b2b_auth_form_max_width spacing token (MAIN region max width stays NULL;
--     b2b_auth_login_layout.form_max_width_token_status remains PENDING_LF_DS_SCALE_TOKEN);
--   * CTA label: element 291 says "Acceder", mockups show "Iniciar sesión".
-- Inventory gaps observed in the mockups but without an element row (not invented here):
--   * header label "Backoffice Empresa"; * subtitle "Ingresa tus credenciales para continuar".
BEGIN;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM lf_design.component_tokens
                 WHERE component_token_id = 39 AND component_token_code = 'b2b_auth_login_layout') THEN
    RAISE EXCEPTION 'B2B_AUTH001_COMPOSITION_LAYOUT_TOKEN_MISSING';
  END IF;
  IF (SELECT count(*) FROM lf_ops.pantalla_elementos WHERE pantalla_id = 51
        AND element_id BETWEEN 280 AND 296) <> 17 THEN
    RAISE EXCEPTION 'B2B_AUTH001_COMPOSITION_ELEMENT_INVENTORY_DRIFT';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM lf_ops.pantalla_variantes WHERE variant_id = 49 AND pantalla_id = 51
                 AND responsive_token_name = 'viewport_mobile') THEN
    RAISE EXCEPTION 'B2B_AUTH001_COMPOSITION_MOBILE_VARIANT_MISSING';
  END IF;
END
$$;

-- Regions of b2b_auth_login_layout (component token 39).
INSERT INTO lf_design.layout_regions
  (layout_component_token_id, region_code, region_order, placement_by_breakpoint,
   max_width_token_id, gap_token_id, status, source_refs, source_decision_id, notes)
VALUES
  (39, 'HEADER', 1,
   '{"viewport_desktop":"TOP","viewport_tablet":"TOP","viewport_mobile":"TOP"}',
   NULL, NULL, 'CANDIDATO_VISUAL',
   '["artifact_ids:46,47,48","visual_decision_id:32"]', 'DEC-B2B-AUTH-001-VISUAL-APPROVAL-20260815',
   'Logo LF a la izquierda y etiqueta Backoffice Empresa a la derecha; sin navegación.'),
  (39, 'DECORATIVE', 2,
   '{"viewport_desktop":"LEFT_COLUMN","viewport_tablet":"BACKGROUND","viewport_mobile":"HIDDEN"}',
   NULL, NULL, 'CANDIDATO_VISUAL',
   '["artifact_ids:46,47,48","visual_decision_id:32","visual_decision_id:35"]', 'VD_B2B_AUTH_MOCKUP_FRAME_20260820',
   'Marca de agua del escudo: columna izquierda en desktop, fondo en tablet, oculta en móvil (artefacto 48 watermark=NONE_MOBILE).'),
  (39, 'MAIN', 3,
   '{"viewport_desktop":"RIGHT_COLUMN","viewport_tablet":"CENTER","viewport_mobile":"STACK"}',
   NULL,
   (SELECT spacing_token_id FROM lf_design.spacing_tokens WHERE token_name = 'space_24'),
   'CANDIDATO_VISUAL',
   '["artifact_ids:46,47,48","visual_decision_id:32","rule_id:580"]', 'DEC-B2B-AUTH-001-VISUAL-APPROVAL-20260815',
   'Bloque central del formulario. max_width_token_id pendiente: no existe token de escala (PENDING_LF_DS_SCALE_TOKEN); no fijar por analogía.'),
  (39, 'FOOTER', 4,
   '{"viewport_desktop":"BOTTOM","viewport_tablet":"BOTTOM","viewport_mobile":"BOTTOM"}',
   NULL,
   (SELECT spacing_token_id FROM lf_design.spacing_tokens WHERE token_name = 'space_32'),
   'CANDIDATO_VISUAL',
   '["artifact_ids:46,47,48","rule_id:469"]', 'DEC-B2B-AUTH-001-VISUAL-APPROVAL-20260815',
   'Enlaces legales y de contacto separados del contenido por una línea divisoria.');

-- Base composition of the 17 elements (variant_id NULL = all breakpoints).
WITH r AS (
  SELECT region_code, layout_region_id FROM lf_design.layout_regions WHERE layout_component_token_id = 39
), s AS (
  SELECT token_name, spacing_token_id FROM lf_design.spacing_tokens
)
INSERT INTO lf_ops.pantalla_elemento_layouts
  (element_id, variant_id, composition_role, layout_region_id, order_in_region,
   alignment, width_mode, width_token_id, spacing_before_token_id, visible, status, source_refs, notes)
SELECT v.element_id, NULL, v.role,
       (SELECT layout_region_id FROM r WHERE r.region_code = v.region),
       v.ord, v.align, v.wmode, NULL,
       (SELECT spacing_token_id FROM s WHERE s.token_name = v.space_before),
       v.vis, 'CANDIDATO_VISUAL', v.refs::jsonb, v.notes
FROM (VALUES
  (280, 'CONTAINER',  NULL,         NULL, 'START',   'FILL_REGION', NULL,       true,  '["component:b2b_auth_mockup_frame","visual_decision_id:35"]', 'Marco de página: canvas por variante.'),
  (281, 'CONTAINER',  NULL,         NULL, 'START',   'FILL_REGION', NULL,       true,  '["component:b2b_auth_login_layout","visual_decision_id:32"]', 'Layout que contiene las regiones.'),
  (282, 'PLACED',     'HEADER',     1,    'START',   'CONTENT',     NULL,       true,  '["artifact_ids:46,47,48","visual_decision_id:21"]', 'Logo LF en 2 líneas.'),
  (283, 'PLACED',     'DECORATIVE', 1,    'START',   'FILL_REGION', NULL,       true,  '["artifact_ids:46,47","visual_decision_id:32"]', 'Marca de agua del escudo.'),
  (284, 'PLACED',     'MAIN',       1,    'START',   'FILL_REGION', NULL,       true,  '["artifact_ids:46,47,48"]', 'Título Iniciar sesión.'),
  (285, 'PLACED',     'MAIN',       2,    'STRETCH', 'FILL_REGION', NULL,       true,  '["artifact_ids:46,47,48","field_id:298"]', 'Correo electrónico (orden visual 1).'),
  (286, 'PLACED',     'MAIN',       3,    'STRETCH', 'FILL_REGION', NULL,       true,  '["artifact_ids:46,47,48","field_id:296"]', 'Contraseña (orden visual 2).'),
  (287, 'EMBEDDED',   NULL,         NULL, 'START',   'CONTENT',     NULL,       true,  '["component:auth_credential_input_icons","visual_decision_id:40"]', 'Iconos dentro de los inputs 285 y 286.'),
  (288, 'EMBEDDED',   NULL,         NULL, 'END',     'CONTENT',     NULL,       true,  '["component:auth_credential_input_icons","rule_id:428"]', 'Mostrar u ocultar, dentro del input 286.'),
  (289, 'NON_VISUAL', NULL,         NULL, 'START',   'CONTENT',     NULL,       false, '["rule_id:580"]', 'Controlador del formulario (FULL/PROGRESSIVE).'),
  (290, 'PLACED',     'MAIN',       4,    'END',     'CONTENT',     NULL,       true,  '["artifact_ids:46,47,48","visual_decision_id:19"]', 'Recuperar contraseña, junto al campo Contraseña.'),
  (291, 'PLACED',     'MAIN',       5,    'STRETCH', 'FILL_REGION', 'space_24', true,  '["artifact_ids:46,47,48","visual_decision_id:19"]', 'CTA primario, separado de la recuperación con space_24.'),
  (292, 'NON_VISUAL', NULL,         NULL, 'START',   'CONTENT',     NULL,       false, '["rule_id:429","security_policy_id:17"]', 'Control anti-bot invisible.'),
  (293, 'EMBEDDED',   NULL,         NULL, 'START',   'FILL_REGION', NULL,       true,  '["component:form_error_inline"]', 'Error inline bajo el input correspondiente; no aparece en las maquetas.'),
  (294, 'PLACED',     'FOOTER',     1,    'END',     'CONTENT',     NULL,       true,  '["artifact_ids:46,47,48","rule_id:469"]', 'Términos y condiciones.'),
  (295, 'PLACED',     'FOOTER',     2,    'END',     'CONTENT',     NULL,       true,  '["artifact_ids:46,47,48","rule_id:469"]', 'Política de privacidad.'),
  (296, 'PLACED',     'FOOTER',     3,    'END',     'CONTENT',     NULL,       true,  '["artifact_ids:46,47,48","rule_id:469"]', 'Contáctanos.')
) AS v(element_id, role, region, ord, align, wmode, space_before, vis, refs, notes);

-- Mobile overrides (variant 49): watermark hidden, footer links centered.
INSERT INTO lf_ops.pantalla_elemento_layouts
  (element_id, variant_id, composition_role, layout_region_id, order_in_region,
   alignment, width_mode, visible, status, source_refs, notes)
SELECT b.element_id, 49, b.composition_role, b.layout_region_id, b.order_in_region,
       CASE WHEN b.element_id IN (294, 295, 296) THEN 'CENTER' ELSE b.alignment END,
       b.width_mode,
       CASE WHEN b.element_id = 283 THEN false ELSE b.visible END,
       'CANDIDATO_VISUAL', '["artifact_id:48"]',
       CASE WHEN b.element_id = 283 THEN 'Sin marca de agua en móvil (watermark=NONE_MOBILE).'
            ELSE 'Enlaces del pie centrados en móvil.' END
FROM lf_ops.pantalla_elemento_layouts b
WHERE b.variant_id IS NULL AND b.element_id IN (283, 294, 295, 296);

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM lf_ops.v_pantalla_composicion_gaps WHERE pantalla_id = 51) THEN
    RAISE EXCEPTION 'B2B_AUTH001_COMPOSITION_INCOMPLETE';
  END IF;
END
$$;

COMMIT;

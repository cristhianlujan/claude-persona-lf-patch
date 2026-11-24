-- Ingreso simple + datos del pedido ítem 11 (orden 8). Sin permisos nuevos.
BEGIN;
CREATE OR REPLACE FUNCTION saly.creative_intake_semantic_gate_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'saly', 'extensions', 'pg_temp'
AS $function$
BEGIN
  IF NEW.request_kind IS DISTINCT FROM 'APP_SCREEN_SINGLE' THEN RETURN NEW; END IF;
  IF NEW.status='BORRADOR' THEN RETURN NEW; END IF;
  IF nullif(btrim(NEW.scope_json->>'literal_request'),'') IS NULL
  THEN RAISE EXCEPTION 'CREATIVE_INTAKE_ORIGINAL_VISUAL_LITERAL_MISSING'; END IF;
  RETURN NEW;
END $function$;
UPDATE saly.creative_orders
SET scope_json = scope_json || jsonb_build_object(
  'literal_request','Pantalla Solicitar adelanto: Volver, título y ayuda; monto disponible S/ 580; ¿Cuánto necesitas? con S/ 300, S/ 450 y S/ 570 y entrada manual; resumen con monto solicitado, cargos S/ 12.00, monto a recibir S/ 558.00 y fecha de descuento 30 de noviembre; botón Continuar.',
  'literal_origin','USER_MESSAGE',
  'source_message_ref','OWNER_CHAT_CLAUDE_2026-11-24T00:31-05:00',
  'interpretation','Pantalla Solicitar adelanto de SALY: el colaborador elige cuánto necesita, entiende cuánto recibirá y las condiciones antes de continuar',
  'content_prompt','Pantalla Solicitar adelanto SALY en iPhone 16 Pro. Arriba: botón Volver, título Solicitar adelanto y acceso a ayuda. Monto disponible S/ 580. ¿Cuánto necesitas?: tres montos para elegir S/ 300, S/ 450 y S/ 570 (S/ 570 seleccionado) y entrada manual. Resumen: monto solicitado S/ 570.00, cargos S/ 12.00, monto a recibir S/ 558.00, fecha de descuento 30 de noviembre. Botón Continuar.',
  'compiled_prompt','Pantalla Solicitar adelanto SALY en iPhone 16 Pro. Arriba: botón Volver, título Solicitar adelanto y acceso a ayuda. Monto disponible S/ 580. ¿Cuánto necesitas?: tres montos para elegir S/ 300, S/ 450 y S/ 570 (S/ 570 seleccionado) y entrada manual. Resumen: monto solicitado S/ 570.00, cargos S/ 12.00, monto a recibir S/ 558.00, fecha de descuento 30 de noviembre. Botón Continuar.',
  'prompt_source','content_prompt',
  'previous_compiled_prompt_superseded', COALESCE(scope_json->'compiled_prompt','null'::jsonb),
  'presentation','mockup frontal iPhone 16 Pro centrado, fondo de estudio gris muy claro, luz suave, sin manos ni perspectiva',
  'creative_freedom','fondo, composición y jerarquía'
)
WHERE id = 8;
COMMIT;

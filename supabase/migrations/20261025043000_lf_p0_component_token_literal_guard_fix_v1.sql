-- P0: Correct HEX detection without silently rewriting preserved, non-authoritative evidence.
BEGIN;
CREATE OR REPLACE FUNCTION lf_design.guard_component_token_bindings_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'lf_design'
AS $function$
DECLARE
  v_checked_bindings jsonb;
  v_key text;
  v_value jsonb;
  v_sval text;
  v_color_status text;
  v_color_keys constant text[] := ARRAY[
    'background','border','text','body_text','title_text',
    'error_text','success_text','error_background',
    'border_focus','border_default','fill','stroke',
    'hero_title_color','hero_subtitle_color','icon_color'
  ];
BEGIN
  IF NEW.token_bindings IS NULL OR jsonb_typeof(NEW.token_bindings)<>'object' THEN
    RAISE EXCEPTION
      USING ERRCODE='23514',
            MESSAGE='DESIGN_TOKEN_BINDINGS_INVALID_SHAPE',
            DETAIL='component_tokens.token_bindings must be a JSON object.';
  END IF;


  -- Only unchanged legacy evidence may retain literal visual observations.
  -- New values or modifications to either evidence field are still rejected.
  v_checked_bindings := NEW.token_bindings;
  IF TG_OP='UPDATE' THEN
    IF OLD.token_bindings ? 'measured_fill'
       AND NEW.token_bindings->'measured_fill' IS NOT DISTINCT FROM OLD.token_bindings->'measured_fill' THEN
      v_checked_bindings := v_checked_bindings - 'measured_fill';
    END IF;
    IF OLD.token_bindings ? 'expected_visible_color_range'
       AND NEW.token_bindings->'expected_visible_color_range' IS NOT DISTINCT FROM OLD.token_bindings->'expected_visible_color_range' THEN
      v_checked_bindings := v_checked_bindings - 'expected_visible_color_range';
    END IF;
  END IF;

  IF v_checked_bindings::text ~* '(#[0-9a-f]{3,8}([^0-9a-f]|$)|rgba?\s*\(|hsla?\s*\()' THEN
    RAISE EXCEPTION
      USING ERRCODE='23514',
            MESSAGE='DESIGN_TOKEN_LITERAL_COLOR_FORBIDDEN',
            DETAIL='Use registered token names in token_bindings; literal HEX/RGB/HSL colors are forbidden.';
  END IF;

  FOR v_key,v_value IN
    SELECT key,value
    FROM jsonb_each(NEW.token_bindings)
  LOOP
    IF v_key = ANY(v_color_keys)
       AND jsonb_typeof(v_value)='string'
    THEN
      v_sval:=trim(both '"' from v_value::text);

      SELECT status
        INTO v_color_status
      FROM lf_design.color_tokens
      WHERE token_name=v_sval
      LIMIT 1;

      IF v_color_status IS NULL THEN
        RAISE EXCEPTION
          USING ERRCODE='23514',
                MESSAGE='DESIGN_COLOR_TOKEN_REFERENCE_NOT_FOUND',
                DETAIL=format(
                  'component=%s key=%s value=%s is not a registered lf_design.color_tokens.token_name',
                  NEW.component_token_code,v_key,v_sval
                );
      END IF;

      IF v_color_status='DEPRECADO' THEN
        RAISE EXCEPTION
          USING ERRCODE='23514',
                MESSAGE='DESIGN_COLOR_TOKEN_REFERENCE_DEPRECATED',
                DETAIL=format(
                  'component=%s key=%s token=%s is DEPRECADO',
                  NEW.component_token_code,v_key,v_sval
                );
      END IF;

      IF NEW.status='VIGENTE' AND v_color_status<>'VIGENTE' THEN
        RAISE EXCEPTION
          USING ERRCODE='23514',
                MESSAGE='DESIGN_VIGENTE_COMPONENT_REQUIRES_VIGENTE_COLOR_TOKEN',
                DETAIL=format(
                  'component=%s key=%s token=%s status=%s',
                  NEW.component_token_code,v_key,v_sval,v_color_status
                );
      END IF;
    END IF;
  END LOOP;

  RETURN NEW;
END
$function$;
COMMIT;

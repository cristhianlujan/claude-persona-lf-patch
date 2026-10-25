BEGIN;

CREATE OR REPLACE FUNCTION lf_design.guard_component_token_bindings_v1()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog','lf_design'
AS $function$
DECLARE
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

  IF NEW.token_bindings::text ~* '(#[0-9a-f]{3,8}\b|rgba?\s*\(|hsla?\s*\()' THEN
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

DROP TRIGGER IF EXISTS trg_guard_component_token_bindings_v1
ON lf_design.component_tokens;

CREATE TRIGGER trg_guard_component_token_bindings_v1
BEFORE INSERT OR UPDATE OF token_bindings,status
ON lf_design.component_tokens
FOR EACH ROW
EXECUTE FUNCTION lf_design.guard_component_token_bindings_v1();

COMMENT ON FUNCTION lf_design.guard_component_token_bindings_v1() IS
'Fail-closed guard for component token bindings: forbids literal HEX/RGB/HSL colors; validates known color-binding keys against registered color token names; VIGENTE components require VIGENTE color tokens. Historical rows are not bulk-revalidated until updated.';

DO $postcheck$
DECLARE
  v_trigger_exists boolean;
  v_failed boolean;
BEGIN
  SELECT exists(
    SELECT 1
    FROM pg_trigger tg
    JOIN pg_class cl ON cl.oid=tg.tgrelid
    JOIN pg_namespace ns ON ns.oid=cl.relnamespace
    WHERE ns.nspname='lf_design'
      AND cl.relname='component_tokens'
      AND tg.tgname='trg_guard_component_token_bindings_v1'
      AND NOT tg.tgisinternal
  ) INTO v_trigger_exists;

  IF NOT v_trigger_exists THEN
    RAISE EXCEPTION 'DESIGN_TOKEN_BINDING_GUARD_TRIGGER_MISSING';
  END IF;

  BEGIN
    INSERT INTO lf_design.component_tokens(
      component_token_code,design_system_code,component_name,component_state,
      token_bindings,allowed_usage,blocked_usage,status,
      source_decision_id,notes,design_system_id,component_token_id
    )
    VALUES(
      '__GUARD_TEST_LITERAL_HEX__','LF_DS_V1','guard_test','default',
      jsonb_build_object('background','#991B1B'),
      'guard test','guard test','CANDIDATO',
      '__GUARD_TEST__','temporary guard test',1,
      (SELECT coalesce(max(component_token_id),0)+1000000 FROM lf_design.component_tokens)
    );
  EXCEPTION WHEN check_violation THEN
    v_failed:=true;
  END;

  IF coalesce(v_failed,false) IS NOT TRUE THEN
    RAISE EXCEPTION 'DESIGN_TOKEN_LITERAL_HEX_FALSE_PASS';
  END IF;

  v_failed:=false;

  BEGIN
    INSERT INTO lf_design.component_tokens(
      component_token_code,design_system_code,component_name,component_state,
      token_bindings,allowed_usage,blocked_usage,status,
      source_decision_id,notes,design_system_id,component_token_id
    )
    VALUES(
      '__GUARD_TEST_UNKNOWN_TOKEN__','LF_DS_V1','guard_test','default',
      jsonb_build_object('background','__TOKEN_DOES_NOT_EXIST__'),
      'guard test','guard test','CANDIDATO',
      '__GUARD_TEST__','temporary guard test',1,
      (SELECT coalesce(max(component_token_id),0)+1000001 FROM lf_design.component_tokens)
    );
  EXCEPTION WHEN check_violation THEN
    v_failed:=true;
  END;

  IF coalesce(v_failed,false) IS NOT TRUE THEN
    RAISE EXCEPTION 'DESIGN_UNKNOWN_COLOR_TOKEN_FALSE_PASS';
  END IF;

  v_failed:=false;

  BEGIN
    INSERT INTO lf_design.component_tokens(
      component_token_code,design_system_code,component_name,component_state,
      token_bindings,allowed_usage,blocked_usage,status,
      source_decision_id,notes,design_system_id,component_token_id
    )
    VALUES(
      '__GUARD_TEST_VALID__','LF_DS_V1','guard_test','default',
      jsonb_build_object(
        'background','error_bg',
        'border','error_text',
        'text','error_text',
        'radius','radius_12',
        'typography','text_button_primary'
      ),
      'guard test','guard test','VIGENTE',
      '__GUARD_TEST__','temporary guard test',1,
      (SELECT coalesce(max(component_token_id),0)+1000002 FROM lf_design.component_tokens)
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'DESIGN_VALID_TOKEN_BINDING_FALSE_BLOCK:%',SQLERRM;
  END;

  DELETE FROM lf_design.component_tokens
  WHERE component_token_code='__GUARD_TEST_VALID__';

  IF NOT EXISTS (
    SELECT 1
    FROM lf_design.component_tokens
    WHERE component_token_code='cta_destructive_default'
      AND status='VIGENTE'
      AND token_bindings->>'background'='error_bg'
      AND token_bindings->>'border'='error_text'
      AND token_bindings->>'text'='error_text'
  ) THEN
    RAISE EXCEPTION 'CTA_DESTRUCTIVE_CURRENT_BINDING_REGRESSION';
  END IF;
END
$postcheck$;

COMMIT;

-- LF-AUD-UI-02: version-aware IG open-work path, shared native profile bridge.
-- Source preimages were read from the live PostgreSQL catalog (18 Nov 2026).
-- No historical migration is edited; drift aborts rather than overwriting changes.
BEGIN;

-- UI02_HELPERS_BEGIN
CREATE OR REPLACE FUNCTION public.lf_profile_ig_open_work_resolution_for_output_v2(
  p_profile_code text, p_profile_output jsonb
) RETURNS jsonb LANGUAGE sql IMMUTABLE
SET search_path TO 'pg_catalog','public'
AS $function$
  SELECT CASE
    WHEN p_profile_code='PERFIL-UI-ARCHITECT'
      AND p_profile_output->>'output_contract_version'='UI_PRODUCTION_SPEC_V6'
    THEN CASE
      WHEN p_profile_output#>>'{governance_envelope,schema}'='LF_UI_GOVERNANCE_ENVELOPE_V1'
       AND p_profile_output#>>'{governance_envelope,render_policy}'='NON_RENDER'
      THEN p_profile_output#>'{governance_envelope,context,ig_open_work_resolution}'
      ELSE NULL::jsonb
    END
    -- Explicit backward-compatible branch: older UI output and all other
    -- native profiles still transport IG resolutions in traceability.
    ELSE p_profile_output#>'{traceability,ig_open_work_resolution}'
  END
$function$;

CREATE OR REPLACE FUNCTION public.lf_profile_ig_open_work_output_field_v2(
  p_profile_code text, p_profile_output jsonb DEFAULT NULL
) RETURNS text LANGUAGE sql IMMUTABLE
SET search_path TO 'pg_catalog','public'
AS $function$
  SELECT CASE
    WHEN p_profile_code='PERFIL-UI-ARCHITECT'
       AND (p_profile_output IS NULL OR
            p_profile_output->>'output_contract_version'='UI_PRODUCTION_SPEC_V6')
    THEN 'governance_envelope.context.ig_open_work_resolution'
    ELSE 'traceability.ig_open_work_resolution'
  END
$function$;
-- UI02_HELPERS_END

REVOKE ALL ON FUNCTION public.lf_profile_ig_open_work_resolution_for_output_v2(text,jsonb)
  FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.lf_profile_ig_open_work_output_field_v2(text,jsonb)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lf_profile_ig_open_work_resolution_for_output_v2(text,jsonb)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.lf_profile_ig_open_work_output_field_v2(text,jsonb)
  TO service_role;

DO $patch$
DECLARE d text; before text;
BEGIN
  d:=pg_get_functiondef('public.lf_profile_native_bridge_prepare_v1(text,text,text,text)'::regprocedure);
  IF md5(d)<>'073fbfea36ac02553f5c7338905b23a1' THEN
    RAISE EXCEPTION 'LF_AUD_UI02_PREPARE_PREIMAGE_DRIFT:%',md5(d);
  END IF;
  before:=d;
  d:=replace(d,
    $old$'output_field','traceability.ig_open_work_resolution'$old$,
    $new$'output_field',public.lf_profile_ig_open_work_output_field_v2(e.target_code,NULL::jsonb)$new$);
  IF d=before OR position($old$'output_field','traceability.ig_open_work_resolution'$old$ in d)>0
  THEN RAISE EXCEPTION 'LF_AUD_UI02_PREPARE_PATCH_MISSING'; END IF;
  EXECUTE d;

  d:=pg_get_functiondef('public.lf_profile_native_bridge_record_output_v1(text,jsonb,jsonb,text,text,text)'::regprocedure);
  IF md5(d)<>'6f138a2cb789f6fbf71d73e855d54c85' THEN
    RAISE EXCEPTION 'LF_AUD_UI02_STEP60_PREIMAGE_DRIFT:%',md5(d);
  END IF;
  before:=d;
  d:=replace(d,
    $old$p_profile_output#>'{traceability,ig_open_work_resolution}'$old$,
    $new$public.lf_profile_ig_open_work_resolution_for_output_v2(e.target_code,p_profile_output)$new$);
  d:=replace(d,
    $old$'required_output_field','traceability.ig_open_work_resolution'$old$,
    $new$'required_output_field',public.lf_profile_ig_open_work_output_field_v2(e.target_code,p_profile_output)$new$);
  IF d=before
    OR position($old$p_profile_output#>'{traceability,ig_open_work_resolution}'$old$ in d)>0
    OR position($old$'required_output_field','traceability.ig_open_work_resolution'$old$ in d)>0
  THEN RAISE EXCEPTION 'LF_AUD_UI02_STEP60_PATCH_INCOMPLETE'; END IF;
  EXECUTE d;

  d:=pg_get_functiondef('public.lf_profile_native_bridge_record_report_v1(text,text,text)'::regprocedure);
  IF md5(d)<>'d1e007a427b5a6003b996733970cf80d' THEN
    RAISE EXCEPTION 'LF_AUD_UI02_STEP80_PREIMAGE_DRIFT:%',md5(d);
  END IF;
  before:=d;
  d:=replace(d,
    $old$v_profile_output#>'{traceability,ig_open_work_resolution}'$old$,
    $new$public.lf_profile_ig_open_work_resolution_for_output_v2(e.target_code,v_profile_output)$new$);
  IF d=before OR position($old$v_profile_output#>'{traceability,ig_open_work_resolution}'$old$ in d)>0
  THEN RAISE EXCEPTION 'LF_AUD_UI02_STEP80_PATCH_MISSING'; END IF;
  EXECUTE d;
END
$patch$;

DO $verify$
BEGIN
  IF position('lf_profile_ig_open_work_output_field_v2' in
     pg_get_functiondef('public.lf_profile_native_bridge_prepare_v1(text,text,text,text)'::regprocedure))=0
   OR position('lf_profile_ig_open_work_resolution_for_output_v2' in
     pg_get_functiondef('public.lf_profile_native_bridge_record_output_v1(text,jsonb,jsonb,text,text,text)'::regprocedure))=0
   OR position('lf_profile_ig_open_work_resolution_for_output_v2' in
     pg_get_functiondef('public.lf_profile_native_bridge_record_report_v1(text,text,text)'::regprocedure))=0
  THEN RAISE EXCEPTION 'LF_AUD_UI02_BRIDGE_READBACK_FAILED'; END IF;
END
$verify$;
COMMIT;

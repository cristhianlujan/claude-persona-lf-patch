-- E20: preserve governance fingerprint and read-only safety; explicit promotion intent is
-- accepted only in a validated Router/Gate2 GOVERNED_REPAIR handoff.
-- Existing historical handoffs with promotion_allowed=false remain valid (no rewriting).
BEGIN;
DO $e20$
DECLARE d text; d0 text;
BEGIN
  d:=pg_get_functiondef('public.lf_router_profile_execution_handoff_v1(jsonb,jsonb,text,text,jsonb)'::regprocedure);
  IF md5(d)<>'3e724020ce7bbdaa42b9debba0b05bca' THEN
    RAISE EXCEPTION 'E20_SOURCE_STATE_DRIFT:handoff_builder';
  END IF;
  d0:=d;
  d:=replace(d,
   $old$  v_repair_write_allowed boolean:=false;$old$,
   $new$  v_repair_write_allowed boolean:=false;
  v_promotion_allowed boolean:=false;$new$);
  d:=replace(d,
   $old$  SELECT a.metadata->>'profile_slug'$old$,
   $new$  -- Only an explicit affirmative owner instruction in the exact Router request.
  -- Fail closed for 'no/sin ... promocionar'; never trust caller-supplied flag.
  v_promotion_allowed:=v_repair_write_allowed
    AND coalesce(p_request->>'literal_request','') ~*
      '(^|[^[:alpha:]])(promociona|promocionar|promoci[oó]n|promueve|promover)([^[:alpha:]]|$)'
    AND coalesce(p_request->>'literal_request','') !~*
      '(^|[^[:alpha:]])(no|sin)([[:space:]]+[[:alpha:]]+){0,3}[[:space:]]+(promociona|promocionar|promoci[oó]n|promueve|promover)';
  SELECT a.metadata->>'profile_slug'$new$);
  d:=replace(d,
   $old$      'promotion_allowed',false,$old$,
   $new$      'promotion_allowed',v_promotion_allowed,$new$);
  IF d=d0 OR position('v_promotion_allowed:=v_repair_write_allowed' IN d)=0 OR
     position($x$'promotion_allowed',false$x$ IN d)>0 THEN
    RAISE EXCEPTION 'E20_BUILDER_PATCH_NOT_APPLIED';
  END IF;
  EXECUTE d;

  d:=pg_get_functiondef('public.lf_router_profile_execution_handoff_validate_v1(jsonb,text,text)'::regprocedure);
  IF md5(d)<>'cb6a8deef3b15d29f05f02e59fe8ed7e' THEN
    RAISE EXCEPTION 'E20_SOURCE_STATE_DRIFT:handoff_validator';
  END IF;
  d0:=d;
  d:=replace(d,
   $old$  v_repair_expected boolean:=false;$old$,
   $new$  v_repair_expected boolean:=false;
  v_promotion_explicit boolean:=false;$new$);
  d:=replace(d,
   $old$  v_repair:=p_handoff->'repair_execution_authority';$old$,
   $new$  v_repair:=p_handoff->'repair_execution_authority';
  v_promotion_explicit:=v_repair_expected
    AND coalesce(p_handoff->>'literal_request','') ~*
      '(^|[^[:alpha:]])(promociona|promocionar|promoci[oó]n|promueve|promover)([^[:alpha:]]|$)'
    AND coalesce(p_handoff->>'literal_request','') !~*
      '(^|[^[:alpha:]])(no|sin)([[:space:]]+[[:alpha:]]+){0,3}[[:space:]]+(promociona|promocionar|promoci[oó]n|promueve|promover)';$new$);
  d:=replace(d,
   $old$       OR coalesce((v_repair->>'promotion_allowed')::boolean,true) IS NOT FALSE$old$,
   $new$       OR (coalesce((v_repair->>'promotion_allowed')::boolean,false)
           AND NOT v_promotion_explicit)$new$);
  d:=replace(d,
   $old$    'governed_repair_write_allowed',v_repair_expected,$old$,
   $new$    'governed_repair_write_allowed',v_repair_expected,
    'promotion_allowed',case when v_repair_expected
      then coalesce((v_repair->>'promotion_allowed')::boolean,false)
      else false end,$new$);
  IF d=d0 OR position('v_promotion_explicit:=v_repair_expected' IN d)=0 OR
     position($x$'promotion_allowed',case when v_repair_expected$x$ IN d)=0 THEN
    RAISE EXCEPTION 'E20_VALIDATOR_PATCH_NOT_APPLIED';
  END IF;
  EXECUTE d;

  d:=pg_get_functiondef('public.lf_profile_execution_begin_from_handoff_v1(jsonb,text,text,text,text,text,text,jsonb)'::regprocedure);
  IF md5(d)<>'fa059196b0e3ad93f17e512f9a7c70a4' THEN
    RAISE EXCEPTION 'E20_SOURCE_STATE_DRIFT:profile_begin';
  END IF;
  d0:=d;
  d:=replace(d,
   $old$'no_promotion',false,$old$,
   $new$'no_promotion',false,
        'promotion_allowed',coalesce((v_valid->>'promotion_allowed')::boolean,false),$new$);
  d:=replace(d,
   $old$    'governed_repair_write',v_repair_write,
    'repair_execution_authority',$old$,
   $new$    'governed_repair_write',v_repair_write,
    'promotion_allowed',coalesce((v_valid->>'promotion_allowed')::boolean,false),
    'repair_execution_authority',$new$);
  IF d=d0 OR position($x$'promotion_allowed',coalesce((v_valid->>'promotion_allowed')::boolean,false)$x$ IN d)=0
  THEN RAISE EXCEPTION 'E20_BEGIN_PATCH_NOT_APPLIED'; END IF;
  EXECUTE d;
END $e20$;
COMMIT;

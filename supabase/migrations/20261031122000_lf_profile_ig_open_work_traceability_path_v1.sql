BEGIN;

DO $patch$
DECLARE d text; before text;
BEGIN
  SELECT pg_get_functiondef('public.lf_profile_native_bridge_prepare_v1(text,text,text,text)'::regprocedure) INTO d;
  IF md5(d)<>'5afa13393316a781dbe6a6cd9700ba3f' THEN
    RAISE EXCEPTION 'BLOCK_PREPARE_SOURCE_DRIFT:%',md5(d);
  END IF;
  before:=d;
  d:=replace(
    d,
    $a$'output_field','ig_open_work_resolution'$a$,
    $b$'output_field','traceability.ig_open_work_resolution'$b$
  );
  IF d=before THEN RAISE EXCEPTION 'BLOCK_PREPARE_IG_PATH_PATCH_NOT_APPLIED'; END IF;
  EXECUTE d;

  SELECT pg_get_functiondef('public.lf_profile_native_bridge_record_output_v1(text,jsonb,jsonb,text,text,text)'::regprocedure) INTO d;
  IF md5(d)<>'6a928986bece7da89a8c896b08d5de7e' THEN
    RAISE EXCEPTION 'BLOCK_RECORD_OUTPUT_SOURCE_DRIFT:%',md5(d);
  END IF;
  before:=d;
  d:=replace(
    d,
    $a$p_profile_output->'ig_open_work_resolution'$a$,
    $b$p_profile_output#>'{traceability,ig_open_work_resolution}'$b$
  );
  d:=replace(
    d,
    $a$'required_output_field','ig_open_work_resolution'$a$,
    $b$'required_output_field','traceability.ig_open_work_resolution'$b$
  );
  IF d=before THEN RAISE EXCEPTION 'BLOCK_RECORD_OUTPUT_IG_PATH_PATCH_NOT_APPLIED'; END IF;
  EXECUTE d;
END
$patch$;

DO $verify$
DECLARE p text; r text;
BEGIN
  SELECT pg_get_functiondef('public.lf_profile_native_bridge_prepare_v1(text,text,text,text)'::regprocedure) INTO p;
  SELECT pg_get_functiondef('public.lf_profile_native_bridge_record_output_v1(text,jsonb,jsonb,text,text,text)'::regprocedure) INTO r;
  IF position('traceability.ig_open_work_resolution' in p)=0
     OR position('traceability,ig_open_work_resolution' in r)=0
     OR position('required_output_field' in r)=0
  THEN
    RAISE EXCEPTION 'IG_OPEN_WORK_TRACEABILITY_PATH_NOT_ENFORCED';
  END IF;
END
$verify$;

COMMIT;

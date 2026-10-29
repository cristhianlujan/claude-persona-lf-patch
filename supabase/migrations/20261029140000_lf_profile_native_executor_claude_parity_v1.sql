-- LF / Native profile execution: accept CLAUDE_NATIVE with the same governance as GPT_NATIVE.
--
-- Scope: three native-bridge functions that hard-coded GPT_NATIVE + OPENAI_CHATGPT_NATIVE.
-- Executor admission, Router handoff and the terminal receipt already accept both modes.
-- The provider is bound to the mode (GPT_NATIVE <-> OPENAI_CHATGPT_NATIVE,
-- CLAUDE_NATIVE <-> ANTHROPIC_CLAUDE_NATIVE); any other pair stays blocked.
-- Authority, read-only, no-write and no-promotion rules are unchanged, as are grants.
-- Missing executor_mode/executor_provider now blocks (the previous `<>` comparison
-- yielded NULL and let the execution through).
BEGIN;

DO $patch$
DECLARE
  d text;
  old_t text;
  new_t text;
BEGIN
  ------------------------------------------------------------------ begin_v1
  d:=pg_get_functiondef('public.lf_profile_native_bridge_begin_v1(jsonb,jsonb,text,text)'::regprocedure);
  IF md5(d)<>'368e6f00cefce9f4d26a331c12bca855' THEN
    RAISE EXCEPTION 'NATIVE_BRIDGE_BEGIN_SOURCE_DRIFT';
  END IF;

  old_t:=$q$IF upper(coalesce(p_executor_mode,''))<>'GPT_NATIVE' THEN$q$;
  new_t:=$q$IF upper(coalesce(p_executor_mode,'')) NOT IN ('GPT_NATIVE','CLAUDE_NATIVE') THEN$q$;
  IF (length(d)-length(replace(d,old_t,'')))/length(old_t)<>1 THEN
    RAISE EXCEPTION 'NATIVE_BRIDGE_BEGIN_MODE_ANCHOR_DRIFT';
  END IF;
  d:=replace(d,old_t,new_t);

  old_t:=$q$'required_executor_mode','GPT_NATIVE'$q$;
  new_t:=$q$'required_executor_mode','GPT_NATIVE|CLAUDE_NATIVE'$q$;
  IF (length(d)-length(replace(d,old_t,'')))/length(old_t)<>1 THEN
    RAISE EXCEPTION 'NATIVE_BRIDGE_BEGIN_REQUIRED_ANCHOR_DRIFT';
  END IF;
  d:=replace(d,old_t,new_t);

  old_t:=E'    \'GPT_NATIVE\',\n    v_actor,';
  new_t:=E'    upper(p_executor_mode),\n    v_actor,';
  IF (length(d)-length(replace(d,old_t,'')))/length(old_t)<>1 THEN
    RAISE EXCEPTION 'NATIVE_BRIDGE_BEGIN_MATERIALIZE_ANCHOR_DRIFT';
  END IF;
  d:=replace(d,old_t,new_t);
  EXECUTE d;

  ---------------------------------------------------------------- prepare_v1
  d:=pg_get_functiondef('public.lf_profile_native_bridge_prepare_v1(text,text,text,text)'::regprocedure);
  IF md5(d)<>'43d6ee82dbd2156e29f4e348e4045e9b' THEN
    RAISE EXCEPTION 'NATIVE_BRIDGE_PREPARE_SOURCE_DRIFT';
  END IF;

  old_t:=E'     OR e.manifest->>\'executor_mode\'<>\'GPT_NATIVE\'\n     OR e.manifest->>\'executor_provider\'<>\'OPENAI_CHATGPT_NATIVE\' THEN';
  new_t:=E'     OR NOT COALESCE(\n       (e.manifest->>\'executor_mode\'=\'GPT_NATIVE\'\n        AND e.manifest->>\'executor_provider\'=\'OPENAI_CHATGPT_NATIVE\')\n       OR (e.manifest->>\'executor_mode\'=\'CLAUDE_NATIVE\'\n        AND e.manifest->>\'executor_provider\'=\'ANTHROPIC_CLAUDE_NATIVE\'),\n       false) THEN';
  IF (length(d)-length(replace(d,old_t,'')))/length(old_t)<>1 THEN
    RAISE EXCEPTION 'NATIVE_BRIDGE_PREPARE_EXECUTOR_ANCHOR_DRIFT';
  END IF;
  d:=replace(d,old_t,new_t);

  old_t:=$q$'next_action','EXECUTE_PROFILE_IN_CURRENT_GPT_NATIVE_CONTEXT',$q$;
  new_t:=$q$'next_action',CASE e.manifest->>'executor_mode' WHEN 'CLAUDE_NATIVE' THEN 'EXECUTE_PROFILE_IN_CURRENT_CLAUDE_NATIVE_CONTEXT' ELSE 'EXECUTE_PROFILE_IN_CURRENT_GPT_NATIVE_CONTEXT' END,$q$;
  IF (length(d)-length(replace(d,old_t,'')))/length(old_t)<>1 THEN
    RAISE EXCEPTION 'NATIVE_BRIDGE_PREPARE_NEXT_ACTION_ANCHOR_DRIFT';
  END IF;
  d:=replace(d,old_t,new_t);
  EXECUTE d;

  ------------------------------------------------------------ record_output_v1
  d:=pg_get_functiondef('public.lf_profile_native_bridge_record_output_v1(text,jsonb,jsonb,text,text,text)'::regprocedure);
  IF md5(d)<>'e16131b4a542c71867e59730ca14b253' THEN
    RAISE EXCEPTION 'NATIVE_BRIDGE_RECORD_OUTPUT_SOURCE_DRIFT';
  END IF;

  old_t:=E'     OR e.manifest->>\'executor_mode\'<>\'GPT_NATIVE\'\n     OR e.manifest->>\'executor_provider\'<>\'OPENAI_CHATGPT_NATIVE\'\n';
  new_t:=E'     OR NOT COALESCE(\n       (e.manifest->>\'executor_mode\'=\'GPT_NATIVE\'\n        AND e.manifest->>\'executor_provider\'=\'OPENAI_CHATGPT_NATIVE\')\n       OR (e.manifest->>\'executor_mode\'=\'CLAUDE_NATIVE\'\n        AND e.manifest->>\'executor_provider\'=\'ANTHROPIC_CLAUDE_NATIVE\'),\n       false)\n';
  IF (length(d)-length(replace(d,old_t,'')))/length(old_t)<>1 THEN
    RAISE EXCEPTION 'NATIVE_BRIDGE_RECORD_OUTPUT_ANCHOR_DRIFT';
  END IF;
  d:=replace(d,old_t,new_t);
  EXECUTE d;
END
$patch$;

DO $postcheck$
DECLARE
  f text;
  s text;
BEGIN
  FOREACH f IN ARRAY ARRAY[
    'public.lf_profile_native_bridge_begin_v1(jsonb,jsonb,text,text)',
    'public.lf_profile_native_bridge_prepare_v1(text,text,text,text)',
    'public.lf_profile_native_bridge_record_output_v1(text,jsonb,jsonb,text,text,text)'
  ] LOOP
    s:=pg_get_functiondef(f::regprocedure);
    IF strpos(s,'CLAUDE_NATIVE')=0 OR strpos(s,'<>''GPT_NATIVE''')<>0 THEN
      RAISE EXCEPTION 'NATIVE_BRIDGE_CLAUDE_PARITY_POSTCHECK_FAILED:%',f;
    END IF;
    IF NOT (SELECT prosecdef FROM pg_proc WHERE oid=f::regprocedure)
       OR has_function_privilege('anon',f::regprocedure,'EXECUTE')
       OR has_function_privilege('authenticated',f::regprocedure,'EXECUTE') THEN
      RAISE EXCEPTION 'NATIVE_BRIDGE_CLAUDE_PARITY_ACL_CHANGED:%',f;
    END IF;
  END LOOP;
END
$postcheck$;

COMMIT;

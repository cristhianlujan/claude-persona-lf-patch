-- El paso CHECKPOINT_TRANSITION del connector_plan no traia la funcion ni los argumentos. El agente lo declaraba
-- contradiccion del paquete READY y activaba fallback para resolver la firma.
-- Cambio transversal: helper fn_engineering_plan_add_transition_args_v1 + execution_packet_from_spec_v1 lo aplica a todo
-- connector_plan. El paso trae entrypoint, arguments (plan/unit/checkpoint ya completos, status DONE) y call_template.
-- No cambia status ni block_reasons (probado con rollback sobre 383 checkpoints: 0 diferencias; 368 planes READY, todos con argumentos).
-- Guarda: aborta si la funcion cambio respecto a la version probada, o si un ancla no es unica; autoverifica y revierte si falla.
DO $mig$
DECLARE
  d text;
  chk jsonb;
BEGIN
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
       WHERE n.nspname='programacion' AND p.proname='fn_engineering_execution_packet_from_spec_v1')
     IS DISTINCT FROM 'ff637ce1d8a810d8cc6c2b017aef5f3c' THEN
    RAISE EXCEPTION 'execution_packet_from_spec_v1 cambio desde la version probada; reprobar antes de aplicar';
  END IF;

  CREATE FUNCTION pg_temp.rep(src text, o text, n text) RETURNS text LANGUAGE plpgsql AS $r$
  BEGIN
    IF (length(src)-length(replace(src,o,'')))/greatest(length(o),1) <> 1 THEN
      RAISE EXCEPTION 'ancla no unica o ausente: %', left(o,70);
    END IF;
    RETURN replace(src,o,n);
  END $r$;

  CREATE FUNCTION programacion.fn_engineering_plan_add_transition_args_v1(p_plan jsonb, p_plan_code text, p_unit_code text, p_checkpoint_code text)
  RETURNS jsonb LANGUAGE sql IMMUTABLE AS $f$
    select coalesce(jsonb_agg(
      case when e->>'operation'='CHECKPOINT_TRANSITION' then e || jsonb_build_object(
        'entrypoint','programacion.fn_engineering_checkpoint_transition_v1',
        'arguments',jsonb_build_object('p_plan_code',p_plan_code,'p_unit_code',p_unit_code,'p_checkpoint_code',p_checkpoint_code,'p_new_status','DONE',
          'p_evidence_ref','<FILL: evidence of THIS run, e.g. supabase://<object-or-query> plus key result>','p_actor','<FILL: agent name>',
          'p_detail','<FILL: live values, numeric deltas vs title, queries run (text)>'),
        'call_template','select programacion.fn_engineering_checkpoint_transition_v1('||quote_literal(p_plan_code)||','||quote_literal(p_unit_code)||','||quote_literal(p_checkpoint_code)||',''DONE'',<p_evidence_ref>,<p_actor>,<p_detail>)',
        'returns','NEXT_BOOTSTRAP_V3_USE_AS_ONLY_NEXT_STATE')
      else e end order by o),'[]'::jsonb)
    from jsonb_array_elements(p_plan) with ordinality t(e,o)
  $f$;

  SELECT pg_get_functiondef(p.oid) INTO d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='programacion' AND p.proname='fn_engineering_execution_packet_from_spec_v1';
  d := pg_temp.rep(d, $o$'connector_plan',case$o$, $n$'connector_plan',programacion.fn_engineering_plan_add_transition_args_v1(case$n$);
  d := pg_temp.rep(d, E'  end,\n  ''retry_policy''', E'  end,p_plan_code,p_unit_code,p_checkpoint_code),\n  ''retry_policy''');
  EXECUTE d;

  -- autoverificacion atomica: si falla, la migracion entera se revierte
  chk := programacion.fn_engineering_execution_packet_from_spec_v1('IG_CURATOR_VALIDATOR_REFACTOR_V2','M3.0','FREEZE_BY_MODULE',
          programacion.fn_engineering_checkpoint_action_spec_v3('IG_CURATOR_VALIDATOR_REFACTOR_V2','M3.0','FREEZE_BY_MODULE'),'{}'::jsonb);
  IF chk->>'status' <> 'READY' OR chk#>>'{connector_plan,-1,arguments,p_checkpoint_code}' IS DISTINCT FROM 'FREEZE_BY_MODULE' THEN
    RAISE EXCEPTION 'autoverificacion fallida: %', left(chk::text,300);
  END IF;
END
$mig$;

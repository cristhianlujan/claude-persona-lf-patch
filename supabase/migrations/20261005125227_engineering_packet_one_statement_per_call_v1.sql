-- El plan de conectores entregaba varias consultas de verificacion como UN solo paso.
-- El agente las enviaba juntas en una llamada y el conector devolvia solo el ultimo resultado.
-- Cambio transversal en execution_packet_from_spec_v1:
--  1) planes de solo lectura: un paso EXECUTE_SQL_READONLY por consulta (statement_index/statement_count).
--  2) todos los packets: query_execution_policy = ONE_STATEMENT_PER_CALL.
-- No cambia status ni block_reasons de ningun packet.
-- Guarda: aborta si la funcion cambio respecto a la version probada, o si un ancla no es unica.
DO $mig$
DECLARE
  d text;
BEGIN
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
       WHERE n.nspname='programacion' AND p.proname='fn_engineering_execution_packet_from_spec_v1')
     IS DISTINCT FROM 'c99e669e66e5bac04323c10ad8384123' THEN
    RAISE EXCEPTION 'execution_packet_from_spec_v1 cambio desde la version probada; reprobar antes de aplicar';
  END IF;

  CREATE FUNCTION pg_temp.rep(src text, o text, n text) RETURNS text LANGUAGE plpgsql AS $r$
  BEGIN
    IF (length(src)-length(replace(src,o,'')))/greatest(length(o),1) <> 1 THEN
      RAISE EXCEPTION 'ancla no unica o ausente: %', left(o,70);
    END IF;
    RETURN replace(src,o,n);
  END $r$;

  SELECT pg_get_functiondef(p.oid) INTO d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='programacion' AND p.proname='fn_engineering_execution_packet_from_spec_v1';

  d := pg_temp.rep(d,
$o$when not effective_material then jsonb_build_array(
      jsonb_build_object('seq',1,'provider','SUPABASE','operation','EXECUTE_SQL_READONLY','queries',verification_queries),
      jsonb_build_object('seq',2,'provider','SUPABASE','operation','CHECKPOINT_TRANSITION')
    )$o$,
$n$when not effective_material then coalesce((select jsonb_agg(jsonb_build_object('seq',t.ord,'provider','SUPABASE','operation','EXECUTE_SQL_READONLY','query',t.q,'statement_index',t.ord,'statement_count',jsonb_array_length(verification_queries)) order by t.ord) from jsonb_array_elements_text(verification_queries) with ordinality t(q,ord)),'[]'::jsonb)
      || jsonb_build_array(jsonb_build_object('seq',jsonb_array_length(verification_queries)+1,'provider','SUPABASE','operation','CHECKPOINT_TRANSITION'))$n$);
  d := pg_temp.rep(d, $o$'execution_input',p_execution_input$o$,
$n$'query_execution_policy',jsonb_build_object('mode','ONE_STATEMENT_PER_CALL','statement_count',jsonb_array_length(verification_queries),'forbidden','CONCATENATE_STATEMENTS_IN_ONE_CALL','reason','CONNECTOR_RETURNS_ONLY_LAST_RESULT'),
  'execution_input',p_execution_input$n$);
  EXECUTE d;
END
$mig$;

-- Se elimina la comparacion entre cifras del titulo del checkpoint y la lectura live: aportaba trabajo (calcular deltas,
-- evaluar deriva) y una via extra de error, sin proteger nada. El agente registra solo los valores live; solo una
-- contradiccion cualitativa de lo que declara el checkpoint sigue siendo CONTRADICTION.
-- Cambia texto en recipe_v1, action_spec_v1 y en el placeholder de fn_engineering_plan_add_transition_args_v1.
-- Probado con rollback sobre 383 checkpoints: 0 cambios de status de spec, de action_kind ni de status de packet.
-- Guarda: aborta si las funciones cambiaron respecto a la version probada, o si un ancla no es unica.
DO $mig$
DECLARE
  d text;
BEGIN
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
       WHERE n.nspname='programacion' AND p.proname='fn_engineering_checkpoint_recipe_v1')
     IS DISTINCT FROM 'aa9208c7f90349c1b988e7ae77f474e2' THEN
    RAISE EXCEPTION 'checkpoint_recipe_v1 cambio desde la version probada; reprobar antes de aplicar';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
       WHERE n.nspname='programacion' AND p.proname='fn_engineering_checkpoint_action_spec_v1')
     IS DISTINCT FROM '6979c867b6010ee6143d2c682c87e97f' THEN
    RAISE EXCEPTION 'checkpoint_action_spec_v1 cambio desde la version probada; reprobar antes de aplicar';
  END IF;

  CREATE FUNCTION pg_temp.rep(src text, o text, n text) RETURNS text LANGUAGE plpgsql AS $r$
  BEGIN
    IF (length(src)-length(replace(src,o,'')))/greatest(length(o),1) <> 1 THEN
      RAISE EXCEPTION 'ancla no unica o ausente: %', left(o,70);
    END IF;
    RETURN replace(src,o,n);
  END $r$;

  SELECT pg_get_functiondef(p.oid) INTO d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='programacion' AND p.proname='fn_engineering_checkpoint_recipe_v1';
  d := pg_temp.rep(d, $o$'EXECUTE_CANONICAL_INPUT_ONCE; record the live observation as evidence; numeric figures in the checkpoint title are historical AS-IS values: record live value and delta in the persisted detail (not blocking); only a qualitative contradiction is CONTRADICTION; then persist DONE immediately; do not design later checkpoints.'$o$,
   $n$'EXECUTE_CANONICAL_INPUT_ONCE; record the live observation as evidence (live values only; do not compare with figures in the checkpoint title); only a qualitative contradiction of what the checkpoint states exists is CONTRADICTION; then persist DONE immediately; do not design later checkpoints.'$n$);
  d := pg_temp.rep(d, $o$'LIVE_OBSERVATION_EXECUTED_AND_RECORDED_WITH_NUMERIC_DRIFT_NOTED_AND_NO_QUALITATIVE_CONTRADICTION'$o$, $n$'LIVE_OBSERVATION_EXECUTED_AND_RECORDED_AND_NO_QUALITATIVE_CONTRADICTION'$n$);
  EXECUTE d;

  SELECT pg_get_functiondef(p.oid) INTO d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='programacion' AND p.proname='fn_engineering_checkpoint_action_spec_v1';
  d := pg_temp.rep(d, $o$RECORD_LIVE_OBSERVATION_AND_NOTE_NUMERIC_DRIFT_FROM_TITLE; BLOCK_ONLY_ON_QUALITATIVE_CONTRADICTION$o$, $n$RECORD_LIVE_OBSERVATION; BLOCK_ONLY_ON_QUALITATIVE_CONTRADICTION$n$);
  EXECUTE d;

  SELECT pg_get_functiondef(p.oid) INTO d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='programacion' AND p.proname='fn_engineering_plan_add_transition_args_v1';
  d := pg_temp.rep(d, $o$'<FILL: live values, numeric deltas vs title, queries run (text)>'$o$, $n$'<FILL: live values and queries run (text)>'$n$);
  EXECUTE d;
END
$mig$;

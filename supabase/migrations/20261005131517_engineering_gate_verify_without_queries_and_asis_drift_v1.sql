-- Dos correcciones transversales del compilador de checkpoints (sin casos especiales por unidad).
-- A) Gate: un checkpoint VERIFY_QUERY_ONCE sin consultas de verificacion declaradas ya no es READY.
--    Antes se cerraba sin ninguna lectura (riesgo de falso PASS). Ahora: BLOCK_SPEC_INCOMPLETE / MISSING_VERIFICATION.
-- B) Observaciones AS-IS: la cifra del titulo es historica. Se registra el valor live y el delta; solo una
--    contradiccion cualitativa bloquea. Ya no se exige que el resultado live coincida con el titulo.
-- Probado con rollback sobre los 388 checkpoints pendientes: unicos cambios = 6 checkpoints NEGATIVE/NEG_* sin consultas.
-- Guarda: aborta si alguna funcion cambio respecto a la version probada, o si un ancla no es unica.
DO $mig$
DECLARE
  d text;
BEGIN
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
       WHERE n.nspname='programacion' AND p.proname='fn_engineering_execution_packet_from_spec_v1')
     IS DISTINCT FROM '3f0e7024a38e27a185289f236ff62303' THEN
    RAISE EXCEPTION 'execution_packet_from_spec_v1 cambio desde la version probada; reprobar antes de aplicar';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
       WHERE n.nspname='programacion' AND p.proname='fn_engineering_checkpoint_recipe_v1')
     IS DISTINCT FROM '64757601f4d6260d460a80a62a00b130' THEN
    RAISE EXCEPTION 'checkpoint_recipe_v1 cambio desde la version probada; reprobar antes de aplicar';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
       WHERE n.nspname='programacion' AND p.proname='fn_engineering_checkpoint_action_spec_v1')
     IS DISTINCT FROM '3733681db3f7d48b04a1c8e619169d90' THEN
    RAISE EXCEPTION 'checkpoint_action_spec_v1 cambio desde la version probada; reprobar antes de aplicar';
  END IF;

  CREATE FUNCTION pg_temp.rep(src text, o text, n text) RETURNS text LANGUAGE plpgsql AS $r$
  BEGIN
    IF (length(src)-length(replace(src,o,'')))/greatest(length(o),1) <> 1 THEN
      RAISE EXCEPTION 'ancla no unica o ausente: %', left(o,70);
    END IF;
    RETURN replace(src,o,n);
  END $r$;

  -- A) packet
  SELECT pg_get_functiondef(p.oid) INTO d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='programacion' AND p.proname='fn_engineering_execution_packet_from_spec_v1';
  d := pg_temp.rep(d, $o$when spec_status<>'READY' then 'BLOCK_ACTION_SPEC'$o$,
$n$when spec_status<>'READY' then 'BLOCK_ACTION_SPEC'
      when action_kind='VERIFY_QUERY_ONCE' and not has_verification then 'BLOCK_SPEC_INCOMPLETE'$n$);
  d := pg_temp.rep(d, $o$when effective_material and not has_verification and not has_migration_artifact then jsonb_build_array('MISSING_VERIFICATION')$o$,
$n$when ((effective_material and not has_migration_artifact) or (action_kind='VERIFY_QUERY_ONCE' and not effective_material)) and not has_verification then jsonb_build_array('MISSING_VERIFICATION')$n$);
  EXECUTE d;

  -- B) recipe_v1
  SELECT pg_get_functiondef(p.oid) INTO d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='programacion' AND p.proname='fn_engineering_checkpoint_recipe_v1';
  d := pg_temp.rep(d, $o$'EXECUTE_CANONICAL_INPUT_ONCE; IF checkpoint_title observation is confirmed THEN persist DONE immediately; do not design later checkpoints.'$o$,
$n$'EXECUTE_CANONICAL_INPUT_ONCE; record the live observation as evidence; numeric figures in the checkpoint title are historical AS-IS values: record live value and delta in the persisted detail (not blocking); only a qualitative contradiction is CONTRADICTION; then persist DONE immediately; do not design later checkpoints.'$n$);
  d := pg_temp.rep(d, $o$'CANONICAL_LIVE_OBSERVATION_MATCHES_CHECKPOINT_TITLE'$o$,
$n$'LIVE_OBSERVATION_EXECUTED_AND_RECORDED_WITH_NUMERIC_DRIFT_NOTED_AND_NO_QUALITATIVE_CONTRADICTION'$n$);
  EXECUTE d;

  -- B) action_spec_v1
  SELECT pg_get_functiondef(p.oid) INTO d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='programacion' AND p.proname='fn_engineering_checkpoint_action_spec_v1';
  d := pg_temp.rep(d, $o$ASSERT_LIVE_OBSERVATION_MATCHES_CHECKPOINT_TITLE$o$,
$n$RECORD_LIVE_OBSERVATION_AND_NOTE_NUMERIC_DRIFT_FROM_TITLE; BLOCK_ONLY_ON_QUALITATIVE_CONTRADICTION$n$);
  EXECUTE d;
END
$mig$;

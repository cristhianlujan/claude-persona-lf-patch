-- expects_migration se activaba por cualquier mencion de "migraci" en el titulo, incluso negada.
-- M3.8 CASE_MATRIX dice "fixtures fuera de migraciones" y quedaba bloqueado con MISSING_OUTPUT_MIGRATION_ARTIFACT.
-- Cambio transversal en execution_packet_from_spec_v1: no cuenta la mencion precedida de fuera de / sin / excepto / salvo.
-- Probado con rollback sobre 379 checkpoints pendientes: el unico cambio es M3.8 CASE_MATRIX (BLOCK_SPEC_INCOMPLETE -> READY,
-- plan USE_DECLARED_ARTIFACT); ningun otro status ni block_reasons cambia.
-- Guarda: aborta si la funcion cambio respecto a la version probada, o si un ancla no es unica; autoverifica y revierte si falla.
DO $mig$
DECLARE
  d text;
  chk jsonb;
BEGIN
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
       WHERE n.nspname='programacion' AND p.proname='fn_engineering_execution_packet_from_spec_v1')
     IS DISTINCT FROM '1facbb902e1da951e9892b1f154212ec' THEN
    RAISE EXCEPTION 'execution_packet_from_spec_v1 cambio desde la version probada; reprobar antes de aplicar';
  END IF;

  CREATE FUNCTION pg_temp.rep(src text, o text, n text) RETURNS text LANGUAGE plpgsql AS $r$
  BEGIN
    IF (length(src)-length(replace(src,o,'')))/greatest(length(o),1) <> 1 THEN
      RAISE EXCEPTION 'ancla no unica o ausente: %', left(o,70);
    END IF;
    RETURN replace(src,o,n);
  END $r$;

  SELECT pg_get_functiondef(p.oid) INTO d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='programacion' AND p.proname='fn_engineering_execution_packet_from_spec_v1';
  d := pg_temp.rep(d, $o$(title_l ~ '(migraci|git-first)') expects_migration$o$,
   $n$(title_l ~ '(migraci|git-first)' and title_l !~ '(fuera de|sin|excepto|salvo) (las |los )?migraci') expects_migration$n$);
  EXECUTE d;

  chk := programacion.fn_engineering_execution_packet_from_spec_v1('IG_CURATOR_VALIDATOR_REFACTOR_V2','M3.8','CASE_MATRIX',
          programacion.fn_engineering_checkpoint_action_spec_v3('IG_CURATOR_VALIDATOR_REFACTOR_V2','M3.8','CASE_MATRIX'),'{}'::jsonb);
  IF chk->>'status' <> 'READY' THEN
    RAISE EXCEPTION 'autoverificacion fallida: %', left(chk::text,300);
  END IF;
END
$mig$;

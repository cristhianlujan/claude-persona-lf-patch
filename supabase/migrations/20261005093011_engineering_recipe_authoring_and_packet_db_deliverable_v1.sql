-- Correccion transversal del compilador de checkpoints (sin casos especiales por unidad).
-- A) recipe_v1: un checkpoint cuyo codigo sugiere TEST/NEGATIVE pero cuyo titulo AUTORA casos/tests
--    es un entregable a materializar, no una verificacion de solo lectura.
-- B) execution_packet_from_spec_v1: un entregable declarado en BD (db_objects) con consulta de
--    verificacion es una operacion ejecutable; ya no exige un artefacto de archivo.
-- Guardas: aborta si las funciones cambiaron respecto a las versiones probadas, o si un ancla no es unica.
DO $mig$
DECLARE
  d text;
  md5_recipe text;
  md5_packet text;
BEGIN
  SELECT md5(p.prosrc) INTO md5_recipe FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='programacion' AND p.proname='fn_engineering_checkpoint_recipe_v1';
  SELECT md5(p.prosrc) INTO md5_packet FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='programacion' AND p.proname='fn_engineering_execution_packet_from_spec_v1';
  IF md5_recipe IS DISTINCT FROM 'c71e69ef17dd7e5cbc173eb71cbc9436' THEN
    RAISE EXCEPTION 'recipe_v1 cambio desde la version probada (md5=%); reprobar antes de aplicar', md5_recipe;
  END IF;
  IF md5_packet IS DISTINCT FROM 'fcb619687c506acfc3dad1f39e9d2796' THEN
    RAISE EXCEPTION 'execution_packet_from_spec_v1 cambio desde la version probada (md5=%); reprobar antes de aplicar', md5_packet;
  END IF;

  CREATE FUNCTION pg_temp.rep(src text, o text, n text) RETURNS text LANGUAGE plpgsql AS $r$
  BEGIN
    IF (length(src)-length(replace(src,o,'')))/greatest(length(o),1) <> 1 THEN
      RAISE EXCEPTION 'ancla no unica o ausente: %', left(o,70);
    END IF;
    RETURN replace(src,o,n);
  END $r$;

  -- A) recipe_v1
  SELECT pg_get_functiondef(p.oid) INTO d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='programacion' AND p.proname='fn_engineering_checkpoint_recipe_v1';
  d := pg_temp.rep(d,
    $o$when cp.checkpoint_code ~* '(^NEG_|NEGATIVE|FALSE_PASS|MUTATION|PARITY|REPRO|DRILL|CONCURRENCY|EQUIVALENCE|TEST)' then 'VERIFY_EXPECTED'$o$,
    $n$when cp.checkpoint_code ~* '(^NEG_|NEGATIVE|FALSE_PASS|MUTATION|PARITY|REPRO|DRILL|CONCURRENCY|EQUIVALENCE|TEST)' and lower(cp.title) ~ '^(casos|tests?|pruebas)( |$)' and lower(cp.title) !~ '(ejecut|invoc|simulad|reproduc|concurren|rollback|mutaci|inyect|verific|compar)' then 'EXECUTE_DECLARED_DELIVERABLE'
      when cp.checkpoint_code ~* '(^NEG_|NEGATIVE|FALSE_PASS|MUTATION|PARITY|REPRO|DRILL|CONCURRENCY|EQUIVALENCE|TEST)' then 'VERIFY_EXPECTED'$n$);
  EXECUTE d;

  -- B) execution packet
  SELECT pg_get_functiondef(p.oid) INTO d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='programacion' AND p.proname='fn_engineering_execution_packet_from_spec_v1';
  d := pg_temp.rep(d, $o$has_artifact,$o$, $n$has_artifact,
    (jsonb_array_length(objects)>0 and jsonb_array_length(verification_queries)>0) has_db_deliverable,$n$);
  d := pg_temp.rep(d, $o$when inherent_operation or has_artifact then 'READY'$o$,
    $n$when inherent_operation or has_artifact or has_db_deliverable then 'READY'$n$);
  d := pg_temp.rep(d, $o$and not inherent_operation and not has_artifact then jsonb_build_array('MISSING_EXECUTABLE_ARTIFACT_OR_OPERATION')$o$,
    $n$and not inherent_operation and not has_artifact and not has_db_deliverable then jsonb_build_array('MISSING_EXECUTABLE_ARTIFACT_OR_OPERATION')$n$);
  d := pg_temp.rep(d, $o$when has_migration_artifact then jsonb_build_array($o$,
    $n$when has_db_deliverable and not has_artifact then jsonb_build_array(
      jsonb_build_object('seq',1,'provider','SUPABASE','operation','MATERIALIZE_DECLARED_DB_OBJECTS','targets',objects),
      jsonb_build_object('seq',2,'provider','SUPABASE','operation','EXECUTE_SQL_READBACK','queries',verification_queries),
      jsonb_build_object('seq',3,'provider','SUPABASE','operation','CHECKPOINT_TRANSITION')
    )
    when has_migration_artifact then jsonb_build_array($n$);
  EXECUTE d;
END
$mig$;

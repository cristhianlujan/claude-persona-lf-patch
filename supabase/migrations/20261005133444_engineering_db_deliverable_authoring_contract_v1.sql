-- El plan MATERIALIZE_DECLARED_DB_OBJECTS (entregable en BD sin artefacto de archivo) nombraba el objeto pero no decia
-- que operacion concreta aplicar; el agente se detenia correctamente en 57 checkpoints (ej. M3.0 PRECEDENCE_FIELDS).
-- Cambio transversal en execution_packet_from_spec_v1: el paso 1 declara la autoridad y el procedimiento:
-- si el titulo solo verifica estado existente, solo se ejecutan las consultas; si no, SQL minimo sobre los objetos declarados,
-- dry-run con ROLLBACK forzado, apply una vez con guardas, readback una consulta por llamada, DONE solo si el readback coincide.
-- No cambia status ni block_reasons de ningun packet (solo el contenido del paso 1 de 57 planes).
-- Guarda: aborta si la funcion cambio respecto a la version probada, o si un ancla no es unica; autoverifica y revierte si falla.
DO $mig$
DECLARE
  d text;
  chk jsonb;
BEGIN
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
       WHERE n.nspname='programacion' AND p.proname='fn_engineering_execution_packet_from_spec_v1')
     IS DISTINCT FROM '0df13d9df125c76a41dc75cc5f3ea3e8' THEN
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
  d := pg_temp.rep(d, $o$jsonb_build_object('seq',1,'provider','SUPABASE','operation','MATERIALIZE_DECLARED_DB_OBJECTS','targets',objects),$o$,
$n$jsonb_build_object('seq',1,'provider','SUPABASE','operation','MATERIALIZE_DECLARED_DB_OBJECTS','targets',objects,
        'authority','AUTHOR_MINIMAL_SQL_THAT_MAKES_CHECKPOINT_TITLE_TRUE_ON_DECLARED_TARGETS_ONLY',
        'procedure',jsonb_build_array('IF_TITLE_ONLY_VERIFIES_EXISTING_STATE_SKIP_AUTHORING_AND_RUN_VERIFICATION_QUERIES','AUTHOR_MINIMAL_SQL','DRY_RUN_IN_SINGLE_DO_BLOCK_WITH_FORCED_ROLLBACK_AND_RUN_VERIFICATION_QUERIES','APPLY_ONCE_VIA_APPLY_MIGRATION_WITH_GUARDS','RUN_VERIFICATION_QUERIES_ONE_PER_CALL','PERSIST_DONE_ONLY_IF_READBACK_MATCHES_TITLE'),
        'forbidden',jsonb_build_array('TOUCH_OBJECTS_OUTSIDE_DECLARED_TARGETS','SKIP_DRY_RUN','DESTRUCTIVE_DDL_NOT_REQUIRED_BY_TITLE'),
        'on_title_not_expressible_as_sql','MISSING_CANONICAL_OBJECT'),$n$);
  EXECUTE d;

  -- autoverificacion atomica: si falla, la migracion entera se revierte
  chk := programacion.fn_engineering_execution_packet_from_spec_v1('IG_CURATOR_VALIDATOR_REFACTOR_V2','M3.0','FREEZE_BY_MODULE',
          programacion.fn_engineering_checkpoint_action_spec_v3('IG_CURATOR_VALIDATOR_REFACTOR_V2','M3.0','FREEZE_BY_MODULE'),'{}'::jsonb);
  IF chk->>'status' <> 'READY' OR chk#>>'{connector_plan,0,authority}' IS NULL OR chk#>>'{connector_plan,0,operation}' <> 'MATERIALIZE_DECLARED_DB_OBJECTS' THEN
    RAISE EXCEPTION 'autoverificacion fallida: %', left(chk::text,300);
  END IF;
END
$mig$;

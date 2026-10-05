-- Route generic GitHub material artifacts through a scoped branch + PR instead of writing to main.
-- Preserves the existing migration-specific path unchanged.
-- Guarded by the exact live fingerprint validated before authoring.
DO $mig$
DECLARE
  d text;
  old_block text := $o$else jsonb_build_array(
      jsonb_build_object('seq',1,'provider','GITHUB','operation','USE_DECLARED_ARTIFACT','targets',artifacts),
      jsonb_build_object('seq',2,'provider','SUPABASE','operation','EXECUTE_SQL_READBACK','queries',verification_queries),
      jsonb_build_object('seq',3,'provider','SUPABASE','operation','CHECKPOINT_TRANSITION')
    )$o$;
  new_block text := $n$else jsonb_build_array(
      jsonb_build_object('seq',1,'provider','GITHUB','operation','USE_OR_CREATE_DECLARED_ARTIFACT','targets',artifacts,'write_route','SCOPED_BRANCH_ONLY'),
      jsonb_build_object('seq',2,'provider','GITHUB','operation','OPEN_AND_MERGE_SCOPED_PR'),
      jsonb_build_object('seq',3,'provider','SUPABASE','operation','EXECUTE_SQL_READBACK','queries',verification_queries),
      jsonb_build_object('seq',4,'provider','SUPABASE','operation','CHECKPOINT_TRANSITION')
    )$n$;
  chk jsonb;
  mig jsonb;
BEGIN
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='programacion' AND p.proname='fn_engineering_execution_packet_from_spec_v1')
     IS DISTINCT FROM 'e5d82f7a0fb23dc7c96d7f51807c98f8' THEN
    RAISE EXCEPTION 'execution_packet_from_spec_v1 fingerprint changed; revalidate before apply';
  END IF;

  SELECT pg_get_functiondef(p.oid) INTO d
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='programacion' AND p.proname='fn_engineering_execution_packet_from_spec_v1';

  IF (length(d)-length(replace(d,old_block,'')))/greatest(length(old_block),1) <> 1 THEN
    RAISE EXCEPTION 'generic artifact connector-plan anchor absent or non-unique';
  END IF;

  EXECUTE replace(d,old_block,new_block);

  chk := programacion.fn_engineering_execution_packet_from_spec_v1(
    'IG_CURATOR_VALIDATOR_REFACTOR_V2','M3.8','CASE_MATRIX',
    programacion.fn_engineering_checkpoint_action_spec_v3('IG_CURATOR_VALIDATOR_REFACTOR_V2','M3.8','CASE_MATRIX'),
    '{}'::jsonb
  );

  IF chk->>'status' <> 'READY'
     OR chk#>>'{connector_plan,0,operation}' <> 'USE_OR_CREATE_DECLARED_ARTIFACT'
     OR chk#>>'{connector_plan,0,write_route}' <> 'SCOPED_BRANCH_ONLY'
     OR chk#>>'{connector_plan,1,operation}' <> 'OPEN_AND_MERGE_SCOPED_PR'
     OR chk#>>'{connector_plan,2,operation}' <> 'EXECUTE_SQL_READBACK'
     OR chk#>>'{connector_plan,3,operation}' <> 'CHECKPOINT_TRANSITION' THEN
    RAISE EXCEPTION 'non-migration GitHub artifact route failed: %', chk->'connector_plan';
  END IF;

  mig := programacion.fn_engineering_execution_packet_from_spec_v1(
    'IG_CURATOR_VALIDATOR_REFACTOR_V2','M3.8','CASE_MATRIX',
    jsonb_build_object(
      'status','READY',
      'action_kind','MATERIALIZE_DECLARED_DELIVERABLE',
      'checkpoint_title','crear migracion de prueba',
      'requires_material_execution',true,
      'target',jsonb_build_object(
        'declared_objects','[]'::jsonb,
        'declared_artifacts',jsonb_build_array(jsonb_build_object('path','cristhianlujan/claude-persona-lf-patch:supabase/migrations/x.sql'))
      ),
      'verification_queries',jsonb_build_array('select 1')
    ),
    '{}'::jsonb
  );

  IF mig->>'status' <> 'READY'
     OR mig#>>'{connector_plan,0,operation}' <> 'USE_OR_CREATE_DECLARED_MIGRATION_ARTIFACT'
     OR mig#>>'{connector_plan,1,operation}' <> 'OPEN_AND_MERGE_SCOPED_PR'
     OR mig#>>'{connector_plan,2,operation}' <> 'APPLY_DECLARED_MIGRATION'
     OR mig#>>'{connector_plan,3,operation}' <> 'EXECUTE_SQL_READBACK'
     OR mig#>>'{connector_plan,4,operation}' <> 'CHECKPOINT_TRANSITION' THEN
    RAISE EXCEPTION 'migration route regression: %', mig->'connector_plan';
  END IF;
END
$mig$;

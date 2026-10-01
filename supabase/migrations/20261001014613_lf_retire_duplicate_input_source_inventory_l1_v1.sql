-- R16 Git-first retirement of the duplicate Input Governance L1 discovery index.
-- Canonical Router discovery authority after this migration: inventory.*
-- Preflight snapshot: 54 active source rows, 129 L1_PILOT_MIGRATION tags on 54 objects,
-- source digest md5=4c4d949f3643a440febca594a10309cb.

DO $$
DECLARE
  v_source_rows integer;
  v_matched_rows integer;
  v_distinct_targets integer;
  v_tag_rows integer;
  v_tagged_objects integer;
  v_existing_keys integer;
  v_source_digest text;
BEGIN
  IF to_regclass('programacion.input_source_inventory_l1') IS NULL THEN
    RAISE EXCEPTION 'R16 preflight failed: programacion.input_source_inventory_l1 is missing';
  END IF;
  IF to_regclass('programacion.v_input_source_inventory_l1_v1') IS NULL THEN
    RAISE EXCEPTION 'R16 preflight failed: programacion.v_input_source_inventory_l1_v1 is missing';
  END IF;
  IF to_regprocedure('programacion.fn_input_source_inventory_lookup_l1_v1(text)') IS NULL THEN
    RAISE EXCEPTION 'R16 preflight failed: programacion.fn_input_source_inventory_lookup_l1_v1(text) is missing';
  END IF;

  SELECT count(*)
    INTO v_source_rows
    FROM programacion.input_source_inventory_l1
   WHERE active IS TRUE;

  IF v_source_rows <> 54 THEN
    RAISE EXCEPTION 'R16 preflight failed: expected 54 active source rows, got %', v_source_rows;
  END IF;

  SELECT count(*), count(DISTINCT o.object_id)
    INTO v_matched_rows, v_distinct_targets
    FROM programacion.input_source_inventory_l1 s
    JOIN inventory.objects o
      ON o.schema_name = s.schema_name
     AND o.object_name = s.table_name
     AND o.object_type = 'DB_TABLE'
   WHERE s.active IS TRUE;

  IF v_matched_rows <> 54 OR v_distinct_targets <> 54 THEN
    RAISE EXCEPTION 'R16 preflight failed: expected 54 one-to-one inventory targets, got matched=% distinct=%', v_matched_rows, v_distinct_targets;
  END IF;

  SELECT count(*)
    INTO v_existing_keys
    FROM programacion.input_source_inventory_l1 s
    JOIN inventory.objects o
      ON o.schema_name = s.schema_name
     AND o.object_name = s.table_name
     AND o.object_type = 'DB_TABLE'
   WHERE s.active IS TRUE
     AND o.metadata ?| ARRAY['query_hints','is_canonical','source_ref'];

  IF v_existing_keys <> 0 THEN
    RAISE EXCEPTION 'R16 preflight failed: % target objects already contain one of the migration metadata keys', v_existing_keys;
  END IF;

  SELECT count(*), count(DISTINCT object_id)
    INTO v_tag_rows, v_tagged_objects
    FROM inventory.object_tags
   WHERE source_system = 'L1_PILOT_MIGRATION';

  IF v_tag_rows <> 129 OR v_tagged_objects <> 54 THEN
    RAISE EXCEPTION 'R16 preflight failed: expected 129 L1_PILOT_MIGRATION tags on 54 objects, got tags=% objects=%', v_tag_rows, v_tagged_objects;
  END IF;

  SELECT md5(string_agg(
           coalesce(schema_name,'') || '.' || coalesce(table_name,'') || '|' ||
           coalesce(source_ref,'') || '|' ||
           coalesce(is_canonical::text,'null') || '|' ||
           coalesce(query_hints::text,'null'),
           E'\n' ORDER BY schema_name, table_name))
    INTO v_source_digest
    FROM programacion.input_source_inventory_l1
   WHERE active IS TRUE;

  IF v_source_digest <> '4c4d949f3643a440febca594a10309cb' THEN
    RAISE EXCEPTION 'R16 preflight failed: source digest drifted: %', v_source_digest;
  END IF;

  IF NOT EXISTS (
    SELECT 1
      FROM public.lf_activos
     WHERE id = 352
       AND codigo_activo = 'PROGRAMACION_INPUT_SOURCE_INVENTORY_L1'
       AND archived_at IS NULL
  ) THEN
    RAISE EXCEPTION 'R16 preflight failed: asset 352 is missing, mismatched, or already archived';
  END IF;
END
$$;

DO $$
DECLARE
  v_updated integer;
  v_target_digest text;
BEGIN
  UPDATE inventory.objects o
     SET metadata = coalesce(o.metadata, '{}'::jsonb)
                    || jsonb_build_object(
                         'query_hints', s.query_hints,
                         'is_canonical', s.is_canonical,
                         'source_ref', s.source_ref
                       ),
         updated_at = now()
    FROM programacion.input_source_inventory_l1 s
   WHERE s.active IS TRUE
     AND o.schema_name = s.schema_name
     AND o.object_name = s.table_name
     AND o.object_type = 'DB_TABLE';

  GET DIAGNOSTICS v_updated = ROW_COUNT;
  IF v_updated <> 54 THEN
    RAISE EXCEPTION 'R16 migration failed: expected 54 inventory.objects updates, got %', v_updated;
  END IF;

  SELECT md5(string_agg(
           coalesce(o.schema_name,'') || '.' || coalesce(o.object_name,'') || '|' ||
           coalesce(o.metadata->>'source_ref','') || '|' ||
           coalesce(o.metadata->>'is_canonical','null') || '|' ||
           coalesce((o.metadata->'query_hints')::text,'null'),
           E'\n' ORDER BY o.schema_name, o.object_name))
    INTO v_target_digest
    FROM programacion.input_source_inventory_l1 s
    JOIN inventory.objects o
      ON o.schema_name = s.schema_name
     AND o.object_name = s.table_name
     AND o.object_type = 'DB_TABLE'
   WHERE s.active IS TRUE;

  IF v_target_digest <> '4c4d949f3643a440febca594a10309cb' THEN
    RAISE EXCEPTION 'R16 migration failed: target metadata digest mismatch: %', v_target_digest;
  END IF;
END
$$;

DO $$
DECLARE
  v_archived integer;
BEGIN
  UPDATE public.lf_activos
     SET archived_at = now(),
         archived_reason = 'Retired duplicate L1 discovery index after query_hints, is_canonical and source_ref were moved to inventory.objects.metadata. Router inventory authority is inventory.*.',
         updated_at = now(),
         updated_by_execution_id = 'CHATGPT-IG-CV-L1-DUP-INVENTORY-RETIRE-R16-20261001'
   WHERE id = 352
     AND codigo_activo = 'PROGRAMACION_INPUT_SOURCE_INVENTORY_L1'
     AND archived_at IS NULL;

  GET DIAGNOSTICS v_archived = ROW_COUNT;
  IF v_archived <> 1 THEN
    RAISE EXCEPTION 'R16 migration failed: expected to archive asset 352 exactly once, got %', v_archived;
  END IF;
END
$$;

DROP FUNCTION programacion.fn_input_source_inventory_lookup_l1_v1(text);
DROP VIEW programacion.v_input_source_inventory_l1_v1;
DROP TABLE programacion.input_source_inventory_l1;

DO $$
DECLARE
  v_tag_rows integer;
  v_tagged_objects integer;
  v_metadata_rows integer;
  v_target_digest text;
  v_lookup_rows integer;
BEGIN
  IF to_regclass('programacion.input_source_inventory_l1') IS NOT NULL
     OR to_regclass('programacion.v_input_source_inventory_l1_v1') IS NOT NULL
     OR to_regprocedure('programacion.fn_input_source_inventory_lookup_l1_v1(text)') IS NOT NULL THEN
    RAISE EXCEPTION 'R16 postflight failed: one or more duplicate L1 inventory objects remain';
  END IF;

  SELECT count(*), count(DISTINCT object_id)
    INTO v_tag_rows, v_tagged_objects
    FROM inventory.object_tags
   WHERE source_system = 'L1_PILOT_MIGRATION';

  IF v_tag_rows <> 129 OR v_tagged_objects <> 54 THEN
    RAISE EXCEPTION 'R16 postflight failed: expected 129 L1_PILOT_MIGRATION tags on 54 objects, got tags=% objects=%', v_tag_rows, v_tagged_objects;
  END IF;

  WITH tagged AS (
    SELECT DISTINCT object_id
      FROM inventory.object_tags
     WHERE source_system = 'L1_PILOT_MIGRATION'
  )
  SELECT count(*), md5(string_agg(
           coalesce(o.schema_name,'') || '.' || coalesce(o.object_name,'') || '|' ||
           coalesce(o.metadata->>'source_ref','') || '|' ||
           coalesce(o.metadata->>'is_canonical','null') || '|' ||
           coalesce((o.metadata->'query_hints')::text,'null'),
           E'\n' ORDER BY o.schema_name, o.object_name))
    INTO v_metadata_rows, v_target_digest
    FROM tagged t
    JOIN inventory.objects o ON o.object_id = t.object_id
   WHERE o.object_type = 'DB_TABLE'
     AND o.metadata ? 'query_hints'
     AND o.metadata ? 'is_canonical'
     AND o.metadata ? 'source_ref';

  IF v_metadata_rows <> 54 OR v_target_digest <> '4c4d949f3643a440febca594a10309cb' THEN
    RAISE EXCEPTION 'R16 postflight failed: expected 54 migrated tagged objects with digest 4c4d949f3643a440febca594a10309cb, got rows=% digest=%', v_metadata_rows, v_target_digest;
  END IF;

  SELECT count(*)
    INTO v_lookup_rows
    FROM inventory.fn_lookup_v2('brand_assets', ARRAY['DB_TABLE']::text[], 10)
   WHERE object_ref = 'db://lf_design.brand_assets';

  IF v_lookup_rows < 1 THEN
    RAISE EXCEPTION 'R16 postflight failed: inventory.fn_lookup_v2 canary did not resolve brand_assets';
  END IF;

  IF NOT EXISTS (
    SELECT 1
      FROM public.lf_activos
     WHERE id = 352
       AND codigo_activo = 'PROGRAMACION_INPUT_SOURCE_INVENTORY_L1'
       AND archived_at IS NOT NULL
       AND archived_reason IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'R16 postflight failed: asset 352 was not archived';
  END IF;
END
$$;

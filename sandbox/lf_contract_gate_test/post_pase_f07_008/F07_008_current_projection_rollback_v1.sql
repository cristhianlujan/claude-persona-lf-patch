-- PASE-ATOM-F07-008 rollback for stale current projection repair.
-- Restores only the two pre-repair asset projection fields.

DO $rollback$
DECLARE
  v_apply_exec constant text := 'CHATGPT-PASE-F07-008-CURRENT-PROJECTION-REPAIR-20261004';
  v_rollback_exec constant text := 'CHATGPT-PASE-F07-008-CURRENT-PROJECTION-ROLLBACK-20261004';
  v_count integer;
BEGIN
  SELECT count(*) INTO v_count
  FROM public.lf_activos
  WHERE codigo_activo='EVIDENCE_ANTIREPLAY'
    AND archived_at IS NULL
    AND updated_by_execution_id=v_apply_exec
    AND metadata->>'registry_version'='1.1.0'
    AND metadata->>'registry_manifest_sha256'='09bd21f5e74de2ec12dc499bb6be63dcd9a230bbaa31eef6067fc5a28adb89b9';

  IF v_count <> 1 THEN
    RAISE EXCEPTION 'BLOCK_F07_008_CURRENT_PROJECTION_ROLLBACK_CURRENTNESS:%',v_count;
  END IF;

  UPDATE public.lf_activos
  SET metadata=jsonb_set(
        jsonb_set(metadata,'{registry_version}',to_jsonb('1.0.0'::text),true),
        '{registry_manifest_sha256}',to_jsonb('ed34a1946155fcdc39bb7773788fc5e565cda6e6955ebdef7541c8d1410ed076'::text),true
      ),
      updated_by_execution_id=v_rollback_exec
  WHERE codigo_activo='EVIDENCE_ANTIREPLAY'
    AND archived_at IS NULL
    AND updated_by_execution_id=v_apply_exec;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'BLOCK_F07_008_CURRENT_PROJECTION_ROLLBACK_NO_ROW';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_activos
    WHERE codigo_activo='EVIDENCE_ANTIREPLAY'
      AND archived_at IS NULL
      AND metadata->>'registry_version'='1.0.0'
      AND metadata->>'registry_manifest_sha256'='ed34a1946155fcdc39bb7773788fc5e565cda6e6955ebdef7541c8d1410ed076'
  ) THEN
    RAISE EXCEPTION 'BLOCK_F07_008_CURRENT_PROJECTION_ROLLBACK_READBACK';
  END IF;
END
$rollback$;

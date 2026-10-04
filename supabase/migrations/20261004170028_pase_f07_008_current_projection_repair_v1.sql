-- LF_PASE_POST_PASE_GLOBAL_ARCHITECTURE_V1 / PASE-ATOM-F07-008
-- Reconcile only demonstrated stale asset current-version/manifest projection.
-- Canonical authority: lf_capability_current for the exact historical L5 cutover set.
-- No registry/current/status/entry-policy/runtime/production mutation.

DO $f07$
DECLARE
  v_exec constant text := 'CHATGPT-PASE-F07-008-CURRENT-PROJECTION-REPAIR-20261004';
  v_target_count integer;
  v_remaining integer;
  v_registry_before text;
  v_registry_after text;
  v_current_before text;
  v_current_after text;
  v_entry_before text;
  v_entry_after text;
BEGIN
  WITH core AS (
    SELECT DISTINCT e.payload->>'capability_code' AS capability_code
    FROM public.lf_eventos e
    WHERE e.payload->>'work_code'='SADM-PP-L5-022'
      AND e.payload ? 'capability_code'
      AND e.payload->>'execution_id' LIKE 'CHATGPT-PASE-GLOBAL-PHASE03-L5-022-CUTOVER-%-READBACK-20261001'
  ), target AS (
    SELECT k.capability_code,c.version,c.manifest_sha256,
           a.metadata->>'registry_version' AS projected_version,
           a.metadata->>'registry_manifest_sha256' AS projected_manifest
    FROM core k
    JOIN public.lf_capability_current c USING(capability_code)
    JOIN public.lf_activos a ON a.codigo_activo=k.capability_code AND a.archived_at IS NULL
    WHERE (a.metadata ? 'registry_version' AND a.metadata->>'registry_version' IS DISTINCT FROM c.version)
       OR (a.metadata ? 'registry_manifest_sha256' AND a.metadata->>'registry_manifest_sha256' IS DISTINCT FROM c.manifest_sha256)
  )
  SELECT count(*) INTO v_target_count FROM target;

  IF v_target_count <> 1 THEN
    RAISE EXCEPTION 'BLOCK_F07_008_CURRENT_PROJECTION_TARGET_DRIFT:%',v_target_count;
  END IF;

  IF NOT EXISTS (
    WITH core AS (
      SELECT DISTINCT e.payload->>'capability_code' AS capability_code
      FROM public.lf_eventos e
      WHERE e.payload->>'work_code'='SADM-PP-L5-022'
        AND e.payload ? 'capability_code'
        AND e.payload->>'execution_id' LIKE 'CHATGPT-PASE-GLOBAL-PHASE03-L5-022-CUTOVER-%-READBACK-20261001'
    )
    SELECT 1
    FROM core k
    JOIN public.lf_capability_current c USING(capability_code)
    JOIN public.lf_activos a ON a.codigo_activo=k.capability_code AND a.archived_at IS NULL
    WHERE k.capability_code='EVIDENCE_ANTIREPLAY'
      AND c.version='1.1.0'
      AND c.manifest_sha256='09bd21f5e74de2ec12dc499bb6be63dcd9a230bbaa31eef6067fc5a28adb89b9'
      AND a.version='1.1.0'
      AND a.metadata->>'registry_version'='1.0.0'
      AND a.metadata->>'registry_manifest_sha256'='ed34a1946155fcdc39bb7773788fc5e565cda6e6955ebdef7541c8d1410ed076'
  ) THEN
    RAISE EXCEPTION 'BLOCK_F07_008_CURRENT_PROJECTION_EXPECTED_OLD_STATE_DRIFT';
  END IF;

  WITH core AS (
    SELECT DISTINCT e.payload->>'capability_code' AS capability_code
    FROM public.lf_eventos e
    WHERE e.payload->>'work_code'='SADM-PP-L5-022'
      AND e.payload ? 'capability_code'
      AND e.payload->>'execution_id' LIKE 'CHATGPT-PASE-GLOBAL-PHASE03-L5-022-CUTOVER-%-READBACK-20261001'
  )
  SELECT encode(extensions.digest(convert_to(jsonb_agg(jsonb_build_object(
      'capability_code',r.capability_code,'status',r.status,
      'entry_guard_required',r.entry_guard_required,'entry_guard_code',r.entry_guard_code
    ) ORDER BY r.capability_code)::text,'UTF8'),'sha256'),'hex')
  INTO v_registry_before
  FROM core k JOIN public.lf_capability_registry r USING(capability_code);

  WITH core AS (
    SELECT DISTINCT e.payload->>'capability_code' AS capability_code
    FROM public.lf_eventos e
    WHERE e.payload->>'work_code'='SADM-PP-L5-022'
      AND e.payload ? 'capability_code'
      AND e.payload->>'execution_id' LIKE 'CHATGPT-PASE-GLOBAL-PHASE03-L5-022-CUTOVER-%-READBACK-20261001'
  )
  SELECT encode(extensions.digest(convert_to(jsonb_agg(jsonb_build_object(
      'capability_code',c.capability_code,'version',c.version,'manifest_sha256',c.manifest_sha256
    ) ORDER BY c.capability_code)::text,'UTF8'),'sha256'),'hex')
  INTO v_current_before
  FROM core k JOIN public.lf_capability_current c USING(capability_code);

  WITH core AS (
    SELECT DISTINCT e.payload->>'capability_code' AS capability_code
    FROM public.lf_eventos e
    WHERE e.payload->>'work_code'='SADM-PP-L5-022'
      AND e.payload ? 'capability_code'
      AND e.payload->>'execution_id' LIKE 'CHATGPT-PASE-GLOBAL-PHASE03-L5-022-CUTOVER-%-READBACK-20261001'
  )
  SELECT encode(extensions.digest(convert_to(jsonb_agg(jsonb_build_object(
      'capability_code',a.codigo_activo,
      'entry_contract',a.metadata->'entry_contract'
    ) ORDER BY a.codigo_activo)::text,'UTF8'),'sha256'),'hex')
  INTO v_entry_before
  FROM core k JOIN public.lf_activos a ON a.codigo_activo=k.capability_code AND a.archived_at IS NULL;

  WITH core AS (
    SELECT DISTINCT e.payload->>'capability_code' AS capability_code
    FROM public.lf_eventos e
    WHERE e.payload->>'work_code'='SADM-PP-L5-022'
      AND e.payload ? 'capability_code'
      AND e.payload->>'execution_id' LIKE 'CHATGPT-PASE-GLOBAL-PHASE03-L5-022-CUTOVER-%-READBACK-20261001'
  ), target AS (
    SELECT k.capability_code,c.version,c.manifest_sha256
    FROM core k
    JOIN public.lf_capability_current c USING(capability_code)
    JOIN public.lf_activos a ON a.codigo_activo=k.capability_code AND a.archived_at IS NULL
    WHERE (a.metadata ? 'registry_version' AND a.metadata->>'registry_version' IS DISTINCT FROM c.version)
       OR (a.metadata ? 'registry_manifest_sha256' AND a.metadata->>'registry_manifest_sha256' IS DISTINCT FROM c.manifest_sha256)
  ), updated AS (
    UPDATE public.lf_activos a
    SET metadata=jsonb_set(
          jsonb_set(a.metadata,'{registry_version}',to_jsonb(t.version),true),
          '{registry_manifest_sha256}',to_jsonb(t.manifest_sha256),true
        ),
        updated_by_execution_id=v_exec
    FROM target t
    WHERE a.codigo_activo=t.capability_code AND a.archived_at IS NULL
    RETURNING a.codigo_activo
  )
  SELECT count(*) INTO v_target_count FROM updated;

  IF v_target_count <> 1 THEN
    RAISE EXCEPTION 'BLOCK_F07_008_CURRENT_PROJECTION_UPDATE_CARDINALITY:%',v_target_count;
  END IF;

  WITH core AS (
    SELECT DISTINCT e.payload->>'capability_code' AS capability_code
    FROM public.lf_eventos e
    WHERE e.payload->>'work_code'='SADM-PP-L5-022'
      AND e.payload ? 'capability_code'
      AND e.payload->>'execution_id' LIKE 'CHATGPT-PASE-GLOBAL-PHASE03-L5-022-CUTOVER-%-READBACK-20261001'
  )
  SELECT count(*) INTO v_remaining
  FROM core k
  JOIN public.lf_capability_current c USING(capability_code)
  JOIN public.lf_activos a ON a.codigo_activo=k.capability_code AND a.archived_at IS NULL
  WHERE (a.metadata ? 'registry_version' AND a.metadata->>'registry_version' IS DISTINCT FROM c.version)
     OR (a.metadata ? 'registry_manifest_sha256' AND a.metadata->>'registry_manifest_sha256' IS DISTINCT FROM c.manifest_sha256);
  IF v_remaining <> 0 THEN
    RAISE EXCEPTION 'BLOCK_F07_008_CURRENT_PROJECTION_POSTCHECK:%',v_remaining;
  END IF;

  WITH core AS (
    SELECT DISTINCT e.payload->>'capability_code' AS capability_code
    FROM public.lf_eventos e
    WHERE e.payload->>'work_code'='SADM-PP-L5-022'
      AND e.payload ? 'capability_code'
      AND e.payload->>'execution_id' LIKE 'CHATGPT-PASE-GLOBAL-PHASE03-L5-022-CUTOVER-%-READBACK-20261001'
  )
  SELECT encode(extensions.digest(convert_to(jsonb_agg(jsonb_build_object(
      'capability_code',r.capability_code,'status',r.status,
      'entry_guard_required',r.entry_guard_required,'entry_guard_code',r.entry_guard_code
    ) ORDER BY r.capability_code)::text,'UTF8'),'sha256'),'hex')
  INTO v_registry_after
  FROM core k JOIN public.lf_capability_registry r USING(capability_code);

  WITH core AS (
    SELECT DISTINCT e.payload->>'capability_code' AS capability_code
    FROM public.lf_eventos e
    WHERE e.payload->>'work_code'='SADM-PP-L5-022'
      AND e.payload ? 'capability_code'
      AND e.payload->>'execution_id' LIKE 'CHATGPT-PASE-GLOBAL-PHASE03-L5-022-CUTOVER-%-READBACK-20261001'
  )
  SELECT encode(extensions.digest(convert_to(jsonb_agg(jsonb_build_object(
      'capability_code',c.capability_code,'version',c.version,'manifest_sha256',c.manifest_sha256
    ) ORDER BY c.capability_code)::text,'UTF8'),'sha256'),'hex')
  INTO v_current_after
  FROM core k JOIN public.lf_capability_current c USING(capability_code);

  WITH core AS (
    SELECT DISTINCT e.payload->>'capability_code' AS capability_code
    FROM public.lf_eventos e
    WHERE e.payload->>'work_code'='SADM-PP-L5-022'
      AND e.payload ? 'capability_code'
      AND e.payload->>'execution_id' LIKE 'CHATGPT-PASE-GLOBAL-PHASE03-L5-022-CUTOVER-%-READBACK-20261001'
  )
  SELECT encode(extensions.digest(convert_to(jsonb_agg(jsonb_build_object(
      'capability_code',a.codigo_activo,'entry_contract',a.metadata->'entry_contract'
    ) ORDER BY a.codigo_activo)::text,'UTF8'),'sha256'),'hex')
  INTO v_entry_after
  FROM core k JOIN public.lf_activos a ON a.codigo_activo=k.capability_code AND a.archived_at IS NULL;

  IF v_registry_before IS DISTINCT FROM v_registry_after THEN RAISE EXCEPTION 'BLOCK_F07_008_REGISTRY_MUTATED'; END IF;
  IF v_current_before IS DISTINCT FROM v_current_after THEN RAISE EXCEPTION 'BLOCK_F07_008_CURRENT_MUTATED'; END IF;
  IF v_entry_before IS DISTINCT FROM v_entry_after THEN RAISE EXCEPTION 'BLOCK_F07_008_ENTRY_POLICY_MUTATED'; END IF;
END
$f07$;

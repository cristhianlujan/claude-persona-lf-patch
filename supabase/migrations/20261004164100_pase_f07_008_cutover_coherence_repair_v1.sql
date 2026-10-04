-- LF_PASE_POST_PASE_GLOBAL_ARCHITECTURE_V1 / PASE-ATOM-F07-008
-- Repair only the demonstrated cutover-coherence split-brain created after
-- containment event #19821. Canonical live entry requiredness remains owned by
-- public.lf_capability_registry; this migration only reconciles stale
-- public.lf_activos.metadata.entry_contract projections.
-- No registry/current pointer/status/operational/runtime/production change.

DO $f07$
DECLARE
  v_exec constant text := 'CHATGPT-PASE-F07-008-COHERENCE-REPAIR-20261004';
  v_authority jsonb;
  v_expected_count integer;
  v_registry_count integer;
  v_asset_count integer;
  v_target_count integer;
  v_remaining integer;
  v_registry_before text;
  v_registry_after text;
  v_current_before text;
  v_current_after text;
  v_operational_before text;
  v_operational_after text;
BEGIN
  SELECT payload INTO v_authority
  FROM public.lf_eventos
  WHERE id = 19821
    AND evento_tipo = 'READBACK_VERIFICADO'
    AND entidad_codigo = 'LF_PASE_POST_PASE_GLOBAL_ARCHITECTURE_V1';

  IF v_authority IS NULL
     OR v_authority->>'execution_id' <> 'CHATGPT-PASE-PREMATURE-ENFORCEMENT-CONTAINMENT-20261001'
     OR v_authority->>'containment_mode' <> 'ENTRY_GUARD_REQUIREMENT_DEFERRED_ONLY'
     OR jsonb_typeof(v_authority->'affected_capabilities') IS DISTINCT FROM 'array'
  THEN
    RAISE EXCEPTION 'BLOCK_F07_008_CONTAINMENT_AUTHORITY_DRIFT';
  END IF;

  v_expected_count := COALESCE((v_authority->>'affected_count')::integer, -1);
  IF v_expected_count < 1
     OR jsonb_array_length(v_authority->'affected_capabilities') <> v_expected_count
  THEN
    RAISE EXCEPTION 'BLOCK_F07_008_CONTAINMENT_CARDINALITY_DRIFT';
  END IF;

  WITH affected AS (
    SELECT jsonb_array_elements_text(v_authority->'affected_capabilities') AS capability_code
  )
  SELECT count(*) INTO v_registry_count
  FROM affected a
  JOIN public.lf_capability_registry r USING (capability_code);
  IF v_registry_count <> v_expected_count THEN
    RAISE EXCEPTION 'BLOCK_F07_008_REGISTRY_AFFECTED_SET_DRIFT:%/%', v_registry_count, v_expected_count;
  END IF;

  WITH affected AS (
    SELECT jsonb_array_elements_text(v_authority->'affected_capabilities') AS capability_code
  )
  SELECT count(*) INTO v_asset_count
  FROM affected a
  JOIN public.lf_activos x
    ON x.codigo_activo = a.capability_code
   AND x.archived_at IS NULL;
  IF v_asset_count <> v_expected_count THEN
    RAISE EXCEPTION 'BLOCK_F07_008_ASSET_AFFECTED_SET_DRIFT:%/%', v_asset_count, v_expected_count;
  END IF;

  WITH affected AS (
    SELECT jsonb_array_elements_text(v_authority->'affected_capabilities') AS capability_code
  )
  SELECT encode(extensions.digest(convert_to(jsonb_agg(
      jsonb_build_object(
        'capability_code',r.capability_code,
        'status',r.status,
        'entry_guard_required',r.entry_guard_required,
        'entry_guard_code',r.entry_guard_code,
        'updated_by_execution_id',r.updated_by_execution_id
      ) ORDER BY r.capability_code
    )::text,'UTF8'),'sha256'),'hex')
  INTO v_registry_before
  FROM affected a JOIN public.lf_capability_registry r USING (capability_code);

  WITH affected AS (
    SELECT jsonb_array_elements_text(v_authority->'affected_capabilities') AS capability_code
  )
  SELECT encode(extensions.digest(convert_to(COALESCE(jsonb_agg(
      jsonb_build_object(
        'capability_code',c.capability_code,
        'version',c.version,
        'manifest_sha256',c.manifest_sha256
      ) ORDER BY c.capability_code
    ),'[]'::jsonb)::text,'UTF8'),'sha256'),'hex')
  INTO v_current_before
  FROM affected a LEFT JOIN public.lf_capability_current c USING (capability_code)
  WHERE c.capability_code IS NOT NULL;

  WITH affected AS (
    SELECT jsonb_array_elements_text(v_authority->'affected_capabilities') AS capability_code
  )
  SELECT encode(extensions.digest(convert_to(jsonb_agg(
      jsonb_build_object(
        'capability_code',x.codigo_activo,
        'estado_documental',x.estado_documental,
        'estado_operativo',x.estado_operativo,
        'runtime_estado',x.runtime_estado,
        'version',x.version,
        'owner_name',x.owner_name
      ) ORDER BY x.codigo_activo
    )::text,'UTF8'),'sha256'),'hex')
  INTO v_operational_before
  FROM affected a
  JOIN public.lf_activos x ON x.codigo_activo=a.capability_code AND x.archived_at IS NULL;

  WITH affected AS (
    SELECT jsonb_array_elements_text(v_authority->'affected_capabilities') AS capability_code
  ), target AS (
    SELECT
      a.capability_code,
      r.entry_guard_required,
      r.entry_guard_code,
      c.version,
      x.metadata#>>'{entry_contract,enforcement_state}' AS old_enforcement
    FROM affected a
    JOIN public.lf_capability_registry r USING (capability_code)
    LEFT JOIN public.lf_capability_current c USING (capability_code)
    JOIN public.lf_activos x
      ON x.codigo_activo=a.capability_code
     AND x.archived_at IS NULL
    WHERE x.metadata->'entry_contract' IS NOT NULL
      AND (
        (x.metadata#>>'{entry_contract,required}')::boolean IS DISTINCT FROM r.entry_guard_required
        OR x.metadata#>>'{entry_contract,guard_code}' IS DISTINCT FROM r.entry_guard_code
        OR (
          r.entry_guard_required
          AND c.version IS NOT NULL
          AND x.metadata#>>'{entry_contract,enforcement_state}' IS DISTINCT FROM 'ENFORCED'
        )
        OR (
          NOT r.entry_guard_required
          AND x.metadata#>>'{entry_contract,enforcement_state}' IN (
            'ENFORCED','ENTRY_ENFORCED_NOT_CURRENT','SOURCE_READY_NOT_REGISTERED'
          )
        )
      )
  ), updated AS (
    UPDATE public.lf_activos x
    SET metadata = jsonb_set(
      jsonb_set(
        x.metadata,
        '{entry_contract,required}',
        to_jsonb(t.entry_guard_required),
        true
      ),
      '{entry_contract,enforcement_state}',
      to_jsonb(
        CASE
          WHEN t.entry_guard_required AND t.version IS NOT NULL THEN 'ENFORCED'::text
          WHEN NOT t.entry_guard_required AND t.old_enforcement LIKE 'DECLARED_DEFERRED%' THEN t.old_enforcement
          ELSE v_authority->>'containment_mode'
        END
      ),
      true
    ),
    updated_by_execution_id = v_exec
    FROM target t
    WHERE x.codigo_activo=t.capability_code
      AND x.archived_at IS NULL
    RETURNING x.codigo_activo
  )
  SELECT count(*) INTO v_target_count FROM updated;

  IF v_target_count > v_expected_count THEN
    RAISE EXCEPTION 'BLOCK_F07_008_UNBOUNDED_UPDATE:%/%', v_target_count, v_expected_count;
  END IF;

  WITH affected AS (
    SELECT jsonb_array_elements_text(v_authority->'affected_capabilities') AS capability_code
  )
  SELECT count(*) INTO v_remaining
  FROM affected a
  JOIN public.lf_capability_registry r USING (capability_code)
  LEFT JOIN public.lf_capability_current c USING (capability_code)
  JOIN public.lf_activos x
    ON x.codigo_activo=a.capability_code
   AND x.archived_at IS NULL
  WHERE x.metadata->'entry_contract' IS NOT NULL
    AND (
      (x.metadata#>>'{entry_contract,required}')::boolean IS DISTINCT FROM r.entry_guard_required
      OR x.metadata#>>'{entry_contract,guard_code}' IS DISTINCT FROM r.entry_guard_code
      OR (
        r.entry_guard_required
        AND c.version IS NOT NULL
        AND x.metadata#>>'{entry_contract,enforcement_state}' IS DISTINCT FROM 'ENFORCED'
      )
      OR (
        NOT r.entry_guard_required
        AND x.metadata#>>'{entry_contract,enforcement_state}' IN (
          'ENFORCED','ENTRY_ENFORCED_NOT_CURRENT','SOURCE_READY_NOT_REGISTERED'
        )
      )
    );
  IF v_remaining <> 0 THEN
    RAISE EXCEPTION 'BLOCK_F07_008_COHERENCE_POSTCHECK:%', v_remaining;
  END IF;

  WITH affected AS (
    SELECT jsonb_array_elements_text(v_authority->'affected_capabilities') AS capability_code
  )
  SELECT encode(extensions.digest(convert_to(jsonb_agg(
      jsonb_build_object(
        'capability_code',r.capability_code,
        'status',r.status,
        'entry_guard_required',r.entry_guard_required,
        'entry_guard_code',r.entry_guard_code,
        'updated_by_execution_id',r.updated_by_execution_id
      ) ORDER BY r.capability_code
    )::text,'UTF8'),'sha256'),'hex')
  INTO v_registry_after
  FROM affected a JOIN public.lf_capability_registry r USING (capability_code);

  WITH affected AS (
    SELECT jsonb_array_elements_text(v_authority->'affected_capabilities') AS capability_code
  )
  SELECT encode(extensions.digest(convert_to(COALESCE(jsonb_agg(
      jsonb_build_object(
        'capability_code',c.capability_code,
        'version',c.version,
        'manifest_sha256',c.manifest_sha256
      ) ORDER BY c.capability_code
    ),'[]'::jsonb)::text,'UTF8'),'sha256'),'hex')
  INTO v_current_after
  FROM affected a LEFT JOIN public.lf_capability_current c USING (capability_code)
  WHERE c.capability_code IS NOT NULL;

  WITH affected AS (
    SELECT jsonb_array_elements_text(v_authority->'affected_capabilities') AS capability_code
  )
  SELECT encode(extensions.digest(convert_to(jsonb_agg(
      jsonb_build_object(
        'capability_code',x.codigo_activo,
        'estado_documental',x.estado_documental,
        'estado_operativo',x.estado_operativo,
        'runtime_estado',x.runtime_estado,
        'version',x.version,
        'owner_name',x.owner_name
      ) ORDER BY x.codigo_activo
    )::text,'UTF8'),'sha256'),'hex')
  INTO v_operational_after
  FROM affected a
  JOIN public.lf_activos x ON x.codigo_activo=a.capability_code AND x.archived_at IS NULL;

  IF v_registry_before IS DISTINCT FROM v_registry_after THEN
    RAISE EXCEPTION 'BLOCK_F07_008_REGISTRY_MUTATED';
  END IF;
  IF v_current_before IS DISTINCT FROM v_current_after THEN
    RAISE EXCEPTION 'BLOCK_F07_008_CURRENT_POINTER_MUTATED';
  END IF;
  IF v_operational_before IS DISTINCT FROM v_operational_after THEN
    RAISE EXCEPTION 'BLOCK_F07_008_OPERATIONAL_STATE_MUTATED';
  END IF;
END
$f07$;

-- IG M4.12: re-anchor the declared shadow-oracle definition pin and refresh registry integrity.
-- Scope: INPUT_FAMILY_POLICY_REGISTRY seed data only. No function/DDL change, no Curator or
-- Validator rewiring, no new judge. The oracle remains comparison-only (semantic_pass_authorized=false).
--
-- Why: all 47 families pin priority_oracle_version_md5 to a definition hash that no longer
-- matches the live function, so fn_input_validator_oracle_admission_v1 always ends in
-- BLOCKED_VERSION_DRIFT. registry_sha256 was also stale versus the families payload.
-- Restoring the historical function body is rejected: direct and effective rule counts differ
-- in 12 of 13 historical screens, so the live (effective-rule) definition is the one to pin.
--
-- Fail-closed: aborts unless the live oracle hash equals the expected one, so the pin can never
-- be written for a function version nobody reviewed. Idempotent: no-op when already anchored.
DO $ig_oracle_pin_reanchor$
DECLARE
  c_expected_live constant text := '4d95df141035b10255e411b3b7adb472';
  c_oracle_sig   constant text := 'programacion.fn_input_governance_shadow_priority_oracle_v2(integer,text,bigint)';
  c_migration    constant text := 'supabase/migrations/20261008235000_ig_m412_oracle_pin_reanchor_v1.sql';
  v_live text;
  v_id bigint;
  v_spec jsonb;
  v_unpinned int;
  v_families jsonb;
  v_sha text;
BEGIN
  SELECT md5(pg_get_functiondef(to_regprocedure(c_oracle_sig))) INTO v_live;
  IF v_live IS DISTINCT FROM c_expected_live THEN
    RAISE EXCEPTION 'IG_ORACLE_PIN_REANCHOR_LIVE_HASH_UNEXPECTED:%', coalesce(v_live,'NULL');
  END IF;

  SELECT c.id, c.especificacion
    INTO v_id, v_spec
  FROM programacion.contratos c
  WHERE c.contrato_codigo = 'INPUT_FAMILY_POLICY_REGISTRY'
    AND c.estado = 'defined' AND c.fail_closed
  ORDER BY c.id DESC LIMIT 1
  FOR UPDATE;

  IF v_id IS NULL THEN
    RAISE EXCEPTION 'IG_ORACLE_PIN_REANCHOR_REGISTRY_NOT_FOUND';
  END IF;

  SELECT count(*) INTO v_unpinned
  FROM jsonb_each(v_spec->'families') f
  WHERE f.value #>> '{validator_oracle_strategy,priority_oracle_version_md5}' IS DISTINCT FROM c_expected_live;

  IF v_unpinned = 0
     AND v_spec->>'registry_sha256' = programacion.fn_v09_sha256_jsonb(v_spec->'families') THEN
    RETURN; -- already anchored and consistent
  END IF;

  SELECT jsonb_object_agg(
           f.key,
           jsonb_set(f.value, '{validator_oracle_strategy,priority_oracle_version_md5}', to_jsonb(c_expected_live))
         )
    INTO v_families
  FROM jsonb_each(v_spec->'families') f;

  IF (SELECT count(*) FROM jsonb_object_keys(v_families)) <> (v_spec->>'family_count')::int THEN
    RAISE EXCEPTION 'IG_ORACLE_PIN_REANCHOR_FAMILY_COUNT_MISMATCH';
  END IF;

  v_sha := programacion.fn_v09_sha256_jsonb(v_families);

  UPDATE programacion.contratos
     SET especificacion = jsonb_set(
           jsonb_set(
             jsonb_set(
               jsonb_set(v_spec, '{families}', v_families),
               '{registry_sha256}', to_jsonb(v_sha)),
             '{contract_revision}', to_jsonb('1.1.0'::text)),
           '{source_migration}', to_jsonb(c_migration))
   WHERE id = v_id;

  -- Read back inside the same transaction; abort the whole migration on any mismatch.
  SELECT especificacion INTO v_spec FROM programacion.contratos WHERE id = v_id;
  IF v_spec->>'registry_sha256' IS DISTINCT FROM programacion.fn_v09_sha256_jsonb(v_spec->'families')
     OR EXISTS (
       SELECT 1 FROM jsonb_each(v_spec->'families') f
       WHERE f.value #>> '{validator_oracle_strategy,priority_oracle_version_md5}' IS DISTINCT FROM c_expected_live
     ) THEN
    RAISE EXCEPTION 'IG_ORACLE_PIN_REANCHOR_READBACK_MISMATCH';
  END IF;
END
$ig_oracle_pin_reanchor$;

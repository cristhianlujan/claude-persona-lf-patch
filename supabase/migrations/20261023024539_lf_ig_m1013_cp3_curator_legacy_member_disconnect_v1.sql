-- IG M10.13 CP3: DISCONNECT historical v1 from active Curator asset membership.
-- Not a function retirement. Preserve pg_proc source, grants, M10.4 freeze,
-- archival reconciliation, metadata historical identity, and checkpoint PENDING.
-- Git-first -> PASE -> LF Migration Merge Train -> exact Supabase readback.
BEGIN;

DO $ig_cp3_asset_disconnect$
DECLARE
  v_identity constant text :=
    'programacion.fn_input_governance_bootstrap_materialize_v1(p_pantalla_id integer, p_consumer text, p_curator_identity text)';
  v_old_sha constant text := '99a1192ddc1cb17420317a159b26127e184eb87d88750ae95f66ff52a41925ba';
  v_expected_new_sha constant text := '124639d2ef4bd4d6d7af9739e12a523ecd309676c71f8d43215f30e240f05bf3';
  v_asset constant text := 'PROGRAMACION_FN_INPUT_GOVERNANCE_CURATION_SET';
  v_source constant text := '20261022214200_lf_ig_m1013_cp3_curator_legacy_member_disconnect_v1';
  v_execution_id text;
  v_record public.lf_activos%ROWTYPE;
  v_new_members jsonb;
  v_sha text;
  v_count integer;
  v_rows integer;
  v_readback public.lf_activos%ROWTYPE;
BEGIN
  -- Retain real train transport provenance; no actor/session forgery.
  SELECT e.execution_id INTO v_execution_id
  FROM public.lf_operation_execution e
  WHERE e.operation_code='ACTUALIZACION_DB_LF'
    AND e.target_type='MIGRATION'
    AND e.target_code LIKE '%'||v_source
    AND e.status='IN_PROGRESS'
  ORDER BY e.created_at DESC LIMIT 1;
  IF v_execution_id IS NULL THEN
    RAISE EXCEPTION 'IG_CP3_DISCONNECT_OFFICIAL_TRAIN_EXECUTION_REQUIRED';
  END IF;

  IF (SELECT w.status FROM programacion.engineering_work_items w WHERE w.id=474)
      IS DISTINCT FROM 'IN_PROGRESS'
    OR (SELECT status FROM programacion.engineering_work_checkpoints
        WHERE work_item_id=474 AND checkpoint_code='GIT_RUNTIME_PARITY')
      IS DISTINCT FROM 'DONE'
    OR (SELECT status FROM programacion.engineering_work_checkpoints
        WHERE work_item_id=474 AND checkpoint_code='ZERO_LEGACY_CALLERS')
      IS DISTINCT FROM 'PENDING'
    OR NOT EXISTS (
      SELECT 1 FROM public.lf_capability_current c
      JOIN public.lf_capability_version_registry v
      ON v.capability_code=c.capability_code AND v.version=c.version
      WHERE c.capability_code='ASSET_RETIREMENT_GOVERNANCE'
        AND c.version='1.0.0' AND v.release_state='RELEASED'
    )
  THEN RAISE EXCEPTION 'IG_CP3_DISCONNECT_GOVERNANCE_OR_PRESTATE_DRIFT'; END IF;

  SELECT * INTO STRICT v_record
  FROM public.lf_activos
  WHERE id=289 AND codigo_activo=v_asset AND archived_at IS NULL
    AND estado_operativo='READ_ONLY' AND runtime_estado='CANDIDATE_READ_ONLY'
  FOR UPDATE;

  IF v_record.raw_payload->>'members_sha256' IS DISTINCT FROM v_old_sha
    OR jsonb_array_length(v_record.raw_payload->'members')<>8
    OR (v_record.raw_payload->>'function_count')::integer<>8
    OR encode(pg_catalog.sha256(convert_to((v_record.raw_payload->'members')::text,'UTF8')),'hex')<>v_old_sha
    OR v_record.metadata->>'lectura_alcance'
       IS DISTINCT FROM '8 funciones exactas por pg_get_function_identity_arguments, incluida la fachada public del Curator'
    OR v_record.metadata ? 'cp3_m1013_legacy_member_disconnection_v1'
  THEN RAISE EXCEPTION 'IG_CP3_DISCONNECT_ASSET_BASELINE_DRIFT'; END IF;

  IF (SELECT COUNT(*) FROM jsonb_array_elements_text(v_record.raw_payload->'members') AS x(member)
      WHERE member=v_identity)<>1
    OR to_regprocedure('programacion.fn_input_governance_bootstrap_materialize_v1(integer,text,text)') IS NULL
    OR (SELECT md5(p.prosrc) FROM pg_proc p
        WHERE p.oid=to_regprocedure('programacion.fn_input_governance_bootstrap_materialize_v1(integer,text,text)'))
       IS DISTINCT FROM 'bfd85f25b23fb127ca67f0dcd6bba668'
    OR to_regprocedure('programacion.fn_input_governance_bootstrap_materialize_v2(integer,text,text)') IS NULL
    OR (SELECT md5(p.prosrc) FROM pg_proc p
        WHERE p.oid=to_regprocedure('programacion.fn_input_governance_bootstrap_materialize_v2(integer,text,text)'))
       IS DISTINCT FROM '6760c7c0e1c8e27c3e6bdfb25a8b13ba'
  THEN RAISE EXCEPTION 'IG_CP3_DISCONNECT_FROZEN_OR_SUCCESSOR_DRIFT'; END IF;

  -- This is only the ACTIVE INVENTORY membership, not pg_proc retirement.
  IF (SELECT COUNT(*) FROM pg_proc p
      WHERE p.oid<>to_regprocedure('programacion.fn_input_governance_bootstrap_materialize_v1(integer,text,text)')
        AND p.prosrc ILIKE '%fn_input_governance_bootstrap_materialize_v1%')<>0
    OR has_function_privilege('anon',
        'programacion.fn_input_governance_bootstrap_materialize_v1(integer,text,text)','EXECUTE')
    OR has_function_privilege('authenticated',
        'programacion.fn_input_governance_bootstrap_materialize_v1(integer,text,text)','EXECUTE')
    OR has_function_privilege('service_role',
        'programacion.fn_input_governance_bootstrap_materialize_v1(integer,text,text)','EXECUTE')
    OR EXISTS (
      SELECT 1 FROM public.lf_activo_relaciones rel
      WHERE rel.codigo_activo=v_asset AND rel.relacionado_codigo LIKE '%MATERIALIZE_V1%'
    )
  THEN RAISE EXCEPTION 'IG_CP3_DISCONNECT_LIVE_CALLER_OR_ACL_DRIFT'; END IF;

  SELECT jsonb_agg(member ORDER BY member),COUNT(*)
  INTO v_new_members,v_count
  FROM jsonb_array_elements_text(v_record.raw_payload->'members') AS x(member)
  WHERE member<>v_identity;
  v_sha:=encode(pg_catalog.sha256(convert_to(v_new_members::text,'UTF8')),'hex');
  IF v_count<>7 OR v_sha IS DISTINCT FROM v_expected_new_sha
    OR v_new_members ? v_identity
    OR NOT (v_new_members @> jsonb_build_array(
      'programacion.fn_input_governance_bootstrap_materialize_v2(p_pantalla_id integer, p_consumer text, p_curator_identity text)',
      'public.fn_input_governance_curator_materialize_v1(p_pantalla_id integer, p_consumer text, p_curator_identity text)'
    ))
  THEN RAISE EXCEPTION 'IG_CP3_DISCONNECT_SET_MISMATCH count=% digest=%',v_count,v_sha; END IF;

  UPDATE public.lf_activos
  SET raw_payload=jsonb_set(
      jsonb_set(
        jsonb_set(raw_payload,'{members}',v_new_members,false),
        '{function_count}',to_jsonb(v_count),false),
      '{members_sha256}',to_jsonb(v_sha),false),
    metadata=jsonb_set(
      jsonb_set(
        metadata,'{lectura_alcance}',
        to_jsonb('7 funciones operativas exactas, incluida la fachada public; función legacy v1 conservada solo como referencia histórica M10.4'::text),false),
      '{cp3_m1013_legacy_member_disconnection_v1}',
      jsonb_build_object(
        'phase','DISCONNECT_CURRENT_ASSET_MEMBERSHIP',
        'historical_identity',v_identity,
        'prior_asset_members_sha256',v_old_sha,
        'new_asset_members_sha256',v_sha,
        'historical_function_source_md5','bfd85f25b23fb127ca67f0dcd6bba668',
        'source_freeze','sandbox/lf_contract_gate_test/engineering_checkpoints/m10_4/legacy_freeze_manifest_v1.json',
        'retirement_intake','sandbox/lf_contract_gate_test/transversal_assets/asset_retirement_governance/evidence/ig_m1013_cp3_retirement_intake_20261022.json',
        'active_member_count_before',8,
        'active_member_count_after',7,
        'function_still_exists',true,
        'acl_and_source_unchanged',true,
        'retirement_or_revoke_authorized',false,
        'checkpoint_close_authorized',false,
        'execution_id',v_execution_id
      ),true),
    updated_at=clock_timestamp(),updated_by_execution_id=v_execution_id
  WHERE id=289 AND codigo_activo=v_asset
    AND raw_payload->>'members_sha256'=v_old_sha;
  GET DIAGNOSTICS v_rows=ROW_COUNT;
  IF v_rows<>1 THEN RAISE EXCEPTION 'IG_CP3_DISCONNECT_ASSET_MUTATION_NOT_UNIQUE'; END IF;

  SELECT * INTO STRICT v_readback FROM public.lf_activos
  WHERE id=289 AND codigo_activo=v_asset;
  IF jsonb_array_length(v_readback.raw_payload->'members')<>7
    OR (v_readback.raw_payload->>'function_count')::integer<>7
    OR v_readback.raw_payload->>'members_sha256' IS DISTINCT FROM v_expected_new_sha
    OR encode(pg_catalog.sha256(convert_to((v_readback.raw_payload->'members')::text,'UTF8')),'hex')
       IS DISTINCT FROM v_expected_new_sha
    OR v_readback.raw_payload->'members' ? v_identity
    OR v_readback.metadata#>>'{cp3_m1013_legacy_member_disconnection_v1,historical_identity}'
       IS DISTINCT FROM v_identity
    OR (SELECT status FROM programacion.engineering_work_checkpoints
        WHERE work_item_id=474 AND checkpoint_code='ZERO_LEGACY_CALLERS')<>'PENDING'
  THEN RAISE EXCEPTION 'IG_CP3_DISCONNECT_READBACK_FAILED'; END IF;
END
$ig_cp3_asset_disconnect$;
COMMIT;

BEGIN;

-- PE10_C4 legacy contract classification.
-- Classifies the six immutable legacy manifests through append-only events.
-- It does NOT rewrite execution manifests and does NOT close any execution.
DO $pe10$
DECLARE
  v_actor constant text := 'EXEC-SUPERADMIN-PE10-C4-CLASSIFY-20261013-001';
  v_ids constant text[] := ARRAY[
    'EXEC-ACTUALIZACION-PERFIL-UI-ARCHITECT-S26-N08C-REPAIR-20260908-001',
    'EXEC-ACTUALIZACION-PERFIL-UI-ARCHITECT-S26-UPSTREAM-BINDING-20260908-002',
    'EXEC-LF-SRCR-PROFILE-RUNTIME-BOUNDED-20260919-001',
    'EXEC-LF-SRCR-PROFILE-PARTITION-V1-20260919-001',
    'EXEC-ACTUALIZACION-PERFIL-SRCR-CLOSURE-20260919-001',
    'EXEC-ACTUALIZACION-PERFIL-SRCR-CLOSURE-20260919-002'
  ];
  v_q constant text := $q$
WITH open_runs AS (
  SELECT e.execution_id,
         nullif(e.manifest->>'contract_code','') AS manifest_contract
  FROM public.lf_operation_execution e
  WHERE e.operation_code='ACTUALIZACION_PERFIL_LF'
    AND e.status='IN_PROGRESS'
),
classified AS (
  SELECT DISTINCT ON (ev.entidad_codigo)
         ev.entidad_codigo AS execution_id,
         ev.payload->>'classified_contract_code' AS classified_contract
  FROM public.lf_eventos ev
  WHERE ev.evento_tipo='PROFILE_UPDATE_LEGACY_CONTRACT_CLASSIFIED'
    AND ev.entidad_tipo='EXECUTION'
    AND ev.payload->>'classification_status'='VERIFIED'
  ORDER BY ev.entidad_codigo,ev.created_at DESC,ev.id DESC
),
resolved AS (
  SELECT o.execution_id,
         coalesce(o.manifest_contract,c.classified_contract) AS contract_code,
         (o.manifest_contract IS NULL AND c.classified_contract IS NULL) AS unclassified
  FROM open_runs o
  LEFT JOIN classified c USING(execution_id)
)
SELECT count(*) FILTER (
         WHERE contract_code='CONTRACT-ACTUALIZACION-PERFIL-LF-v0.1'
       )::int AS open_explicit_v01,
       count(*) FILTER (WHERE unclassified)::int AS open_unclassified,
       count(*)::int AS open_total
FROM resolved
$q$;
  v_meta jsonb;
  v_spec jsonb;
  v_contract jsonb;
  v_pack jsonb;
  v_packet jsonb;
  v_open integer;
  v_v01 integer;
  v_unclassified integer;
  v_eligible integer;
  v_event_count integer;
BEGIN
  -- Exact-scope preflight after lot 001 drained one verified execution.
  SELECT count(*)::int INTO v_open
  FROM public.lf_operation_execution
  WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND status='IN_PROGRESS';
  IF v_open<>24 THEN
    RAISE EXCEPTION 'PE10_C4_CLASSIFY_OPEN_COUNT_DRIFT:%',v_open;
  END IF;

  IF (SELECT count(*) FROM public.lf_operation_execution
      WHERE execution_id=ANY(v_ids)
        AND operation_code='ACTUALIZACION_PERFIL_LF'
        AND status='IN_PROGRESS'
        AND nullif(manifest->>'contract_code','') IS NULL)<>6 THEN
    RAISE EXCEPTION 'PE10_C4_CLASSIFY_LEGACY_SET_DRIFT';
  END IF;

  -- There is exactly one updater operation contract in authority and it predates
  -- all six runs. No v0.2 authority exists at this point.
  IF (SELECT count(*) FROM public.lf_operation_contracts
      WHERE operation_code='ACTUALIZACION_PERFIL_LF')<>1
     OR NOT EXISTS (
       SELECT 1 FROM public.lf_operation_contracts c
       WHERE c.operation_code='ACTUALIZACION_PERFIL_LF'
         AND c.contract_code='CONTRACT-ACTUALIZACION-PERFIL-LF-v0.1'
         AND c.created_at <= (
           SELECT min(started_at) FROM public.lf_operation_execution
           WHERE execution_id=ANY(v_ids)
         )
     )
     OR EXISTS (
       SELECT 1 FROM public.lf_operation_contracts
       WHERE operation_code='ACTUALIZACION_PERFIL_LF'
         AND contract_code<>'CONTRACT-ACTUALIZACION-PERFIL-LF-v0.1'
     ) THEN
    RAISE EXCEPTION 'PE10_C4_CLASSIFY_CONTRACT_AUTHORITY_AMBIGUOUS';
  END IF;

  -- Every run snapshots the updater pass policy and every recorded judge is from
  -- the canonical v0.1 lineage (main judge or its pre-write binding judge).
  SELECT count(*)::int INTO v_eligible
  FROM public.lf_operation_execution e
  WHERE e.execution_id=ANY(v_ids)
    AND e.manifest#>>'{operation_policy_snapshots,PASS_POLICY,policy_code}'='POL-PROFILE-UPDATE-PASS'
    AND e.manifest#>>'{operation_policy_snapshots,PASS_POLICY,policy_version}' IN ('v1.0','v1.1')
    AND jsonb_array_length(
          coalesce(e.manifest#>'{operation_policy_snapshots,PASS_POLICY,policy_payload,required_steps}','[]'::jsonb)
        ) IN (14,15)
    AND NOT EXISTS (
      SELECT 1
      FROM public.lf_operation_execution_steps s
      WHERE s.execution_id=e.execution_id
        AND coalesce(s.evidence_payload->>'derived_by_judge','')
            NOT IN (
              'JUDGE-ACTUALIZACION-PERFIL-LF-v0.1',
              'JUDGE-ACTUALIZACION-PERFIL-LF-PREWRITE-BINDING-v1'
            )
    );
  IF v_eligible<>6 THEN
    RAISE EXCEPTION 'PE10_C4_CLASSIFY_LINEAGE_NOT_PROVEN:%',v_eligible;
  END IF;

  -- Test first: append the six classifications + patch C4's readback to consume
  -- append-only classification evidence, verify 24/0/24, then roll all of it back.
  BEGIN
    INSERT INTO public.lf_eventos(
      evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,payload,
      origen,created_at,created_by_execution_id
    )
    SELECT
      'PROFILE_UPDATE_LEGACY_CONTRACT_CLASSIFIED',
      'EXECUTION',
      e.execution_id,
      'Legacy updater execution contract classified without rewriting immutable manifest',
      'INFO',
      jsonb_build_object(
        'classification_status','VERIFIED',
        'classified_contract_code','CONTRACT-ACTUALIZACION-PERFIL-LF-v0.1',
        'operation_code',e.operation_code,
        'execution_started_at',e.started_at,
        'snapshot_policy_code',e.manifest#>>'{operation_policy_snapshots,PASS_POLICY,policy_code}',
        'snapshot_policy_version',e.manifest#>>'{operation_policy_snapshots,PASS_POLICY,policy_version}',
        'snapshot_required_steps',
          jsonb_array_length(coalesce(e.manifest#>'{operation_policy_snapshots,PASS_POLICY,policy_payload,required_steps}','[]'::jsonb)),
        'authority_basis','ONLY_CANONICAL_UPDATER_CONTRACT_EXISTING_BEFORE_EXECUTION',
        'judge_lineage_verified',true,
        'execution_manifest_modified',false,
        'execution_status_changed',false,
        'classification_only',true
      ),
      'PE10_C4_LEGACY_CLASSIFICATION',
      clock_timestamp(),
      v_actor
    FROM public.lf_operation_execution e
    WHERE e.execution_id=ANY(v_ids)
      AND NOT EXISTS (
        SELECT 1 FROM public.lf_eventos ev
        WHERE ev.evento_tipo='PROFILE_UPDATE_LEGACY_CONTRACT_CLASSIFIED'
          AND ev.entidad_tipo='EXECUTION'
          AND ev.entidad_codigo=e.execution_id
          AND ev.payload->>'classification_status'='VERIFIED'
      );

    SELECT unit_metadata INTO v_meta
    FROM programacion.engineering_plan_units
    WHERE plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1' AND unit_code='PE10'
    FOR UPDATE;

    v_spec:=v_meta#>'{action_specs_v1,PE10_C4}';
    v_contract:=v_meta#>'{checkpoint_contracts,PE10_C4}';
    v_pack:=v_meta#>'{source_pack_v2,checkpoint_inputs,PE10_C4}';

    v_spec:=jsonb_set(v_spec,'{verification_queries}',jsonb_build_array(v_q),true);
    v_spec:=jsonb_set(v_spec,'{validator_contract,validation_input,assertion}',
      to_jsonb('resolved_open_v01_execution_count=0 AND open_unclassified=0'::text),true);
    v_contract:=jsonb_set(v_contract,'{validation_input,queries}',jsonb_build_array(v_q),true);
    v_pack:=jsonb_set(v_pack,'{inputs,queries}',jsonb_build_array(v_q),true);
    v_pack:=jsonb_set(v_pack,'{inputs,db_objects}',
      jsonb_build_array('public.lf_operation_execution','public.lf_eventos'),true);
    v_pack:=jsonb_set(v_pack,'{inputs,events}',
      jsonb_build_array('PROFILE_UPDATE_LEGACY_CONTRACT_CLASSIFIED'),true);

    v_meta:=jsonb_set(v_meta,'{action_specs_v1,PE10_C4}',v_spec,false);
    v_meta:=jsonb_set(v_meta,'{checkpoint_contracts,PE10_C4}',v_contract,false);
    v_meta:=jsonb_set(v_meta,'{source_pack_v2,checkpoint_inputs,PE10_C4}',v_pack,true);
    v_meta:=jsonb_set(v_meta,'{phase_separation_v1,cutover_checkpoints_v1,c4}',
      to_jsonb('24_OPEN_RESOLVED_V01_0_UNCLASSIFIED_REQUIRE_PER_EXECUTION_DRAIN'::text),true);

    UPDATE programacion.engineering_plan_units
    SET unit_metadata=v_meta
    WHERE plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1' AND unit_code='PE10';

    v_packet:=programacion.fn_engineering_execution_packet_from_spec_v1(
      'PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1','PE10','PE10_C4',v_spec,v_pack);
    IF v_packet->>'status' IS DISTINCT FROM 'READY' THEN
      RAISE EXCEPTION 'PE10_C4_CLASSIFY_DRY_PACKET_NOT_READY:%',v_packet->'block_reasons';
    END IF;

    EXECUTE v_q INTO v_v01,v_unclassified,v_open;
    IF v_v01<>24 OR v_unclassified<>0 OR v_open<>24 THEN
      RAISE EXCEPTION 'PE10_C4_CLASSIFY_DRY_READBACK_FAILED v01=% unclassified=% total=%',
        v_v01,v_unclassified,v_open;
    END IF;

    RAISE EXCEPTION 'PE10_C4_CLASSIFY_DRY_RUN_ROLLBACK_SENTINEL';
  EXCEPTION
    WHEN SQLSTATE 'P0001' THEN
      IF SQLERRM<>'PE10_C4_CLASSIFY_DRY_RUN_ROLLBACK_SENTINEL' THEN
        RAISE;
      END IF;
  END;

  -- Prove dry-run rollback: no classification events persisted.
  SELECT count(*)::int INTO v_event_count
  FROM public.lf_eventos
  WHERE evento_tipo='PROFILE_UPDATE_LEGACY_CONTRACT_CLASSIFIED'
    AND entidad_tipo='EXECUTION'
    AND entidad_codigo=ANY(v_ids)
    AND payload->>'classification_status'='VERIFIED';
  IF v_event_count<>0 THEN
    RAISE EXCEPTION 'PE10_C4_CLASSIFY_DRY_ROLLBACK_EVENT_LEAK:%',v_event_count;
  END IF;

  -- Durable classification, still no execution manifest/status mutation.
  INSERT INTO public.lf_eventos(
    evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,payload,
    origen,created_at,created_by_execution_id
  )
  SELECT
    'PROFILE_UPDATE_LEGACY_CONTRACT_CLASSIFIED',
    'EXECUTION',
    e.execution_id,
    'Legacy updater execution contract classified without rewriting immutable manifest',
    'INFO',
    jsonb_build_object(
      'classification_status','VERIFIED',
      'classified_contract_code','CONTRACT-ACTUALIZACION-PERFIL-LF-v0.1',
      'operation_code',e.operation_code,
      'execution_started_at',e.started_at,
      'snapshot_policy_code',e.manifest#>>'{operation_policy_snapshots,PASS_POLICY,policy_code}',
      'snapshot_policy_version',e.manifest#>>'{operation_policy_snapshots,PASS_POLICY,policy_version}',
      'snapshot_required_steps',
        jsonb_array_length(coalesce(e.manifest#>'{operation_policy_snapshots,PASS_POLICY,policy_payload,required_steps}','[]'::jsonb)),
      'authority_basis','ONLY_CANONICAL_UPDATER_CONTRACT_EXISTING_BEFORE_EXECUTION',
      'judge_lineage_verified',true,
      'execution_manifest_modified',false,
      'execution_status_changed',false,
      'classification_only',true
    ),
    'PE10_C4_LEGACY_CLASSIFICATION',
    clock_timestamp(),
    v_actor
  FROM public.lf_operation_execution e
  WHERE e.execution_id=ANY(v_ids)
    AND NOT EXISTS (
      SELECT 1 FROM public.lf_eventos ev
      WHERE ev.evento_tipo='PROFILE_UPDATE_LEGACY_CONTRACT_CLASSIFIED'
        AND ev.entidad_tipo='EXECUTION'
        AND ev.entidad_codigo=e.execution_id
        AND ev.payload->>'classification_status'='VERIFIED'
    );

  IF (SELECT count(*) FROM public.lf_eventos
      WHERE evento_tipo='PROFILE_UPDATE_LEGACY_CONTRACT_CLASSIFIED'
        AND entidad_tipo='EXECUTION'
        AND entidad_codigo=ANY(v_ids)
        AND payload->>'classification_status'='VERIFIED')<>6 THEN
    RAISE EXCEPTION 'PE10_C4_CLASSIFY_EVENT_PERSIST_FAILED';
  END IF;

  SELECT unit_metadata INTO v_meta
  FROM programacion.engineering_plan_units
  WHERE plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1' AND unit_code='PE10'
  FOR UPDATE;

  v_spec:=v_meta#>'{action_specs_v1,PE10_C4}';
  v_contract:=v_meta#>'{checkpoint_contracts,PE10_C4}';
  v_pack:=v_meta#>'{source_pack_v2,checkpoint_inputs,PE10_C4}';

  v_spec:=jsonb_set(v_spec,'{verification_queries}',jsonb_build_array(v_q),true);
  v_spec:=jsonb_set(v_spec,'{validator_contract,validation_input,assertion}',
    to_jsonb('resolved_open_v01_execution_count=0 AND open_unclassified=0'::text),true);
  v_contract:=jsonb_set(v_contract,'{validation_input,queries}',jsonb_build_array(v_q),true);
  v_pack:=jsonb_set(v_pack,'{inputs,queries}',jsonb_build_array(v_q),true);
  v_pack:=jsonb_set(v_pack,'{inputs,db_objects}',
    jsonb_build_array('public.lf_operation_execution','public.lf_eventos'),true);
  v_pack:=jsonb_set(v_pack,'{inputs,events}',
    jsonb_build_array('PROFILE_UPDATE_LEGACY_CONTRACT_CLASSIFIED'),true);

  v_meta:=jsonb_set(v_meta,'{action_specs_v1,PE10_C4}',v_spec,false);
  v_meta:=jsonb_set(v_meta,'{checkpoint_contracts,PE10_C4}',v_contract,false);
  v_meta:=jsonb_set(v_meta,'{source_pack_v2,checkpoint_inputs,PE10_C4}',v_pack,true);
  v_meta:=jsonb_set(v_meta,'{phase_separation_v1,cutover_checkpoints_v1,c4}',
    to_jsonb('24_OPEN_RESOLVED_V01_0_UNCLASSIFIED_REQUIRE_PER_EXECUTION_DRAIN'::text),true);

  UPDATE programacion.engineering_plan_units
  SET unit_metadata=v_meta
  WHERE plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1' AND unit_code='PE10';

  v_packet:=programacion.fn_engineering_execution_packet_from_spec_v1(
    'PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1','PE10','PE10_C4',v_spec,v_pack);
  IF v_packet->>'status' IS DISTINCT FROM 'READY' THEN
    RAISE EXCEPTION 'PE10_C4_CLASSIFY_PACKET_NOT_READY:%',v_packet->'block_reasons';
  END IF;

  EXECUTE v_q INTO v_v01,v_unclassified,v_open;
  IF v_v01<>24 OR v_unclassified<>0 OR v_open<>24 THEN
    RAISE EXCEPTION 'PE10_C4_CLASSIFY_FINAL_READBACK_FAILED v01=% unclassified=% total=%',
      v_v01,v_unclassified,v_open;
  END IF;

  -- Immutable-ledger assertion.
  IF (SELECT count(*) FROM public.lf_operation_execution
      WHERE execution_id=ANY(v_ids)
        AND status='IN_PROGRESS'
        AND nullif(manifest->>'contract_code','') IS NULL)<>6 THEN
    RAISE EXCEPTION 'PE10_C4_CLASSIFY_IMMUTABILITY_BREACH';
  END IF;
END
$pe10$;

INSERT INTO public.lf_error_knowledge
(codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
 severidad,frecuencia,primera_vez,ultima_vez,lote_origen,estado,source_ref)
SELECT
 'LF-PE10-C4-LEGACY-CONTRACT-CLASSIFY-IMMUTABLE-20261013-001',
 'PROFILE_EVOLUTION',
 'Legacy contract classification must not rewrite immutable execution manifests',
 'Six updater executions had no manifest.contract_code even though the only canonical updater contract v0.1 predated all runs and their policy/judge lineage is v0.1. Rewriting manifests would destroy historical fidelity.',
 'The cutover gate originally interpreted missing contract_code as unclassified without an append-only classification overlay.',
 'Historical execution lacks a field introduced after execution start',
 'Classify through append-only PROFILE_UPDATE_LEGACY_CONTRACT_CLASSIFIED events, bind the gate readback to manifest-or-verified-classification resolution, and preserve the original manifest/status unchanged.',
 'Rollback rehearsal must yield resolved 24 v0.1 / 0 unclassified / 24 total, persist exactly six classification events, compile PE10_C4 READY, and prove all six original manifests still lack contract_code.',
 'HIGH',1,clock_timestamp(),clock_timestamp(),
 'PE10_C4_LEGACY_CLASSIFICATION','ACTIVO',
 'supabase://public/lf_eventos/PROFILE_UPDATE_LEGACY_CONTRACT_CLASSIFIED;supabase://programacion.engineering_plan_units/PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1/PE10'
WHERE NOT EXISTS (
  SELECT 1 FROM public.lf_error_knowledge
  WHERE codigo='LF-PE10-C4-LEGACY-CONTRACT-CLASSIFY-IMMUTABLE-20261013-001'
);

COMMIT;

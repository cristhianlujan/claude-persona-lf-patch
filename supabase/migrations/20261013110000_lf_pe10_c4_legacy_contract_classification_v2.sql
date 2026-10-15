BEGIN;

-- PE10_C4 legacy contract classification V2.
-- Fixes the rejected V1 source by governing the new event type before use.
-- Scope: append-only classification + PE10_C4 readback/governance parity.
-- No execution close, no execution-manifest rewrite, no runtime/v0.2 activation.
DO $pe10$
DECLARE
  v_actor constant text := 'EXEC-SUPERADMIN-PE10-C4-CLASSIFY-20261013-002';
  v_event_type constant text := 'PROFILE_UPDATE_LEGACY_CONTRACT_CLASSIFIED';
  v_ids constant text[] := ARRAY[
    'EXEC-ACTUALIZACION-PERFIL-UI-ARCHITECT-S26-N08C-REPAIR-20260908-001',
    'EXEC-ACTUALIZACION-PERFIL-UI-ARCHITECT-S26-UPSTREAM-BINDING-20260908-002',
    'EXEC-LF-SRCR-PROFILE-RUNTIME-BOUNDED-20260919-001',
    'EXEC-LF-SRCR-PROFILE-PARTITION-V1-20260919-001',
    'EXEC-ACTUALIZACION-PERFIL-SRCR-CLOSURE-20260919-001',
    'EXEC-ACTUALIZACION-PERFIL-SRCR-CLOSURE-20260919-002'
  ];
  v_proposed_contract constant jsonb := jsonb_build_object(
    'active',true,
    'rationale','Append-only operational classification of immutable legacy updater executions; never declares acceptance or closure.',
    'contract_mode','OPERATIONAL',
    'allowed_evidence_schemas',jsonb_build_array('operational-event/v2')
  );
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
    AND ev.payload->>'classification_status'='OBSERVED'
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
       )::int AS open_v01_resolved,
       count(*) FILTER (WHERE unclassified)::int AS open_unclassified,
       count(*)::int AS open_total
FROM resolved
$q$;
  v_meta jsonb;
  v_spec jsonb;
  v_contract jsonb;
  v_pack jsonb;
  v_packet jsonb;
  v_request bigint;
  v_approval bigint;
  v_contract_hash text;
  v_open integer;
  v_v01 integer;
  v_unclassified integer;
  v_eligible integer;
  v_events integer;
BEGIN
  -- EKB/readback-driven preflight: failed V1 must have left no DB effects.
  IF EXISTS (
    SELECT 1 FROM supabase_migrations.schema_migrations
    WHERE version='20261013104500'
  ) THEN
    RAISE EXCEPTION 'PE10_C4_V1_UNEXPECTED_LEDGER_EFFECT';
  END IF;

  IF EXISTS (
    SELECT 1 FROM private.lf_event_type_contracts_v2
    WHERE event_type=v_event_type
  ) OR EXISTS (
    SELECT 1 FROM public.lf_eventos
    WHERE evento_tipo=v_event_type
  ) THEN
    RAISE EXCEPTION 'PE10_C4_CLASSIFICATION_ALREADY_MATERIALIZED';
  END IF;

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

  -- Only one updater contract exists and it predates all six historical runs.
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
     ) THEN
    RAISE EXCEPTION 'PE10_C4_CLASSIFY_CONTRACT_AUTHORITY_AMBIGUOUS';
  END IF;

  -- Every run snapshots the updater PASS policy and all already-recorded judge
  -- evidence belongs to the canonical v0.1 lineage.
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

  ---------------------------------------------------------------------------
  -- TEST FIRST: exact governance + six event writes + C4 metadata patch,
  -- then deliberate subtransaction rollback.
  ---------------------------------------------------------------------------
  BEGIN
    v_request := private.fn_create_lf_event_type_contract_request_v2(
      v_event_type,'INSERT',v_proposed_contract,v_actor
    );
    SELECT proposed_contract_sha256 INTO v_contract_hash
    FROM private.lf_event_type_contract_change_requests_v2
    WHERE id=v_request;

    INSERT INTO public.lf_eventos(
      evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,payload,
      origen,created_at,created_by_execution_id
    ) VALUES (
      'EVENT_TYPE_CONTRACT_CHANGE_APPROVED',
      'EVENT_TYPE_CONTRACT',
      v_event_type,
      'SUPER_ADMIN governed approval for legacy updater classification event contract',
      'INFO',
      jsonb_build_object(
        'evidence_schema_version','event-type-contract-governance/v1',
        'decision','APPROVED',
        'request_id',v_request,
        'event_type',v_event_type,
        'proposed_contract_sha256',v_contract_hash,
        'approved_at',clock_timestamp(),
        'execution_id',v_actor
      ),
      'DERIVE_FROM_EXECUTION_ID',
      clock_timestamp(),
      v_actor
    ) RETURNING id INTO v_approval;

    PERFORM private.fn_approve_lf_event_type_contract_request_v2(v_request,v_approval);
    PERFORM private.fn_apply_lf_event_type_contract_change_v2(v_request);

    IF NOT EXISTS (
      SELECT 1 FROM private.lf_event_type_contracts_v2
      WHERE event_type=v_event_type
        AND active
        AND contract_mode='OPERATIONAL'
        AND allowed_evidence_schemas=ARRAY['operational-event/v2']::text[]
        AND governance_state='GOVERNED_V2'
    ) THEN
      RAISE EXCEPTION 'PE10_C4_DRY_EVENT_CONTRACT_NOT_GOVERNED';
    END IF;

    INSERT INTO public.lf_eventos(
      evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,payload,
      origen,created_at,created_by_execution_id
    )
    SELECT
      v_event_type,
      'EXECUTION',
      e.execution_id,
      'Immutable legacy updater contract classification observed; no acceptance or closure declared',
      'INFO',
      jsonb_build_object(
        'evidence_schema_version','operational-event/v2',
        'execution_id',v_actor,
        'producer','PE10_C4_LEGACY_CLASSIFIER_V2',
        'purpose','Record immutable legacy updater contract classification without acceptance',
        'acceptance_declared',false,
        'occurred_at',clock_timestamp(),
        'classification_status','OBSERVED',
        'classified_contract_code','CONTRACT-ACTUALIZACION-PERFIL-LF-v0.1',
        'operation_code',e.operation_code,
        'execution_started_at',e.started_at,
        'snapshot_policy_code',e.manifest#>>'{operation_policy_snapshots,PASS_POLICY,policy_code}',
        'snapshot_policy_version',e.manifest#>>'{operation_policy_snapshots,PASS_POLICY,policy_version}',
        'snapshot_required_steps',
          jsonb_array_length(coalesce(e.manifest#>'{operation_policy_snapshots,PASS_POLICY,policy_payload,required_steps}','[]'::jsonb)),
        'authority_basis','ONLY_CANONICAL_UPDATER_CONTRACT_EXISTING_BEFORE_EXECUTION',
        'judge_lineage_observed',true,
        'execution_manifest_modified',false,
        'execution_status_changed',false,
        'classification_only',true
      ),
      'DERIVE_FROM_EXECUTION_ID',
      clock_timestamp(),
      v_actor
    FROM public.lf_operation_execution e
    WHERE e.execution_id=ANY(v_ids);

    IF (SELECT count(*) FROM public.lf_eventos
        WHERE evento_tipo=v_event_type
          AND entidad_tipo='EXECUTION'
          AND entidad_codigo=ANY(v_ids)
          AND payload->>'classification_status'='OBSERVED')<>6 THEN
      RAISE EXCEPTION 'PE10_C4_DRY_CLASSIFICATION_EVENT_COUNT_FAILED';
    END IF;

    SELECT unit_metadata INTO v_meta
    FROM programacion.engineering_plan_units
    WHERE plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1'
      AND unit_code='PE10'
    FOR UPDATE;

    v_spec:=v_meta#>'{action_specs_v1,PE10_C4}';
    v_contract:=v_meta#>'{checkpoint_contracts,PE10_C4}';
    v_pack:=v_meta#>'{source_pack_v2,checkpoint_inputs,PE10_C4}';

    v_spec:=jsonb_set(v_spec,'{verification_queries}',jsonb_build_array(v_q),true);
    v_spec:=jsonb_set(v_spec,'{validator_contract,validation_input,assertion}',
      to_jsonb('resolved_open_v01_execution_count=0 AND open_unclassified=0'::text),true);
    v_spec:=jsonb_set(v_spec,'{assertion_contract,pass_when}',
      jsonb_build_object('open_v01_resolved',0,'open_unclassified',0,'open_total',0),true);
    v_contract:=jsonb_set(v_contract,'{validation_input,queries}',jsonb_build_array(v_q),true);
    v_pack:=jsonb_set(v_pack,'{inputs,queries}',jsonb_build_array(v_q),true);
    v_pack:=jsonb_set(v_pack,'{inputs,db_objects}',
      jsonb_build_array(
        'public.lf_operation_execution',
        'public.lf_eventos',
        'private.lf_event_type_contracts_v2'
      ),true);
    v_pack:=jsonb_set(v_pack,'{inputs,events}',jsonb_build_array(v_event_type),true);

    v_meta:=jsonb_set(v_meta,'{action_specs_v1,PE10_C4}',v_spec,false);
    v_meta:=jsonb_set(v_meta,'{checkpoint_contracts,PE10_C4}',v_contract,false);
    v_meta:=jsonb_set(v_meta,'{source_pack_v2,checkpoint_inputs,PE10_C4}',v_pack,true);
    v_meta:=jsonb_set(v_meta,'{phase_separation_v1,cutover_checkpoints_v1,c4}',
      to_jsonb('24_OPEN_RESOLVED_V01_0_UNCLASSIFIED_REQUIRE_PER_EXECUTION_DRAIN'::text),true);

    UPDATE programacion.engineering_plan_units
    SET unit_metadata=v_meta
    WHERE plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1'
      AND unit_code='PE10';

    v_packet:=programacion.fn_engineering_execution_packet_from_spec_v1(
      'PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1','PE10','PE10_C4',v_spec,v_pack
    );
    IF v_packet->>'status' IS DISTINCT FROM 'READY' THEN
      RAISE EXCEPTION 'PE10_C4_DRY_PACKET_NOT_READY:%',v_packet->'block_reasons';
    END IF;

    EXECUTE v_q INTO v_v01,v_unclassified,v_open;
    IF v_v01<>24 OR v_unclassified<>0 OR v_open<>24 THEN
      RAISE EXCEPTION
        'PE10_C4_DRY_READBACK_FAILED v01=% unclassified=% total=%',
        v_v01,v_unclassified,v_open;
    END IF;

    RAISE EXCEPTION 'PE10_C4_CLASSIFY_DRY_RUN_ROLLBACK_SENTINEL';
  EXCEPTION
    WHEN SQLSTATE 'P0001' THEN
      IF SQLERRM<>'PE10_C4_CLASSIFY_DRY_RUN_ROLLBACK_SENTINEL' THEN
        RAISE;
      END IF;
  END;

  -- Prove rehearsal rollback, including governed event-type registration.
  IF EXISTS (
    SELECT 1 FROM private.lf_event_type_contracts_v2
    WHERE event_type=v_event_type
  ) OR EXISTS (
    SELECT 1 FROM public.lf_eventos
    WHERE evento_tipo=v_event_type
  ) OR EXISTS (
    SELECT 1 FROM private.lf_event_type_contract_change_requests_v2
    WHERE event_type=v_event_type
  ) THEN
    RAISE EXCEPTION 'PE10_C4_DRY_RUN_ROLLBACK_FAILED';
  END IF;

  ---------------------------------------------------------------------------
  -- DURABLE REPLAY: same governed path after successful rollback rehearsal.
  ---------------------------------------------------------------------------
  v_request := private.fn_create_lf_event_type_contract_request_v2(
    v_event_type,'INSERT',v_proposed_contract,v_actor
  );
  SELECT proposed_contract_sha256 INTO v_contract_hash
  FROM private.lf_event_type_contract_change_requests_v2
  WHERE id=v_request;

  INSERT INTO public.lf_eventos(
    evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,payload,
    origen,created_at,created_by_execution_id
  ) VALUES (
    'EVENT_TYPE_CONTRACT_CHANGE_APPROVED',
    'EVENT_TYPE_CONTRACT',
    v_event_type,
    'SUPER_ADMIN governed approval for legacy updater classification event contract',
    'INFO',
    jsonb_build_object(
      'evidence_schema_version','event-type-contract-governance/v1',
      'decision','APPROVED',
      'request_id',v_request,
      'event_type',v_event_type,
      'proposed_contract_sha256',v_contract_hash,
      'approved_at',clock_timestamp(),
      'execution_id',v_actor
    ),
    'DERIVE_FROM_EXECUTION_ID',
    clock_timestamp(),
    v_actor
  ) RETURNING id INTO v_approval;

  PERFORM private.fn_approve_lf_event_type_contract_request_v2(v_request,v_approval);
  PERFORM private.fn_apply_lf_event_type_contract_change_v2(v_request);

  INSERT INTO public.lf_eventos(
    evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,payload,
    origen,created_at,created_by_execution_id
  )
  SELECT
    v_event_type,
    'EXECUTION',
    e.execution_id,
    'Immutable legacy updater contract classification observed; no acceptance or closure declared',
    'INFO',
    jsonb_build_object(
      'evidence_schema_version','operational-event/v2',
      'execution_id',v_actor,
      'producer','PE10_C4_LEGACY_CLASSIFIER_V2',
      'purpose','Record immutable legacy updater contract classification without acceptance',
      'acceptance_declared',false,
      'occurred_at',clock_timestamp(),
      'classification_status','OBSERVED',
      'classified_contract_code','CONTRACT-ACTUALIZACION-PERFIL-LF-v0.1',
      'operation_code',e.operation_code,
      'execution_started_at',e.started_at,
      'snapshot_policy_code',e.manifest#>>'{operation_policy_snapshots,PASS_POLICY,policy_code}',
      'snapshot_policy_version',e.manifest#>>'{operation_policy_snapshots,PASS_POLICY,policy_version}',
      'snapshot_required_steps',
        jsonb_array_length(coalesce(e.manifest#>'{operation_policy_snapshots,PASS_POLICY,policy_payload,required_steps}','[]'::jsonb)),
      'authority_basis','ONLY_CANONICAL_UPDATER_CONTRACT_EXISTING_BEFORE_EXECUTION',
      'judge_lineage_observed',true,
      'execution_manifest_modified',false,
      'execution_status_changed',false,
      'classification_only',true
    ),
    'DERIVE_FROM_EXECUTION_ID',
    clock_timestamp(),
    v_actor
  FROM public.lf_operation_execution e
  WHERE e.execution_id=ANY(v_ids);

  IF (SELECT count(*) FROM public.lf_eventos
      WHERE evento_tipo=v_event_type
        AND entidad_tipo='EXECUTION'
        AND entidad_codigo=ANY(v_ids)
        AND payload->>'classification_status'='OBSERVED')<>6 THEN
    RAISE EXCEPTION 'PE10_C4_CLASSIFICATION_EVENT_PERSIST_FAILED';
  END IF;

  SELECT unit_metadata INTO v_meta
  FROM programacion.engineering_plan_units
  WHERE plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1'
    AND unit_code='PE10'
  FOR UPDATE;

  v_spec:=v_meta#>'{action_specs_v1,PE10_C4}';
  v_contract:=v_meta#>'{checkpoint_contracts,PE10_C4}';
  v_pack:=v_meta#>'{source_pack_v2,checkpoint_inputs,PE10_C4}';

  v_spec:=jsonb_set(v_spec,'{verification_queries}',jsonb_build_array(v_q),true);
  v_spec:=jsonb_set(v_spec,'{validator_contract,validation_input,assertion}',
    to_jsonb('resolved_open_v01_execution_count=0 AND open_unclassified=0'::text),true);
  v_spec:=jsonb_set(v_spec,'{assertion_contract,pass_when}',
    jsonb_build_object('open_v01_resolved',0,'open_unclassified',0,'open_total',0),true);
  v_contract:=jsonb_set(v_contract,'{validation_input,queries}',jsonb_build_array(v_q),true);
  v_pack:=jsonb_set(v_pack,'{inputs,queries}',jsonb_build_array(v_q),true);
  v_pack:=jsonb_set(v_pack,'{inputs,db_objects}',
    jsonb_build_array(
      'public.lf_operation_execution',
      'public.lf_eventos',
      'private.lf_event_type_contracts_v2'
    ),true);
  v_pack:=jsonb_set(v_pack,'{inputs,events}',jsonb_build_array(v_event_type),true);

  v_meta:=jsonb_set(v_meta,'{action_specs_v1,PE10_C4}',v_spec,false);
  v_meta:=jsonb_set(v_meta,'{checkpoint_contracts,PE10_C4}',v_contract,false);
  v_meta:=jsonb_set(v_meta,'{source_pack_v2,checkpoint_inputs,PE10_C4}',v_pack,true);
  v_meta:=jsonb_set(v_meta,'{phase_separation_v1,cutover_checkpoints_v1,c4}',
    to_jsonb('24_OPEN_RESOLVED_V01_0_UNCLASSIFIED_REQUIRE_PER_EXECUTION_DRAIN'::text),true);

  UPDATE programacion.engineering_plan_units
  SET unit_metadata=v_meta
  WHERE plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1'
    AND unit_code='PE10';

  v_packet:=programacion.fn_engineering_execution_packet_from_spec_v1(
    'PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1','PE10','PE10_C4',v_spec,v_pack
  );
  IF v_packet->>'status' IS DISTINCT FROM 'READY' THEN
    RAISE EXCEPTION 'PE10_C4_PACKET_NOT_READY:%',v_packet->'block_reasons';
  END IF;

  EXECUTE v_q INTO v_v01,v_unclassified,v_open;
  IF v_v01<>24 OR v_unclassified<>0 OR v_open<>24 THEN
    RAISE EXCEPTION
      'PE10_C4_FINAL_READBACK_FAILED v01=% unclassified=% total=%',
      v_v01,v_unclassified,v_open;
  END IF;

  -- Immutable-ledger assertion: classification overlays history; it never rewrites it.
  IF (SELECT count(*) FROM public.lf_operation_execution
      WHERE execution_id=ANY(v_ids)
        AND status='IN_PROGRESS'
        AND nullif(manifest->>'contract_code','') IS NULL)<>6 THEN
    RAISE EXCEPTION 'PE10_C4_CLASSIFY_IMMUTABILITY_BREACH';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM private.lf_event_type_contracts_v2
    WHERE event_type=v_event_type
      AND active
      AND governance_state='GOVERNED_V2'
      AND last_changed_by_execution_id=v_actor
  ) THEN
    RAISE EXCEPTION 'PE10_C4_EVENT_CONTRACT_FINAL_READBACK_FAILED';
  END IF;
END
$pe10$;

INSERT INTO public.lf_error_knowledge
(codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
 severidad,frecuencia,primera_vez,ultima_vez,lote_origen,estado,source_ref)
SELECT *
FROM (VALUES
(
 'LF-PE10-C4-EVENT-TYPE-DEFAULT-DENY-20261013-001',
 'PROFILE_EVOLUTION',
 'Classification migration rejected because new lf_eventos type was not governed first',
 'PR 2386 reached LF Migration Merge Train exact apply but PostgreSQL rejected the migration before apply/ledger completion. The source attempted PROFILE_UPDATE_LEGACY_CONTRACT_CLASSIFIED before registering its event-type contract.',
 'public.lf_eventos is default-deny for unregistered evento_tipo through trg_01_lf_eventos_type_contract_v2. Constraint-only preflight missed active triggers and event-contract governance.',
 'New append-only event type introduced without trigger/registry preflight',
 'Before any new lf_eventos write, inspect table triggers plus private.lf_event_type_contracts_v2. If a new type is necessary, use fn_create_lf_event_type_contract_request_v2 -> typed approval event -> fn_approve -> fn_apply, and rehearse the whole chain under rollback before durable replay.',
 'V2 requires governed OPERATIONAL contract with operational-event/v2, rollback rehearsal, six classification events, PE10_C4 packet READY and 24 resolved v0.1 / 0 unclassified / 24 total. PR 2386 remains unmerged and its migration version absent.',
 'HIGH',1,clock_timestamp(),clock_timestamp(),
 'PE10_C4_LEGACY_CLASSIFICATION_V2','ACTIVO',
 'github://cristhianlujan/claude-persona-lf-patch/pull/2386'
),
(
 'LF-PE10-C4-LEGACY-CONTRACT-CLASSIFY-IMMUTABLE-20261013-001',
 'PROFILE_EVOLUTION',
 'Legacy contract classification must not rewrite immutable execution manifests',
 'Six updater executions have no manifest.contract_code although the only canonical updater contract v0.1 predates all six and their policy/judge lineage is v0.1.',
 'The cutover gate originally treated missing contract_code as unclassified without an append-only classification overlay.',
 'Historical execution lacks a field introduced after execution start',
 'Classify with governed append-only PROFILE_UPDATE_LEGACY_CONTRACT_CLASSIFIED operational events, bind C4 to manifest-or-classification resolution, and preserve original execution manifest/status.',
 'Final readback requires 24 resolved v0.1 / 0 unclassified / 24 total, exactly six classification events, packet READY, and all six historical manifests still missing contract_code.',
 'HIGH',1,clock_timestamp(),clock_timestamp(),
 'PE10_C4_LEGACY_CLASSIFICATION_V2','ACTIVO',
 'supabase://public/lf_eventos/PROFILE_UPDATE_LEGACY_CONTRACT_CLASSIFIED'
)
) AS x(
 codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
 severidad,frecuencia,primera_vez,ultima_vez,lote_origen,estado,source_ref
)
WHERE NOT EXISTS (
  SELECT 1 FROM public.lf_error_knowledge e WHERE e.codigo=x.codigo
);

COMMIT;

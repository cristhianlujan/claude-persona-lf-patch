-- T-DECCTX / PAULO-187 — bind N-16 as IG consumer of DECISION_CONTEXT_ASOF.
-- This migration does NOT execute, start, complete, or otherwise advance N-16 / PAULO-181.

DO $bind$
DECLARE
  v_manifest_sha text;
  v_unit_id bigint;
  v_work_item_id bigint;
  v_work_status text;
BEGIN
  SELECT c.manifest_sha256
    INTO v_manifest_sha
  FROM public.lf_capability_current c
  JOIN public.lf_capability_registry r USING(capability_code)
  WHERE c.capability_code='DECISION_CONTEXT_ASOF'
    AND c.version='1.0.0'
    AND r.status='ACTIVE'
    AND r.capability_kind='TRANSVERSAL'
    AND r.owner_scope='SUPER_ADMIN';

  IF NOT FOUND OR v_manifest_sha !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'BLOCK_T_DECCTX_CAPABILITY_NOT_CURRENT';
  END IF;

  SELECT pu.id,pu.work_item_id,wi.status
    INTO v_unit_id,v_work_item_id,v_work_status
  FROM programacion.engineering_plan_units pu
  JOIN programacion.engineering_work_items wi ON wi.id=pu.work_item_id
  WHERE pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
    AND pu.unit_code='N-16'
    AND wi.work_code='PAULO-181';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'BLOCK_T_DECCTX_N16_NOT_FOUND';
  END IF;
  IF v_work_status<>'BACKLOG' THEN
    RAISE EXCEPTION 'BLOCK_T_DECCTX_N16_NOT_BACKLOG:%',v_work_status;
  END IF;

  UPDATE programacion.engineering_plan_units
  SET unit_metadata = jsonb_set(
      coalesce(unit_metadata,'{}'::jsonb),
      '{transversalization_v1,event_pending}',
      'false'::jsonb,
      true
    ) || jsonb_build_object(
      'decision_context_asof_binding_v1',jsonb_build_object(
        'capability_code','DECISION_CONTEXT_ASOF',
        'version','1.0.0',
        'manifest_sha256',v_manifest_sha,
        'provider_owner','SUPER_ADMIN',
        'ig_role','CONSUMER',
        'binding_role','PLAN_ONLY',
        'execution_authorized',false,
        'unit_executed',false,
        'asof_semantics','HISTORICAL_RECEIPT_NOT_LATEST',
        'input_contract','LF_DECISION_CONTEXT_ASOF_INPUT_V1',
        'second_consumer_proof','STORY_CREATOR',
        'bound_by_work_code','PAULO-187',
        'source_ref','github://cristhianlujan/claude-persona-lf-patch/sandbox/lf_contract_gate_test/transversal_assets/decision_context_asof/README.md'
      )
    )
  WHERE id=v_unit_id;

  IF NOT EXISTS (
    SELECT 1
    FROM programacion.engineering_plan_units pu
    JOIN programacion.engineering_work_items wi ON wi.id=pu.work_item_id
    WHERE pu.id=v_unit_id
      AND wi.id=v_work_item_id
      AND wi.work_code='PAULO-181'
      AND wi.status='BACKLOG'
      AND pu.capability_ref='DECISION_CONTEXT_ASOF (CONSUME)'
      AND pu.unit_metadata#>>'{decision_context_asof_binding_v1,capability_code}'='DECISION_CONTEXT_ASOF'
      AND pu.unit_metadata#>>'{decision_context_asof_binding_v1,version}'='1.0.0'
      AND pu.unit_metadata#>>'{decision_context_asof_binding_v1,manifest_sha256}'=v_manifest_sha
      AND pu.unit_metadata#>>'{decision_context_asof_binding_v1,ig_role}'='CONSUMER'
      AND pu.unit_metadata#>>'{decision_context_asof_binding_v1,binding_role}'='PLAN_ONLY'
      AND (pu.unit_metadata#>>'{decision_context_asof_binding_v1,execution_authorized}')::boolean IS FALSE
      AND (pu.unit_metadata#>>'{decision_context_asof_binding_v1,unit_executed}')::boolean IS FALSE
      AND (pu.unit_metadata#>>'{transversalization_v1,event_pending}')::boolean IS FALSE
  ) THEN
    RAISE EXCEPTION 'BLOCK_T_DECCTX_N16_BINDING_READBACK';
  END IF;
END
$bind$;

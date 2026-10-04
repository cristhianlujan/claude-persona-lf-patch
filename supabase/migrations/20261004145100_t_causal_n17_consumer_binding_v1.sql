-- T-CAUSAL / PAULO-188 — bind N-17 as IG consumer of CAUSAL_EFFECT_LINEAGE.
-- This migration does NOT execute, start, complete, or otherwise advance N-17 / PAULO-182.

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
  WHERE c.capability_code='CAUSAL_EFFECT_LINEAGE'
    AND c.version='1.0.0'
    AND r.status='ACTIVE'
    AND r.capability_kind='TRANSVERSAL'
    AND r.owner_scope='SUPER_ADMIN';
  IF NOT FOUND OR v_manifest_sha !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'BLOCK_T_CAUSAL_CAPABILITY_NOT_CURRENT';
  END IF;

  SELECT pu.id,pu.work_item_id,wi.status
    INTO v_unit_id,v_work_item_id,v_work_status
  FROM programacion.engineering_plan_units pu
  JOIN programacion.engineering_work_items wi ON wi.id=pu.work_item_id
  WHERE pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
    AND pu.unit_code='N-17'
    AND wi.work_code='PAULO-182';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'BLOCK_T_CAUSAL_N17_NOT_FOUND';
  END IF;
  IF v_work_status<>'BACKLOG' THEN
    RAISE EXCEPTION 'BLOCK_T_CAUSAL_N17_NOT_BACKLOG:%',v_work_status;
  END IF;

  UPDATE programacion.engineering_plan_units
  SET unit_metadata = coalesce(unit_metadata,'{}'::jsonb) || jsonb_build_object(
    'causal_effect_lineage_binding_v1',jsonb_build_object(
      'capability_code','CAUSAL_EFFECT_LINEAGE',
      'version','1.0.0',
      'manifest_sha256',v_manifest_sha,
      'provider_owner','SUPER_ADMIN',
      'ig_role','CONSUMER',
      'binding_role','PLAN_ONLY',
      'execution_authorized',false,
      'unit_executed',false,
      'boundary','ASYNC_JOB',
      'receiver_readback_required',true,
      'binding_source','sandbox/lf_contract_gate_test/transversal_assets/causal_effect_lineage/ig_n17_consumer_binding_v1.json',
      'bound_by_work_code','PAULO-188'
    )
  )
  WHERE id=v_unit_id;

  IF NOT EXISTS (
    SELECT 1
    FROM programacion.engineering_plan_units pu
    JOIN programacion.engineering_work_items wi ON wi.id=pu.work_item_id
    WHERE pu.id=v_unit_id
      AND wi.id=v_work_item_id
      AND wi.work_code='PAULO-182'
      AND wi.status='BACKLOG'
      AND pu.capability_ref='CAUSAL_EFFECT_LINEAGE (CONSUME)'
      AND pu.unit_metadata#>>'{causal_effect_lineage_binding_v1,ig_role}'='CONSUMER'
      AND pu.unit_metadata#>>'{causal_effect_lineage_binding_v1,binding_role}'='PLAN_ONLY'
      AND (pu.unit_metadata#>>'{causal_effect_lineage_binding_v1,execution_authorized}')::boolean IS FALSE
      AND (pu.unit_metadata#>>'{causal_effect_lineage_binding_v1,unit_executed}')::boolean IS FALSE
      AND pu.unit_metadata#>>'{causal_effect_lineage_binding_v1,manifest_sha256}'=v_manifest_sha
  ) THEN
    RAISE EXCEPTION 'BLOCK_T_CAUSAL_N17_BINDING_READBACK';
  END IF;
END
$bind$;

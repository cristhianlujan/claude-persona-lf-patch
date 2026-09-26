-- Correct INDEPENDENT_ASSURANCE inventory ownership boundary.
-- EKB: S36-ASSURANCE-BOUNDARY-CONTAMINATION-001
-- Source-first candidate only; no lifecycle/owner-name/function changes.

DO $pre$
DECLARE
  v public.lf_activos%rowtype;
BEGIN
  SELECT * INTO v
  FROM public.lf_activos
  WHERE codigo_activo='INDEPENDENT_ASSURANCE';

  IF NOT FOUND
     OR v.id<>139
     OR v.archived_at IS NOT NULL
     OR v.estado_operativo<>'ACTIVO'
     OR v.owner_name IS NOT NULL
     OR v.metadata #>> '{transversal_inventory,inventory_status}' <> 'ACTIVE_SHARED_ENFORCEMENT'
     OR v.metadata #> '{transversal_inventory,physical_assets}' IS DISTINCT FROM
        '["REVISION_INDEPENDIENTE_ESTRATEGIA_LF","public.lf_finalize_qualification_independent_review_v1"]'::jsonb THEN
    RAISE EXCEPTION 'LF_INDEPENDENT_ASSURANCE_INVENTORY_PRESTATE_MISMATCH';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_operation_registry
    WHERE operation_code='REVISION_INDEPENDIENTE_ESTRATEGIA_LF'
      AND operation_type='INDEPENDENT_REVIEW'
      AND lifecycle_state_code='OP_OPERATIONAL'
  ) THEN
    RAISE EXCEPTION 'LF_INDEPENDENT_ASSURANCE_CANONICAL_OPERATION_NOT_OPERATIONAL';
  END IF;

  IF to_regprocedure('public.lf_finalize_qualification_independent_review_v1(uuid,text,jsonb)') IS NULL THEN
    RAISE EXCEPTION 'LF_QUALIFICATION_FINALIZER_MISSING';
  END IF;
END
$pre$;

UPDATE public.lf_activos
SET metadata = jsonb_set(
      metadata,
      '{transversal_inventory,physical_assets}',
      '["REVISION_INDEPENDIENTE_ESTRATEGIA_LF"]'::jsonb,
      false
    ),
    updated_at = clock_timestamp()
WHERE codigo_activo='INDEPENDENT_ASSURANCE';

DO $post$
DECLARE
  v public.lf_activos%rowtype;
BEGIN
  SELECT * INTO v
  FROM public.lf_activos
  WHERE codigo_activo='INDEPENDENT_ASSURANCE';

  IF v.metadata #> '{transversal_inventory,physical_assets}' IS DISTINCT FROM
       '["REVISION_INDEPENDIENTE_ESTRATEGIA_LF"]'::jsonb
     OR v.owner_name IS NOT NULL
     OR v.estado_operativo<>'ACTIVO'
     OR v.archived_at IS NOT NULL
     OR v.metadata #>> '{transversal_inventory,inventory_status}' <> 'ACTIVE_SHARED_ENFORCEMENT' THEN
    RAISE EXCEPTION 'LF_INDEPENDENT_ASSURANCE_INVENTORY_POSTSTATE_MISMATCH';
  END IF;

  -- The Qualification finalizer must continue to exist; it is removed only from
  -- Independent Review ownership inventory, not from Qualification Framework.
  IF to_regprocedure('public.lf_finalize_qualification_independent_review_v1(uuid,text,jsonb)') IS NULL THEN
    RAISE EXCEPTION 'LF_QUALIFICATION_FINALIZER_REMOVED_BY_INVENTORY_CLEANUP';
  END IF;
END
$post$;

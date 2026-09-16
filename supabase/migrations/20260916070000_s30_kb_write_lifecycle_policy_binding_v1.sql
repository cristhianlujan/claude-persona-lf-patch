-- S30 R19 / A2R: make the canonical EKB child operation lifecycle-executable.
-- Reuses the existing transversal lifecycle policy. No new policy, writer, table or router.

DO $pre$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.lf_operation_registry
    WHERE operation_code='ESCRITURA_BASE_CONOCIMIENTO_LF'
      AND lifecycle_state_code='OP_OPERATIONAL'
      AND status='APROBADO_PRODUCCION_CONTROLADA'
  ) THEN RAISE EXCEPTION 'S30_A2R_KB_WRITE_OPERATION_NOT_OPERATIONAL'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_policy_versions
    WHERE policy_code='POL-LF-OPERATION-LIFECYCLE'
      AND policy_version='v1.0'
      AND status='ACTIVE'
      AND superseded_at IS NULL
      AND policy_payload->>'scope'='TRANSVERSAL_LF_GOVERNANCE'
      AND policy_payload->>'policy_kind'='OPERATION_LIFECYCLE_POLICY'
  ) THEN RAISE EXCEPTION 'S30_A2R_TRANSVERSAL_LIFECYCLE_POLICY_NOT_ACTIVE'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_operation_execution
    WHERE execution_id='EXEC-S30-R19-AUTONOMOUS-20260915-001'
      AND operation_code='EJECUCION_ESTRATEGIA_LF'
  ) THEN RAISE EXCEPTION 'S30_A2R_R19_PROVENANCE_EXECUTION_MISSING'; END IF;
END
$pre$;

INSERT INTO public.lf_operation_policy_bindings(
  operation_code,policy_code,policy_role,required,distribution_modes,binding_status,
  created_by_execution_id,updated_by_execution_id
)
VALUES (
  'ESCRITURA_BASE_CONOCIMIENTO_LF',
  'POL-LF-OPERATION-LIFECYCLE',
  'GOVERNANCE_LIFECYCLE',
  true,
  ARRAY['ROUTER','DIRECT']::text[],
  'ACTIVE',
  'EXEC-S30-R19-AUTONOMOUS-20260915-001',
  'EXEC-S30-R19-AUTONOMOUS-20260915-001'
)
ON CONFLICT (operation_code,policy_code) DO UPDATE SET
  policy_role=excluded.policy_role,
  required=excluded.required,
  distribution_modes=excluded.distribution_modes,
  binding_status=excluded.binding_status,
  updated_by_execution_id=excluded.updated_by_execution_id,
  updated_at=clock_timestamp();

DO $post$
DECLARE
  c integer;
BEGIN
  SELECT count(*) INTO c
  FROM public.v_lf_operation_policy_snapshot
  WHERE operation_code='ESCRITURA_BASE_CONOCIMIENTO_LF'
    AND policy_role='GOVERNANCE_LIFECYCLE'
    AND policy_code='POL-LF-OPERATION-LIFECYCLE'
    AND policy_version='v1.0'
    AND policy_sha='973b5a0ad26433095066ff06b53c3043f38fef51d04e9482c458e178f20920e8'
    AND required;
  IF c<>1 THEN RAISE EXCEPTION 'S30_A2R_KB_WRITE_LIFECYCLE_POLICY_BINDING_NOT_RESOLVED:%',c; END IF;
END
$post$;

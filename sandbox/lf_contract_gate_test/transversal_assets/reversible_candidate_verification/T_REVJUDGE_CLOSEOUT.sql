-- T-REVJUDGE / PAULO-191 — governed closeout only.
-- Preconditions/readback are fail-closed. No candidate/runtime promotion or cutover.

begin;

DO $pre$
DECLARE
  v_count integer;
BEGIN
  -- Single governed unit/work item.
  SELECT count(*) INTO v_count
  FROM programacion.engineering_plan_units
  WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='T-REVJUDGE' AND work_item_id=887;
  IF v_count <> 1 THEN RAISE EXCEPTION 'BLOCK_T_REVJUDGE_UNIT_IDENTITY:%',v_count; END IF;

  -- Dependency N-9 must remain complete and untouched.
  IF NOT EXISTS (
    SELECT 1 FROM programacion.v_engineering_work_progress v
    JOIN programacion.engineering_plan_units u ON u.work_item_id=v.id
    WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND u.unit_code='N-9'
      AND v.status='DONE' AND v.done_checkpoint_count=7 AND v.required_checkpoint_count=7 AND v.open_blockers=0
  ) THEN RAISE EXCEPTION 'BLOCK_T_REVJUDGE_N9_NOT_PRESERVED'; END IF;

  -- Required transversal dependencies remain exactly current.
  IF NOT EXISTS (SELECT 1 FROM public.lf_capability_current WHERE capability_code='MIGRATION_SOURCE_PARITY' AND version='1.0.0' AND manifest_sha256='39bb96aa3668c9e82af061f80be658c093545c918ee8a18cc24c21c423df257e') THEN
    RAISE EXCEPTION 'BLOCK_T_REVJUDGE_MSP_CURRENTNESS';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.lf_capability_current WHERE capability_code='RUNTIME_DEPLOY_VERIFICATION' AND version='1.0.0' AND manifest_sha256='ee733461092d956da32ccd27607c0600a8d954a820a05feeae8a0e4fa3b779b9') THEN
    RAISE EXCEPTION 'BLOCK_T_REVJUDGE_RDV_CURRENTNESS';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.lf_capability_current WHERE capability_code='INDEPENDENT_ASSURANCE' AND version='1.0.0' AND manifest_sha256='a6f5e2fe21ed305b6d47e8722035685b243cfc4e697ff397d1724e5d34f6c6e8') THEN
    RAISE EXCEPTION 'BLOCK_T_REVJUDGE_IA_CURRENTNESS';
  END IF;

  -- Final capability contract/currentness.
  IF NOT EXISTS (
    SELECT 1
    FROM public.lf_capability_registry r
    JOIN public.lf_capability_current c USING(capability_code)
    JOIN public.lf_capability_version_registry vr
      ON vr.capability_code=c.capability_code AND vr.version=c.version AND vr.manifest_sha256=c.manifest_sha256
    WHERE r.capability_code='REVERSIBLE_CANDIDATE_VERIFICATION'
      AND r.owner_scope='SUPER_ADMIN' AND r.status='ACTIVE'
      AND c.version='1.0.1'
      AND c.manifest_sha256='b44e4eff5dac794835b4496036b76d28d883117b64c05aa03ee02309bceeb722'
      AND vr.release_state='RELEASED' AND vr.supersedes_version='1.0.0'
      AND coalesce((vr.manifest->'compatibility'->>'domain_agnostic_provider')::boolean,false)
      AND vr.manifest->'compatibility'->>'ig_role'='CONSUMER_ADAPTER'
      AND coalesce((vr.manifest->'compatibility'->>'n9_preserved')::boolean,false)
      AND coalesce((vr.manifest->'compatibility'->>'provider_knows_curator_validator_screens_families')::boolean,true)=false
      AND coalesce((vr.manifest->'compatibility'->>'special_domain_branch_in_provider')::boolean,true)=false
      AND coalesce((vr.manifest->'qualification'->>'non_ig_positive')::boolean,false)
      AND coalesce((vr.manifest->'qualification'->>'non_ig_negative')::boolean,false)
      AND coalesce((vr.manifest->'qualification'->>'rollback_failure_blocks')::boolean,false)
      AND coalesce((vr.manifest->'qualification'->>'independent_assurance_missing_blocks')::boolean,false)
      AND coalesce((vr.manifest->'qualification'->>'not_independent_blocks')::boolean,false)
      AND coalesce((vr.manifest->'qualification'->>'tampered_assurance_receipt_blocks')::boolean,false)
      AND (vr.manifest->'qualification'->>'n9_rollback_residue')::integer=0
  ) THEN RAISE EXCEPTION 'BLOCK_T_REVJUDGE_CAPABILITY_READBACK'; END IF;

  -- Exact source/ledger parity for v1.0.1.
  IF NOT EXISTS (
    SELECT 1 FROM supabase_migrations.schema_migrations
    WHERE version='20261004152145' AND name='t_revjudge_reversible_candidate_verification_v1_0_1'
  ) THEN RAISE EXCEPTION 'BLOCK_T_REVJUDGE_LEDGER_PARITY'; END IF;

  -- All four required checkpoints exist exactly once before closeout.
  SELECT count(*) INTO v_count
  FROM programacion.engineering_work_checkpoints
  WHERE work_item_id=887 AND required=true
    AND checkpoint_code IN ('EXTRACT_PRIOR_ART','NEG_ROLLBACK','NON_IG_CONSUMER','IG_BINDING');
  IF v_count <> 4 THEN RAISE EXCEPTION 'BLOCK_T_REVJUDGE_CHECKPOINT_SHAPE:%',v_count; END IF;
END
$pre$;

INSERT INTO transversal.error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,
  lote_origen,pr,estado,evidencia,lifecycle_phase,consumer_role,root_cause_family,detectability,
  source_context,source_ref,primera_vez,ultima_vez,frecuencia
) VALUES (
  'T-REVJUDGE-INDEPENDENCE-PIN-NOT-PROOF-001',
  'GOVERNANCE',
  'Pin de INDEPENDENT_ASSURANCE no prueba independencia del oracle',
  'Una capacidad consumidora puede fijar INDEPENDENT_ASSURANCE como dependencia y aun así quedar fail-open si no exige y valida un receipt de independencia en cada verificación material.',
  'REVERSIBLE_CANDIDATE_VERIFICATION v1.0.0 fijaba la capability transversal pero no exigía receipt call-time. La revisión contra T-INDEP mostró además dependencias compartidas en oracles IG existentes, por lo que una etiqueta independent no era evidencia suficiente.',
  'DEPENDENCY_PIN_WITHOUT_OPERATIONAL_RECEIPT',
  'Para cualquier verificación que requiera oracle independiente, exigir antes de ejecutar candidato: capability/version/manifest exactos de INDEPENDENT_ASSURANCE, estado INDEPENDENT, dimensiones dependency+data+author, evidence_refs y digest íntegro. Missing/UNPROVEN/NOT_INDEPENDENT/tampered => BLOCK.',
  'REVERSIBLE_CANDIDATE_VERIFICATION v1.0.1 qualified 8/8: missing receipt BLOCK, NOT_INDEPENDENT BLOCK, tampered digest BLOCK; IG positive+negative y no-IG positive+negative conservan rollback exacto y 0 residuos.',
  'HIGH',
  'T-REVJUDGE/PAULO-191',
  'PR#1620,PR#1622,PR#1623',
  'ACTIVO',
  'capability://REVERSIBLE_CANDIDATE_VERIFICATION@1.0.1 manifest=b44e4eff5dac794835b4496036b76d28d883117b64c05aa03ee02309bceeb722; lf_eventos#20017 T-INDEP; N9 positive PR1460/job110660596974; N9 negative PR1459/job110658154758; qualification cases=8 independence_gate=3',
  'PRE_APPLY',
  ARRAY['SUPER_ADMIN','IG']::text[],
  'R2_NO_VE',
  'LOUD_EARLY',
  'IG_CURATOR_VALIDATOR_REFACTOR_V2:T-REVJUDGE',
  'github://cristhianlujan/claude-persona-lf-patch/sandbox/lf_contract_gate_test/transversal_assets/reversible_candidate_verification/README.md',
  now(),now(),1
)
ON CONFLICT(codigo) DO UPDATE SET
  categoria=excluded.categoria,
  titulo=excluded.titulo,
  descripcion=excluded.descripcion,
  causa_raiz=excluded.causa_raiz,
  patron=excluded.patron,
  prevencion=excluded.prevencion,
  validacion=excluded.validacion,
  severidad=excluded.severidad,
  lote_origen=excluded.lote_origen,
  pr=excluded.pr,
  estado='ACTIVO',
  evidencia=excluded.evidencia,
  lifecycle_phase=excluded.lifecycle_phase,
  consumer_role=excluded.consumer_role,
  root_cause_family=excluded.root_cause_family,
  detectability=excluded.detectability,
  source_context=excluded.source_context,
  source_ref=excluded.source_ref,
  ultima_vez=now(),
  frecuencia=transversal.error_knowledge.frecuencia+1,
  updated_at=now();

UPDATE programacion.engineering_work_checkpoints
SET status='DONE',
    evidence_ref=CASE checkpoint_code
      WHEN 'EXTRACT_PRIOR_ART' THEN 'N-9 preserved DONE 7/7; lf_eventos#19824; REVERSIBLE_CANDIDATE_VERIFICATION@1.0.1 CURRENT b44e4eff5dac794835b4496036b76d28d883117b64c05aa03ee02309bceeb722'
      WHEN 'NEG_ROLLBACK' THEN 'qualification cases=8; rollback_failure=BLOCK; post-rollback exact; residue=0; N9 negative PR1459/job110658154758; independence missing/not-independent/tampered all BLOCK'
      WHEN 'NON_IG_CONSUMER' THEN 'TRANSACTIONAL_MAPPING_FLOW_V1: positive PASS + negative BLOCK + exact rollback; same provider core; domain_branches_in_core=0'
      WHEN 'IG_BINDING' THEN 'IG_N9_FLOW_ADAPTER_V1 + separate IG_N9_RAW_FLOW_ORACLE_V1; positive PR1460/job110660596974; negative PR1459/job110658154758; INDEPENDENT_ASSURANCE receipt required'
    END,
    completed_at=coalesce(completed_at,now()),
    updated_at=now(),
    updated_by_execution_id='CHATGPT-IG-T-REVJUDGE-PAULO-191-20261004'
WHERE work_item_id=887
  AND checkpoint_code IN ('EXTRACT_PRIOR_ART','NEG_ROLLBACK','NON_IG_CONSUMER','IG_BINDING');

UPDATE programacion.engineering_work_items
SET status='DONE',
    started_at=coalesce(started_at,now()),
    completed_at=coalesce(completed_at,now()),
    updated_at=now(),
    updated_by_execution_id='CHATGPT-IG-T-REVJUDGE-PAULO-191-20261004'
WHERE id=887 AND work_code='PAULO-191';

DO $post$
DECLARE
  v_count integer;
BEGIN
  SELECT count(*) INTO v_count
  FROM programacion.engineering_work_checkpoints
  WHERE work_item_id=887 AND required=true AND status='DONE';
  IF v_count <> 4 THEN RAISE EXCEPTION 'BLOCK_T_REVJUDGE_POST_CHECKPOINTS:%',v_count; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM programacion.v_engineering_work_progress
    WHERE id=887 AND work_code='PAULO-191' AND status='DONE'
      AND progress_pct=100 AND done_checkpoint_count=4 AND required_checkpoint_count=4 AND open_blockers=0
  ) THEN RAISE EXCEPTION 'BLOCK_T_REVJUDGE_POST_PROGRESS'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM programacion.v_engineering_work_progress v
    JOIN programacion.engineering_plan_units u ON u.work_item_id=v.id
    WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND u.unit_code='N-9'
      AND v.status='DONE' AND v.done_checkpoint_count=7 AND v.required_checkpoint_count=7 AND v.open_blockers=0
  ) THEN RAISE EXCEPTION 'BLOCK_T_REVJUDGE_POST_N9'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM transversal.error_knowledge
    WHERE codigo='T-REVJUDGE-INDEPENDENCE-PIN-NOT-PROOF-001' AND estado='ACTIVO'
  ) THEN RAISE EXCEPTION 'BLOCK_T_REVJUDGE_POST_EKB'; END IF;
END
$post$;

commit;

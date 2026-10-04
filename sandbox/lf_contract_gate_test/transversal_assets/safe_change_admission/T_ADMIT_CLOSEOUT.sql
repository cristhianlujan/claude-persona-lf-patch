-- T-ADMIT / PAULO-185 terminal closeout.
-- Operational state/evidence closure only. No runtime effects and no other IG unit state changes.

DO $closeout$
DECLARE
  v_exec constant text := 'CHATGPT-T-ADMIT-PAULO-185-20261004';
  v_cap_sha constant text := '267f85ca0ca96c4105d55fb1f5e4ca29a82e1f5e7134f0f5351e03a1693f8c7c';
  v_neg jsonb;
  v_non_ig jsonb;
  v_done_count integer;
BEGIN
  -- Generic contract/currentness readback.
  IF NOT EXISTS (
    SELECT 1
    FROM public.lf_capability_registry r
    JOIN public.lf_capability_current c USING(capability_code)
    JOIN public.lf_capability_version_registry vr
      ON vr.capability_code=c.capability_code
     AND vr.version=c.version
     AND vr.manifest_sha256=c.manifest_sha256
    WHERE r.capability_code='SAFE_CHANGE_ADMISSION'
      AND r.capability_kind='TRANSVERSAL'
      AND r.owner_scope='SUPER_ADMIN'
      AND r.status='ACTIVE'
      AND r.entry_guard_required=true
      AND r.entry_guard_code='ORCHESTRATOR_EXECUTION_GUARD_V1'
      AND c.version='1.0.0'
      AND c.manifest_sha256=v_cap_sha
      AND vr.release_state='RELEASED'
      AND vr.manifest#>>'{compatibility,domain_agnostic}'='true'
      AND vr.manifest#>>'{compatibility,ig_owner}'='false'
      AND vr.manifest#>>'{compatibility,executes_changes}'='false'
      AND vr.manifest#>>'{compatibility,runtime_mutation}'='false'
      AND vr.manifest#>>'{contract,recommendation_is_permission}'='false'
  ) THEN
    RAISE EXCEPTION 'BLOCK_T_ADMIT_CLOSEOUT_GENERIC_CONTRACT_READBACK';
  END IF;

  IF position('story_creator' in lower(pg_get_functiondef('public.lf_safe_change_admission_classify_v1(jsonb)'::regprocedure)))<>0
     OR position('m5.8' in lower(pg_get_functiondef('public.lf_safe_change_admission_classify_v1(jsonb)'::regprocedure)))<>0
     OR position('ig_curator' in lower(pg_get_functiondef('public.lf_safe_change_admission_classify_v1(jsonb)'::regprocedure)))<>0 THEN
    RAISE EXCEPTION 'BLOCK_T_ADMIT_CLOSEOUT_DOMAIN_BRANCH_FOUND';
  END IF;

  -- Permission negative: favorable/high-confidence recommendation is not permission.
  v_neg:=public.lf_safe_change_admission_classify_v1(
    '{"consumer_ref":"T-ADMIT-NEG_PERMISSION","evidence":{"items":[{"schema_version":"architecture-baseline/v1","payload":{"evidence_schema_version":"architecture-baseline/v1","blocked":0,"not_validated":0,"pass_with_evidence":1,"frozen_at":"2026-10-04T13:50:00Z","execution_id":"CHATGPT-T-ADMIT-NEG-20261004"}}]},"authority":{"state":"INSUFFICIENT","authority_ref":"event://20170"},"materiality":{"change_required":true,"scope_bounded":true,"level":"LOW"},"reversibility":{"state":"DEMONSTRATED","negative_proven":true,"rollback_proven":true,"readback_proven":true},"recommendation":{"state":"FAVORABLE","confidence":"HIGH"}}'::jsonb
  );
  IF v_neg->>'classification'<>'REQUIERE_DECISION'
     OR v_neg->>'code'<>'AUTHORITY_INSUFFICIENT'
     OR v_neg->>'execution_permission'<>'NO_EXECUTION_PERMISSION'
     OR coalesce((v_neg->>'effects_executed')::boolean,true) IS NOT FALSE THEN
    RAISE EXCEPTION 'BLOCK_T_ADMIT_CLOSEOUT_NEG_PERMISSION:%',v_neg::text;
  END IF;

  -- Real second consumer outside IG; no provider branch is needed.
  IF NOT EXISTS (
    SELECT 1 FROM programacion.engineering_plan_units
    WHERE plan_code='STORY_CREATOR_IMPLEMENTATION_SPEC_REFACTOR_V1'
  ) THEN
    RAISE EXCEPTION 'BLOCK_T_ADMIT_CLOSEOUT_NON_IG_CONSUMER_NOT_LIVE';
  END IF;
  v_non_ig:=public.lf_safe_change_admission_classify_v1(
    '{"consumer_ref":"STORY_CREATOR_IMPLEMENTATION_SPEC_REFACTOR_V1","evidence":{"items":[{"schema_version":"architecture-baseline/v1","payload":{"evidence_schema_version":"architecture-baseline/v1","blocked":0,"not_validated":0,"pass_with_evidence":1,"frozen_at":"2026-10-04T13:52:00Z","execution_id":"CHATGPT-T-ADMIT-NONIG-20261004"}}]},"authority":{"state":"INSUFFICIENT","authority_ref":"event://20170"},"materiality":{"change_required":false,"scope_bounded":true,"level":"LOW"},"reversibility":{"state":"NOT_DEMONSTRATED","negative_proven":false,"rollback_proven":false,"readback_proven":false},"recommendation":{"state":"FAVORABLE","confidence":"HIGH"}}'::jsonb
  );
  IF v_non_ig->>'classification'<>'VERIFY_NO_CHANGE'
     OR v_non_ig->>'execution_permission'<>'NO_EXECUTION_PERMISSION'
     OR coalesce((v_non_ig->>'effects_executed')::boolean,true) IS NOT FALSE THEN
    RAISE EXCEPTION 'BLOCK_T_ADMIT_CLOSEOUT_NON_IG:%',v_non_ig::text;
  END IF;

  -- Exact guarded IG binding for planned consumer M5.8; no M5.8 execution.
  IF NOT EXISTS (
    SELECT 1
    FROM public.lf_capability_binding b
    JOIN public.lf_capability_current c USING(capability_code)
    JOIN public.lf_operation_execution e USING(execution_id)
    WHERE b.execution_id='T-ADMIT-IG-M5-8-20261004-V1'
      AND b.capability_code='SAFE_CHANGE_ADMISSION'
      AND b.binding_state='BOUND'
      AND b.bound_version='1.0.0'
      AND b.bound_manifest_sha256=v_cap_sha
      AND b.bound_version=c.version
      AND b.bound_manifest_sha256=c.manifest_sha256
      AND e.status='COMPLETED'
      AND e.target_code='IG_CURATOR_VALIDATOR_REFACTOR_V2:M5.8'
      AND coalesce((e.checkpoint_payload->>'effects_executed')::boolean,true)=false
      AND e.checkpoint_payload->>'guard_code'='ORCHESTRATOR_EXECUTION_GUARD_V1'
  ) THEN
    RAISE EXCEPTION 'BLOCK_T_ADMIT_CLOSEOUT_IG_BINDING_READBACK';
  END IF;

  -- Git/source parity against applied ledger versions.
  IF NOT EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20261004135055' AND name='t_admit_safe_change_admission_v1')
     OR NOT EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20261004135653' AND name='t_admit_m5_8_safe_change_binding_v1') THEN
    RAISE EXCEPTION 'BLOCK_T_ADMIT_CLOSEOUT_MIGRATION_LEDGER_PARITY';
  END IF;

  -- EKB post: learned preflight requirement from the transactional first-apply rejection.
  INSERT INTO transversal.error_knowledge(
    codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,
    lote_origen,pr,estado,evidencia,lifecycle_phase,consumer_role,root_cause_family,detectability,
    source_context,source_ref,updated_at,ultima_vez
  ) VALUES (
    'T-ADMIT-CAPABILITY-MANIFEST-PREFLIGHT-001',
    'TRANSVERSAL_CAPABILITY',
    'Validar contrato estructural del manifest antes de promover una capability',
    'El primer apply de SAFE_CHANGE_ADMISSION fue rechazado transaccionalmente porque el manifest omitía delivery e installation, claves obligatorias del registry.',
    'La fuente se preparó sin leer previamente el CHECK estructural vigente de lf_capability_version_registry.',
    'Una capability puede ser semánticamente correcta y aun así ser inadmisible si su manifest no satisface la estructura gobernada live.',
    'Antes de crear/promover una nueva capability, leer las constraints live del version registry y validar todas las claves requeridas antes del merge/apply.',
    'El apply corregido debe ser atómico y el readback debe demostrar registry ACTIVE, version RELEASED y current pointer exacto.',
    'MEDIA',
    'T-ADMIT/PAULO-185',
    '#1604,#1607,#1609,#1610',
    'activo',
    'Primer apply rechazado por lf_capability_version_registry_manifest_check1; rollback transaccional sin persistencia parcial. Corrección #1607; capability CURRENT 1.0.0 sha 267f85ca0ca96c4105d55fb1f5e4ca29a82e1f5e7134f0f5351e03a1693f8c7c.',
    'construction',
    ARRAY['Architect','Builder','Verifier']::text[],
    'R2_NO_VE',
    'LOUD_EARLY',
    'IG_CURATOR_VALIDATOR_REFACTOR_V2:T-ADMIT',
    'github://cristhianlujan/claude-persona-lf-patch/sandbox/lf_contract_gate_test/transversal_assets/safe_change_admission/T_ADMIT_CLOSEOUT.sql',
    clock_timestamp(),clock_timestamp()
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
    estado=excluded.estado,
    evidencia=excluded.evidencia,
    lifecycle_phase=excluded.lifecycle_phase,
    consumer_role=excluded.consumer_role,
    root_cause_family=excluded.root_cause_family,
    detectability=excluded.detectability,
    source_context=excluded.source_context,
    source_ref=excluded.source_ref,
    updated_at=clock_timestamp(),
    ultima_vez=clock_timestamp();

  -- Four required checkpoints; evidence refs are immutable readback locators.
  UPDATE programacion.engineering_work_checkpoints
  SET status='DONE',
      evidence_ref=CASE checkpoint_code
        WHEN 'GENERIC_CONTRACT' THEN 'capability://SAFE_CHANGE_ADMISSION@1.0.0#267f85ca0ca96c4105d55fb1f5e4ca29a82e1f5e7134f0f5351e03a1693f8c7c'
        WHEN 'NEG_PERMISSION' THEN 'classification://T-ADMIT/NEG_PERMISSION#AUTHORITY_INSUFFICIENT:NO_EXECUTION_PERMISSION'
        WHEN 'NON_IG_CONSUMER' THEN 'classification://STORY_CREATOR_IMPLEMENTATION_SPEC_REFACTOR_V1#VERIFY_NO_CHANGE'
        WHEN 'IG_BINDING' THEN 'binding://T-ADMIT-IG-M5-8-20261004-V1/SAFE_CHANGE_ADMISSION@1.0.0#267f85ca0ca96c4105d55fb1f5e4ca29a82e1f5e7134f0f5351e03a1693f8c7c'
      END,
      completed_at=coalesce(completed_at,clock_timestamp()),
      updated_at=clock_timestamp(),
      updated_by_execution_id=v_exec
  WHERE work_item_id=881
    AND checkpoint_code IN ('GENERIC_CONTRACT','NEG_PERMISSION','NON_IG_CONSUMER','IG_BINDING');

  SELECT count(*) INTO v_done_count
  FROM programacion.engineering_work_checkpoints
  WHERE work_item_id=881
    AND required=true
    AND status='DONE'
    AND evidence_ref IS NOT NULL;
  IF v_done_count<>4 THEN
    RAISE EXCEPTION 'BLOCK_T_ADMIT_CLOSEOUT_CHECKPOINTS:%',v_done_count;
  END IF;

  UPDATE programacion.engineering_work_items
  SET status='DONE',
      started_at=coalesce(started_at,clock_timestamp()),
      completed_at=coalesce(completed_at,clock_timestamp()),
      updated_at=clock_timestamp(),
      updated_by_execution_id=v_exec
  WHERE id=881 AND work_code='PAULO-185';

  IF NOT EXISTS (
    SELECT 1 FROM programacion.engineering_work_items
    WHERE id=881 AND work_code='PAULO-185' AND status='DONE' AND completed_at IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'BLOCK_T_ADMIT_CLOSEOUT_TERMINAL_STATE';
  END IF;
END
$closeout$;

-- T-DECCTX / PAULO-187 terminal closeout.
-- Evidence/state closure only. N-16 remains BACKLOG and is not executed.

DO $closeout$
DECLARE
  v_exec constant text := 'CHATGPT-IG-T-DECCTX-PAULO-187-20261004';
  v_cap_sha constant text := '28b95beda0dc45e28c1c3e917dd105c7d7974f5f26fee50c0c2636229d425388';
  v_done_count integer;
  v_dep_done integer;
  v_terminal_count integer;
BEGIN
  SELECT count(*) INTO v_dep_done
  FROM programacion.engineering_work_dependencies d
  JOIN programacion.engineering_work_items wi ON wi.id=d.work_item_id
  JOIN programacion.engineering_work_items dep ON dep.id=d.depends_on_work_item_id
  WHERE wi.id=883
    AND wi.work_code='PAULO-187'
    AND dep.work_code IN ('PAULO-020','PAULO-027','PAULO-028')
    AND dep.status='DONE';
  IF v_dep_done<>3 THEN
    RAISE EXCEPTION 'BLOCK_T_DECCTX_DEPENDENCY_REFRESH:%',v_dep_done;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_eventos
    WHERE id=20170
      AND evento_tipo='ARCHITECTURE_V2_CLOSURE_EVALUATED'
      AND entidad_codigo='IGQ_BENCH_ANALYSIS_VALIDATION_V1:FINAL'
  ) THEN
    RAISE EXCEPTION 'BLOCK_T_DECCTX_SOURCE_EVENT_20170_NOT_CURRENT';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.lf_capability_registry r
    JOIN public.lf_capability_current c USING(capability_code)
    JOIN public.lf_capability_version_registry vr
      ON vr.capability_code=c.capability_code
     AND vr.version=c.version
     AND vr.manifest_sha256=c.manifest_sha256
    WHERE r.capability_code='DECISION_CONTEXT_ASOF'
      AND r.capability_kind='TRANSVERSAL'
      AND r.owner_scope='SUPER_ADMIN'
      AND r.status='ACTIVE'
      AND c.version='1.0.0'
      AND c.manifest_sha256=v_cap_sha
      AND vr.release_state='RELEASED'
      AND vr.manifest#>>'{contract,input}'='LF_DECISION_CONTEXT_ASOF_INPUT_V1'
      AND vr.manifest#>>'{contract,temporal_semantics}'='RECORDED_AS_OF_NOT_LATEST_MUTABLE'
      AND vr.manifest#>>'{currentness,authority}'='CURRENTNESS_AUTHORITY'
      AND vr.manifest#>>'{currentness,latest_is_asof}'='false'
      AND vr.manifest#>>'{compatibility,version_authority}'='CAPABILITY_VERSION_COMPATIBILITY'
      AND vr.manifest#>>'{compatibility,duplicate_temporal_authority_forbidden}'='true'
      AND vr.manifest#>>'{evidence,typed_registry}'='TYPED_EVIDENCE_REGISTRY'
      AND vr.manifest#>>'{evidence,registry_write}'='false'
      AND vr.manifest#>>'{evidence,authority_copy_forbidden}'='true'
      AND vr.manifest#>>'{evidence,references_and_digests_only}'='true'
      AND vr.manifest#>>'{consumers,ig_role}'='CONSUMER'
      AND vr.manifest#>>'{consumers,ig_binding}'='IG_CURATOR_VALIDATOR_REFACTOR_V2:N-16'
      AND vr.manifest#>>'{consumers,non_ig_supported}'='true'
  ) THEN
    RAISE EXCEPTION 'BLOCK_T_DECCTX_CLOSEOUT_CAPABILITY_READBACK';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_capability_current
    WHERE capability_code='CURRENTNESS_AUTHORITY'
      AND version='1.0.0'
      AND manifest_sha256='9f715dc226fd55a60c4002fa1960f848c4bf39e80b8863792eeef451073fce09'
  ) OR NOT EXISTS (
    SELECT 1 FROM public.lf_capability_current
    WHERE capability_code='CAPABILITY_VERSION_COMPATIBILITY'
      AND version='1.0.0'
      AND manifest_sha256='f2894a7f433ccd1c92f6f1bd4783c3e27b7f9b94ab28b4ab08b6732c92259bf1'
  ) OR NOT EXISTS (
    SELECT 1 FROM public.lf_capability_current
    WHERE capability_code='TYPED_EVIDENCE_REGISTRY'
      AND version='3.0.0'
      AND manifest_sha256='0fb00eeeb84567129bde17df0fac9f04c136a874518010a21af60c37810134da'
  ) THEN
    RAISE EXCEPTION 'BLOCK_T_DECCTX_CLOSEOUT_DEPENDENCY_DRIFT';
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='private'
      AND table_name='lf_decision_context_asof_v1'
      AND column_name ilike '%ig%'
  ) THEN
    RAISE EXCEPTION 'BLOCK_T_DECCTX_IG_SPECIFIC_COLUMN_FOUND';
  END IF;

  IF position('IG_CURATOR' in pg_get_functiondef('public.fn_lf_decision_context_asof_record_v1(jsonb,text)'::regprocedure))<>0
     OR position('IG_CURATOR' in pg_get_functiondef('public.fn_lf_decision_context_asof_resolve_v1(text,text,timestamptz)'::regprocedure))<>0
     OR position('IG_CURATOR' in pg_get_functiondef('private.fn_lf_decision_context_asof_payload_valid_v1(jsonb)'::regprocedure))<>0 THEN
    RAISE EXCEPTION 'BLOCK_T_DECCTX_IG_SPECIFIC_BRANCH_FOUND';
  END IF;

  IF EXISTS (
    SELECT 1 FROM private.lf_decision_context_asof_v1
    WHERE decision_ref LIKE 'canary://t-decctx/%'
  ) THEN
    RAISE EXCEPTION 'BLOCK_T_DECCTX_ROLLBACK_PROOF_RESIDUE';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM programacion.engineering_plan_units pu
    JOIN programacion.engineering_work_items wi ON wi.id=pu.work_item_id
    WHERE pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
      AND pu.unit_code='N-16'
      AND pu.capability_ref='DECISION_CONTEXT_ASOF (CONSUME)'
      AND wi.work_code='PAULO-181'
      AND wi.status='BACKLOG'
      AND pu.unit_metadata#>>'{decision_context_asof_binding_v1,capability_code}'='DECISION_CONTEXT_ASOF'
      AND pu.unit_metadata#>>'{decision_context_asof_binding_v1,version}'='1.0.0'
      AND pu.unit_metadata#>>'{decision_context_asof_binding_v1,manifest_sha256}'=v_cap_sha
      AND pu.unit_metadata#>>'{decision_context_asof_binding_v1,ig_role}'='CONSUMER'
      AND pu.unit_metadata#>>'{decision_context_asof_binding_v1,binding_role}'='PLAN_ONLY'
      AND pu.unit_metadata#>>'{decision_context_asof_binding_v1,input_contract}'='LF_DECISION_CONTEXT_ASOF_INPUT_V1'
      AND pu.unit_metadata#>>'{decision_context_asof_binding_v1,second_consumer_proof}'='STORY_CREATOR'
      AND (pu.unit_metadata#>>'{decision_context_asof_binding_v1,execution_authorized}')::boolean IS FALSE
      AND (pu.unit_metadata#>>'{decision_context_asof_binding_v1,unit_executed}')::boolean IS FALSE
      AND (pu.unit_metadata#>>'{transversalization_v1,event_pending}')::boolean IS FALSE
  ) THEN
    RAISE EXCEPTION 'BLOCK_T_DECCTX_CLOSEOUT_N16_CONSUMER_READBACK';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM supabase_migrations.schema_migrations
    WHERE name='t_decctx_decision_context_asof_v1'
  ) OR NOT EXISTS (
    SELECT 1 FROM supabase_migrations.schema_migrations
    WHERE name='t_decctx_n16_consumer_binding_v1'
  ) THEN
    RAISE EXCEPTION 'BLOCK_T_DECCTX_CLOSEOUT_MIGRATION_LEDGER_PARITY';
  END IF;

  INSERT INTO transversal.error_knowledge(
    codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,
    lote_origen,pr,estado,evidencia,lifecycle_phase,consumer_role,root_cause_family,detectability,
    source_context,source_ref,updated_at,ultima_vez
  ) VALUES (
    'DECISION-CONTEXT-LATEST-NOT-ASOF-001',
    'TRANSVERSAL_CAPABILITY',
    'Latest mutable no reescribe contexto histórico as-of',
    'Una decisión histórica conserva subject/version, actor/effective authority, policy/terms, tiempos y authority refs/digests del momento de decisión; resolver as-of no reinterpreta esos datos contra latest mutable.',
    'Resolver decisiones históricas dereferenciando rol, owner, policy o terms actuales puede cambiar retroactivamente el significado de una decisión ya tomada.',
    'Un cambio posterior de autoridad/policy/terms puede producir un latest válido pero distinto del contexto que gobernaba la decisión original.',
    'Persistir un receipt append-only con refs/version/digests; separar latest de as-of; bloquear copias de autoridad y reutilizar CURRENTNESS_AUTHORITY, CAPABILITY_VERSION_COMPATIBILITY y TYPED_EVIDENCE_REGISTRY sin crear shadows.',
    'Registrar contexto v1, mutar canary authority/policy/terms a v2 y resolver as-of demostrando v1 retenido; repetir el mismo contrato con un consumer no-IG y verificar rollback sin residuos.',
    'ALTA','T-DECCTX/PAULO-187','#1613','activo',
    'DECISION_CONTEXT_ASOF CURRENT 1.0.0 sha 28b95beda0dc45e28c1c3e917dd105c7d7974f5f26fee50c0c2636229d425388; asof_negative=PASS latest V1->V2 historical=V1_RETAINED latest_reinterpreted=false rollback_only=true; STORY_CREATOR same_contract=PASS; 0 IG-specific columns/branches; N-16 remains BACKLOG consumer-only.',
    'construction',ARRAY['Architect','Builder','Verifier']::text[],'R4_NO_CUESTIONA','LOUD_EARLY',
    'IG_CURATOR_VALIDATOR_REFACTOR_V2:T-DECCTX',
    'github://cristhianlujan/claude-persona-lf-patch/sandbox/lf_contract_gate_test/transversal_assets/decision_context_asof/README.md',
    clock_timestamp(),clock_timestamp()
  )
  ON CONFLICT(codigo) DO UPDATE SET
    categoria=excluded.categoria,titulo=excluded.titulo,descripcion=excluded.descripcion,
    causa_raiz=excluded.causa_raiz,patron=excluded.patron,prevencion=excluded.prevencion,
    validacion=excluded.validacion,severidad=excluded.severidad,lote_origen=excluded.lote_origen,
    pr=excluded.pr,estado=excluded.estado,evidencia=excluded.evidencia,
    lifecycle_phase=excluded.lifecycle_phase,consumer_role=excluded.consumer_role,
    root_cause_family=excluded.root_cause_family,detectability=excluded.detectability,
    source_context=excluded.source_context,source_ref=excluded.source_ref,
    updated_at=clock_timestamp(),ultima_vez=clock_timestamp();

  UPDATE programacion.engineering_work_checkpoints
  SET status='DONE',
      evidence_ref=CASE checkpoint_code
        WHEN 'GENERIC_CONTRACT' THEN 'capability://DECISION_CONTEXT_ASOF@1.0.0#28b95beda0dc45e28c1c3e917dd105c7d7974f5f26fee50c0c2636229d425388'
        WHEN 'NEG_LATEST_MUTATION' THEN 'test://DECISION_CONTEXT_ASOF_V1#asof_negative=PASS;latest=V2;historical=V1_RETAINED;latest_reinterpreted=false;rollback_only=true'
        WHEN 'NON_IG_CONSUMER' THEN 'proof://STORY_CREATOR/LF_DECISION_CONTEXT_ASOF_INPUT_V1#same_contract=PASS'
        WHEN 'IG_BINDING' THEN 'plan://IG_CURATOR_VALIDATOR_REFACTOR_V2/N-16#CONSUMER;PLAN_ONLY;BACKLOG;unit_executed=false'
      END,
      completed_at=coalesce(completed_at,clock_timestamp()),
      updated_at=clock_timestamp(),
      updated_by_execution_id=v_exec
  WHERE work_item_id=883
    AND checkpoint_code IN ('GENERIC_CONTRACT','NEG_LATEST_MUTATION','NON_IG_CONSUMER','IG_BINDING');

  SELECT count(*) INTO v_done_count
  FROM programacion.engineering_work_checkpoints
  WHERE work_item_id=883 AND required=true AND status='DONE' AND evidence_ref IS NOT NULL;
  IF v_done_count<>4 THEN
    RAISE EXCEPTION 'BLOCK_T_DECCTX_CLOSEOUT_CHECKPOINTS:%',v_done_count;
  END IF;

  UPDATE programacion.engineering_work_items
  SET status='DONE',
      started_at=coalesce(started_at,clock_timestamp()),
      completed_at=coalesce(completed_at,clock_timestamp()),
      updated_at=clock_timestamp(),
      updated_by_execution_id=v_exec
  WHERE id=883 AND work_code='PAULO-187' AND status IN ('BACKLOG','IN_PROGRESS');

  SELECT count(*) INTO v_terminal_count
  FROM programacion.engineering_work_items
  WHERE id=883 AND work_code='PAULO-187' AND status='DONE' AND completed_at IS NOT NULL;
  IF v_terminal_count<>1 THEN
    RAISE EXCEPTION 'BLOCK_T_DECCTX_CLOSEOUT_TERMINAL_STATE:%',v_terminal_count;
  END IF;
END
$closeout$;

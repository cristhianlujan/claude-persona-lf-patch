-- T-CAUSAL / PAULO-188 terminal closeout.
-- Evidence/state closure only. No N-17 execution, no runtime cutover, no new event type.

DO $closeout$
DECLARE
  v_exec constant text := 'CHATGPT-IG-T-CAUSAL-PAULO-188-20261004';
  v_cap_sha constant text := '3794208d7ff52fec77c6703616be1a5b67e96c4290845910d31ec200609fe8d0';
  v_done_count integer;
  v_dep_done integer;
  v_terminal_count integer;
BEGIN
  SELECT count(*) INTO v_dep_done
  FROM programacion.engineering_work_dependencies d
  JOIN programacion.engineering_work_items wi ON wi.id=d.work_item_id
  JOIN programacion.engineering_work_items dep ON dep.id=d.depends_on_work_item_id
  WHERE wi.id=884
    AND wi.work_code='PAULO-188'
    AND dep.work_code IN ('PAULO-026','PAULO-028','PAULO-106')
    AND dep.status='DONE';
  IF v_dep_done<>3 THEN
    RAISE EXCEPTION 'BLOCK_T_CAUSAL_DEPENDENCY_REFRESH:%',v_dep_done;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_eventos
    WHERE id=20170
      AND evento_tipo='ARCHITECTURE_V2_CLOSURE_EVALUATED'
      AND entidad_codigo='IGQ_BENCH_ANALYSIS_VALIDATION_V1:FINAL'
  ) THEN
    RAISE EXCEPTION 'BLOCK_T_CAUSAL_SOURCE_EVENT_20170_NOT_CURRENT';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.lf_capability_registry r
    JOIN public.lf_capability_current c USING(capability_code)
    JOIN public.lf_capability_version_registry vr
      ON vr.capability_code=c.capability_code
     AND vr.version=c.version
     AND vr.manifest_sha256=c.manifest_sha256
    WHERE r.capability_code='CAUSAL_EFFECT_LINEAGE'
      AND r.capability_kind='TRANSVERSAL'
      AND r.owner_scope='SUPER_ADMIN'
      AND r.status='ACTIVE'
      AND c.version='1.0.0'
      AND c.manifest_sha256=v_cap_sha
      AND vr.release_state='RELEASED'
      AND vr.manifest#>>'{compatibility,domain_agnostic}'='true'
      AND vr.manifest#>>'{compatibility,ledger_duplicated}'='false'
      AND vr.manifest#>>'{compatibility,business_authority_owned}'='false'
      AND vr.manifest#>>'{contract,identity}'='SCOPED_OPAQUE_ONLY'
      AND vr.manifest#>>'{contract,name_match}'='NON_PROBATIVE'
      AND vr.manifest#>>'{contract,same_object}'='NON_PROBATIVE'
      AND vr.manifest#>>'{contract,timestamp_proximity}'='NON_PROBATIVE'
      AND vr.manifest#>>'{contract,pii_allowed}'='false'
      AND vr.manifest#>>'{contract,receiver_effect_readback_required}'='true'
      AND vr.manifest#>>'{qualification,heuristic_negative}'='PASS'
      AND vr.manifest#>>'{qualification,async_consumers}'='2'
      AND vr.manifest#>>'{qualification,receiver_readbacks}'='2'
      AND vr.manifest#>>'{consumer_proofs,non_ig,boundary}'='ASYNC_EVENT'
      AND vr.manifest#>>'{consumer_proofs,non_ig,receiver_readback_proven}'='true'
  ) THEN
    RAISE EXCEPTION 'BLOCK_T_CAUSAL_CLOSEOUT_CAPABILITY_READBACK';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_capability_current
    WHERE capability_code='TYPED_EVIDENCE_REGISTRY'
      AND version='3.0.0'
      AND manifest_sha256='0fb00eeeb84567129bde17df0fac9f04c136a874518010a21af60c37810134da'
  ) OR NOT EXISTS (
    SELECT 1 FROM public.lf_capability_current
    WHERE capability_code='EVIDENCE_LEDGER'
      AND version='1.1.0'
      AND manifest_sha256='b9c21eaa0cb4eceec3e6a0ae78272ed2da84e408e804c127ed6e43d1360f0982'
  ) THEN
    RAISE EXCEPTION 'BLOCK_T_CAUSAL_CLOSEOUT_EVIDENCE_DEPENDENCY_DRIFT';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM programacion.engineering_plan_units pu
    JOIN programacion.engineering_work_items wi ON wi.id=pu.work_item_id
    WHERE pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
      AND pu.unit_code='N-17'
      AND pu.capability_ref='CAUSAL_EFFECT_LINEAGE (CONSUME)'
      AND wi.work_code='PAULO-182'
      AND wi.status='BACKLOG'
      AND pu.unit_metadata#>>'{causal_effect_lineage_binding_v1,capability_code}'='CAUSAL_EFFECT_LINEAGE'
      AND pu.unit_metadata#>>'{causal_effect_lineage_binding_v1,manifest_sha256}'=v_cap_sha
      AND pu.unit_metadata#>>'{causal_effect_lineage_binding_v1,ig_role}'='CONSUMER'
      AND pu.unit_metadata#>>'{causal_effect_lineage_binding_v1,binding_role}'='PLAN_ONLY'
      AND pu.unit_metadata#>>'{causal_effect_lineage_binding_v1,boundary}'='ASYNC_JOB'
      AND (pu.unit_metadata#>>'{causal_effect_lineage_binding_v1,execution_authorized}')::boolean IS FALSE
      AND (pu.unit_metadata#>>'{causal_effect_lineage_binding_v1,unit_executed}')::boolean IS FALSE
      AND (pu.unit_metadata#>>'{causal_effect_lineage_binding_v1,receiver_readback_required}')::boolean IS TRUE
  ) THEN
    RAISE EXCEPTION 'BLOCK_T_CAUSAL_CLOSEOUT_N17_CONSUMER_READBACK';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM supabase_migrations.schema_migrations
    WHERE name='t_causal_causal_effect_lineage_v1'
  ) OR NOT EXISTS (
    SELECT 1 FROM supabase_migrations.schema_migrations
    WHERE name='t_causal_n17_consumer_binding_v1'
  ) THEN
    RAISE EXCEPTION 'BLOCK_T_CAUSAL_CLOSEOUT_MIGRATION_LEDGER_PARITY';
  END IF;

  INSERT INTO transversal.error_knowledge(
    codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,
    lote_origen,pr,estado,evidencia,lifecycle_phase,consumer_role,root_cause_family,detectability,
    source_context,source_ref,updated_at,ultima_vez
  ) VALUES (
    'CAUSAL-LINEAGE-WEAK-HEURISTICS-NONPROBATIVE-001',
    'TRANSVERSAL_CAPABILITY',
    'Nombre, objeto o proximidad temporal no demuestran causalidad',
    'La continuidad causal transversal solo puede quedar LINKED con identidades scoped/opaque explícitas, provenance/currentness vigente, producer receipt verificado, receiver-effect receipt cruzado y readback exacto del efecto receptor.',
    'La correlación superficial puede confundir co-ocurrencia con causalidad al cruzar límites sync/async.',
    'Name-match, mismo objeto o timestamp cercano pueden coincidir sin que exista una transición causal demostrada.',
    'Fail closed: sin prueba explícita devolver UNLINKED; si receipts explícitos se contradicen devolver AMBIGUOUS; nunca elevar heurísticas a LINKED.',
    'Ejecutar el negativo heurístico y demostrar dos consumers async distintos con receiver readback; verificar además que el provider no asume autoridad de negocio ni introduce PII.',
    'ALTA','T-CAUSAL/PAULO-188','#1614','activo',
    'CAUSAL_EFFECT_LINEAGE CURRENT 1.0.0 sha 3794208d7ff52fec77c6703616be1a5b67e96c4290845910d31ec200609fe8d0; PASS_CAUSAL_EFFECT_LINEAGE_V1 checks=24 states=3 async_consumers=2 heuristic_negative=PASS receiver_readbacks=2; N-17 remains BACKLOG consumer-only.',
    'construction',ARRAY['Architect','Builder','Verifier']::text[],'R4_NO_CUESTIONA','LOUD_EARLY',
    'IG_CURATOR_VALIDATOR_REFACTOR_V2:T-CAUSAL',
    'github://cristhianlujan/claude-persona-lf-patch/sandbox/lf_contract_gate_test/transversal_assets/causal_effect_lineage/README.md',
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
        WHEN 'GENERIC_CONTRACT' THEN 'capability://CAUSAL_EFFECT_LINEAGE@1.0.0#3794208d7ff52fec77c6703616be1a5b67e96c4290845910d31ec200609fe8d0'
        WHEN 'NEG_HEURISTIC_LINK' THEN 'test://CAUSAL_EFFECT_LINEAGE_V1#heuristic_negative=PASS;checks=24'
        WHEN 'NON_IG_CONSUMER' THEN 'proof://POST_PASE_PROOF_CONSUMER/ASYNC_EVENT#receiver_readback=PASS'
        WHEN 'IG_BINDING' THEN 'plan://IG_CURATOR_VALIDATOR_REFACTOR_V2/N-17#CONSUMER;PLAN_ONLY;BACKLOG;unit_executed=false'
      END,
      completed_at=coalesce(completed_at,clock_timestamp()),
      updated_at=clock_timestamp(),
      updated_by_execution_id=v_exec
  WHERE work_item_id=884
    AND checkpoint_code IN ('GENERIC_CONTRACT','NEG_HEURISTIC_LINK','NON_IG_CONSUMER','IG_BINDING');

  SELECT count(*) INTO v_done_count
  FROM programacion.engineering_work_checkpoints
  WHERE work_item_id=884 AND required=true AND status='DONE' AND evidence_ref IS NOT NULL;
  IF v_done_count<>4 THEN
    RAISE EXCEPTION 'BLOCK_T_CAUSAL_CLOSEOUT_CHECKPOINTS:%',v_done_count;
  END IF;

  UPDATE programacion.engineering_work_items
  SET status='DONE',
      started_at=coalesce(started_at,clock_timestamp()),
      completed_at=coalesce(completed_at,clock_timestamp()),
      updated_at=clock_timestamp(),
      updated_by_execution_id=v_exec
  WHERE id=884 AND work_code='PAULO-188' AND status IN ('BACKLOG','IN_PROGRESS');

  SELECT count(*) INTO v_terminal_count
  FROM programacion.engineering_work_items
  WHERE id=884 AND work_code='PAULO-188' AND status='DONE' AND completed_at IS NOT NULL;
  IF v_terminal_count<>1 THEN
    RAISE EXCEPTION 'BLOCK_T_CAUSAL_CLOSEOUT_TERMINAL_STATE:%',v_terminal_count;
  END IF;
END
$closeout$;

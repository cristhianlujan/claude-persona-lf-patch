-- M4.11 CP3: reconcile false M9.2 prerequisite with real M4.12/R11 novation.
-- Contract + governance + source-pack update together; no checkpoint transition,
-- no oracle activation, no runtime/production change.
-- Apply ONLY with authorized LF Migration Merge Train.
-- EKB: AUD-045, IG-M412-ORACLE-VERSION-PIN-AND-INDEPENDENCE-DRIFT-001,
-- IG-M412-SEMANTIC-SCOPE-IMPLICIT-EMPTY-001, INDEPENDENCE-CONTRACT-APPLICABILITY-001,
-- IG-M99-SANDBOX-LIVE-ADMISSION-CONFLATION-001,
-- IG-EKB-READ-WITHOUT-SEMANTIC-PREFLIGHT-001.
DO $m411_cp3$
DECLARE
  v_unit record;
  v_m92 bigint;
  v_m412 bigint;
  v_novation jsonb;
  v_meta jsonb;
  v_old jsonb;
  v_new jsonb;
  v_source jsonb;
  v_input jsonb;
  v_assurance record;
  v_now_spec jsonb;
  v_bootstrap jsonb;
  v_m92_done integer;
  v_cp2 record;
  v_binding_count integer;
  v_receipt_count integer;
  v_m412_behav jsonb;
  v_readback_sql text;
  v_evidence_sql text;
BEGIN
  SELECT pu.id,pu.work_item_id,pu.unit_metadata,w.status as work_status,
         w.expected_result,w.acceptance_criteria
    INTO STRICT v_unit
    FROM programacion.engineering_plan_units pu
    JOIN programacion.engineering_work_items w ON w.id=pu.work_item_id
   WHERE pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
     AND pu.unit_code='M4.11' AND pu.disposition='ASSIGNED'
   FOR UPDATE OF pu,w;

  IF v_unit.work_status IS DISTINCT FROM 'IN_PROGRESS' THEN
    RAISE EXCEPTION 'M411_CP3_UNIT_NOT_IN_PROGRESS';
  END IF;
  SELECT status,evidence_ref INTO STRICT v_cp2
    FROM programacion.engineering_work_checkpoints
   WHERE work_item_id=v_unit.work_item_id AND checkpoint_code='PREREQ_GATES_PASS';
  IF v_cp2.status IS DISTINCT FROM 'DONE'
     OR v_cp2.evidence_ref NOT LIKE '%readback=IG_M411_UPSTREAM_READBACK_V1:PASS%'
  THEN RAISE EXCEPTION 'M411_CP3_CP2_NOT_PROVEN'; END IF;
  IF EXISTS(
    SELECT 1 FROM programacion.engineering_work_checkpoints
     WHERE work_item_id=v_unit.work_item_id
       AND sequence_no >= 3
       AND (status<>'PENDING' OR evidence_ref IS NOT NULL)
  ) THEN RAISE EXCEPTION 'M411_CP3_ALREADY_TRANSITIONED'; END IF;

  SELECT w.id INTO STRICT v_m92
    FROM programacion.engineering_plan_units pu
    JOIN programacion.engineering_work_items w ON w.id=pu.work_item_id
   WHERE pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
     AND pu.unit_code='M9.2' AND w.status='DONE';
  SELECT count(*) INTO v_m92_done
    FROM programacion.engineering_work_checkpoints
   WHERE work_item_id=v_m92 AND status='DONE';
  IF v_m92_done<>6 THEN RAISE EXCEPTION 'M411_M92_NOT_DONE_6_OF_6'; END IF;

  SELECT count(*) INTO v_binding_count
    FROM programacion.engineering_work_items w
   WHERE w.work_code IN ('SADM-PP-L4-021','SADM-PP-L5-022')
     AND w.status='DONE';
  IF v_binding_count<>2 THEN RAISE EXCEPTION 'M411_CUTOVER_SADM_MECHANISM_NOT_DONE'; END IF;

  SELECT w.id INTO STRICT v_m412
    FROM programacion.engineering_plan_units pu
    JOIN programacion.engineering_work_items w ON w.id=pu.work_item_id
   WHERE pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
     AND pu.unit_code='M4.12' AND w.status='DONE';
  SELECT payload INTO STRICT v_novation
    FROM public.lf_eventos WHERE id=20635
      AND entidad_codigo='IG_CV_REFACTOR_V2.L0.M4.12.R11_NOVATION';
  IF v_novation->>'schema_novation' IS DISTINCT FROM 'IG_R11_NOVATION_V1'
     OR v_novation->>'original_criterion_met' IS DISTINCT FROM 'false'
     OR v_novation->>'validator_independent_of_curator' IS DISTINCT FROM 'false'
     OR v_novation->>'promotion_authorized' IS DISTINCT FROM 'false'
     OR v_novation->>'production_authorized' IS DISTINCT FROM 'false'
     OR v_novation->'new_controls' IS DISTINCT FROM
          '["FACTS_INVARIANTS","LOGIC_SEVERITY_INVARIANT","CORRELATION_DEFECT_INJECTION"]'::jsonb
  THEN RAISE EXCEPTION 'M411_M412_HISTORICAL_NOVATION_DRIFT'; END IF;
  SELECT assertion_receipt INTO STRICT v_m412_behav
    FROM programacion.engineering_work_checkpoints
   WHERE work_item_id=v_m412 AND checkpoint_code='CORRELATION_RERUN'
     AND status='DONE';
  IF v_m412_behav->>'passed' IS DISTINCT FROM 'true'
  THEN RAISE EXCEPTION 'M411_M412_BEHAVIORAL_RECEIPT_NOT_PASS'; END IF;

  SELECT count(*) INTO v_receipt_count
    FROM programacion.provenance_receipts
   WHERE id=1667
     AND subject_ref='plan://IG_CURATOR_VALIDATOR_REFACTOR_V2/M9.12/CUTOVER_READY'
     AND receipt_kind='EVIDENCE_VERIFICATION'
     AND receipt_sha256='b4b8174360d8478c122340ca25973ba54cdcd7785d2d168ae8271840fc0c7fc5'
     AND payload->>'verification_status'='VERIFIED'
     AND payload->>'bundle_sha256'='db84f4ab3cdcc0fe3dcdd463be70ad9b4c96ec7beb9be9cc56b9d344793e7f2f'
     AND payload#>>'{manifest,production_activation}'='false';
  IF v_receipt_count<>1 THEN RAISE EXCEPTION 'M411_M912_SIGNED_BUNDLE_NOT_CURRENT'; END IF;

  SELECT version,manifest_sha256 INTO STRICT v_assurance
    FROM public.lf_capability_current
   WHERE capability_code='INDEPENDENT_ASSURANCE';
  IF nullif(v_assurance.version,'') IS NULL
     OR length(coalesce(v_assurance.manifest_sha256,''))<>64
  THEN RAISE EXCEPTION 'M411_REUSE_INDEPENDENT_ASSURANCE_NOT_CURRENT'; END IF;

  v_meta:=v_unit.unit_metadata;
  v_old:=v_meta#>'{action_specs_v1,DECISIONAL_BINDING_VIA_RELEASE}';
  IF v_old->>'status' IS DISTINCT FROM 'BLOCK_UPSTREAM_CAPABILITY_CUTOVER_PENDING'
     OR v_old->>'action_kind' IS DISTINCT FROM 'DECISION_GATE'
     OR v_old#>>'{required_evidence_contract,required_overall_state}' IS DISTINCT FROM 'INDEPENDENT'
     OR v_meta#>>'{m411_admission_boundary_v1,version}' IS DISTINCT FROM '1.0.0'
  THEN RAISE EXCEPTION 'M411_CP3_CONTRACT_PRESTATE_DRIFT'; END IF;

  -- Exact, deterministic verification input. No inferred selector, no "latest" bundle.
  v_readback_sql := $q$
WITH upstream AS (
 SELECT u.unit_code,w.status
   FROM programacion.engineering_plan_units u
   JOIN programacion.engineering_work_items w ON w.id=u.work_item_id
  WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
    AND u.unit_code IN ('M9.2','M4.12')
), s AS (
 SELECT count(*) FILTER(WHERE status='DONE') done FROM upstream
), h AS (
 SELECT payload FROM public.lf_eventos WHERE id=20635
   AND entidad_codigo='IG_CV_REFACTOR_V2.L0.M4.12.R11_NOVATION'
), c AS (
 SELECT version,manifest_sha256
 FROM public.lf_capability_current
 WHERE capability_code='INDEPENDENT_ASSURANCE'
), b AS (
 SELECT version FROM public.lf_capability_current
 WHERE capability_code='INPUT_GOVERNANCE'
), r AS (
 SELECT id FROM programacion.provenance_receipts
 WHERE id=1667
   AND receipt_sha256='b4b8174360d8478c122340ca25973ba54cdcd7785d2d168ae8271840fc0c7fc5'
   AND payload->>'verification_status'='VERIFIED'
   AND payload->>'bundle_sha256'='db84f4ab3cdcc0fe3dcdd463be70ad9b4c96ec7beb9be9cc56b9d344793e7f2f'
)
SELECT jsonb_build_object(
 'contract','IG_M411_CP3_GOVERNANCE_READBACK_V2',
 'status',CASE WHEN (SELECT done FROM s)=2 AND (SELECT count(*) FROM r)=1
   AND (SELECT count(*) FROM c)=1 AND (SELECT count(*) FROM b)=1
   AND (SELECT payload->>'original_criterion_met' FROM h)='false'
   AND (SELECT payload->>'promotion_authorized' FROM h)='false'
   THEN 'PASS_BOUNDARY_ONLY' ELSE 'BLOCKED' END,
 'm92_m412_done',(SELECT done FROM s),
 'm412_novation_event',20635,
 'historical_behavioral_controls_reused',true,
 'semantic_independence_certified',false,
 'independent_assurance_version',(SELECT version FROM c),
 'input_governance_current_version',(SELECT version FROM b),
 'cutover_receipt_id',(SELECT id FROM r),
 'decisional_release_authorized',false,
 'production_authorized',false
) AS result
$q$;

  v_evidence_sql := $q$
SELECT id,receipt_kind,subject_type,subject_ref,issuer_identity,receipt_sha256,
       payload->>'verification_status' verification_status,
       payload->>'bundle_sha256' bundle_sha256
FROM programacion.provenance_receipts
WHERE subject_ref LIKE 'plan://IG_CURATOR_VALIDATOR_REFACTOR_V2/M4.11/%'
ORDER BY id DESC LIMIT 15
$q$;

  v_new:=v_old || jsonb_build_object(
    'status','BLOCK_INDEPENDENCE_RECEIPT_REQUIRED',
    'precision','M411_CP3_SEMANTIC_DECISIONAL_SCOPE_V2',
    'contract_family','SEMANTIC_DECISIONAL_ORACLE_ADMISSION',
    'action_kind','DECISION_GATE',
    'recipe_mode','REUSE_HISTORICAL_BEHAVIORAL_AND_VALIDATE_MATERIAL_INDEPENDENCE',
    'mutation_policy','NO_DOMAIN_MUTATION',
    'requires_material_execution',false,
    'expected','Reuse M9.2 6/6 release mechanism and M4.12 event 20635 behavioral qualification. Semantic decisional oracle promotion ONLY if separate exact-subject T-INDEP proof DEPENDENCIES/DATA/AUTHOR INDEPENDENT plus immutable M9.12 bundle 1667 and authorized governed release binding. Historical M4.12 explicitly did NOT certify semantic independence. Never promote on structural/source integrity alone.',
    'action_steps',jsonb_build_array(
      'READ_M92_RELEASE_BINDING_6_OF_6',
      'CONSUME_M412_R11_NOVATION_20635_AS_BEHAVIORAL_ONLY',
      'CLASSIFY_CLAIM_SEMANTIC_DECISIONAL_VS_SOURCE_INTEGRITY',
      'REUSE_CURRENT_INDEPENDENT_ASSURANCE_NO_NEW_JUDGE',
      'REQUIRE_FROZEN_CANDIDATE_DEPENDENCY_DATA_AUTHOR_PROVENANCE',
      'MEASURE_AND_VERIFY_EXACT_T_INDEP_SUBJECT_RECEIPT',
      'REQUIRE_AUTHORIZED_RELEASE_BINDING_AND_NEGATIVE_BEFORE_DONE',
      'PERSIST_CHECKPOINT_ONLY_WITH_NONEMPTY_VERIFIED_EVIDENCE'
    ),
    'verification_queries',jsonb_build_array(v_readback_sql,v_evidence_sql),
    'source_pack_missing_typed','[]'::jsonb,
    'release_binding_contract',coalesce(v_old->'release_binding_contract','{}'::jsonb) ||
      jsonb_build_object(
        'producer_unit','M9.2',
        'producer_unit_status','DONE_6_OF_6',
        'super_admin_cutover_evidence','SADM-PP-L4-021+SADM-PP-L5-022:DONE',
        'current_pointer','public.lf_capability_current',
        'validator_function_rewrite','FORBIDDEN',
        'write_transport','CANONICAL_GOVERNED_RELEASE_ONLY',
        'current_candidate_mechanism_missing',false,
        'decisional_activation_in_this_contract','NOT_AUTHORIZED_WITHOUT_ADMISSION'
      ),
    'required_evidence_contract',coalesce(v_old->'required_evidence_contract','{}'::jsonb) ||
      jsonb_build_object(
        'phase','SEMANTIC_DECISIONAL_ORACLE_ADMISSION',
        'claim_applicability','MATERIAL_SEMANTIC_DECISIONAL_ONLY',
        'historical_m412_novation_event_id',20635,
        'historical_m412_behavioral_pass',true,
        'historical_m412_semantic_independence_proven',false,
        'historical_behavioral_control_codes',jsonb_build_array(
          'FACTS_INVARIANTS','LOGIC_SEVERITY_INVARIANT','CORRELATION_DEFECT_INJECTION'),
        'dependency_schema','programacion',
        'producer_root','fn_input_governance_bootstrap_classify_v2',
        'reviewer_root','fn_input_governance_shadow_priority_oracle_v2',
        'max_depth',8,
        'required_overall_state','INDEPENDENT',
        'required_dimensions',jsonb_build_array('DEPENDENCIES','DATA','AUTHOR'),
        'admission_capability','INDEPENDENT_ASSURANCE',
        'admission_manifest_current_sha256',v_assurance.manifest_sha256,
        'admission_capability_current_version',v_assurance.version,
        'execution_context_status','REQUIRES_VERIFIED_SOURCE_AND_REVIEWER_PROVENANCE',
        'data_refs_source','FROZEN_ACTUAL_PRODUCER_AND_REVIEWER_INPUTS',
        'author_refs_source','ATTESTED_DIFFERENT_PROVENANCE',
        'independence_context_may_be_invented',false,
        'receipt_subject','plan://IG_CURATOR_VALIDATOR_REFACTOR_V2/M4.11/DECISIONAL_BINDING_VIA_RELEASE',
        'receipt_candidate_bundle_sha256','db84f4ab3cdcc0fe3dcdd463be70ad9b4c96ec7beb9be9cc56b9d344793e7f2f',
        'receipt_issuer_independent_required',true,
        'missing_receipt_behavior','BLOCK_NOT_AUTO_CREATE',
        'source_integrity_only_does_not_claim_semantic_independence',true,
        'no_new_judge_or_oracle_engine',true,
        'runtime_activation_authorized',false,
        'production_activation_authorized',false,
        'evidence_ref_required',true
      ),
    'forbidden',coalesce(v_old->'forbidden','[]'::jsonb) || jsonb_build_array(
      'EQUATE_M412_NOVATION_TO_INDEPENDENCE',
      'REQUIRE_T_INDEP_FOR_PLAIN_SOURCE_READBACK',
      'EMIT_INDEPENDENCE_RECEIPT_WITHOUT_VERIFIED_ORIGIN',
      'RECLASSIFY_47_FAMILIES_AS_SEMANTIC_WITHOUT_DECLARED_SCOPE',
      'AUTO_ACTIVATE_FROM_CP2_OR_M92_DONE',
      'MUTATE_EXISTING_ORACLE_OR_VALIDATOR_FUNCTION'
    )
  );

  v_source:=coalesce(v_meta->'source_pack_v1','{}'::jsonb);
  v_input:=coalesce(v_source#>'{checkpoint_inputs,DECISIONAL_BINDING_VIA_RELEASE}','{}'::jsonb);
  v_input:=jsonb_set(v_input,'{missing}','[]'::jsonb,true);
  v_input:=jsonb_set(v_input,'{missing_typed}','[]'::jsonb,true);
  v_input:=jsonb_set(v_input,'{inputs,queries}',jsonb_build_array(v_readback_sql,v_evidence_sql),true);
  v_input:=jsonb_set(v_input,'{inputs,db_objects}',
    jsonb_build_array(
      'programacion.engineering_plan_units',
      'programacion.engineering_work_items',
      'programacion.engineering_work_checkpoints',
      'public.lf_eventos',
      'programacion.provenance_receipts',
      'public.lf_capability_current'),true);
  v_source:=jsonb_set(v_source,'{checkpoint_inputs,DECISIONAL_BINDING_VIA_RELEASE}',v_input,true);
  v_source:=jsonb_set(v_source,'{exact_dependencies}',
    '["M4.10","M9.12","M9.2","M9.8"]'::jsonb,true);

  v_meta:=jsonb_set(v_meta,'{action_specs_v1,DECISIONAL_BINDING_VIA_RELEASE}',v_new,true);
  v_meta:=jsonb_set(v_meta,'{source_pack_v1}',v_source,true);
  v_meta:=jsonb_set(v_meta,'{m411_admission_boundary_v1}', 
    (coalesce(v_meta->'m411_admission_boundary_v1','{}'::jsonb) ||
      jsonb_build_object(
        'version','2.0.0',
        'cp3_scope','MATERIAL_SEMANTIC_DECISIONAL_ADMISSION_ONLY',
        'm92_release_binding_mechanism','DONE_VERIFIED_6_OF_6',
        'm412_r11_novation_event',20635,
        'm412_behavioral_proof','REUSED_NOT_SEMANTIC_INDEPENDENCE',
        'semantic_independence_claim','REQUIRES_FROZEN_T_INDEP_SUBJECT_RECEIPT',
        'plain_source_integrity','NO_SEMANTIC_INDEPENDENCE_CLAIM',
        'assurance_capability','INDEPENDENT_ASSURANCE',
        'assurance_current_version_at_correction',v_assurance.version,
        'm912_immutable_bundle_sha256','db84f4ab3cdcc0fe3dcdd463be70ad9b4c96ec7beb9be9cc56b9d344793e7f2f',
        'cutover_actual_activation','NOT_AUTHORIZED',
        'production_activation','NOT_AUTHORIZED',
        'no_new_engine',true
      )),true);

  UPDATE programacion.engineering_plan_units pu SET
    title='Calificacion para oracle decisional y release gobernado, sin activar produccion',
    exit_criterion='CP2 conserva 3/3 + recibo M9.12 firmado; CP3 reutiliza mecanismo M9.2 y la calificacion conductual M4.12/R11 (evento 20635), sin tratarla como independencia semantica. Solo una promocion que emita decisiones semanticas requiere T-INDEP trazable de dependencias, datos y autor para el candidato/bundle exactos, mas release autorizado. CP4 exige negativo oracle ausente->BLOCKED; CP5 exige 47/47 con estrategia y aplicabilidad tipada; CP6 exige readback real por run_id. No autoriza activacion productiva.',
    unit_metadata=v_meta
  WHERE pu.id=v_unit.id;
  UPDATE programacion.engineering_work_items w SET
    title='M4.11 — Admisión gobernada de oracle decisional y validación de release',
    objective='Preparar y verificar admision para promover un oracle desde shadow sin autocertificacion semantica. Reusar M9.2 y R11/M4.12; habilitacion de produccion separada.',
    expected_result='M4.11 terminal solo con evidencia de binding decisional gobernado, T-INDEP cuando hay veredicto semantico, negativo sin oracle, cobertura 47/47 y readback de runs nuevos.',
    acceptance_criteria=jsonb_build_array(
      'M9.2 release CURRENT/CANDIDATE: 6/6 DONE; no exigir reconstruccion de mecanismo existente',
      'M4.12 R11 novation event 20635 reutilizado como calificacion conductual; semantica independiente NO afirmada',
      'CP3 solo admite oracle decisional semantico con INDEPENDENT_ASSURANCE actual y T-INDEP verificado DEPENDENCIES DATA AUTHOR ligado al bundle M9.12 exacto; sin recibo CP3 BLOCKED',
      'La opcion SOURCE_INTEGRITY_ONLY no autoriza veredicto semantico ni puede cerrar CP3 decisional',
      'CP4 negativo sin oracle => BLOCKED; CP5 47/47 estrategias declaradas; CP6 readback real de binding/run_id',
      'Produccion/activacion live no autorizada por esta correccion contractual'
    )
  WHERE w.id=v_unit.work_item_id;

  v_now_spec:=programacion.fn_engineering_checkpoint_action_spec_v3(
      'IG_CURATOR_VALIDATOR_REFACTOR_V2','M4.11','DECISIONAL_BINDING_VIA_RELEASE');
  v_bootstrap:=programacion.fn_engineering_unit_bootstrap_v3(
      'IG_CURATOR_VALIDATOR_REFACTOR_V2','M4.11');

  IF v_now_spec->>'status' IS DISTINCT FROM 'BLOCK_INDEPENDENCE_RECEIPT_REQUIRED'
     OR v_now_spec#>>'{required_evidence_contract,historical_m412_semantic_independence_proven}' IS DISTINCT FROM 'false'
     OR v_now_spec#>>'{required_evidence_contract,claim_applicability}' IS DISTINCT FROM 'MATERIAL_SEMANTIC_DECISIONAL_ONLY'
     OR jsonb_array_length(coalesce(v_now_spec->'action_steps','[]'::jsonb))<>8
     OR jsonb_array_length(coalesce(v_now_spec->'source_pack_missing_typed','[]'::jsonb))<>0
     OR v_bootstrap#>>'{current_checkpoint,checkpoint_code}' IS DISTINCT FROM 'DECISIONAL_BINDING_VIA_RELEASE'
     OR v_bootstrap#>>'{state,done_checkpoint_count}' IS DISTINCT FROM '2'
     OR v_bootstrap#>>'{state,checkpoint_count}' IS DISTINCT FROM '6'
     OR v_bootstrap#>>'{current_checkpoint,status}' IS DISTINCT FROM 'PENDING'
  THEN
    RAISE EXCEPTION 'M411_CP3_CONTRACT_POSTCHECK_FAILED:%',v_now_spec->>'status';
  END IF;
  IF EXISTS (
    SELECT 1 FROM programacion.engineering_work_checkpoints
    WHERE work_item_id=v_unit.work_item_id AND sequence_no>=3
      AND status<>'PENDING'
  ) THEN RAISE EXCEPTION 'M411_CP3_UNAUTHORIZED_CLOSURE'; END IF;
END;
$m411_cp3$;

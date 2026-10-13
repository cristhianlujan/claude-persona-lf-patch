-- PE10_C3 source adapter to the CURRENT transversal INDEPENDENT_ASSURANCE.
-- No new judge, subject-whitelist, operation, ACTIVE binding, or cutover.
BEGIN;
DO $pe10$
DECLARE
  v_meta jsonb;
  v_w bigint;
  v_spec jsonb;
  v_input jsonb;
  v_query text:=$review_query$with frozen as (
  select encode(extensions.digest(convert_to(
    jsonb_build_object(
      'plan','PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1',
      'unit','PE10',
      'c1',(select assertion_receipt_sha256 from programacion.engineering_work_checkpoints
            where work_item_id=1103 and checkpoint_code='PE10_C1'),
      'c2',(select assertion_receipt_sha256 from programacion.engineering_work_checkpoints
            where work_item_id=1103 and checkpoint_code='PE10_C2'),
      'c2b',(select assertion_receipt_sha256 from programacion.engineering_work_checkpoints
            where work_item_id=1103 and checkpoint_code='PE10_C2B'),
      'first_evolution',(select c.assertion_receipt_sha256
            from programacion.engineering_work_checkpoints c
            join programacion.engineering_plan_units u on u.work_item_id=c.work_item_id
            where u.plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1'
              and u.unit_code='PE10E' and c.checkpoint_code='PE10E_C4'),
      'active_policy',(select policy_sha from public.lf_policy_versions
             where policy_code='POL-PROFILE-UPDATE-PASS' and status='ACTIVE')
    )::text,'UTF8'),'sha256'),'hex') digest
), receipts as (
  select e.receipt_id,e.execution_id
  from private.lf_evidence_ledger_v1 e
  join public.lf_operation_execution op on op.execution_id=e.execution_id
    and op.operation_code='REVISION_INDEPENDIENTE_ESTRATEGIA_LF' and op.status='COMPLETED'
  join public.lf_capability_binding cb on cb.execution_id=e.execution_id
    and cb.capability_code='INDEPENDENT_ASSURANCE' and cb.binding_state='BOUND'
  join public.lf_capability_current cur on cur.capability_code=cb.capability_code
    and cb.bound_version=cur.version and cb.bound_manifest_sha256=cur.manifest_sha256
  cross join frozen f
  where e.capability_code='INDEPENDENT_ASSURANCE' and e.receipt_kind='AUDIT_VERDICT'
    and e.verification_state='VERIFIED'
    and e.subject_type='PROFILE_EVOLUTION_CUTOVER'
    and e.subject_ref='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1/PE10'
    and e.subject_sha256=f.digest
    and e.receipt_payload->>'verdict'='PASS'
    and e.receipt_payload->>'independent'='true'
    and e.receipt_payload#>>'{independence_measure,state}'='INDEPENDENT'
    and e.receipt_payload->>'execution_id'=e.execution_id
    and e.receipt_payload->>'subject_sha256'=e.subject_sha256
    and e.receipt_payload->>'source_head_sha'=e.source_head_sha
    and e.receipt_sha256 is not null
)
select (select digest from frozen) as frozen_subject_digest,
 (select count(*) from receipts) as qualified_current_independent_review_receipts,
 (select count(*) from private.lf_evidence_ledger_v1
   where capability_code='INDEPENDENT_ASSURANCE' and receipt_kind='AUDIT_VERDICT'
     and verification_state='VERIFIED') as historical_verified_unscoped_receipts$review_query$;
  v_packet jsonb;
BEGIN
  SELECT unit_metadata,work_item_id INTO STRICT v_meta,v_w
  FROM programacion.engineering_plan_units
  WHERE plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1'
    AND unit_code='PE10' FOR UPDATE;
  IF v_meta#>>'{action_specs_v1,PE10_C3,status}' IS DISTINCT FROM 'READY'
    OR v_meta#>>'{phase_separation_v1,independent_cutover_assurance,receipt_status}'
          IS DISTINCT FROM 'NOT_PROVEN_AT_PUBLICATION'
    OR jsonb_typeof(v_meta#>'{source_pack_v2,checkpoint_inputs,PE10_C3}') IS DISTINCT FROM 'object'
    OR (SELECT status FROM programacion.engineering_work_checkpoints
        WHERE work_item_id=v_w AND checkpoint_code='PE10_C3') IS DISTINCT FROM 'IN_PROGRESS'
    OR coalesce((v_meta#>>'{phase_separation_v1,independent_cutover_assurance,operational_cutover_allowed}')::boolean,true)
  THEN RAISE EXCEPTION 'PE10_C3_ADAPTER_PRESTATE_DRIFT'; END IF;

  IF NOT EXISTS(select 1 from public.lf_capability_current c
                join public.lf_capability_registry r using (capability_code)
                where c.capability_code='INDEPENDENT_ASSURANCE'
                and r.status='ACTIVE' and r.owner_scope='SUPER_ADMIN')
     OR NOT EXISTS(select 1 from public.lf_capability_current c
                join public.lf_capability_registry r using (capability_code)
                where c.capability_code='ASSURANCE_EVALUATOR'
                and r.status='ACTIVE' and r.owner_scope='SUPER_ADMIN')
  THEN RAISE EXCEPTION 'PE10_C3_CANONICAL_ASSURANCE_CAPABILITY_NOT_CURRENT'; END IF;

  v_input:=v_meta#>'{source_pack_v2,checkpoint_inputs,PE10_C3}';
  v_input:=jsonb_set(v_input,'{inputs,queries}',jsonb_build_array(v_query),false);
  v_input:=jsonb_set(v_input,'{inputs,db_objects}',jsonb_build_array(
    'private.lf_evidence_ledger_v1','public.lf_operation_execution',
    'public.lf_capability_binding','public.lf_capability_current',
    'public.lf_capability_registry','public.lf_policy_versions',
    'programacion.engineering_work_checkpoints','programacion.engineering_plan_units'),false);
  v_input:=v_input || jsonb_build_object(
    'expected_result','QUALIFIED_CURRENT_INDEPENDENT_REVIEW_RECEIPTS_GT_ZERO',
    'source','INDEPENDENT_ASSURANCE_EVIDENCE_LEDGER_CURRENT_BINDING',
    'no_independent_verdict_expected_at_registration',true);
  IF jsonb_array_length(v_input#>'{inputs,queries}')<>1
  THEN RAISE EXCEPTION 'PE10_C3_REVIEW_QUERY_MISSING'; END IF;

  v_spec:=v_meta#>'{action_specs_v1,PE10_C3}';
  v_spec:=v_spec || jsonb_build_object(
    'status','READY','action_kind','READBACK_ONCE','recipe_mode','READBACK_EXACT',
    'requires_material_execution',false,
    'verification_queries',jsonb_build_array(v_query),
    'subject_adapter',jsonb_build_object(
      'schema','PE10_C3_INDEPENDENT_ASSURANCE_CONSUMER_V1',
      'capability_code','INDEPENDENT_ASSURANCE',
      'current_pointer','public.lf_capability_current',
      'existing_review_operation','REVISION_INDEPENDIENTE_ESTRATEGIA_LF',
      'existing_begin_entrypoint','public.lf_independent_review_begin_v3',
      'existing_evidence_ledger','private.lf_evidence_ledger_v1',
      'subject_type','PROFILE_EVOLUTION_CUTOVER',
      'subject_ref','PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1/PE10',
      'subject_digest_rule','SHA256_JSONB_FROZEN_C1_C2_C2B_PE10E_C4_ACTIVE_POLICY',
      'required_dimensions',jsonb_build_array('dependency','data','author'),
      'provider_attested_subject_receipt_required',true,
      'orchestrator_dispatch_receipt_required',true,
      'reviewer_must_differ_from_producer',true,
      'cutover_approval_implied',false),
    'validator_contract',jsonb_build_object(
      'required',true,
      'validator_code','PROFILE_EVOLUTION_BENCHMARK_ADMISSION_V1',
      'failure_code','PE10_C3_INDEPENDENT_REVIEW_RECEIPT_NOT_YET_PROVEN',
      'pass_when','A current-version BOUND INDEPENDENT_ASSURANCE VERIFIED AUDIT_VERDICT PASS, independent measure INDEPENDENT, exact frozen subject digest, completed governed review operation',
      'resolver_policy','REUSE_GENERIC_INDEPENDENT_REVIEW_V3_NO_PARALLEL_JUDGE'),
    'forbidden',jsonb_build_array('SELF_JUDGE','CLAIM_OLD_OTHER_SUBJECT_RECEIPTS',
      'CLAIM_CAPABILITY_ACTIVE_AS_PASS','SKIP_CURRENT_VERSION_BINDING',
      'AUTO_ACTIVATE_V02'));

  v_packet:=programacion.fn_engineering_execution_packet_from_spec_v1(
    'PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1','PE10','PE10_C3',
    v_spec,v_input);
  IF v_packet->>'status' IS DISTINCT FROM 'READY'
  THEN RAISE EXCEPTION 'PE10_C3_ADAPTER_COMPILE_FAILED: %',v_packet->'block_reasons'; END IF;

  v_meta:=jsonb_set(v_meta,'{source_pack_v2,checkpoint_inputs,PE10_C3}',v_input,false);
  v_meta:=jsonb_set(v_meta,'{action_specs_v1,PE10_C3}',v_spec,false);
  v_meta:=jsonb_set(v_meta,'{phase_separation_v1,independent_cutover_assurance}',
    (v_meta#>'{phase_separation_v1,independent_cutover_assurance}') ||
      jsonb_build_object('consumer_adapter','PE10_C3_INDEPENDENT_ASSURANCE_CONSUMER_V1',
        'canonical_evidence','private.lf_evidence_ledger_v1',
        'candidate_review_subject','PROFILE_EVOLUTION_CUTOVER',
        'receipt_status','MISSING_REAL_INDEPENDENT_REVIEW',
        'operational_cutover_allowed',false),false);
  UPDATE programacion.engineering_plan_units SET unit_metadata=v_meta
   WHERE plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1' AND unit_code='PE10';
  UPDATE programacion.engineering_work_items w
   SET acceptance_criteria=(SELECT jsonb_agg(
      case when x.value LIKE 'PE10_C3:%' then to_jsonb(
       'PE10_C3: exact subject-bound VERIFIED AUDIT_VERDICT PASS in existing INDEPENDENT_ASSURANCE evidence ledger, with CURRENT capability binding, independent dependency/data/author measure, frozen evidence digest, governed completed reviewer operation; no pass merely from active capability'::text)
       else to_jsonb(x.value) end order by x.ordinality)
       from jsonb_array_elements_text(w.acceptance_criteria)
       with ordinality as x(value,ordinality))
   WHERE w.id=v_w;
  IF NOT FOUND THEN RAISE EXCEPTION 'PE10_C3_ACCEPTANCE_GOVERNANCE_NOT_UPDATED'; END IF;
END $pe10$;

INSERT INTO public.lf_error_knowledge
 (codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
  severidad,frecuencia,primera_vez,ultima_vez,lote_origen,estado,source_ref)
SELECT 'LF-PE10-C3-WRONG-ASSURANCE-LEDGER-20261012-001','PROFILE_EVOLUTION',
  'Independent Assurance evidence was read from unrelated Evaluator tables',
  'PE10_C3 had a valid source pack but read only lf_assurance_subject_bindings and lf_assurance_evaluations instead of the generic INDEPENDENT_ASSURANCE evidence ledger and operation receipt.',
  'Consumer adapter conflated separate assurance mechanisms; ACTIVE capability and historical other-subject receipts do not certify Profile Evolution.',
  'Assurance wiring to wrong consumer ledger risks false negatives or false positives.',
  'Consume existing INDEPENDENT_ASSURANCE through exact frozen subject digest, current binding, VERIFIED AUDIT_VERDICT and independent dimensions; no new judge or parallel engine.',
  'Positive: seven historical other-subject VERIFIED receipts are rejected for PE10; negative: zero matching PE10 receipts means PE10_C3 remains IN_PROGRESS; no cutover.',
  'HIGH',1,clock_timestamp(),clock_timestamp(),'PE10_C3','ACTIVO',
  'supabase://programacion.engineering_plan_units/PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1/PE10'
WHERE NOT EXISTS (SELECT 1 FROM public.lf_error_knowledge
  WHERE codigo='LF-PE10-C3-WRONG-ASSURANCE-LEDGER-20261012-001');
COMMIT;

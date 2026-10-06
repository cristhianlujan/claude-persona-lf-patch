-- M1.8 / UNMAPPED_NEGATIVE
-- Append-only reconciliation of INPUT_READINESS_CONTRACT 5.13 traceability after
-- R5-C added two storage-representation clauses. Matrix revision 1 is preserved.

do $pre$
declare
  v_revision text;
  v_md5 text;
  v_base_rows int;
  v_base_sha text;
begin
  select especificacion->>'contract_revision', md5(especificacion::text)
    into v_revision,v_md5
  from programacion.contratos
  where id=37
    and contrato_codigo='INPUT_READINESS_CONTRACT';

  if v_revision is distinct from '5.13'
     or v_md5 is distinct from '229eb569cf7e988ec1b222df91b70876' then
    raise exception 'M18_CONTRACT_BASE_DRIFT revision=% md5=%',v_revision,v_md5;
  end if;

  select m.matrix_sha256,count(r.id)
    into v_base_sha,v_base_rows
  from programacion.contract_traceability_matrices m
  left join programacion.contract_traceability_rows r on r.matrix_id=m.id
  where m.id=1
    and m.matrix_code='INPUT_READINESS_CONTRACT_5_13_TRACEABILITY'
    and m.matrix_revision=1
  group by m.matrix_sha256;

  if v_base_sha is distinct from '9ccf8537bd96de7d30e05d5493711a1b99b7858fa573bf7541ebf456f12e30b4'
     or v_base_rows<>60 then
    raise exception 'M18_TRACEABILITY_BASE_DRIFT sha=% rows=%',v_base_sha,v_base_rows;
  end if;

  if exists (
    select 1
    from programacion.contract_traceability_matrices
    where matrix_code='INPUT_READINESS_CONTRACT_5_13_TRACEABILITY'
      and matrix_revision=2
  ) then
    raise exception 'M18_TRACEABILITY_REV2_ALREADY_EXISTS';
  end if;
end;
$pre$;

create temporary table _m18_trace_rows (
  clause_key text primary key,
  target_layer text not null,
  target_owner text not null,
  target_enforcement text not null,
  current_function_refs text[] not null,
  current_trigger_refs text[] not null,
  current_enforcement_status text not null,
  integrity_test_refs text[] not null,
  semantic_test_status text not null,
  row_status text not null,
  observed_at timestamptz not null,
  source_ref text not null
) on commit drop;

insert into _m18_trace_rows
select
  r.clause_key,
  r.target_layer,
  r.target_owner,
  r.target_enforcement,
  r.current_function_refs,
  r.current_trigger_refs,
  r.current_enforcement_status,
  r.integrity_test_refs,
  r.semantic_test_status,
  'DEFINED',
  now(),
  r.source_ref
from programacion.contract_traceability_rows r
where r.matrix_id=1;

insert into _m18_trace_rows(
  clause_key,target_layer,target_owner,target_enforcement,
  current_function_refs,current_trigger_refs,current_enforcement_status,
  integrity_test_refs,semantic_test_status,row_status,observed_at,source_ref
) values
(
  'validator_evidence_required_fields_scope',
  'EVIDENCE',
  'EVIDENCE_AND_ASSURANCE',
  'EVIDENCE_READBACK_AND_DIGEST_BINDING',
  array[
    'fn_input_validator_evidence_rehydrate_v1',
    'fn_guard_input_family_assessment_update'
  ]::text[],
  array['trg_input_family_assessment_update']::text[],
  'CURRENT_LOCATOR_OBSERVED_NOT_SEMANTIC_PROOF',
  array['R5C_LOGICAL_REHYDRATED_EVIDENCE_SCOPE']::text[],
  'PENDING_CLAUSE_SEMANTIC_TEST',
  'DEFINED',
  now(),
  'github://cristhianlujan/claude-persona-lf-patch/supabase/migrations/20261006204044_input_governance_r5_c_logical_readers_storage_compaction_v1.sql#validator_evidence_required_fields_scope'
),
(
  'validator_evidence_storage_contract',
  'PERSISTENCE',
  'PERSISTENCE_GUARD',
  'DB_GUARD_CONSTRAINT_WRITE_BOUNDARY',
  array[
    'fn_input_validator_evidence_rehydrate_v1',
    'fn_input_validator_storage_compaction_check_v1',
    'fn_guard_input_governance_continuation_currentness_v1',
    'fn_guard_input_family_assessment_update'
  ]::text[],
  array[
    'trg_input_family_assessment_00a_continuation_currentness_update',
    'trg_input_family_assessment_update'
  ]::text[],
  'CURRENT_LOCATOR_OBSERVED_NOT_SEMANTIC_PROOF',
  array[
    'R5C_STORAGE_COMPACTION_POSITIVE_SELFTEST',
    'R5C_STORAGE_COMPACTION_NEGATIVE_CLAUSES_1_TO_5'
  ]::text[],
  'PENDING_CLAUSE_SEMANTIC_TEST',
  'DEFINED',
  now(),
  'github://cristhianlujan/claude-persona-lf-patch/supabase/migrations/20261006204044_input_governance_r5_c_logical_readers_storage_compaction_v1.sql#validator_evidence_storage_contract'
);

do $build$
declare
  v_contract_keys int;
  v_rows int;
  v_missing int;
  v_extra int;
  v_unmapped int;
  v_sha text;
  v_snapshot_sha text;
  v_new_matrix_id bigint;
begin
  select count(*)
    into v_contract_keys
  from programacion.contratos c
  cross join lateral jsonb_object_keys(c.especificacion) k
  where c.id=37;

  select count(*),
         count(*) filter(
           where target_layer is null
              or target_owner is null
              or target_enforcement is null
         )
    into v_rows,v_unmapped
  from _m18_trace_rows;

  select count(*) into v_missing
  from (
    select k clause_key
    from programacion.contratos c
    cross join lateral jsonb_object_keys(c.especificacion) k
    where c.id=37
    except
    select clause_key from _m18_trace_rows
  ) x;

  select count(*) into v_extra
  from (
    select clause_key from _m18_trace_rows
    except
    select k clause_key
    from programacion.contratos c
    cross join lateral jsonb_object_keys(c.especificacion) k
    where c.id=37
  ) x;

  if v_contract_keys<>62 or v_rows<>62 or v_missing<>0 or v_extra<>0 or v_unmapped<>0 then
    raise exception
      'M18_TRACEABILITY_REV2_SET_MISMATCH contract=% rows=% missing=% extra=% unmapped=%',
      v_contract_keys,v_rows,v_missing,v_extra,v_unmapped;
  end if;

  select encode(
    extensions.digest(
      convert_to(
        jsonb_agg(
          jsonb_build_object(
            'clause_key',clause_key,
            'target_layer',target_layer,
            'target_owner',target_owner,
            'target_enforcement',target_enforcement,
            'current_function_refs',to_jsonb(current_function_refs),
            'current_trigger_refs',to_jsonb(current_trigger_refs),
            'current_enforcement_status',current_enforcement_status,
            'integrity_test_refs',to_jsonb(integrity_test_refs),
            'semantic_test_status',semantic_test_status
          )
          order by clause_key
        )::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  )
  into v_sha
  from _m18_trace_rows;

  select encode(
    extensions.digest(convert_to(especificacion::text,'UTF8'),'sha256'),
    'hex'
  )
  into v_snapshot_sha
  from programacion.contratos
  where id=37;

  insert into programacion.contract_traceability_matrices(
    matrix_code,matrix_revision,contract_id,contract_revision,contract_spec_md5,
    source_plan_code,source_unit_code,source_event_id,
    upstream_classification_sha256,upstream_snapshot_sha256,
    locator_scope,matrix_sha256,clause_count,
    semantic_test_covered_count,semantic_test_pending_count,
    status,source_ref,created_by_execution_id
  ) values (
    'INPUT_READINESS_CONTRACT_5_13_TRACEABILITY',
    2,
    37,
    '5.13',
    '229eb569cf7e988ec1b222df91b70876',
    'IG_CURATOR_VALIDATOR_REFACTOR_V2',
    'M1.8',
    null,
    '9ccf8537bd96de7d30e05d5493711a1b99b7858fa573bf7541ebf456f12e30b4',
    v_snapshot_sha,
    'INPUT_GOVERNANCE_FUNCTIONS_TRIGGERS_AND_R5C_STORAGE_V2',
    v_sha,
    62,
    0,
    62,
    'DEFINED',
    'supabase://programacion.contratos/37#5.13',
    'ENGINEERING_PARALLEL_EXECUTOR_V1:M1.8:TRACEABILITY_REV2'
  )
  returning id into v_new_matrix_id;

  insert into programacion.contract_traceability_rows(
    matrix_id,clause_key,target_layer,target_owner,target_enforcement,
    current_function_refs,current_trigger_refs,current_enforcement_status,
    integrity_test_refs,semantic_test_status,row_status,
    observed_at,source_ref,created_by_execution_id
  )
  select
    v_new_matrix_id,
    clause_key,target_layer,target_owner,target_enforcement,
    current_function_refs,current_trigger_refs,current_enforcement_status,
    integrity_test_refs,semantic_test_status,row_status,
    observed_at,source_ref,
    'ENGINEERING_PARALLEL_EXECUTOR_V1:M1.8:TRACEABILITY_REV2'
  from _m18_trace_rows
  order by clause_key;
end;
$build$;

update programacion.engineering_plan_units
set unit_metadata=jsonb_set(
  coalesce(unit_metadata,'{}'::jsonb),
  '{action_specs_v1}',
  coalesce(unit_metadata->'action_specs_v1','{}'::jsonb)
  || jsonb_build_object(
    'UNMAPPED_NEGATIVE',
    jsonb_build_object(
      'schema_version','ENGINEERING_ACTION_SPEC_V3',
      'status','READY',
      'checkpoint_code','UNMAPPED_NEGATIVE',
      'checkpoint_title','Negativo: 0 cláusulas sin destino; cláusulas legacy_contract_v1/v2_authoritative con decisión explícita',
      'action_kind','VERIFY_QUERY_ONCE',
      'recipe_mode','VERIFY_EXACT',
      'precision','EXPLICIT_TRACEABILITY_SET_EQUIVALENCE',
      'requires_material_execution',false,
      'mutation_policy','NO_DOMAIN_MUTATION',
      'target',jsonb_build_object(
        'declared_objects',jsonb_build_array(
          'programacion.contratos',
          'programacion.contract_traceability_matrices',
          'programacion.contract_traceability_rows'
        ),
        'evidence_artifacts','[]'::jsonb,
        'mutation_artifacts','[]'::jsonb
      ),
      'expected','Current 5.13 contract keys and traceability revision 2 are exact set-equals: 62/62, missing=0, extra=0, unmapped=0. legacy_contract_v1_authoritative and legacy_contract_v2_authoritative are explicit false values and both are mapped to fail-closed READINESS_POLICY rows.',
      'verification_queries',jsonb_build_array(
        $q$
with m as (
  select *
  from programacion.contract_traceability_matrices
  where matrix_code='INPUT_READINESS_CONTRACT_5_13_TRACEABILITY'
    and matrix_revision=2
), ck as (
  select k clause_key
  from programacion.contratos c
  cross join lateral jsonb_object_keys(c.especificacion) k
  where c.id=(select contract_id from m)
), mr as (
  select r.*
  from programacion.contract_traceability_rows r
  where r.matrix_id=(select id from m)
), missing as (
  select clause_key from ck
  except
  select clause_key from mr
), extra as (
  select clause_key from mr
  except
  select clause_key from ck
)
select
  (select count(*) from ck) as contract_clause_count,
  (select clause_count from m) as matrix_declared_clause_count,
  (select count(*) from mr) as matrix_row_count,
  (select count(*) from missing) as missing_clause_count,
  (select count(*) from extra) as extra_clause_count,
  (select count(*) from mr where target_layer is null or target_owner is null or target_enforcement is null) as unmapped_target_count,
  (select count(*) from mr where row_status<>'DEFINED') as non_defined_row_count,
  (select especificacion->'legacy_contract_v1_authoritative' from programacion.contratos where id=(select contract_id from m)) as legacy_v1_value,
  (select especificacion->'legacy_contract_v2_authoritative' from programacion.contratos where id=(select contract_id from m)) as legacy_v2_value,
  (select count(*) from mr where clause_key in ('legacy_contract_v1_authoritative','legacy_contract_v2_authoritative')
      and target_layer='READINESS_POLICY'
      and target_owner='READINESS_POLICY'
      and target_enforcement='FAIL_CLOSED_READINESS_POLICY') as legacy_explicit_mapping_count,
  (select matrix_sha256 from m) as matrix_sha256
$q$
      ),
      'persist',jsonb_build_object(
        'on_pass','DONE',
        'entrypoint','programacion.fn_engineering_checkpoint_transition_v1',
        'next_state','RETURNED_BOOTSTRAP_ONLY'
      ),
      'forbidden',jsonb_build_array(
        'LIST_KEYS_WITHOUT_SET_EQUIVALENCE',
        'IGNORE_CURRENT_CONTRACT_CLAUSES',
        'UPDATE_APPEND_ONLY_TRACEABILITY_REVISION_1',
        'INFER_LEGACY_AUTHORITY_DECISION_FROM_ABSENCE'
      ),
      'contract_correction','TRACEABILITY_REV2_EXACT_SET_EQUALITY_AFTER_R5C'
    )
  ),
  true
)
where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
  and unit_code='M1.8';

insert into public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,
  frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia,lifecycle_phase,
  consumer_role,root_cause_family,detectability,source_context,source_ref
) values (
  'INPUT-GOV-CONTRACT-TRACEABILITY-CURRENT-CLAUSE-DRIFT-001',
  'INPUT_GOVERNANCE',
  'Traceability negative must compare the current contract key set, not trust historical clause_count',
  'M1.8 inherited a 60-row traceability matrix while R5-C added validator_evidence_required_fields_scope and validator_evidence_storage_contract to the same 5.13 contract representation. The old negative only listed contract keys and could not detect the two unmapped clauses.',
  'Traceability completeness was treated as a historical matrix property instead of exact set equality against the current contract representation.',
  'HISTORICAL_TRACEABILITY_COUNT_MASKS_NEW_CURRENT_CLAUSES',
  'For compatibility negatives, compare current contract keys against the current traceability revision using bidirectional EXCEPT. Preserve historical matrices append-only and create a new revision whenever the current contract representation adds/removes clauses.',
  'Revision 2 copies the 60 historical mappings, adds the two R5-C storage/evidence clauses, requires 62/62 exact set equality, zero missing/extra/unmapped rows, and explicit false/mapped decisions for legacy_contract_v1_authoritative and legacy_contract_v2_authoritative.',
  'HIGH',1,now(),now(),'IG_CURATOR_VALIDATOR_REFACTOR_V2','ACTIVO',
  'supabase://programacion.contract_traceability_matrices/INPUT_READINESS_CONTRACT_5_13_TRACEABILITY@2; github://cristhianlujan/claude-persona-lf-patch/supabase/migrations/20261006204044_input_governance_r5_c_logical_readers_storage_compaction_v1.sql',
  'EXECUTION',
  array['INPUT_GOVERNANCE','ENGINEERING_SCHEDULER']::text[],
  'R2_NO_VE','LOUD_EARLY',
  'M1.8 UNMAPPED_NEGATIVE currentness repair',
  'supabase://programacion.contract_traceability_matrices'
)
on conflict (codigo) do update set
  descripcion=excluded.descripcion,
  causa_raiz=excluded.causa_raiz,
  patron=excluded.patron,
  prevencion=excluded.prevencion,
  validacion=excluded.validacion,
  evidencia=excluded.evidencia,
  ultima_vez=now(),
  updated_at=now();

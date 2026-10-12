-- POL-LF-MIGRATION-NAMING v1.0: deliver the migration naming rule (PRV-CI-009)
-- through the Router snapshot of ACTUALIZACION_DB_LF.
-- The policy points to the git classifier as the list authority; it does not
-- duplicate the prefix/name lists. No schema change, no runtime change.
-- Requires the canonical execution EXEC-DB-MIGRATION-NAMING-POLICY-20261012-001
-- (operation ACTUALIZACION_DB_LF, IN_PROGRESS) to exist before apply.
begin;

do $pre$
begin
  if not exists (
    select 1 from public.lf_operation_execution
    where execution_id = 'EXEC-DB-MIGRATION-NAMING-POLICY-20261012-001'
      and operation_code = 'ACTUALIZACION_DB_LF'
      and status = 'IN_PROGRESS'
  ) then
    raise exception 'LF_MIGRATION_NAMING_POLICY_EXECUTION_MISSING';
  end if;
  if exists (select 1 from public.lf_activos where codigo_activo = 'POL-LF-MIGRATION-NAMING') then
    raise exception 'LF_MIGRATION_NAMING_POLICY_ASSET_ALREADY_EXISTS';
  end if;
  if not exists (
    select 1 from transversal.prevention_rules
    where regla_codigo = 'PRV-CI-009' and activa is true
  ) then
    raise exception 'LF_MIGRATION_NAMING_PREVENTION_RULE_MISSING';
  end if;
end $pre$;

insert into public.lf_activos (
  codigo_activo, nombre_canonico, tipo_activo, subtipo_activo,
  estado_documental, estado_operativo, version, url, owner_name,
  nivel_control, formato_nativo, runtime_estado, impacto_automatico,
  ruta_esperada, tipo_original, estado_original, accion_migracion,
  rol_arquitectura, ultima_revision,
  source_spreadsheet_id, source_spreadsheet_title, source_sheet_name,
  source_row_number, migration_batch_id, raw_payload, metadata,
  created_by_execution_id, updated_by_execution_id
) values (
  'POL-LF-MIGRATION-NAMING', 'POL_LF_MIGRATION_NAMING', 'REGLA', 'POLICY_OPERATION_GOV',
  'VIGENTE', 'ACTIVO', 'v1.0',
  'supabase://public/lf_policy_versions/POL-LF-MIGRATION-NAMING/v1.0', 'LF_GOVERNANCE',
  'GOVERNANCE_ENFORCED', 'SUPABASE_JSONB', 'NO_APLICA', 'BLOQUEADO',
  'Supabase/public/lf_policy_versions/POL-LF-MIGRATION-NAMING', 'POLICY', 'NUEVO_CANONICO', 'INVENTARIADO_SUPABASE',
  'Migration naming rule delivered to agents before a migration PR is labeled', '2026-10-12',
  'SUPABASE_DIRECT_INVENTORY', 'LF_SUPABASE_SANDBOX', 'public.lf_activos',
  0, 'a3c5e2d1-6f4b-4c1e-9b7a-20261012f0c1'::uuid,
  '{"key":"POL-LF-MIGRATION-NAMING","class":"POLICY"}'::jsonb,
  jsonb_build_object(
    'policy_kind', 'MIGRATION_NAMING_POLICY',
    'snapshot_view', 'public.v_lf_operation_policy_snapshot',
    'applies_to_operations', jsonb_build_array('ACTUALIZACION_DB_LF'),
    'canonical_policy_store', 'public.lf_policy_versions',
    'operation_binding_store', 'public.lf_operation_policy_bindings',
    'prevention_rule', 'PRV-CI-009',
    'precedents_are_authority', false
  ),
  'EXEC-DB-MIGRATION-NAMING-POLICY-20261012-001', 'EXEC-DB-MIGRATION-NAMING-POLICY-20261012-001'
);

with p as (
  select jsonb_build_object(
    'policy_kind', 'MIGRATION_NAMING_POLICY',
    'version', 'v1.0',
    'scope', 'OPERATION_ACTUALIZACION_DB_LF',
    'authority', 'GIT_CLASSIFIER_ON_MAIN',
    'prevention_rule', 'PRV-CI-009',
    'classifier_path', 'sandbox/lf_contract_gate_test/migration_source_parity/lf_migration_source_parity_ci_context.py',
    'classifier_ref', 'main',
    'name_definition', 'migration filename without the 14-digit version and .sql',
    'accepted_if_any', jsonb_build_array(
      'MANAGED_PREFIXES', 'STRATEGY_MIGRATION_RE', 'MANAGED_EXACT_NAMES',
      'CLASSIFIED_EXTERNAL_PREFIXES', 'CLASSIFIED_EXTERNAL_NAMES'),
    'rules', jsonb_build_array(
      'READ_CLASSIFIER_ON_MAIN_BEFORE_NAMING_A_MIGRATION',
      'UNCLASSIFIED_NAME_REQUIRES_SEPARATE_CLASSIFICATION_PR_MERGED_TO_MAIN_FIRST',
      'CLASSIFICATION_PR_INCLUDES_POSITIVE_AND_NEGATIVE_TEST',
      'NO_PREFIX_BROADENING_WITHOUT_OWNER_APPROVAL',
      'DO_NOT_LABEL_READY_TO_MERGE_IF_UNCLASSIFIED',
      'LISTS_LIVE_ONLY_IN_CLASSIFIER_NOT_IN_THIS_POLICY'),
    'failure_code', 'FAIL_UNCLASSIFIED_POST_CUTOVER_MIGRATION',
    'known_gap', 'TRAIN_CLASSIFIES_AFTER_APPLY_UNTIL_PRE_APPLY_CHECK_LANDS',
    'test_pattern', 'sandbox/lf_contract_gate_test/migration_source_parity/test_f0_train_exact_classification.py'
  ) as payload
)
insert into public.lf_policy_versions
  (policy_code, policy_version, policy_payload, policy_sha, status, effective_at, source_ref, created_by_execution_id)
select 'POL-LF-MIGRATION-NAMING', 'v1.0', payload,
       encode(extensions.digest(convert_to(payload::text, 'UTF8'), 'sha256'), 'hex'),
       'ACTIVE', clock_timestamp(),
       'supabase/migrations/20261012220000_lf_migration_naming_policy_v1.sql',
       'EXEC-DB-MIGRATION-NAMING-POLICY-20261012-001'
from p;

insert into public.lf_operation_policy_bindings
  (operation_code, policy_code, policy_role, required, distribution_modes, binding_status, created_by_execution_id)
values
  ('ACTUALIZACION_DB_LF', 'POL-LF-MIGRATION-NAMING', 'MIGRATION_NAMING', true,
   array['DIRECT', 'ROUTER'], 'ACTIVE', 'EXEC-DB-MIGRATION-NAMING-POLICY-20261012-001');

do $post$
begin
  if (select count(*) from public.v_lf_operation_policy_snapshot
      where operation_code = 'ACTUALIZACION_DB_LF'
        and policy_code = 'POL-LF-MIGRATION-NAMING'
        and policy_version = 'v1.0'
        and policy_role = 'MIGRATION_NAMING'
        and policy_payload->>'prevention_rule' = 'PRV-CI-009'
        and length(policy_payload::text) <= 1800) <> 1 then
    raise exception 'LF_MIGRATION_NAMING_POLICY_SNAPSHOT_INVALID';
  end if;
  if (select count(*) from public.v_lf_operation_policy_snapshot
      where operation_code = 'ACTUALIZACION_DB_LF') <> 5 then
    raise exception 'LF_MIGRATION_NAMING_POLICY_UNEXPECTED_BINDING_COUNT';
  end if;
end $post$;

commit;

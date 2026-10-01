-- IG_CURATOR_VALIDATOR_REFACTOR_V2 · L1
-- Register the reconciled L1 source inventory as a candidate capability only.
-- No approval, no promotion, no runtime binding, no relation to T-SOURCE is asserted.

begin;

do $candidate$
declare
  v_batch constant uuid := '1a4f1d14-5d36-4f6c-a01e-1a0f11500001'::uuid;
  v_exec constant text := 'IG-CV-L1-SOURCE-INVENTORY-CANDIDATE-20260930';
  v_code constant text := 'PROGRAMACION_INPUT_SOURCE_INVENTORY_L1';
  v_count integer;
begin
  if exists (
    select 1 from public.lf_activos
    where codigo_activo=v_code and archived_at is null
  ) then
    raise exception 'SOURCE_INVENTORY_CANDIDATE_ALREADY_EXISTS';
  end if;

  if to_regclass('programacion.input_source_inventory_l1') is null
     or to_regclass('programacion.v_input_source_inventory_l1_v1') is null
     or to_regprocedure('programacion.fn_input_source_inventory_lookup_l1_v1(text)') is null
  then
    raise exception 'SOURCE_INVENTORY_RUNTIME_SURFACE_INCOMPLETE';
  end if;

  if (
    select count(*)
    from supabase_migrations.schema_migrations
    where version='20260930211500'
      and name='lf_input_source_inventory_l1_reconcile_v1'
  ) <> 1 then
    raise exception 'SOURCE_INVENTORY_RECONCILIATION_NOT_LEDGERED';
  end if;

  if (select count(*) from programacion.input_source_inventory_l1) <> 54 then
    raise exception 'SOURCE_INVENTORY_ROW_COUNT_DRIFT';
  end if;

  insert into public.lf_activos(
    codigo_activo,nombre_canonico,tipo_activo,subtipo_activo,
    estado_documental,estado_operativo,nivel_control,runtime_estado,impacto_automatico,
    accion_migracion,version,ruta_esperada,url,owner_name,rol_arquitectura,
    source_spreadsheet_id,source_spreadsheet_title,source_sheet_name,source_row_number,
    migration_batch_id,raw_payload,metadata,created_by_execution_id,updated_by_execution_id
  ) values (
    v_code,
    'programacion.input_source_inventory_l1',
    'CAPABILITY',
    'SOURCE_INVENTORY',
    'CANDIDATO',
    'READ_ONLY',
    'CONTROLADO',
    'CANDIDATE_READ_ONLY',
    'BLOQUEADO',
    'REGISTER_SOURCE_INVENTORY_CANDIDATE',
    'v1',
    null,
    'supabase://programacion/input_source_inventory_l1',
    'LF_GOVERNANCE',
    'Inventario de fuentes de Input Governance L1. Discovery index only; no canonical business rows are duplicated. Pending transversal qualification.',
    'SUPABASE_DIRECT_CONTROLLED_ENTRY',
    'LF_OPERATION_CONTROLLED_CANDIDATES',
    'INPUT_SOURCE_INVENTORY_L1_20260930',
    1,
    v_batch,
    jsonb_build_object(
      'table','programacion.input_source_inventory_l1',
      'view','programacion.v_input_source_inventory_l1_v1',
      'lookup','programacion.fn_input_source_inventory_lookup_l1_v1(text)',
      'row_count',54,
      'reconciliation_migration','20260930211500',
      'table_sha256','1e6d387bf41f443051ae023d28f251e7209a19dedabd9009e7b13c4792ad280d',
      'view_sha256','17214d508ece399dd250252e3efaddbcb92d49f407b715c5604d7b5dd7406fe0',
      'function_sha256','2939fae3252aaf08367b5e5a28dbf01ee411981e09fd80a786fa188697f7c782',
      'data_sha256','71941b10ece0bb159fd05f77ec6c6848b100854705e627c28244541a58b0642e'
    ),
    jsonb_build_object(
      'dominio','INPUT_GOVERNANCE',
      'inventory_status','CANDIDATE_PENDING_QUALIFICATION',
      'approval_status','NOT_APPROVED',
      'semantics','DISCOVERY_INDEX_ONLY',
      'canonical_rows_duplicated',false,
      'source_count',54,
      'candidate_duplicate_risk',jsonb_build_array('T-SOURCE','TYPED_DATA_ACCESS'),
      'l2_decision_note','decidir en L2 si lo absorbe T-SOURCE',
      'transversal_owner_decision_required',true,
      'no_runtime_binding_asserted',true,
      'no_relation_inserted_reason','No verified runtime consumer relation; avoid inventing dependency before L2 qualification.',
      'observed_global_inventory_overlap','inventory.* exists live but remains separate drift reconciliation scope at registration time',
      'state_model_authority','POL-LF-STATE-MODEL/v2.0-canonical-lifecycle'
    ),
    v_exec,
    v_exec
  );

  select count(*) into v_count
  from public.lf_activos
  where migration_batch_id=v_batch
    and codigo_activo=v_code
    and archived_at is null
    and estado_documental='CANDIDATO'
    and estado_operativo='READ_ONLY'
    and runtime_estado='CANDIDATE_READ_ONLY'
    and metadata->>'approval_status'='NOT_APPROVED'
    and metadata->>'l2_decision_note'='decidir en L2 si lo absorbe T-SOURCE';

  if v_count <> 1 then
    raise exception 'SOURCE_INVENTORY_CANDIDATE_POSTCHECK:%',v_count;
  end if;
end
$candidate$;

commit;

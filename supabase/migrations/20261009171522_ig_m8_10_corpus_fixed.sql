-- IG_CURATOR_VALIDATOR_REFACTOR_V2 / M8.10 / CORPUS_FIXED
-- Freezes the benchmark corpus (screen x fixture) as DATA with a SHA-256.
-- Fixture = the latest fully COMPLETED run (Curator + Validator) of each screen: an exact, replayable input.
-- Screens with no completed run are listed as excluded (not silently dropped).
-- Governance-only: no runtime, timeout, Edge, deploy or production change.
do $preflight$
declare v_n int;
begin
  select count(distinct pantalla_id) into v_n from programacion.input_readiness_runs
   where status='COMPLETED' and validator_completed_at is not null;
  if v_n < 1 then raise exception 'IG_M8_10_CORPUS_NO_COMPLETED_RUNS'; end if;
  if exists (select 1 from public.lf_activos where codigo_activo='INPUT_GOVERNANCE_BENCHMARK_CORPUS_V1' and archived_at is null) then
    raise exception 'IG_M8_10_CORPUS_ASSET_ALREADY_EXISTS';
  end if;
end
$preflight$;

do $persist$
declare
  v_exec constant text := 'CLAUDE-IG-M8-10-CORPUS-FIXED';
  v_batch uuid := gen_random_uuid();
  v_entries jsonb;
  v_excluded jsonb;
  v_sha text;
begin
  select coalesce(jsonb_agg(jsonb_build_object('pantalla_id',x.pantalla_id,'codigo',x.codigo,'fixture_run_id',x.run_id) order by x.pantalla_id),'[]'::jsonb)
    into v_entries
  from (select r.pantalla_id, p.codigo, max(r.id) run_id
          from programacion.input_readiness_runs r
          join lf_ops.pantallas p on p.id=r.pantalla_id
         where r.status='COMPLETED' and r.validator_completed_at is not null
         group by r.pantalla_id, p.codigo) x;

  select coalesce(jsonb_agg(jsonb_build_object('pantalla_id',p.id,'codigo',p.codigo,'reason','NO_COMPLETED_RUN') order by p.id),'[]'::jsonb)
    into v_excluded
  from lf_ops.pantallas p
  where p.activa and not exists (select 1 from programacion.input_readiness_runs r
                                  where r.pantalla_id=p.id and r.status='COMPLETED' and r.validator_completed_at is not null);

  select encode(extensions.digest(convert_to(string_agg(e->>'pantalla_id'||':'||(e->>'fixture_run_id'),E'\n' order by (e->>'pantalla_id')::bigint),'UTF8'),'sha256'),'hex')
    into v_sha from jsonb_array_elements(v_entries) e;

  insert into public.lf_activos(
    codigo_activo,nombre_canonico,tipo_activo,subtipo_activo,tipo_original,formato_nativo,linea_codigo,
    estado_original,estado_documental,estado_operativo,nivel_control,runtime_estado,impacto_automatico,
    accion_migracion,version,ruta_esperada,url,owner_name,ultima_revision,rol_arquitectura,
    source_spreadsheet_id,source_spreadsheet_title,source_sheet_name,source_row_number,migration_batch_id,
    raw_payload,metadata,created_by_execution_id,updated_by_execution_id
  ) values (
    'INPUT_GOVERNANCE_BENCHMARK_CORPUS_V1','INPUT_GOVERNANCE_BENCHMARK_CORPUS_V1',
    'CONTRACT','GOVERNANCE','M8.10_BENCHMARK_CORPUS','JSON',null,
    'M8_10_CORPUS_FIXED','VIGENTE','READ_ONLY','GOVERNED_CONTRACT','NO_RUNTIME_CHANGE','BLOQUEADO',
    'REGISTER_GOVERNED_CONTRACT','1.0.0',null,null,'INPUT_GOVERNANCE',v_sha,
    'PERFORMANCE_QUALITY_GUARD',
    'SUPABASE:IG_CURATOR_VALIDATOR_REFACTOR_V2','IG_CURATOR_VALIDATOR_REFACTOR_V2','M8.10',1,v_batch,
    jsonb_build_object('status','CORPUS_FIXED_ONLY','runtime_change',false,'timeout_tuning',false,'production_authorized',false,
                       'fixture_rule','LATEST_COMPLETED_RUN_PER_PANTALLA','corpus_sha256',v_sha,'entries',jsonb_array_length(v_entries)),
    jsonb_build_object('schema_version','LF_IG_BENCHMARK_CORPUS_V1','plan_code','IG_CURATOR_VALIDATOR_REFACTOR_V2','unit_code','M8.10',
                       'corpus_sha256',v_sha,'entries',v_entries,'excluded',v_excluded,
                       'consumer_capability','PERFORMANCE_EXACT_SOURCE_BENCHMARK@1.0.0'),
    v_exec,v_exec);

  insert into public.lf_activo_relaciones(codigo_activo,relacionado_codigo,relacion_tipo,valor_original,fuente,migration_batch_id,created_by_execution_id,updated_by_execution_id)
  values ('INPUT_GOVERNANCE_BENCHMARK_CORPUS_V1','PERFORMANCE_EXACT_SOURCE_BENCHMARK','DEPENDE_DE','T-PERF@1.0.0','supabase://lf_activos/INPUT_GOVERNANCE_BENCHMARK_CORPUS_V1',v_batch,v_exec,v_exec),
         ('INPUT_GOVERNANCE_BENCHMARK_CORPUS_V1','INPUT_GOVERNANCE_PERFORMANCE_ASSURANCE_V1','DEPENDE_DE','M8.0',     'supabase://lf_activos/INPUT_GOVERNANCE_BENCHMARK_CORPUS_V1',v_batch,v_exec,v_exec);
end
$persist$;

do $selftest$
declare v_meta jsonb; v_calc text; v_n int; v_rel int;
begin
  select metadata into v_meta from public.lf_activos where codigo_activo='INPUT_GOVERNANCE_BENCHMARK_CORPUS_V1' and archived_at is null;
  if v_meta is null then raise exception 'IG_M8_10_CORPUS_SELFTEST_ASSET_MISSING'; end if;
  select encode(extensions.digest(convert_to(string_agg(e->>'pantalla_id'||':'||(e->>'fixture_run_id'),E'\n' order by (e->>'pantalla_id')::bigint),'UTF8'),'sha256'),'hex'), count(*)
    into v_calc, v_n from jsonb_array_elements(v_meta->'entries') e;
  if v_calc is distinct from v_meta->>'corpus_sha256' or v_n=0 then raise exception 'IG_M8_10_CORPUS_SELFTEST_SHA_MISMATCH'; end if;
  if exists (select 1 from jsonb_array_elements(v_meta->'entries') e
              where not exists (select 1 from programacion.input_readiness_runs r where r.id=(e->>'fixture_run_id')::bigint and r.pantalla_id=(e->>'pantalla_id')::bigint and r.status='COMPLETED' and r.validator_completed_at is not null)) then
    raise exception 'IG_M8_10_CORPUS_SELFTEST_FIXTURE_NOT_COMPLETED';
  end if;
  select count(*) into v_rel from public.lf_activo_relaciones where codigo_activo='INPUT_GOVERNANCE_BENCHMARK_CORPUS_V1';
  if v_rel<>2 then raise exception 'IG_M8_10_CORPUS_SELFTEST_RELATIONS:%',v_rel; end if;
end
$selftest$;

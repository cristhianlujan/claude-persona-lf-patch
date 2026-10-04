-- IG_CURATOR_VALIDATOR_REFACTOR_V2 · M9.4 / PAULO-154
-- Governed representative cohorts as data. No soak/canary/release-candidate execution.
-- Source artifact blob SHA-1: 3caf20a9b8c6d1444930383361b614bfbf32c266

begin;

do $m9_4_preflight$
declare
  v_work_status text;
  v_blockers integer;
  v_seed_screens integer;
  v_old_sweep text;
begin
  select w.status,
         (select count(*) from programacion.engineering_work_blockers b where b.work_item_id=w.id and coalesce(b.status,'OPEN') not in ('DONE','RESOLVED','CLOSED'))
    into v_work_status,v_blockers
  from programacion.engineering_work_items w
  where w.id=467 and w.work_code='PAULO-154';

  if v_work_status is null then
    raise exception 'M9_4_WORK_ITEM_NOT_FOUND';
  end if;
  if v_work_status='DONE' then
    raise exception 'M9_4_ALREADY_DONE';
  end if;
  if v_blockers<>0 then
    raise exception 'M9_4_OPEN_BLOCKERS:%',v_blockers;
  end if;

  if to_regclass('programacion.input_governance_cohort_types') is not null
     or to_regclass('programacion.input_governance_cohort_memberships') is not null
     or to_regclass('programacion.v_input_governance_representative_cohort_v1') is not null then
    raise exception 'M9_4_COHORT_AUTHORITY_ALREADY_EXISTS';
  end if;

  if exists (select 1 from transversal.decision_log where adr='DEC-INPUT-GOV-M9.4-COHORT-SELECTION-001') then
    raise exception 'M9_4_DECISION_ALREADY_EXISTS';
  end if;
  if exists (select 1 from public.lf_error_knowledge where codigo='IG-M9-4-GOVERNED-COHORTS-001') then
    raise exception 'M9_4_EKB_ALREADY_EXISTS';
  end if;
  if exists (select 1 from public.lf_activos where codigo_activo='INPUT_GOVERNANCE_COHORT_SELECTION_V1' and archived_at is null) then
    raise exception 'M9_4_ASSET_ALREADY_EXISTS';
  end if;

  select p.prosrc into v_old_sweep
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='programacion' and p.proname='fn_input_governance_shadow_sweep_v2';
  if v_old_sweep is null then
    raise exception 'M9_4_SHADOW_SWEEP_NOT_FOUND';
  end if;
  if v_old_sweep not ilike '%p.codigo in (%' or v_old_sweep not ilike '%order by case p.codigo%' then
    raise exception 'M9_4_ASIS_LITERAL_DRIFT';
  end if;

  select count(*) into v_seed_screens
  from lf_ops.pantallas p
  where p.codigo in ('B2B-AUTH-001','ONB_004','HOME_001','B2B-SIMULA-002','ONB_001','REC_001','ONB_002')
    and p.activa=true and p.module_id is not null;
  if v_seed_screens<>7 then
    raise exception 'M9_4_REPRESENTATIVE_SCREENS_NOT_JOINABLE:%',v_seed_screens;
  end if;

  if not exists (
    select 1 from transversal.decision_log
    where adr='DEC-INPUT-GOV-512-API-STAGE-HUMAN-001' and upper(estado)='VIGENTE'
  ) then
    raise exception 'M9_4_API_SELECTION_AUTHORITY_MISSING';
  end if;
end
$m9_4_preflight$;

create table programacion.input_governance_cohort_types (
  cohort_type_code text primary key,
  label text not null unique,
  display_order smallint not null unique check (display_order between 1 and 100),
  selection_contract jsonb not null,
  authority_ref text not null,
  status text not null default 'ACTIVE' check (status in ('ACTIVE','INACTIVE')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table programacion.input_governance_cohort_memberships (
  cohort_type_code text not null references programacion.input_governance_cohort_types(cohort_type_code) on update cascade on delete restrict,
  pantalla_id integer not null references lf_ops.pantallas(id) on update cascade on delete restrict,
  representative_rank smallint not null default 1 check (representative_rank>0),
  selection_basis jsonb not null,
  authority_ref text not null,
  status text not null default 'ACTIVE' check (status in ('ACTIVE','INACTIVE')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (cohort_type_code,pantalla_id)
);

insert into programacion.input_governance_cohort_types(
  cohort_type_code,label,display_order,selection_contract,authority_ref,status
) values
  ('AUTH','auth',1,'{"observable":"module/name identify authentication entry"}'::jsonb,'lf_ops.pantallas+lf_ops.modulos','ACTIVE'),
  ('FORMS','formularios',2,'{"observable":"screen materially captures structured user input"}'::jsonb,'lf_ops.pantallas','ACTIVE'),
  ('NAVIGATION','navegación',3,'{"observable":"screen is an entry/routing surface between governed flows"}'::jsonb,'lf_ops.pantallas+lf_ops.modulos','ACTIVE'),
  ('DESIGN','diseño',4,'{"observable":"screen has material visual interaction complexity"}'::jsonb,'lf_ops.pantallas+lf_ops.modulos','ACTIVE'),
  ('ONBOARDING','onboarding',5,'{"observable":"flow/step identifies onboarding"}'::jsonb,'lf_ops.pantallas','ACTIVE'),
  ('RECOVERY','recuperación',6,'{"observable":"flow/step identifies recovery"}'::jsonb,'lf_ops.pantallas','ACTIVE'),
  ('API','API',7,'{"observable":"positive API_DATA_CONTRACT behavioral authority exists"}'::jsonb,'transversal.decision_log/DEC-INPUT-GOV-512-API-STAGE-HUMAN-001','ACTIVE');

with seed(cohort_type_code,screen_code,representative_rank,selection_basis,authority_ref) as (
  values
    ('AUTH','B2B-AUTH-001',1,'{"module_code":"B2B_AUTENTICACION","name":"Iniciar sesión"}'::jsonb,'lf_ops.pantallas+lf_ops.modulos'),
    ('FORMS','ONB_004',1,'{"flow":"onboarding","step":"4 de 4","captures":["name","email","terms"]}'::jsonb,'lf_ops.pantallas'),
    ('NAVIGATION','HOME_001',1,'{"module_code":"CLIENT_HOME","flow":"home","routing_property":"public entry CTA routes to onboarding"}'::jsonb,'lf_ops.pantallas+lf_ops.modulos'),
    ('DESIGN','B2B-SIMULA-002',1,'{"module_code":"B2B_SIMULA","visual_properties":["matrix_heatmap","multi_cell_selection","range_editing"]}'::jsonb,'lf_ops.pantallas+lf_ops.modulos'),
    ('ONBOARDING','ONB_001',1,'{"flow":"onboarding","step":"1 de 3"}'::jsonb,'lf_ops.pantallas'),
    ('RECOVERY','REC_001',1,'{"flow":"recovery","step":"post-DNI recovery"}'::jsonb,'lf_ops.pantallas'),
    ('API','ONB_002',1,'{"api_data_contract_story_ready":true,"decision":"DEC-INPUT-GOV-512-API-STAGE-HUMAN-001"}'::jsonb,'transversal.decision_log/DEC-INPUT-GOV-512-API-STAGE-HUMAN-001')
)
insert into programacion.input_governance_cohort_memberships(
  cohort_type_code,pantalla_id,representative_rank,selection_basis,authority_ref,status
)
select s.cohort_type_code,p.id,s.representative_rank,s.selection_basis,s.authority_ref,'ACTIVE'
from seed s
join lf_ops.pantallas p on p.codigo=s.screen_code;

create view programacion.v_input_governance_representative_cohort_v1
with (security_invoker=true)
as
select
  t.cohort_type_code,
  t.label as cohort_type,
  t.display_order,
  m.representative_rank,
  p.id as pantalla_id,
  p.codigo as screen_code,
  p.nombre as screen_name,
  p.module_id,
  p.module_code,
  p.flujo,
  p.paso,
  m.selection_basis,
  m.authority_ref
from programacion.input_governance_cohort_types t
join programacion.input_governance_cohort_memberships m
  on m.cohort_type_code=t.cohort_type_code and m.status='ACTIVE'
join lf_ops.pantallas p
  on p.id=m.pantalla_id and p.activa=true and p.module_id is not null
where t.status='ACTIVE';

create or replace function programacion.fn_input_governance_shadow_sweep_v2(p_version_id bigint default 19)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog'
as $function$
declare
  v_screen record;
  v_eval jsonb;
  v_rows jsonb:='[]'::jsonb;
  v_screen_count integer:=0;
  v_type_count integer:=0;
  v_payload jsonb;
begin
  select count(distinct cohort_type_code) into v_type_count
  from programacion.v_input_governance_representative_cohort_v1;

  for v_screen in
    select
      v.pantalla_id as id,
      max(v.screen_code) as codigo,
      max(v.screen_name) as nombre,
      jsonb_agg(v.cohort_type order by v.display_order) as cohort_types,
      min(v.display_order) as cohort_order
    from programacion.v_input_governance_representative_cohort_v1 v
    group by v.pantalla_id
    order by min(v.display_order),v.pantalla_id
  loop
    v_screen_count:=v_screen_count+1;
    v_eval:=programacion.fn_input_governance_shadow_evaluate_v2(v_screen.id,p_version_id);
    v_rows:=v_rows||jsonb_build_array(jsonb_build_object(
      'pantalla_id',v_screen.id,
      'screen_code',v_screen.codigo,
      'name',v_screen.nombre,
      'cohort_types',v_screen.cohort_types,
      'summary',v_eval->'summary',
      'shadow_sha256',v_eval->>'shadow_sha256'
    ));
  end loop;

  v_payload:=jsonb_build_object(
    'shadow_contract','INPUT_GOVERNANCE_SHADOW_SWEEP_V2',
    'version_id',p_version_id,
    'decisional',false,
    'mutates_readiness',false,
    'promotion_authorized',false,
    'production_authorized',false,
    'representative_sample',true,
    'cohort_authority','programacion.v_input_governance_representative_cohort_v1',
    'cohort_type_count',v_type_count,
    'screen_count',v_screen_count,
    'screens',v_rows
  );
  return v_payload||jsonb_build_object('shadow_sha256',programacion.fn_v09_sha256_jsonb(v_payload));
end;
$function$;

comment on table programacion.input_governance_cohort_types is 'M9.4 governed catalog for representative Input Governance cohort types.';
comment on table programacion.input_governance_cohort_memberships is 'M9.4 governed screen-to-cohort relations; runtime selection must consume these relations rather than screen literals.';
comment on view programacion.v_input_governance_representative_cohort_v1 is 'M9.4 read model: active, joinable representative screens by governed cohort type.';
comment on function programacion.fn_input_governance_shadow_sweep_v2(bigint) is 'Non-decisional v2 shadow sweep; screen selection is governed by M9.4 cohort data and contains no screen literal authority.';

do $m9_4_governance$
declare
  v_execution_id constant text := 'CHATGPT-IG-CV-M9-4-20261004';
  v_batch uuid := gen_random_uuid();
  v_source_blob constant text := '3caf20a9b8c6d1444930383361b614bfbf32c266';
  v_source_ref constant text := 'github://cristhianlujan/claude-persona-lf-patch/docs/ig_refactor/m9_4_governed_cohorts_v1.json#blob=3caf20a9b8c6d1444930383361b614bfbf32c266';
begin
  insert into transversal.decision_log(adr,titulo,decision,razon,impacto,estado)
  values (
    'DEC-INPUT-GOV-M9.4-COHORT-SELECTION-001',
    'M9.4 cohortes representativas gobernadas como datos',
    'M9.4 / PAULO-154 reemplaza la muestra fija de fn_input_governance_shadow_sweep_v2 por una autoridad de datos compuesta por catálogo de 7 tipos, relaciones pantalla→tipo y un read-model reutilizable. Los tipos vigentes son auth, formularios, navegación, diseño, onboarding, recuperación y API. Runtime shadow/canary/sweep no puede gobernar la selección mediante IDs o códigos literales de pantalla.',
    'El AS-IS embebía 8 códigos en p.codigo IN (...) y CASE p.codigo. La autoridad efectiva estaba en código, impedía evolución sin redeploy y ocultaba la representatividad por tipo. La nueva relación usa lf_ops.pantallas y lf_ops.modulos y conserva evidencia observable por membresía.',
    'Cambia únicamente la autoridad de selección representativa y el cuerpo del sweep para consumirla. No ejecuta soak, canary, release candidate ni promoción/producción. Literales de pantalla usados por oracles semánticos fuera de selección no se modifican.',
    'VIGENTE'
  );

  insert into public.lf_activos(
    codigo_activo,nombre_canonico,tipo_activo,subtipo_activo,tipo_original,formato_nativo,linea_codigo,
    estado_original,estado_documental,estado_operativo,nivel_control,runtime_estado,impacto_automatico,
    accion_migracion,version,ruta_esperada,url,owner_name,ultima_revision,rol_arquitectura,
    source_spreadsheet_id,source_spreadsheet_title,source_sheet_name,source_row_number,migration_batch_id,
    raw_payload,metadata,created_by_execution_id,updated_by_execution_id
  ) values (
    'INPUT_GOVERNANCE_COHORT_SELECTION_V1',
    'INPUT_GOVERNANCE_COHORT_SELECTION_V1',
    'CONTRACT','GOVERNANCE','M9.4_GOVERNED_COHORT_SELECTION','JSON+DB_RELATION',null,
    'M9_4_APPROVED','VIGENTE','READ_ONLY','GOVERNED_CONTRACT','RUNTIME_SELECTION_AUTHORITY','BLOQUEADO',
    'REGISTER_GOVERNED_CONTRACT','1.0.0','docs/ig_refactor/m9_4_governed_cohorts_v1.json',null,'SUPER_ADMIN',v_source_blob,
    'REPRESENTATIVE_COHORT_AUTHORITY',
    'GIT:IG_CURATOR_VALIDATOR_REFACTOR_V2','IG_CURATOR_VALIDATOR_REFACTOR_V2','M9.4',1,v_batch,
    jsonb_build_object(
      'status','APPROVED_SELECTION_ONLY',
      'source_ref',v_source_ref,
      'type_catalog','programacion.input_governance_cohort_types',
      'membership_authority','programacion.input_governance_cohort_memberships',
      'read_model','programacion.v_input_governance_representative_cohort_v1',
      'runtime_consumer','programacion.fn_input_governance_shadow_sweep_v2',
      'soak_executed',false,
      'canary_executed',false,
      'release_candidate_executed',false,
      'production_authorized',false
    ),
    jsonb_build_object(
      'schema_version','IG_COHORT_SELECTION_V1',
      'plan_code','IG_CURATOR_VALIDATOR_REFACTOR_V2',
      'unit_code','M9.4',
      'work_code','PAULO-154',
      'owner','SUPER_ADMIN',
      'required_types',jsonb_build_array('auth','formularios','navegación','diseño','onboarding','recuperación','API'),
      'owner_approval','CHAT_SCOPE_AND_M9_4_MERGE_AUTHORIZED'
    ),
    v_execution_id,v_execution_id
  );

  insert into public.lf_activo_relaciones(
    codigo_activo,relacionado_codigo,relacion_tipo,valor_original,fuente,migration_batch_id,
    created_by_execution_id,updated_by_execution_id
  ) values
    ('PROGRAMACION_FN_INPUT_GOVERNANCE_SHADOW_SET','INPUT_GOVERNANCE_COHORT_SELECTION_V1','DEPENDE_DE','M9.4 representative selection authority',v_source_ref,v_batch,v_execution_id,v_execution_id),
    ('INPUT_GOVERNANCE_COHORT_SELECTION_V1','INPUT_READINESS_CONTRACT','FUENTE_RECTORA','Screen/readiness authority remains canonical Input Governance contract + lf_ops registries',v_source_ref,v_batch,v_execution_id,v_execution_id);

  insert into public.lf_error_knowledge(
    id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
    severidad,frecuencia,primera_vez,ultima_vez,lote_origen,pr,estado,evidencia,
    created_at,updated_at,lifecycle_phase,consumer_role,root_cause_family,
    detectability,source_context,source_ref
  ) values (
    gen_random_uuid(),
    'IG-M9-4-GOVERNED-COHORTS-001',
    'INPUT_GOVERNANCE',
    'La muestra shadow/canary no debe estar gobernada por literales de pantalla',
    'M9.4 detectó que fn_input_governance_shadow_sweep_v2 contenía 8 códigos de pantalla embebidos. La selección se movió a catálogo + membresías + read-model gobernados como datos con cobertura explícita de 7 tipos.',
    'La representatividad estaba implícita en una lista IN y un CASE del runtime, sin autoridad pantalla→tipo trazable.',
    'Las cohortes representativas deben resolverse por relaciones de datos hacia lf_ops.pantallas/modulos; el runtime solo consume el read-model y no selecciona por IDs/códigos literales.',
    'Persistir tipos y membresías; exigir pantalla activa y module_id; registrar observable selection_basis y authority_ref; escanear funciones shadow/canary para detectar literales usados como mecanismo de selección.',
    'PASS cuando hay cobertura 7/7, 0 tipos sin pantalla activa/unible, fn_input_governance_shadow_sweep_v2 consume v_input_governance_representative_cohort_v1 y no contiene p.codigo IN ni CASE p.codigo ni códigos de pantalla de la muestra.',
    'HIGH',1,now(),now(),'IG_CURATOR_VALIDATOR_REFACTOR_V2',null,'ACTIVO',
    'M9.4 / PAULO-154; AS-IS 8 fixed screen codes; governed model 7 types/7 active joinable representatives; source blob 3caf20a9b8c6d1444930383361b614bfbf32c266.',
    now(),now(),'RELEASE_GOVERNANCE',array['INPUT_GOVERNANCE','CURATOR','VALIDATOR','AUDITOR'],
    'HARDCODED_SELECTION_AUTHORITY','LOUD_EARLY',
    'IG_CURATOR_VALIDATOR_REFACTOR_V2 M9.4 / PAULO-154',v_source_ref
  );

  update programacion.engineering_work_checkpoints c
  set status='DONE',
      evidence_ref=case c.checkpoint_code
        when 'SWEEP_LITERAL_ASIS' then 'github://cristhianlujan/claude-persona-lf-patch@449420bb1676dde460fbb048f749f790eab1b2f9/supabase/migrations/20260826150414_lf_input_governance_shadow_evaluator_v2.sql#fixed-8-screen-codes'
        when 'COHORT_DATA_MODEL' then 'supabase://programacion.input_governance_cohort_types|programacion.input_governance_cohort_memberships|programacion.v_input_governance_representative_cohort_v1'
        when 'TYPE_COVERAGE_7' then 'supabase://programacion.v_input_governance_representative_cohort_v1#7-of-7-types-active-joinable'
        when 'LITERAL_NEGATIVE' then 'supabase://pg_proc/programacion.fn_input_governance_shadow_sweep_v2#data-driven-selection-no-screen-literals'
        when 'COHORT_APPROVAL_READBACK' then 'supabase://transversal.decision_log/DEC-INPUT-GOV-M9.4-COHORT-SELECTION-001'
      end,
      completed_at=clock_timestamp(),updated_at=clock_timestamp(),updated_by_execution_id=v_execution_id
  where c.work_item_id=467;

  update programacion.engineering_plan_units u
  set unit_metadata=
    jsonb_set(
      jsonb_set(
        jsonb_set(
          jsonb_set(
            jsonb_set(coalesce(u.unit_metadata,'{}'::jsonb),
              '{source_pack_v1,checkpoint_inputs,COHORT_DATA_MODEL,missing}','[]'::jsonb,true),
            '{source_pack_v1,checkpoint_inputs,COHORT_DATA_MODEL,missing_typed}','[]'::jsonb,true),
          '{source_pack_v1,checkpoint_inputs,COHORT_DATA_MODEL,inputs,db_objects}',
          jsonb_build_array('programacion.input_governance_cohort_types','programacion.input_governance_cohort_memberships','programacion.v_input_governance_representative_cohort_v1','lf_ops.pantallas','lf_ops.modulos'),true),
        '{source_pack_v1,lookup_strategy_v2,preferred_input,source}',to_jsonb('programacion.v_input_governance_representative_cohort_v1'::text),true),
      '{m9_4_terminal}',
      jsonb_build_object(
        'status','DONE',
        'decision','DEC-INPUT-GOV-M9.4-COHORT-SELECTION-001',
        'asset','INPUT_GOVERNANCE_COHORT_SELECTION_V1',
        'source_blob_sha1',v_source_blob,
        'types_covered',7,
        'active_joinable_types',7,
        'runtime_selection_literals',0,
        'r17_preflight','PASS_ROLLBACK',
        'runtime_smoke_executed',false,
        'soak_executed',false,
        'canary_executed',false,
        'release_candidate_executed',false,
        'closed_at',clock_timestamp()
      ),true
    )
  where u.id=278 and u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and u.unit_code='M9.4';

  update programacion.engineering_work_items
  set status='DONE',completed_at=clock_timestamp(),updated_at=clock_timestamp(),updated_by_execution_id=v_execution_id
  where id=467 and work_code='PAULO-154';
end
$m9_4_governance$;

do $m9_4_readback$
declare
  v_type_count integer;
  v_covered integer;
  v_screen_count integer;
  v_literal_selectors integer;
  v_done_checkpoints integer;
begin
  select count(*) into v_type_count
  from programacion.input_governance_cohort_types
  where status='ACTIVE';
  if v_type_count<>7 then
    raise exception 'M9_4_TYPE_COUNT_FAILED:%',v_type_count;
  end if;

  select count(distinct cohort_type_code),count(distinct pantalla_id)
    into v_covered,v_screen_count
  from programacion.v_input_governance_representative_cohort_v1;
  if v_covered<>7 or v_screen_count<7 then
    raise exception 'M9_4_COVERAGE_FAILED:types=% screens=%',v_covered,v_screen_count;
  end if;

  if exists (
    select 1
    from programacion.input_governance_cohort_memberships m
    left join lf_ops.pantallas p on p.id=m.pantalla_id
    where m.status='ACTIVE' and (p.id is null or not coalesce(p.activa,false) or p.module_id is null)
  ) then
    raise exception 'M9_4_NON_JOINABLE_ACTIVE_MEMBERSHIP';
  end if;

  select count(*) into v_literal_selectors
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='programacion'
    and (p.proname ilike '%shadow%' or p.proname ilike '%canary%')
    and p.prosrc ~ '''(REC_[0-9]+|ONB_[0-9]+|HOME_[0-9]+|B2B-[A-Z]+-[0-9]+)'''
    and (
      p.prosrc ~* 'codigo[[:space:]]+in[[:space:]]*\\('
      or p.prosrc ~* 'order[[:space:]]+by[[:space:]]+case[[:space:]]+[^;]*codigo'
      or p.prosrc ~* 'pantalla_id[[:space:]]+in[[:space:]]*\\('
    );
  if v_literal_selectors<>0 then
    raise exception 'M9_4_LITERAL_SELECTOR_NEGATIVE_FAILED:%',v_literal_selectors;
  end if;

  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='programacion' and p.proname='fn_input_governance_shadow_sweep_v2'
      and p.prosrc ilike '%v_input_governance_representative_cohort_v1%'
      and p.prosrc not ilike '%p.codigo in (%'
      and p.prosrc not ilike '%order by case p.codigo%'
  ) then
    raise exception 'M9_4_SWEEP_READMODEL_BINDING_FAILED';
  end if;

  if (select count(*) from transversal.decision_log where adr='DEC-INPUT-GOV-M9.4-COHORT-SELECTION-001' and upper(estado)='VIGENTE')<>1 then
    raise exception 'M9_4_DECISION_READBACK_FAILED';
  end if;
  if (select count(*) from public.lf_activos where codigo_activo='INPUT_GOVERNANCE_COHORT_SELECTION_V1' and archived_at is null and estado_documental='VIGENTE')<>1 then
    raise exception 'M9_4_ASSET_READBACK_FAILED';
  end if;
  if (select count(*) from public.lf_activo_relaciones where relacionado_codigo='INPUT_GOVERNANCE_COHORT_SELECTION_V1' and relacion_tipo='DEPENDE_DE')<>1 then
    raise exception 'M9_4_RELATION_READBACK_FAILED';
  end if;
  if (select count(*) from public.lf_error_knowledge where codigo='IG-M9-4-GOVERNED-COHORTS-001' and estado='ACTIVO')<>1 then
    raise exception 'M9_4_EKB_READBACK_FAILED';
  end if;

  select count(*) into v_done_checkpoints
  from programacion.engineering_work_checkpoints
  where work_item_id=467 and required=true and status='DONE';
  if v_done_checkpoints<>5 then
    raise exception 'M9_4_CHECKPOINTS_NOT_DONE:%',v_done_checkpoints;
  end if;
  if (select status from programacion.engineering_work_items where id=467)<>'DONE' then
    raise exception 'M9_4_WORK_NOT_DONE';
  end if;
end
$m9_4_readback$;

commit;

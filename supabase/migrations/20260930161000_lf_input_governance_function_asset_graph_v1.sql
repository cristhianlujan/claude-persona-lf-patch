-- IG_CURATOR_VALIDATOR_REFACTOR_V2 · L1 · M0.4 (PAULO-103)
-- Register current Input Governance SQL assets as grouped DB_FUNCTION_SET capabilities,
-- plus a dedicated asset for the cross-team SQL entrypoint.
-- Registry-only: no runtime behavior change, no deploy, no promotion.

begin;

do $m04$
declare
  v_batch constant uuid := 'e14f1d14-5d36-4f6c-a01e-1a0f10300001'::uuid;
  v_exec constant text := 'IG-CV-V2-L1-M04-ASSET-GRAPH-20260930';
  v_source constant text := 'supabase/migrations/20260930161000_lf_input_governance_function_asset_graph_v1.sql';
  v_def text;
  v_def_sha text;
  v_count integer;
  v_total_members integer := 0;
  g record;
begin
  if exists (
    select 1 from public.lf_activos
    where codigo_activo in (
      'PROGRAMACION_FN_INPUT_GOVERNANCE_CURATION_SET',
      'PROGRAMACION_FN_INPUT_GOVERNANCE_CURRENTNESS_SET',
      'PROGRAMACION_FN_INPUT_GOVERNANCE_EKB_SET',
      'PROGRAMACION_FN_INPUT_GOVERNANCE_EXECUTION_SET',
      'PROGRAMACION_FN_INPUT_GOVERNANCE_GUARD_SET',
      'PROGRAMACION_FN_INPUT_GOVERNANCE_HEALTH_SET',
      'PROGRAMACION_FN_INPUT_GOVERNANCE_REMEDIATION_SET',
      'PROGRAMACION_FN_INPUT_GOVERNANCE_SEMANTIC_CLASSIFICATION_SET',
      'PROGRAMACION_FN_INPUT_GOVERNANCE_SHADOW_SET',
      'PROGRAMACION_FN_INPUT_GOVERNANCE_VALIDATION_SET',
      'PROGRAMACION_FN_LF_ROUTER_INPUT_GOVERNANCE_RESOLVE_V1'
    )
      and archived_at is null
  ) then
    raise exception 'M04_TARGET_ASSET_ALREADY_EXISTS';
  end if;

  if to_regprocedure('programacion.fn_lf_router_input_governance_resolve_v1(text,jsonb,text)') is null then
    raise exception 'M04_ENTRYPOINT_NOT_FOUND';
  end if;

  if (
    select count(*)
    from public.lf_activos
    where codigo_activo in (
      'EDGE_FN_INPUT_GOVERNANCE_AGENT_V1',
      'EDGE_FN_INPUT_GOVERNANCE_CURATOR_V1',
      'EDGE_FN_INPUT_GOVERNANCE_VALIDATOR_V1'
    ) and archived_at is null
  ) <> 3 then
    raise exception 'M04_EDGE_ASSET_SET_INCOMPLETE';
  end if;

  v_def := pg_get_functiondef('programacion.fn_lf_router_input_governance_resolve_v1(text,jsonb,text)'::regprocedure);
  v_def_sha := encode(extensions.digest(convert_to(v_def,'UTF8'),'sha256'),'hex');
  if v_def_sha <> 'c8f81b362211d4f9b113ee055914ab57f779abf1f42b0a4349d95a0ecf1c7387' then
    raise exception 'M04_ENTRYPOINT_DEFINITION_DRIFT:%',v_def_sha;
  end if;

  for g in
    with expected(grp,asset_code,expected_count,expected_sha,row_no,role_text) as (
      values
      ('CURATION','PROGRAMACION_FN_INPUT_GOVERNANCE_CURATION_SET',7,'37bb15d9ba84af5499653653467f924fa7a813c63f8b90a93288e74493ee2f13',1,'Curator materialization, rebind and recuration functions.'),
      ('CURRENTNESS','PROGRAMACION_FN_INPUT_GOVERNANCE_CURRENTNESS_SET',3,'4e8fa7d3cf70c816253ecabca40303eefed38b92158f77a7c5ce6b96ade4bdc8',2,'Input readiness run currentness functions.'),
      ('EKB','PROGRAMACION_FN_INPUT_GOVERNANCE_EKB_SET',2,'3b0578c182fc774820a06c1d97ed4ff08ab67dc4c60590766a656e97557f28d9',3,'Input Governance EKB checkpoint and occurrence functions.'),
      ('EXECUTION','PROGRAMACION_FN_INPUT_GOVERNANCE_EXECUTION_SET',4,'e4168ae798e86043d95c21d3c17b60d72f87f5f1a655906396675f5c46c1d3a4',4,'Runtime execute and worker-spec functions.'),
      ('GUARD','PROGRAMACION_FN_INPUT_GOVERNANCE_GUARD_SET',1,'31fc779e4f96584dbe7a249aa87823b50935ef861a6f3cac2b691510bab17077',5,'BEFORE trigger guard for input_readiness_runs.'),
      ('HEALTH','PROGRAMACION_FN_INPUT_GOVERNANCE_HEALTH_SET',1,'625d2cc78e4f790bd48f4fc12f918c85c561d8af7b3388aa831f2f35252e2264',6,'Module health projection function.'),
      ('REMEDIATION','PROGRAMACION_FN_INPUT_GOVERNANCE_REMEDIATION_SET',1,'d0ad00e5fa4177863b55f35bbb889a965cdd4f7ece9fe03bed741e16c159547a',7,'Safe-autofix remediation function.'),
      ('SEMANTIC_CLASSIFICATION','PROGRAMACION_FN_INPUT_GOVERNANCE_SEMANTIC_CLASSIFICATION_SET',16,'559a258f8240de9f16bcea3ada3cf684e9805a223c6fd79b282a0c6c140b7191',8,'Classifier, semantic probe, field probe and assertion functions.'),
      ('SHADOW','PROGRAMACION_FN_INPUT_GOVERNANCE_SHADOW_SET',6,'237f55d1e8873e2be9b47a46cb3a18fceeaca05a66ece57680d2c8b69d7f9ece',9,'Non-decisional shadow evaluation and oracle functions.'),
      ('VALIDATION','PROGRAMACION_FN_INPUT_GOVERNANCE_VALIDATION_SET',6,'317d7910a7bdee1eb1bebd605bdb74183abf8d16357bd55fcca4cbc4a470c731',10,'Validator functions, including public resume-context helper.')
    ),
    funcs as (
      select n.nspname schema_name,p.proname,pg_get_function_identity_arguments(p.oid) args,
             case
               when n.nspname='public' and p.proname='fn_input_governance_validator_resume_context_v1' then 'VALIDATION'
               when n.nspname='programacion' and p.proname='fn_lf_router_input_governance_resolve_v1' then 'ENTRYPOINT'
               when p.proname ilike '%shadow%' then 'SHADOW'
               when p.proname ilike '%semantic%' or p.proname ilike '%classify%' or p.proname ilike '%field_reference%' or p.proname ilike '%assertion%' then 'SEMANTIC_CLASSIFICATION'
               when p.proname ilike '%validator%' or p.proname ilike '%validate%' then 'VALIDATION'
               when p.proname ilike '%curator%' or p.proname ilike '%materialize%' or p.proname ilike '%recurate%' then 'CURATION'
               when p.proname ilike '%execute%' or p.proname ilike '%worker_spec%' then 'EXECUTION'
               when p.proname ilike '%current%' then 'CURRENTNESS'
               when p.proname ilike '%safe_autofix%' or p.proname ilike '%gap%' then 'REMEDIATION'
               when p.proname ilike '%ekb%' then 'EKB'
               when p.proname ilike 'fn_guard%' then 'GUARD'
               when p.proname ilike '%health%' then 'HEALTH'
               else null
             end grp
      from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where (n.nspname='programacion' and (p.proname ilike '%input_governance%' or p.proname ilike '%input_readiness%'))
         or (n.nspname='public' and p.proname='fn_input_governance_validator_resume_context_v1')
    ),
    agg as (
      select grp,count(*) n,
             jsonb_agg(schema_name||'.'||proname||'('||args||')' order by schema_name,proname,args) members
      from funcs
      where grp is not null and grp<>'ENTRYPOINT'
      group by grp
    )
    select e.*,a.n,a.members,
           encode(extensions.digest(convert_to(a.members::text,'UTF8'),'sha256'),'hex') members_sha
    from expected e join agg a using(grp)
    order by e.row_no
  loop
    if g.n <> g.expected_count or g.members_sha <> g.expected_sha then
      raise exception 'M04_GROUP_DRIFT:% count=%/% sha=%/%',
        g.grp,g.n,g.expected_count,g.members_sha,g.expected_sha;
    end if;
    v_total_members := v_total_members + g.n;

    insert into public.lf_activos(
      codigo_activo,nombre_canonico,tipo_activo,subtipo_activo,
      estado_documental,estado_operativo,nivel_control,runtime_estado,impacto_automatico,
      accion_migracion,version,ruta_esperada,url,owner_name,rol_arquitectura,
      source_spreadsheet_id,source_spreadsheet_title,source_sheet_name,source_row_number,
      migration_batch_id,raw_payload,metadata,created_by_execution_id,updated_by_execution_id
    ) values (
      g.asset_code,g.asset_code,'CAPABILITY','DB_FUNCTION_SET',
      'CANDIDATO','READ_ONLY','CONTROLADO','CANDIDATE_READ_ONLY','BLOQUEADO',
      'REGISTER_DB_FUNCTION_SET_CANDIDATE','runtime-20260930',null,
      'supabase://input-governance/functions/'||lower(g.grp),'LF_GOVERNANCE',g.role_text,
      'SUPABASE_DIRECT_CONTROLLED_ENTRY','LF_OPERATION_CONTROLLED_CANDIDATES',
      'INPUT_GOVERNANCE_FUNCTION_GRAPH_20260930',g.row_no,
      v_batch,
      jsonb_build_object(
        'domain','INPUT_GOVERNANCE',
        'group',g.grp,
        'function_count',g.n,
        'members',g.members,
        'members_sha256',g.members_sha
      ),
      jsonb_build_object(
        'dominio','INPUT_GOVERNANCE',
        'lectura','COMPLETA',
        'lectura_fecha','2026-09-30',
        'lectura_alcance',g.n::text||' funciones exactas por pg_get_function_identity_arguments',
        'inventory_status','CANDIDATE_PENDING_QUALIFICATION',
        'no_duplicate_engine',true,
        'm0_2_baseline_118_status','NOT_RECONSTRUCTED_FROM_CANONICAL_SOURCE',
        'grouping_rule','NAME_AND_RUNTIME_ROLE_V1',
        'source_of_truth','pg_proc + pg_get_functiondef'
      ),
      v_exec,v_exec
    );
  end loop;

  if v_total_members <> 47 then
    raise exception 'M04_INTERNAL_GROUP_MEMBER_TOTAL:%',v_total_members;
  end if;

  insert into public.lf_activos(
    codigo_activo,nombre_canonico,tipo_activo,subtipo_activo,
    estado_documental,estado_operativo,nivel_control,runtime_estado,impacto_automatico,
    accion_migracion,version,ruta_esperada,url,owner_name,rol_arquitectura,
    source_spreadsheet_id,source_spreadsheet_title,source_sheet_name,source_row_number,
    migration_batch_id,raw_payload,metadata,created_by_execution_id,updated_by_execution_id
  ) values (
    'PROGRAMACION_FN_LF_ROUTER_INPUT_GOVERNANCE_RESOLVE_V1',
    'programacion.fn_lf_router_input_governance_resolve_v1',
    'CAPABILITY','DB_FUNCTION',
    'CANDIDATO','READ_ONLY','CONTROLADO','CANDIDATE_READ_ONLY','BLOQUEADO',
    'REGISTER_DB_FUNCTION_ENTRYPOINT_CANDIDATE','v1',null,
    'supabase://programacion/fn_lf_router_input_governance_resolve_v1',
    'LF_GOVERNANCE',
    'Cross-team SQL entrypoint used by Router and Profiles batch worker. Resolves IG applicability/subject and calls internal worker-spec, execute and currentness functions; it is not the Edge Agent.',
    'SUPABASE_DIRECT_CONTROLLED_ENTRY','LF_OPERATION_CONTROLLED_CANDIDATES',
    'INPUT_GOVERNANCE_FUNCTION_GRAPH_20260930',11,
    v_batch,
    jsonb_build_object(
      'schema','programacion',
      'function','fn_lf_router_input_governance_resolve_v1',
      'signature','programacion.fn_lf_router_input_governance_resolve_v1(text,jsonb,text)',
      'definition_sha256',v_def_sha,
      'definition_bytes',octet_length(v_def)
    ),
    jsonb_build_object(
      'dominio','INPUT_GOVERNANCE',
      'external_sql_entrypoint',true,
      'consumed_by_other_teams',true,
      'direct_callees',jsonb_build_array(
        'programacion.fn_input_governance_worker_spec',
        'programacion.fn_input_governance_execute',
        'programacion.fn_input_readiness_run_is_current'
      ),
      'must_not_point_directly_to_edge_agent',true,
      'source_of_truth','pg_get_functiondef'
    ),
    v_exec,v_exec
  );

  insert into public.lf_activo_relaciones(
    codigo_activo,relacionado_codigo,relacion_tipo,valor_original,fuente,
    migration_batch_id,created_by_execution_id,updated_by_execution_id
  )
  values
  ('PROGRAMACION_FN_LF_ROUTER_INPUT_GOVERNANCE_RESOLVE_V1','PROGRAMACION_FN_INPUT_GOVERNANCE_EXECUTION_SET','DEPENDE_DE',
   'Direct calls: fn_input_governance_worker_spec + fn_input_governance_execute.',v_source,v_batch,v_exec,v_exec),
  ('PROGRAMACION_FN_LF_ROUTER_INPUT_GOVERNANCE_RESOLVE_V1','PROGRAMACION_FN_INPUT_GOVERNANCE_CURRENTNESS_SET','DEPENDE_DE',
   'Direct call: fn_input_readiness_run_is_current.',v_source,v_batch,v_exec,v_exec),

  ('EDGE_FN_INPUT_GOVERNANCE_AGENT_V1','PROGRAMACION_FN_INPUT_GOVERNANCE_EXECUTION_SET','DEPENDE_DE',
   'Exact main source calls RPC fn_input_governance_execute.',v_source,v_batch,v_exec,v_exec),
  ('EDGE_FN_INPUT_GOVERNANCE_AGENT_V1','PROGRAMACION_FN_INPUT_GOVERNANCE_REMEDIATION_SET','DEPENDE_DE',
   'Exact main source calls RPC fn_input_governance_safe_autofix_v1.',v_source,v_batch,v_exec,v_exec),
  ('EDGE_FN_INPUT_GOVERNANCE_AGENT_V1','EDGE_FN_INPUT_GOVERNANCE_CURATOR_V1','DEPENDE_DE',
   'Exact main source calls runtime input-governance-curator-v1.',v_source,v_batch,v_exec,v_exec),
  ('EDGE_FN_INPUT_GOVERNANCE_AGENT_V1','EDGE_FN_INPUT_GOVERNANCE_VALIDATOR_V1','DEPENDE_DE',
   'Exact main source calls runtime input-governance-validator-v1.',v_source,v_batch,v_exec,v_exec),
  ('EDGE_FN_INPUT_GOVERNANCE_CURATOR_V1','PROGRAMACION_FN_INPUT_GOVERNANCE_CURATION_SET','DEPENDE_DE',
   'Exact main source calls RPC fn_input_governance_curator_materialize_v1.',v_source,v_batch,v_exec,v_exec),
  ('EDGE_FN_INPUT_GOVERNANCE_VALIDATOR_V1','PROGRAMACION_FN_INPUT_GOVERNANCE_VALIDATION_SET','DEPENDE_DE',
   'Exact main source calls fn_input_governance_validator_resume_context_v1 and fn_input_governance_validator_validate_v1.',v_source,v_batch,v_exec,v_exec),

  ('PROGRAMACION_FN_INPUT_GOVERNANCE_CURATION_SET','PROGRAMACION_FN_INPUT_GOVERNANCE_CURRENTNESS_SET','DEPENDE_DE',
   'pg_get_functiondef: curation functions call input readiness currentness functions.',v_source,v_batch,v_exec,v_exec),
  ('PROGRAMACION_FN_INPUT_GOVERNANCE_CURATION_SET','PROGRAMACION_FN_INPUT_GOVERNANCE_EKB_SET','DEPENDE_DE',
   'pg_get_functiondef: curation functions call fn_input_governance_ekb_checkpoint.',v_source,v_batch,v_exec,v_exec),
  ('PROGRAMACION_FN_INPUT_GOVERNANCE_CURATION_SET','PROGRAMACION_FN_INPUT_GOVERNANCE_SEMANTIC_CLASSIFICATION_SET','DEPENDE_DE',
   'pg_get_functiondef: curation functions call bootstrap classifier functions.',v_source,v_batch,v_exec,v_exec),
  ('PROGRAMACION_FN_INPUT_GOVERNANCE_CURRENTNESS_SET','PROGRAMACION_FN_INPUT_GOVERNANCE_SEMANTIC_CLASSIFICATION_SET','DEPENDE_DE',
   'pg_get_functiondef: currentness functions call bootstrap classifier functions.',v_source,v_batch,v_exec,v_exec),
  ('PROGRAMACION_FN_INPUT_GOVERNANCE_EXECUTION_SET','PROGRAMACION_FN_INPUT_GOVERNANCE_CURRENTNESS_SET','DEPENDE_DE',
   'pg_get_functiondef: execution functions call input readiness currentness functions.',v_source,v_batch,v_exec,v_exec),
  ('PROGRAMACION_FN_INPUT_GOVERNANCE_EXECUTION_SET','PROGRAMACION_FN_INPUT_GOVERNANCE_EKB_SET','DEPENDE_DE',
   'pg_get_functiondef: fn_input_governance_execute calls fn_input_governance_ekb_checkpoint.',v_source,v_batch,v_exec,v_exec),
  ('PROGRAMACION_FN_INPUT_GOVERNANCE_HEALTH_SET','PROGRAMACION_FN_INPUT_GOVERNANCE_CURRENTNESS_SET','DEPENDE_DE',
   'pg_get_functiondef: module health calls fn_input_readiness_run_is_current.',v_source,v_batch,v_exec,v_exec),
  ('PROGRAMACION_FN_INPUT_GOVERNANCE_SHADOW_SET','PROGRAMACION_FN_INPUT_GOVERNANCE_SEMANTIC_CLASSIFICATION_SET','DEPENDE_DE',
   'pg_get_functiondef: shadow evaluate functions call classifier/semantic probe functions.',v_source,v_batch,v_exec,v_exec),
  ('PROGRAMACION_FN_INPUT_GOVERNANCE_VALIDATION_SET','PROGRAMACION_FN_INPUT_GOVERNANCE_EKB_SET','DEPENDE_DE',
   'pg_get_functiondef: validator functions call fn_input_governance_ekb_checkpoint.',v_source,v_batch,v_exec,v_exec),
  ('PROGRAMACION_FN_INPUT_GOVERNANCE_VALIDATION_SET','PROGRAMACION_FN_INPUT_GOVERNANCE_SEMANTIC_CLASSIFICATION_SET','DEPENDE_DE',
   'pg_get_functiondef: validator functions call assertions/classifier functions.',v_source,v_batch,v_exec,v_exec),

  ('PROGRAMACION_FN_INPUT_GOVERNANCE_CURATION_SET','PROGRAMACION_FN_INPUT_GOVERNANCE_GUARD_SET','DEPENDE_DE',
   'Trigger path: curation functions INSERT/UPDATE programacion.input_readiness_runs; BEFORE triggers execute fn_guard_input_readiness_run.',v_source,v_batch,v_exec,v_exec),
  ('PROGRAMACION_FN_INPUT_GOVERNANCE_VALIDATION_SET','PROGRAMACION_FN_INPUT_GOVERNANCE_GUARD_SET','DEPENDE_DE',
   'Trigger path: validation functions UPDATE programacion.input_readiness_runs; BEFORE UPDATE trigger executes fn_guard_input_readiness_run.',v_source,v_batch,v_exec,v_exec);

  select count(*) into v_count
  from public.lf_activos
  where migration_batch_id=v_batch and archived_at is null;
  if v_count <> 11 then
    raise exception 'M04_ASSET_COUNT:%',v_count;
  end if;

  select count(*) into v_count
  from public.lf_activo_relaciones
  where migration_batch_id=v_batch;
  if v_count <> 20 then
    raise exception 'M04_RELATION_COUNT:%',v_count;
  end if;

  if exists (
    select 1 from public.lf_activo_relaciones
    where migration_batch_id=v_batch
      and codigo_activo='PROGRAMACION_FN_LF_ROUTER_INPUT_GOVERNANCE_RESOLVE_V1'
      and relacionado_codigo='EDGE_FN_INPUT_GOVERNANCE_AGENT_V1'
  ) then
    raise exception 'M04_FORBIDDEN_ENTRYPOINT_TO_AGENT_RELATION';
  end if;

  if exists (
    select 1
    from public.lf_activo_relaciones rel
    left join public.lf_activos src on src.codigo_activo=rel.codigo_activo and src.archived_at is null
    left join public.lf_activos dst on dst.codigo_activo=rel.relacionado_codigo and dst.archived_at is null
    where rel.migration_batch_id=v_batch
      and (src.codigo_activo is null or dst.codigo_activo is null)
  ) then
    raise exception 'M04_ORPHAN_RELATION';
  end if;

  if exists (
    select 1
    from public.lf_activos a
    where a.migration_batch_id=v_batch
      and not exists (
        select 1 from public.lf_activo_relaciones rr
        where rr.migration_batch_id=v_batch
          and (rr.codigo_activo=a.codigo_activo or rr.relacionado_codigo=a.codigo_activo)
      )
  ) then
    raise exception 'M04_ISOLATED_NEW_ASSET';
  end if;
end
$m04$;

commit;

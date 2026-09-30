-- IG_CURATOR_VALIDATOR_REFACTOR_V2 · L1 · M0.4 extension (PAULO-103)
-- Register the remaining 48 programacion.fn_input_* Input Governance functions
-- as 8 grouped DB_FUNCTION_SET assets and materialize code-derived group relations.
-- Registry-only: no runtime behavior change, no deploy, no promotion.

begin;

do $m04x$
declare
  v_batch constant uuid := 'e14f1d14-5d36-4f6c-a01e-1a0f10300002'::uuid;
  v_exec constant text := 'IG-CV-V2-L1-M04-EXTENDED-ASSET-GRAPH-20260930';
  v_source constant text := 'supabase/migrations/20260930165000_lf_input_governance_extended_function_asset_graph_v1.sql';
  v_count integer;
  v_total_members integer := 0;
  v_edge_count integer;
  v_edge_sha text;
  g record;
begin
  if exists (
    select 1 from public.lf_activos
    where codigo_activo in (
      'PROGRAMACION_FN_INPUT_GOVERNANCE_ASSERTION_ENGINE_SET',
      'PROGRAMACION_FN_INPUT_GOVERNANCE_CANONICAL_CONTEXT_SET',
      'PROGRAMACION_FN_INPUT_GOVERNANCE_CURRENTNESS_INVALIDATION_SET',
      'PROGRAMACION_FN_INPUT_GOVERNANCE_DESIGN_BINDING_SET',
      'PROGRAMACION_FN_INPUT_GOVERNANCE_NA_AUTHORITY_SET',
      'PROGRAMACION_FN_INPUT_GOVERNANCE_OUTCOME_REMEDIATION_SET',
      'PROGRAMACION_FN_INPUT_GOVERNANCE_SECURITY_EXPECTATIONS_SET',
      'PROGRAMACION_FN_INPUT_GOVERNANCE_STAGE_AUTHORITY_SET'
    ) and archived_at is null
  ) then
    raise exception 'M04X_TARGET_ASSET_ALREADY_EXISTS';
  end if;

  if (
    select count(*)
    from public.lf_activos
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
      'PROGRAMACION_FN_INPUT_GOVERNANCE_VALIDATION_SET'
    ) and archived_at is null
  ) <> 10 then
    raise exception 'M04X_PR1307_ASSET_SET_INCOMPLETE';
  end if;

  select count(*) into v_count
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='programacion'
    and p.proname like 'fn_input_%'
    and p.proname not like 'fn_input_governance_%'
    and p.proname not like 'fn_input_readiness_%';
  if v_count <> 48 then
    raise exception 'M04X_REMAINING_FUNCTION_COUNT_DRIFT:%',v_count;
  end if;

  for g in
    with expected(grp,asset_code,expected_count,expected_sha,row_no,role_text) as (
      values
      ('NEW_ASSERTION_ENGINE','PROGRAMACION_FN_INPUT_GOVERNANCE_ASSERTION_ENGINE_SET',11,'6f1a4ad232b89a677e446e16405b866c03d6605d5f6b8b94db8d6d08255d2898',1,'Assertion templates, relevance/evaluation, rebind and assertion builders.'),
      ('NEW_CANONICAL_CONTEXT','PROGRAMACION_FN_INPUT_GOVERNANCE_CANONICAL_CONTEXT_SET',10,'48fba10c2a7b51d768b2335df5548ab31fa95758b49af032a015f81c5e3364ac',2,'Canonical screen/source/context/provenance and retrieval resolution.'),
      ('NEW_CURRENTNESS_INVALIDATION','PROGRAMACION_FN_INPUT_GOVERNANCE_CURRENTNESS_INVALIDATION_SET',2,'4a00df24d4a082613687bb8f5e33e9d357c73b7dbacad18d016dd7aa97d1b30e',3,'Freshness delta and predecessor invalidation helpers.'),
      ('NEW_DESIGN_BINDING','PROGRAMACION_FN_INPUT_GOVERNANCE_DESIGN_BINDING_SET',7,'d4f12a67cbf244d4254819bd56465c18a77fc9c8a3fe39befd9859f26836f0ec',4,'Design-system resolution, binding graph, readiness and component receipt helpers.'),
      ('NEW_NA_AUTHORITY','PROGRAMACION_FN_INPUT_GOVERNANCE_NA_AUTHORITY_SET',2,'10b5dd396e2a597396884cfc0c9bf0a603b53229206a4cc998b155dc1274c711',5,'Positive authority for NOT_APPLICABLE classification.'),
      ('NEW_OUTCOME_REMEDIATION','PROGRAMACION_FN_INPUT_GOVERNANCE_OUTCOME_REMEDIATION_SET',6,'b6065f9682403e2657fb6f9c9d57a4d4fa43be2dabb7cbd72507d2e830e53215',6,'Evaluation outcome, remediation and proposal summaries.'),
      ('NEW_SECURITY_EXPECTATIONS','PROGRAMACION_FN_INPUT_GOVERNANCE_SECURITY_EXPECTATIONS_SET',5,'d7c4b99c32a1f049507e7fb5ea6cdec42fe492eab0a18ef7c13e3df610ec00bb',7,'Security capability/threat and subject-depth expectations.'),
      ('NEW_STAGE_AUTHORITY','PROGRAMACION_FN_INPUT_GOVERNANCE_STAGE_AUTHORITY_SET',5,'4e109ea7ccadb89fc28dfd422505e50fbcced7ef77bff0e737d2e15259de676d',8,'Stage authority applicability, resolution and gate summaries.')
    ),
    funcs as (
      select n.nspname schema_name,p.proname,pg_get_function_identity_arguments(p.oid) args,
             case
               when p.proname in ('fn_input_na_positive_authority_v512','fn_input_na_positive_authority_v512_cached_v1') then 'NEW_NA_AUTHORITY'
               when p.proname in ('fn_input_freshness_delta','fn_input_latch_predecessor_invalidation') then 'NEW_CURRENTNESS_INVALIDATION'
               when p.proname ~ '(security_|subject_depth_)' then 'NEW_SECURITY_EXPECTATIONS'
               when p.proname ~ 'stage_' then 'NEW_STAGE_AUTHORITY'
               when p.proname ~ '(design_|component_binding_|resolve_design_ref)' then 'NEW_DESIGN_BINDING'
               when p.proname ~ '(assertion|auth006|bootstrap_rule_probe|owner_decision|rate_enrichment|rebind_assertion|v58_|v512_)' then 'NEW_ASSERTION_ENGINE'
               when p.proname ~ '(actionable_remediation|evaluation_outcome|internal_remediation|proposal_summary)' then 'NEW_OUTCOME_REMEDIATION'
               else 'NEW_CANONICAL_CONTEXT'
             end grp
      from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='programacion'
        and p.proname like 'fn_input_%'
        and p.proname not like 'fn_input_governance_%'
        and p.proname not like 'fn_input_readiness_%'
    ),
    agg as (
      select grp,count(*) n,
             jsonb_agg(schema_name||'.'||proname||'('||args||')' order by schema_name,proname,args) members
      from funcs
      group by grp
    )
    select e.*,a.n,a.members,
           encode(extensions.digest(convert_to(a.members::text,'UTF8'),'sha256'),'hex') members_sha
    from expected e join agg a using(grp)
    order by e.row_no
  loop
    if g.n <> g.expected_count or g.members_sha <> g.expected_sha then
      raise exception 'M04X_GROUP_DRIFT:% count=%/% sha=%/%',
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
      'supabase://input-governance/functions/'||lower(replace(g.grp,'NEW_','')),
      'LF_GOVERNANCE',g.role_text,
      'SUPABASE_DIRECT_CONTROLLED_ENTRY','LF_OPERATION_CONTROLLED_CANDIDATES',
      'INPUT_GOVERNANCE_EXTENDED_FUNCTION_GRAPH_20260930',g.row_no,
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
        'extends_pr',1307,
        'grouping_rule','RUNTIME_ROLE_V2_FOR_FN_INPUT_PREFIX',
        'source_of_truth','pg_proc + pg_get_functiondef'
      ),
      v_exec,v_exec
    );
  end loop;

  if v_total_members <> 48 then
    raise exception 'M04X_GROUP_MEMBER_TOTAL:%',v_total_members;
  end if;

  with funcs as (
    select p.oid,n.nspname schema_name,p.proname,pg_get_functiondef(p.oid) def,
           case
             when n.nspname='public' and p.proname='fn_input_governance_validator_resume_context_v1' then 'REG_VALIDATION'
             when n.nspname='programacion' and p.proname='fn_lf_router_input_governance_resolve_v1' then 'REG_ENTRYPOINT'
             when n.nspname='programacion' and p.proname='fn_guard_input_readiness_run' then 'REG_GUARD'
             when n.nspname='programacion' and (p.proname ilike 'fn_input_governance_%' or p.proname ilike 'fn_input_readiness_%') then
               case
                 when p.proname ilike '%shadow%' then 'REG_SHADOW'
                 when p.proname ilike '%semantic%' or p.proname ilike '%classify%' or p.proname ilike '%field_reference%' or p.proname ilike '%assertion%' then 'REG_SEMANTIC_CLASSIFICATION'
                 when p.proname ilike '%validator%' or p.proname ilike '%validate%' then 'REG_VALIDATION'
                 when p.proname ilike '%curator%' or p.proname ilike '%materialize%' or p.proname ilike '%recurate%' then 'REG_CURATION'
                 when p.proname ilike '%execute%' or p.proname ilike '%worker_spec%' then 'REG_EXECUTION'
                 when p.proname ilike '%current%' then 'REG_CURRENTNESS'
                 when p.proname ilike '%safe_autofix%' or p.proname ilike '%gap%' then 'REG_REMEDIATION'
                 when p.proname ilike '%ekb%' then 'REG_EKB'
                 when p.proname ilike 'fn_guard%' then 'REG_GUARD'
                 when p.proname ilike '%health%' then 'REG_HEALTH'
               end
             when n.nspname='programacion' and p.proname like 'fn_input_%'
                  and p.proname not like 'fn_input_governance_%'
                  and p.proname not like 'fn_input_readiness_%' then
               case
                 when p.proname in ('fn_input_na_positive_authority_v512','fn_input_na_positive_authority_v512_cached_v1') then 'NEW_NA_AUTHORITY'
                 when p.proname in ('fn_input_freshness_delta','fn_input_latch_predecessor_invalidation') then 'NEW_CURRENTNESS_INVALIDATION'
                 when p.proname ~ '(security_|subject_depth_)' then 'NEW_SECURITY_EXPECTATIONS'
                 when p.proname ~ 'stage_' then 'NEW_STAGE_AUTHORITY'
                 when p.proname ~ '(design_|component_binding_|resolve_design_ref)' then 'NEW_DESIGN_BINDING'
                 when p.proname ~ '(assertion|auth006|bootstrap_rule_probe|owner_decision|rate_enrichment|rebind_assertion|v58_|v512_)' then 'NEW_ASSERTION_ENGINE'
                 when p.proname ~ '(actionable_remediation|evaluation_outcome|internal_remediation|proposal_summary)' then 'NEW_OUTCOME_REMEDIATION'
                 else 'NEW_CANONICAL_CONTEXT'
               end
           end grp
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where (n.nspname='programacion' and (
            p.proname like 'fn_input_%'
            or p.proname='fn_lf_router_input_governance_resolve_v1'
            or p.proname='fn_guard_input_readiness_run'
          ))
       or (n.nspname='public' and p.proname='fn_input_governance_validator_resume_context_v1')
  ),
  raw_edges as (
    select distinct a.grp caller_group,b.grp callee_group,a.proname caller_fn,b.proname callee_fn
    from funcs a join funcs b
      on a.oid<>b.oid and a.grp is not null and b.grp is not null
     and regexp_replace(a.def,'[[:space:]]+','','g') ~
         ('(^|[^A-Za-z0-9_])' || b.proname || '\(')
    where a.grp<>b.grp and (a.grp like 'NEW_%' or b.grp like 'NEW_%')
  ),
  edge_pairs as (
    select caller_group,callee_group,count(*) evidence_pairs
    from raw_edges
    group by caller_group,callee_group
  ),
  canon as (
    select jsonb_agg(
      jsonb_build_object(
        'caller_group',caller_group,
        'callee_group',callee_group,
        'evidence_pairs',evidence_pairs
      )
      order by caller_group,callee_group
    ) edges
    from edge_pairs
  )
  select jsonb_array_length(edges),
         encode(extensions.digest(convert_to(edges::text,'UTF8'),'sha256'),'hex')
  into v_edge_count,v_edge_sha
  from canon;

  if v_edge_count <> 30 or v_edge_sha <> '1f1289e24894dd09aeecae8d48fe071b4345108f13a40e748743eaeaee58fe6a' then
    raise exception 'M04X_EDGE_GRAPH_DRIFT:count=% sha=%',v_edge_count,v_edge_sha;
  end if;

  with group_map(group_key,asset_code) as (
    values
      ('REG_CURATION','PROGRAMACION_FN_INPUT_GOVERNANCE_CURATION_SET'),
      ('REG_CURRENTNESS','PROGRAMACION_FN_INPUT_GOVERNANCE_CURRENTNESS_SET'),
      ('REG_EKB','PROGRAMACION_FN_INPUT_GOVERNANCE_EKB_SET'),
      ('REG_EXECUTION','PROGRAMACION_FN_INPUT_GOVERNANCE_EXECUTION_SET'),
      ('REG_GUARD','PROGRAMACION_FN_INPUT_GOVERNANCE_GUARD_SET'),
      ('REG_HEALTH','PROGRAMACION_FN_INPUT_GOVERNANCE_HEALTH_SET'),
      ('REG_REMEDIATION','PROGRAMACION_FN_INPUT_GOVERNANCE_REMEDIATION_SET'),
      ('REG_SEMANTIC_CLASSIFICATION','PROGRAMACION_FN_INPUT_GOVERNANCE_SEMANTIC_CLASSIFICATION_SET'),
      ('REG_SHADOW','PROGRAMACION_FN_INPUT_GOVERNANCE_SHADOW_SET'),
      ('REG_VALIDATION','PROGRAMACION_FN_INPUT_GOVERNANCE_VALIDATION_SET'),
      ('REG_ENTRYPOINT','PROGRAMACION_FN_LF_ROUTER_INPUT_GOVERNANCE_RESOLVE_V1'),
      ('NEW_ASSERTION_ENGINE','PROGRAMACION_FN_INPUT_GOVERNANCE_ASSERTION_ENGINE_SET'),
      ('NEW_CANONICAL_CONTEXT','PROGRAMACION_FN_INPUT_GOVERNANCE_CANONICAL_CONTEXT_SET'),
      ('NEW_CURRENTNESS_INVALIDATION','PROGRAMACION_FN_INPUT_GOVERNANCE_CURRENTNESS_INVALIDATION_SET'),
      ('NEW_DESIGN_BINDING','PROGRAMACION_FN_INPUT_GOVERNANCE_DESIGN_BINDING_SET'),
      ('NEW_NA_AUTHORITY','PROGRAMACION_FN_INPUT_GOVERNANCE_NA_AUTHORITY_SET'),
      ('NEW_OUTCOME_REMEDIATION','PROGRAMACION_FN_INPUT_GOVERNANCE_OUTCOME_REMEDIATION_SET'),
      ('NEW_SECURITY_EXPECTATIONS','PROGRAMACION_FN_INPUT_GOVERNANCE_SECURITY_EXPECTATIONS_SET'),
      ('NEW_STAGE_AUTHORITY','PROGRAMACION_FN_INPUT_GOVERNANCE_STAGE_AUTHORITY_SET')
  ),
  funcs as (
    select p.oid,n.nspname schema_name,p.proname,pg_get_functiondef(p.oid) def,
           case
             when n.nspname='public' and p.proname='fn_input_governance_validator_resume_context_v1' then 'REG_VALIDATION'
             when n.nspname='programacion' and p.proname='fn_lf_router_input_governance_resolve_v1' then 'REG_ENTRYPOINT'
             when n.nspname='programacion' and p.proname='fn_guard_input_readiness_run' then 'REG_GUARD'
             when n.nspname='programacion' and (p.proname ilike 'fn_input_governance_%' or p.proname ilike 'fn_input_readiness_%') then
               case
                 when p.proname ilike '%shadow%' then 'REG_SHADOW'
                 when p.proname ilike '%semantic%' or p.proname ilike '%classify%' or p.proname ilike '%field_reference%' or p.proname ilike '%assertion%' then 'REG_SEMANTIC_CLASSIFICATION'
                 when p.proname ilike '%validator%' or p.proname ilike '%validate%' then 'REG_VALIDATION'
                 when p.proname ilike '%curator%' or p.proname ilike '%materialize%' or p.proname ilike '%recurate%' then 'REG_CURATION'
                 when p.proname ilike '%execute%' or p.proname ilike '%worker_spec%' then 'REG_EXECUTION'
                 when p.proname ilike '%current%' then 'REG_CURRENTNESS'
                 when p.proname ilike '%safe_autofix%' or p.proname ilike '%gap%' then 'REG_REMEDIATION'
                 when p.proname ilike '%ekb%' then 'REG_EKB'
                 when p.proname ilike 'fn_guard%' then 'REG_GUARD'
                 when p.proname ilike '%health%' then 'REG_HEALTH'
               end
             when n.nspname='programacion' and p.proname like 'fn_input_%'
                  and p.proname not like 'fn_input_governance_%'
                  and p.proname not like 'fn_input_readiness_%' then
               case
                 when p.proname in ('fn_input_na_positive_authority_v512','fn_input_na_positive_authority_v512_cached_v1') then 'NEW_NA_AUTHORITY'
                 when p.proname in ('fn_input_freshness_delta','fn_input_latch_predecessor_invalidation') then 'NEW_CURRENTNESS_INVALIDATION'
                 when p.proname ~ '(security_|subject_depth_)' then 'NEW_SECURITY_EXPECTATIONS'
                 when p.proname ~ 'stage_' then 'NEW_STAGE_AUTHORITY'
                 when p.proname ~ '(design_|component_binding_|resolve_design_ref)' then 'NEW_DESIGN_BINDING'
                 when p.proname ~ '(assertion|auth006|bootstrap_rule_probe|owner_decision|rate_enrichment|rebind_assertion|v58_|v512_)' then 'NEW_ASSERTION_ENGINE'
                 when p.proname ~ '(actionable_remediation|evaluation_outcome|internal_remediation|proposal_summary)' then 'NEW_OUTCOME_REMEDIATION'
                 else 'NEW_CANONICAL_CONTEXT'
               end
           end grp
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where (n.nspname='programacion' and (
            p.proname like 'fn_input_%'
            or p.proname='fn_lf_router_input_governance_resolve_v1'
            or p.proname='fn_guard_input_readiness_run'
          ))
       or (n.nspname='public' and p.proname='fn_input_governance_validator_resume_context_v1')
  ),
  raw_edges as (
    select distinct a.grp caller_group,b.grp callee_group,a.proname caller_fn,b.proname callee_fn
    from funcs a join funcs b
      on a.oid<>b.oid and a.grp is not null and b.grp is not null
     and regexp_replace(a.def,'[[:space:]]+','','g') ~
         ('(^|[^A-Za-z0-9_])' || b.proname || '\(')
    where a.grp<>b.grp and (a.grp like 'NEW_%' or b.grp like 'NEW_%')
  ),
  edge_pairs as (
    select caller_group,callee_group,count(*) evidence_pairs
    from raw_edges
    group by caller_group,callee_group
  )
  insert into public.lf_activo_relaciones(
    codigo_activo,relacionado_codigo,relacion_tipo,valor_original,fuente,
    migration_batch_id,created_by_execution_id,updated_by_execution_id
  )
  select src.asset_code,dst.asset_code,'DEPENDE_DE',
         'pg_get_functiondef group edge '||e.caller_group||' -> '||e.callee_group||
         '; evidence_pairs='||e.evidence_pairs::text,
         v_source,v_batch,v_exec,v_exec
  from edge_pairs e
  join group_map src on src.group_key=e.caller_group
  join group_map dst on dst.group_key=e.callee_group
  order by e.caller_group,e.callee_group;

  select count(*) into v_count
  from public.lf_activos
  where migration_batch_id=v_batch and archived_at is null;
  if v_count <> 8 then
    raise exception 'M04X_ASSET_COUNT:%',v_count;
  end if;

  select count(*) into v_count
  from public.lf_activo_relaciones
  where migration_batch_id=v_batch;
  if v_count <> 30 then
    raise exception 'M04X_RELATION_COUNT:%',v_count;
  end if;

  if exists (
    select 1
    from public.lf_activo_relaciones rel
    left join public.lf_activos src on src.codigo_activo=rel.codigo_activo and src.archived_at is null
    left join public.lf_activos dst on dst.codigo_activo=rel.relacionado_codigo and dst.archived_at is null
    where rel.migration_batch_id=v_batch
      and (src.codigo_activo is null or dst.codigo_activo is null)
  ) then
    raise exception 'M04X_ORPHAN_RELATION';
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
    raise exception 'M04X_ISOLATED_NEW_ASSET';
  end if;
end
$m04x$;

commit;

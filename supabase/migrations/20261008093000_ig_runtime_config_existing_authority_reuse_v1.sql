-- IG RUNTIME CONFIG EXISTING AUTHORITY REUSE V1
-- Reuses an already-governed current architecture decision referenced by a current
-- screen rule before declaring RUNTIME_CONFIG source missing.
-- Generic by declared source_architecture_decision; no screen/decision IDs hardcoded.

create or replace function programacion.fn_input_runtime_config_existing_authority_probe_v1(
  p_pantalla_id integer,
  p_version_id bigint default 19,
  p_graph jsonb default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v_graph jsonb;
  v_rules jsonb;
  v_ref_count integer:=0;
  v_current_count integer:=0;
  v_sufficient_count integer:=0;
  v_decision_ref text;
  v_decision_number bigint;
  v_production_authorized boolean:=false;
begin
  v_graph:=coalesce(
    p_graph,
    programacion.fn_input_screen_canonical_graph(p_pantalla_id,p_version_id)
  );

  if jsonb_typeof(v_graph)<>'object' then
    return jsonb_build_object(
      'handled',false,
      'family_code','RUNTIME_CONFIG',
      'reason','CANONICAL_GRAPH_UNAVAILABLE'
    );
  end if;

  v_rules:=coalesce(v_graph->'canonical_contract'->'rules','[]'::jsonb);

  with refs as (
    select distinct nullif(btrim(r.value->'config'->>'source_architecture_decision'),'') as decision_ref
    from jsonb_array_elements(v_rules) r(value)
    where coalesce(r.value->>'status','') in ('VIGENTE','ACTIVO')
      and not coalesce((r.value->>'pending_decision')::boolean,false)
      and nullif(btrim(r.value->'config'->>'source_architecture_decision'),'') is not null
  ),
  inspected as (
    select refs.decision_ref,
           d.decision_number,
           d.estado_normalizado,
           d.raw_payload,
           (
             d.estado_normalizado='VIGENTE'
             and jsonb_typeof(d.raw_payload)='object'
             and nullif(btrim(d.raw_payload->>'auth_provider'),'') is not null
             and nullif(btrim(d.raw_payload->>'auth_principal'),'') is not null
             and jsonb_typeof(d.raw_payload->'server_boundary')='object'
             and nullif(btrim(d.raw_payload#>>'{server_boundary,runtime}'),'') is not null
             and jsonb_typeof(d.raw_payload->'session')='object'
             and nullif(btrim(d.raw_payload#>>'{session,policy_code}'),'') is not null
             and jsonb_typeof(d.raw_payload->'otp')='object'
             and nullif(btrim(d.raw_payload#>>'{otp,issuer}'),'') is not null
             and nullif(btrim(d.raw_payload#>>'{otp,verifier}'),'') is not null
           ) as sufficient
    from refs
    left join public.lf_decisiones_gov d
      on d.id_decision=refs.decision_ref
  )
  select
    count(*),
    count(*) filter(where estado_normalizado='VIGENTE'),
    count(*) filter(where sufficient),
    max(decision_ref) filter(where sufficient),
    max(decision_number) filter(where sufficient),
    coalesce(bool_or(coalesce((raw_payload->>'production_authorized')::boolean,false))
      filter(where sufficient),false)
  into
    v_ref_count,
    v_current_count,
    v_sufficient_count,
    v_decision_ref,
    v_decision_number,
    v_production_authorized
  from inspected;

  if v_ref_count=0 then
    return jsonb_build_object(
      'handled',false,
      'family_code','RUNTIME_CONFIG',
      'reason','NO_DECLARED_ARCHITECTURE_DECISION_REF'
    );
  end if;

  if v_ref_count<>1
     or v_current_count<>1
     or v_sufficient_count<>1
     or v_decision_ref is null then
    return jsonb_build_object(
      'handled',false,
      'family_code','RUNTIME_CONFIG',
      'reason','ARCHITECTURE_DECISION_AUTHORITY_NOT_UNIQUE_CURRENT_SUFFICIENT',
      'declared_ref_count',v_ref_count,
      'current_ref_count',v_current_count,
      'sufficient_ref_count',v_sufficient_count
    );
  end if;

  return jsonb_build_object(
    'handled',true,
    'family_code','RUNTIME_CONFIG',
    'level','COMPLETE',
    'severity','P4',
    'blocker_code',null,
    'stage_statuses',jsonb_build_object(
      'story','READY',
      'implementation','READY',
      'qa','READY',
      'production','READY'
    ),
    'stage_blockers','[]'::jsonb,
    'probe',jsonb_build_object(
      'resolution_contract','RUNTIME_CONFIG_EXISTING_ARCHITECTURE_AUTHORITY_V1',
      'source_authority','GOVERNED_ARCHITECTURE_DECISION',
      'decision_ref',v_decision_ref,
      'decision_number',v_decision_number,
      'decision_state','VIGENTE',
      'required_fields',jsonb_build_array(
        'auth_provider',
        'auth_principal',
        'server_boundary.runtime',
        'session.policy_code',
        'otp.issuer',
        'otp.verifier'
      ),
      'production_authorized',v_production_authorized,
      'production_activation_separate_gate',true,
      'screen_id',p_pantalla_id
    )
  );
end
$function$;

revoke all on function programacion.fn_input_runtime_config_existing_authority_probe_v1(integer,bigint,jsonb)
  from public,anon,authenticated;

do $patch_live$
declare
  v_def text;
  v_sha text;
  v_anchor text:=E'  if p_family_code=''RUNTIME_CONFIG'' then\n    select';
  v_replacement text:=E'  if p_family_code=''RUNTIME_CONFIG'' then\n    v_base:=programacion.fn_input_runtime_config_existing_authority_probe_v1(p_pantalla_id,p_version_id,null);\n    if coalesce((v_base->>''handled'')::boolean,false) then return v_base; end if;\n\n    select';
begin
  select pg_get_functiondef(
           'programacion.fn_input_governance_semantic_probe_v3(integer,text,bigint)'::regprocedure
         ),
         encode(
           extensions.digest(
             convert_to(
               pg_get_functiondef(
                 'programacion.fn_input_governance_semantic_probe_v3(integer,text,bigint)'::regprocedure
               ),
               'UTF8'
             ),
             'sha256'
           ),
           'hex'
         )
    into v_def,v_sha;

  if v_sha<>'c0068db8a08d837ef9df9c9b38c01c59308d51f45f5df55565311aed5bc7554d' then
    raise exception 'IG_RUNTIME_CONFIG_SEMANTIC_V3_BASELINE_SHA_MISMATCH:%',v_sha;
  end if;

  if position(v_anchor in v_def)=0 then
    raise exception 'IG_RUNTIME_CONFIG_SEMANTIC_V3_ANCHOR_DRIFT';
  end if;

  execute replace(v_def,v_anchor,v_replacement);
end
$patch_live$;

do $patch_cached$
declare
  v_def text;
  v_sha text;
  v_anchor text:=E'  if p_family_code=''RUNTIME_CONFIG'' then\n    select';
  v_replacement text:=E'  if p_family_code=''RUNTIME_CONFIG'' then\n    v_base:=programacion.fn_input_runtime_config_existing_authority_probe_v1(p_pantalla_id,p_version_id,p_graph);\n    if coalesce((v_base->>''handled'')::boolean,false) then return v_base; end if;\n\n    select';
begin
  select pg_get_functiondef(
           'programacion.fn_input_governance_semantic_probe_v3_cached_v1(integer,text,bigint,jsonb)'::regprocedure
         ),
         encode(
           extensions.digest(
             convert_to(
               pg_get_functiondef(
                 'programacion.fn_input_governance_semantic_probe_v3_cached_v1(integer,text,bigint,jsonb)'::regprocedure
               ),
               'UTF8'
             ),
             'sha256'
           ),
           'hex'
         )
    into v_def,v_sha;

  if v_sha<>'9b3236d123aefbb3c8be293d7e926f8b558b77c1bb78af5189e2fe91b06c4ef9' then
    raise exception 'IG_RUNTIME_CONFIG_SEMANTIC_V3_CACHED_BASELINE_SHA_MISMATCH:%',v_sha;
  end if;

  if position(v_anchor in v_def)=0 then
    raise exception 'IG_RUNTIME_CONFIG_SEMANTIC_V3_CACHED_ANCHOR_DRIFT';
  end if;

  execute replace(v_def,v_anchor,v_replacement);
end
$patch_cached$;

insert into public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
  severidad,estado,source_ref,updated_at
)
values(
  'IG-RUNTIME-CONFIG-EXISTING-AUTHORITY-UNDERCONSUMED-001',
  'INPUT_GOVERNANCE',
  'RUNTIME_CONFIG can appear missing when a governed architecture decision is already referenced by a current rule',
  'The live IG RUNTIME_CONFIG resolver primarily searched for B2B-RULE-RUNTIME-001 and runtime-binding-shaped rule config. On Client ONB_002, a VIGENTE rule already referenced a VIGENTE architecture decision containing the canonical auth provider, principal, server boundary, session policy and OTP authority, but the resolver did not consume that decision and reported source missing.',
  'Existing source_architecture_decision references were not traversed as a governed runtime-config authority path.',
  'CURRENT RULE -> source_architecture_decision -> VIGENTE lf_decisiones_gov -> required runtime contract fields -> RUNTIME_CONFIG COMPLETE. Unknown, multiple, non-current or structurally insufficient decisions fail closed and fall back to existing resolution.',
  'Before declaring RUNTIME_CONFIG missing, inspect an explicit architecture-decision reference already present in current canonical rules. Require exactly one VIGENTE structurally sufficient authority; never infer from free text and never treat production_authorized=false as missing input authority because production activation is a separate gate.',
  'Migration adds a generic existing-authority probe and inserts it ahead of the existing V3 and cached-V3 runtime resolution paths without changing other families.',
  'HIGH','ACTIVO',
  'github://cristhianlujan/claude-persona-lf-patch/supabase/migrations/20261008093000_ig_runtime_config_existing_authority_reuse_v1.sql',
  now()
)
on conflict(codigo) do update
set descripcion=excluded.descripcion,
    causa_raiz=excluded.causa_raiz,
    patron=excluded.patron,
    prevencion=excluded.prevencion,
    validacion=excluded.validacion,
    severidad=excluded.severidad,
    estado=excluded.estado,
    source_ref=excluded.source_ref,
    updated_at=excluded.updated_at;

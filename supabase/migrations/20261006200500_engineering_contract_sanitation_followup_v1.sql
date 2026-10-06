-- Contract sanitation follow-up:
-- 1) align action-spec READY state with packet requirement for Git-first migrations;
-- 2) publish exact repository implementation_ref for CAUSAL_EFFECT_LINEAGE without changing functional source.

create or replace function programacion.fn_engineering_action_spec_apply_git_migration_guard_v1(
  p_spec jsonb
)
returns jsonb
language plpgsql
stable
set search_path = programacion, public, pg_catalog
as $function$
declare
  v_spec jsonb := coalesce(p_spec,'{}'::jsonb);
  v_title text := lower(coalesce(v_spec->>'checkpoint_title',''));
  v_material boolean := coalesce((v_spec->>'requires_material_execution')::boolean,false);
  v_expects_migration boolean := false;
  v_has_migration boolean := false;
begin
  if coalesce(v_spec->>'status','')<>'READY' then
    return v_spec;
  end if;

  v_expects_migration :=
    v_material
    and (
      coalesce(v_spec->>'recipe_mode','') in ('GIT_FIRST_MIGRATION','GIT_FIRST_OR_VERSIONED_CONTRACT')
      or (
        v_title ~ '(migraci|git-first)'
        and v_title !~ '(fuera de|sin|excepto|salvo) (las |los )?migraci'
      )
    );

  if not v_expects_migration then
    return v_spec;
  end if;

  select exists(
    select 1
    from jsonb_array_elements(coalesce(v_spec#>'{target,declared_artifacts}','[]'::jsonb)) a(item)
    where coalesce(a.item->>'path','') like '%:supabase/migrations/%'
  ) into v_has_migration;

  if v_has_migration then
    return v_spec;
  end if;

  return v_spec || jsonb_build_object(
    'status','BLOCK_GIT_MIGRATION_ARTIFACT_NOT_AUTHORED',
    'precision','EXPLICIT_GIT_FIRST_MIGRATION_OUTPUT_REQUIRED',
    'migration_guard',jsonb_build_object(
      'expected_output','supabase/migrations/<version>_<name>.sql',
      'declared_migration_artifact_present',false,
      'docs_or_auxiliary_artifacts_do_not_satisfy_output',true
    ),
    'forbidden',
      coalesce(v_spec->'forbidden','[]'::jsonb)
      || jsonb_build_array(
        'ACTION_SPEC_READY_WITHOUT_REQUIRED_MIGRATION_OUTPUT',
        'TREAT_DOC_AS_MIGRATION_OUTPUT'
      )
  );
end;
$function$;

create or replace function programacion.fn_engineering_checkpoint_action_spec_v3(
  p_plan_code text,
  p_unit_code text,
  p_checkpoint_code text default null::text
)
returns jsonb
language plpgsql
stable
set search_path = programacion, public, pg_catalog
as $function$
declare
  v_base jsonb;
  v_tx jsonb;
  v_cp text;
  v_state jsonb;
  v_item jsonb;
  v_spec jsonb;
begin
  v_base:=programacion.fn_engineering_checkpoint_action_spec_v3_legacy(
    p_plan_code,p_unit_code,p_checkpoint_code
  );
  if v_base is null then return null; end if;

  v_cp:=coalesce(p_checkpoint_code,v_base->>'checkpoint_code');
  v_base:=programacion.fn_engineering_action_spec_apply_git_migration_guard_v1(v_base);

  select pu.unit_metadata#>array['transversal_execution_v1',v_cp]
    into v_tx
  from programacion.engineering_plan_units pu
  where pu.plan_code=p_plan_code
    and pu.unit_code=p_unit_code;

  if v_tx is null then return v_base; end if;

  if coalesce(v_tx->>'activation','ACTIVE')='DECLARED_ONLY' then
    return v_base || jsonb_build_object(
      'transversal_execution',v_tx,
      'transversal_gate','DECLARED_NOT_ACTIVATED',
      'transversal_routing_changed',false
    );
  end if;

  if coalesce(v_tx->>'mode','')='SELECT' then
    return v_base || jsonb_build_object(
      'status','BLOCK_TRANSVERSAL_SELECTOR_RUNTIME_REQUIRED',
      'precision','STRUCTURAL_TRANSVERSAL_SELECT',
      'transversal_execution',v_tx,
      'transversal_gate','SELECTOR_REQUIRED'
    );
  end if;

  if coalesce(v_tx->>'mode','')<>'EXPLICIT' then
    return v_base || jsonb_build_object(
      'status','BLOCK_TRANSVERSAL_MODE_INVALID',
      'transversal_execution',v_tx
    );
  end if;

  v_state:=programacion.fn_engineering_transversal_sequence_state_v1(
    p_plan_code,p_unit_code,v_cp
  );

  if coalesce((v_state->>'total')::int,0)=0 then
    return v_base || jsonb_build_object(
      'status','BLOCK_TRANSVERSAL_CAPABILITIES_MISSING',
      'transversal_execution',v_tx
    );
  end if;

  if coalesce((v_state->>'all_done')::boolean,false) then
    return v_base || jsonb_build_object(
      'status','BLOCK_TRANSVERSAL_SEQUENCE_ALREADY_COMPLETE_REQUIRES_CHECKPOINT_TRANSITION',
      'transversal_execution',v_tx,
      'transversal_sequence',v_state
    );
  end if;

  v_item:=v_state->'current_item';
  v_spec:=programacion.fn_engineering_transversal_capability_action_spec_v2(
    p_plan_code,p_unit_code,v_cp,v_item,v_base
  );
  v_spec:=programacion.fn_engineering_action_spec_apply_git_migration_guard_v1(v_spec);

  return v_spec || jsonb_build_object(
    'transversal_execution',v_tx,
    'transversal_sequence',v_state,
    'transversal_gate',
      case when v_spec->>'status'='READY' then 'PASS_CURRENT_ITEM' else 'BLOCK_CURRENT_ITEM' end,
    'forbidden',
      coalesce(v_spec->'forbidden','[]'::jsonb)
      || jsonb_build_array('FALLBACK_TO_TITLE_HEURISTIC_WHEN_EXPLICIT_DECLARED')
  );
end;
$function$;

comment on function programacion.fn_engineering_action_spec_apply_git_migration_guard_v1(jsonb)
is 'Fail-closes a material Git-first/migration checkpoint before packet compilation unless its declared output includes an exact supabase/migrations SQL artifact.';

do $causal$
declare
  v_old public.lf_capability_version_registry%rowtype;
  v_manifest jsonb;
  v_sha text;
  v_promote jsonb;
  v_execution_id constant text := 'CHATGPT-IG-CONTRACT-SANITATION-N17-20261006';
  v_impl constant text := 'sandbox/lf_contract_gate_test/transversal_assets/causal_effect_lineage/causal_effect_lineage_v1.py';
begin
  select *
  into v_old
  from public.lf_capability_version_registry
  where capability_code='CAUSAL_EFFECT_LINEAGE'
    and version='1.0.0'
    and release_state='RELEASED';

  if not found then
    raise exception 'BLOCK_CAUSAL_V100_RELEASE_NOT_FOUND';
  end if;

  if v_old.manifest_sha256 <> '3794208d7ff52fec77c6703616be1a5b67e96c4290845910d31ec200609fe8d0' then
    raise exception 'BLOCK_CAUSAL_V100_MANIFEST_DRIFT:%',v_old.manifest_sha256;
  end if;

  if not exists (
    select 1
    from public.lf_capability_current
    where capability_code='CAUSAL_EFFECT_LINEAGE'
      and version='1.0.0'
      and manifest_sha256=v_old.manifest_sha256
  ) then
    raise exception 'BLOCK_CAUSAL_V100_NOT_CURRENT';
  end if;

  if exists (
    select 1 from public.lf_capability_version_registry
    where capability_code='CAUSAL_EFFECT_LINEAGE' and version='1.0.1'
  ) then
    raise exception 'BLOCK_CAUSAL_V101_ALREADY_EXISTS';
  end if;

  v_manifest :=
    v_old.manifest
    || jsonb_build_object(
      'version','1.0.1',
      'usage',
        coalesce(v_old.manifest->'usage','{}'::jsonb)
        || jsonb_build_object(
          'implementation',v_impl,
          'call','evaluate_lineage(request)'
        ),
      'delivery',
        coalesce(v_old.manifest->'delivery','{}'::jsonb)
        || jsonb_build_object(
          'source_path',v_impl,
          'functional_source_unchanged',true
        ),
      'compatibility',
        coalesce(v_old.manifest->'compatibility','{}'::jsonb)
        || jsonb_build_object(
          'functional_core_unchanged',true,
          'manifest_contract_completion_only',true
        ),
      'currentness',
        coalesce(v_old.manifest->'currentness','{}'::jsonb)
        || jsonb_build_object(
          'implementation_ref_completed_by_execution_id',v_execution_id
        )
    );

  v_sha := encode(
    extensions.digest(convert_to(v_manifest::text,'UTF8'),'sha256'),
    'hex'
  );

  insert into public.lf_capability_version_registry(
    capability_code,version,version_major,version_minor,version_patch,
    release_state,supersedes_version,manifest,manifest_sha256,
    source_ref,docs_ref,validator_ref,created_by_execution_id
  ) values (
    'CAUSAL_EFFECT_LINEAGE','1.0.1',1,0,1,
    'RELEASED','1.0.0',v_manifest,v_sha,
    v_old.source_ref,v_old.docs_ref,v_old.validator_ref,v_execution_id
  );

  v_promote := public.fn_lf_capability_promote_v1(
    'CAUSAL_EFFECT_LINEAGE',
    '1.0.1',
    null,
    v_execution_id,
    'Manifest-only contract completion: publish exact implementation_ref/source_path already pinned by v1.0.0 source_ref and source_blob_sha1; functional source unchanged.'
  );

  if coalesce((v_promote->>'ready')::boolean,false) is not true then
    raise exception 'BLOCK_CAUSAL_V101_PROMOTION:%',v_promote::text;
  end if;

  if not exists (
    select 1
    from public.lf_capability_current c
    join public.lf_capability_version_registry v
      on v.capability_code=c.capability_code
     and v.version=c.version
     and v.manifest_sha256=c.manifest_sha256
    where c.capability_code='CAUSAL_EFFECT_LINEAGE'
      and c.version='1.0.1'
      and v.release_state='RELEASED'
      and v.manifest#>>'{usage,implementation}'=v_impl
      and v.manifest#>>'{delivery,source_path}'=v_impl
      and v.manifest#>>'{delivery,source_blob_sha1}'='f15cc736d2eabbfa3bd9f6211ca69ef324956eb8'
      and (v.manifest#>>'{delivery,functional_source_unchanged}')::boolean is true
  ) then
    raise exception 'BLOCK_CAUSAL_V101_CURRENT_READBACK';
  end if;
end;
$causal$;

update public.lf_error_knowledge
set validacion =
  'PASS when generic adapters compile to existing router capabilities; migration-expected checkpoints fail closed at action-spec before packet if no output SQL is declared; CAUSAL_EFFECT_LINEAGE resolves implementation_ref from CURRENT manifest v1.0.1 without changing its pinned functional source.'
where codigo='ENGINEERING-TRANSVERSAL-ADAPTER-COMPILATION-GAP-001';

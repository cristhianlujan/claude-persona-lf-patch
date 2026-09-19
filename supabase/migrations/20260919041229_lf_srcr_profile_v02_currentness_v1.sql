do $$
declare
  v_version text;
  v_profile_pack_id text;
  v_entrypoint_sha text;
  v_manifest_sha text;
  v_last_pr int;
  v_last_merge text;
begin
  select
    version,
    metadata->>'profile_pack_id',
    metadata->>'entrypoint_sha',
    metadata->>'manifest_sha',
    nullif(metadata->>'last_governed_pr','')::int,
    metadata->>'last_governed_merge_sha'
  into
    v_version,
    v_profile_pack_id,
    v_entrypoint_sha,
    v_manifest_sha,
    v_last_pr,
    v_last_merge
  from public.lf_activos
  where codigo_activo='PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF'
    and tipo_activo='PERFIL'
    and archived_at is null
  for update;

  if not found then
    raise exception 'SRCR_PROFILE_ASSET_NOT_FOUND';
  end if;

  if v_version='v0.2'
     and v_profile_pack_id='SYSTEMIC_ROOT_CAUSE_REPAIR_LF_V0_2'
     and v_entrypoint_sha='a827d0bbfe6295b1d0b3a10d01f3f4d9d6475488'
     and v_manifest_sha='43e5913ce35b181d2fc72f732b0d9bb6aae48447'
     and v_last_pr=928
     and v_last_merge='a688f110634eb0b1aa9e1efa62a4a5d473810e89' then
    return;
  end if;

  if v_version <> 'v0.1'
     or v_profile_pack_id <> 'SYSTEMIC_ROOT_CAUSE_REPAIR_LF_V0_1'
     or v_entrypoint_sha <> '89485c60c971c0645850ced577609c8b9f13f84c'
     or v_last_pr <> 867
     or v_last_merge <> '6c7adf72851d459acb5156924a52f05f186c65cb' then
    raise exception 'SRCR_PROFILE_CURRENTNESS_PRESTATE_MISMATCH';
  end if;

  update public.lf_activos
  set
    version='v0.2',
    ultima_revision='2026-09-19',
    raw_payload=jsonb_set(
      jsonb_set(
        coalesce(raw_payload,'{}'::jsonb),
        '{skill_sha}',
        to_jsonb('a827d0bbfe6295b1d0b3a10d01f3f4d9d6475488'::text),
        true
      ),
      '{profile_pack_id}',
      to_jsonb('SYSTEMIC_ROOT_CAUSE_REPAIR_LF_V0_2'::text),
      true
    ),
    metadata=coalesce(metadata,'{}'::jsonb)
      || jsonb_build_object(
        'entrypoint_sha','a827d0bbfe6295b1d0b3a10d01f3f4d9d6475488',
        'manifest_sha','43e5913ce35b181d2fc72f732b0d9bb6aae48447',
        'profile_pack_id','SYSTEMIC_ROOT_CAUSE_REPAIR_LF_V0_2',
        'last_governed_pr',928,
        'last_governed_merge_sha','a688f110634eb0b1aa9e1efa62a4a5d473810e89',
        'currentness_synced_at','2026-09-19T04:12:29Z',
        'currentness_reason','POST_MERGE_PROFILE_V0_2_RUNTIME_CANARY'
      ),
    updated_by_execution_id='EXEC-LF-SRCR-PROFILE-CURRENTNESS-20260919-001'
  where codigo_activo='PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF'
    and tipo_activo='PERFIL'
    and archived_at is null;

  if not exists (
    select 1
    from public.lf_activos
    where codigo_activo='PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF'
      and version='v0.2'
      and metadata->>'profile_pack_id'='SYSTEMIC_ROOT_CAUSE_REPAIR_LF_V0_2'
      and metadata->>'entrypoint_sha'='a827d0bbfe6295b1d0b3a10d01f3f4d9d6475488'
      and metadata->>'manifest_sha'='43e5913ce35b181d2fc72f732b0d9bb6aae48447'
      and metadata->>'last_governed_pr'='928'
      and metadata->>'last_governed_merge_sha'='a688f110634eb0b1aa9e1efa62a4a5d473810e89'
  ) then
    raise exception 'SRCR_PROFILE_CURRENTNESS_READBACK_FAILED';
  end if;
end
$$;

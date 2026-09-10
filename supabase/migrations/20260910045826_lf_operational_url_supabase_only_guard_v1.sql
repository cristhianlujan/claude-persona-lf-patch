update public.lf_activos
set metadata = coalesce(metadata,'{}'::jsonb)
  || jsonb_build_object(
       'storage_refs',coalesce(metadata->'storage_refs','{}'::jsonb)
         || jsonb_build_object('google_drive',jsonb_build_object(
              'url',url,
              'role','STORAGE_ONLY',
              'authority',false,
              'operational_read_allowed',false,
              'normalized_at',now()
            )),
       'source_governance',coalesce(metadata->'source_governance','{}'::jsonb)
         || jsonb_build_object(
              'operational_authority','SUPABASE',
              'operational_source_ref','supabase://public/lf_activos/'||codigo_activo,
              'external_storage_is_authority',false,
              'drive_role','STORAGE_ONLY',
              'policy_code','POL-LF-SOURCE-RESOLUTION',
              'policy_version','v1.3-transversal-supabase-authority'
            )
     ),
    url='supabase://public/lf_activos/'||codigo_activo,
    updated_by_execution_id='EXEC-SOURCE-AUTHORITY-SUPABASE-ONLY-20260909-001'
where archived_at is null
  and url ~* '^https?://(docs|drive)\.google\.com/';

update public.lf_activos
set metadata = coalesce(metadata,'{}'::jsonb)
  || jsonb_build_object(
       'technical_refs',coalesce(metadata->'technical_refs','{}'::jsonb)
         || jsonb_build_object('github',jsonb_build_object(
              'url',url,
              'role','TECHNICAL_IMPLEMENTATION_ARTIFACT',
              'authority',false,
              'operational_resolution_requires_supabase_binding',true,
              'normalized_at',now()
            )),
       'source_governance',coalesce(metadata->'source_governance','{}'::jsonb)
         || jsonb_build_object(
              'operational_authority','SUPABASE',
              'operational_source_ref','supabase://public/lf_activos/'||codigo_activo,
              'github_role','TECHNICAL_IMPLEMENTATION_ARTIFACT',
              'github_is_authority',false,
              'policy_code','POL-LF-SOURCE-RESOLUTION',
              'policy_version','v1.3-transversal-supabase-authority'
            )
     )
  || case
       when upper(coalesce(metadata->>'registry_source','')) like '%GITHUB%'
         then jsonb_build_object(
                'registry_source','SUPABASE',
                'legacy_registry_source',metadata->>'registry_source'
              )
       else '{}'::jsonb
     end,
    url='supabase://public/lf_activos/'||codigo_activo,
    updated_by_execution_id='EXEC-SOURCE-AUTHORITY-SUPABASE-ONLY-20260909-001'
where archived_at is null
  and url ~* '^https?://github\.com/';

update public.lf_activos
set metadata = coalesce(metadata,'{}'::jsonb)
  || jsonb_build_object(
       'external_refs',coalesce(metadata->'external_refs','{}'::jsonb)
         || jsonb_build_object('legacy_http',jsonb_build_object(
              'url',url,
              'role','REFERENCE_ONLY',
              'authority',false,
              'normalized_at',now()
            )),
       'source_governance',coalesce(metadata->'source_governance','{}'::jsonb)
         || jsonb_build_object(
              'operational_authority','SUPABASE',
              'operational_source_ref','supabase://public/lf_activos/'||codigo_activo,
              'external_http_is_authority',false,
              'policy_code','POL-LF-SOURCE-RESOLUTION',
              'policy_version','v1.3-transversal-supabase-authority'
            )
     ),
    url='supabase://public/lf_activos/'||codigo_activo,
    updated_by_execution_id='EXEC-SOURCE-AUTHORITY-SUPABASE-ONLY-20260909-001'
where archived_at is null
  and url ~* '^https?://'
  and url !~* '^https?://github\.com/'
  and url !~* '^https?://(docs|drive)\.google\.com/';

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid='public.lf_activos'::regclass
      and conname='lf_activos_operational_url_supabase_only_chk'
  ) then
    alter table public.lf_activos
      add constraint lf_activos_operational_url_supabase_only_chk
      check (archived_at is not null or url is null or url like 'supabase://%');
  end if;
end $$;
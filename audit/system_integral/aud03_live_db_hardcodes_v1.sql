-- AUD-3 live DB hardcode scanner v1
-- Read-only. Live functions are material runtime; unlike migration files, they are not historical artifacts.
with funcs as (
  select n.nspname schema_name,p.proname,
         n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')' function_identity,
         pg_get_functiondef(p.oid) definition
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname in ('public','private','programacion') and p.prokind='f'
),
sha_hits as (
  select f.function_identity,(m)[1] sha40
  from funcs f,lateral regexp_matches(f.definition,'((?<![0-9a-f])[0-9a-f]{40}(?![0-9a-f]))','g') m
),
pooler_hits as (
  select function_identity
  from funcs
  where lower(definition) like '%pooler.supabase.com%'
)
select jsonb_build_object(
 'functions_scanned',(select count(*) from funcs),
 'functions_with_sha40',(select count(distinct function_identity) from sha_hits),
 'sha40_occurrences',(select count(*) from sha_hits),
 'sha40_functions',coalesce((select jsonb_agg(distinct function_identity order by function_identity) from sha_hits),'[]'::jsonb),
 'functions_with_pooler_host',(select count(*) from pooler_hits),
 'pooler_functions',coalesce((select jsonb_agg(function_identity order by function_identity) from pooler_hits),'[]'::jsonb)
) as aud03_live_db_hardcodes;

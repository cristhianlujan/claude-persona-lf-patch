-- PR93 · Production readiness P0 · external function search-path assertions
-- Read-only verification after the corresponding migration.

begin;
set local transaction read only;

select lf_ops.fn_normalize_relation_segment('a b')='A_B' as normalize_ok;
select lf_ops.fn_relation_code('REL','SRC','CTX','DST')='LFREL:REL:SRC:CTX:DST' as relation_code_ok;
select lf_ops.fn_b2b_native_numeric_id('SCREEN','__P0_NONEXISTENT__') is null as lookup_ok;

set local role service_role;
select count(*)=0 as empty_restock_ok
from public.fn_restock_url_queue(array[]::text[],'P0_READBACK','p0');
select (public.lf_validar_cierre_verificacion(
  'TEST','P0','CANDIDATO','READ_ONLY',false,null,null,null,null,'{}'::jsonb
)->>'allowed')::boolean as closure_validator_ok;
select public.sbx_lf_validation_engine_evidence_ref_ok(
  jsonb_build_object('id','E1','hash_referencia','H')
) as evidence_ref_ok;
select public.sbx_lf_validation_engine_source_ref_ok(
  jsonb_build_object('source_type','ROW','source_id','1','source_sha_or_row_id','1')
) as source_ref_ok;
select public.sbx_lf_validation_engine_check_run('PASS',true,true,'PASS') as check_run_ok;
select public.sbx_lf_validation_engine_valid_proof() ? 'verification' as valid_proof_ok;
select public.sbx_lf_validation_engine_check_step(
  29,'report_output',true,public.sbx_lf_validation_engine_valid_proof()
) as check_step_ok;
select public.fn_kb_quality_score(kb) is not null as kb_score_ok
from public.lf_knowledge_base kb limit 1;
reset role;

do $assertions$
declare
  v_count integer;
  v_fixed integer;
  v_invalid integer;
begin
  select count(*), count(*) filter (where p.proconfig is not null)
  into v_count, v_fixed
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where (n.nspname,p.proname) in (
    ('lf_ops','fn_b2b_native_numeric_id'),
    ('lf_ops','fn_normalize_relation_segment'),
    ('lf_ops','fn_relation_code'),
    ('public','fn_kb_quality_score'),
    ('public','fn_restock_url_queue'),
    ('public','lf_register_strategy_event'),
    ('public','lf_validar_cierre_verificacion'),
    ('public','sbx_lf_validation_engine_check_run'),
    ('public','sbx_lf_validation_engine_check_step'),
    ('public','sbx_lf_validation_engine_evidence_ref_ok'),
    ('public','sbx_lf_validation_engine_source_ref_ok'),
    ('public','sbx_lf_validation_engine_valid_proof')
  );

  if v_count <> 12 or v_fixed <> 12 then
    raise exception 'P0_EXTERNAL_FUNCTION_SEARCH_PATH_MISMATCH count=% fixed=%', v_count, v_fixed;
  end if;

  select count(*) into v_invalid
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public'
    and (
      (p.proname='fn_restock_url_queue' and (
        has_function_privilege('anon',p.oid,'EXECUTE')
        or has_function_privilege('authenticated',p.oid,'EXECUTE')
        or not has_function_privilege('service_role',p.oid,'EXECUTE')
      ))
      or
      (p.proname='lf_register_strategy_event' and (
        has_function_privilege('anon',p.oid,'EXECUTE')
        or has_function_privilege('authenticated',p.oid,'EXECUTE')
        or has_function_privilege('service_role',p.oid,'EXECUTE')
      ))
    );

  if v_invalid <> 0 then
    raise exception 'P0_MUTATION_RPC_GRANT_ASSERTION_FAILED invalid=%', v_invalid;
  end if;

  if has_schema_privilege('anon','lf_ops','USAGE')
     or has_schema_privilege('authenticated','lf_ops','USAGE')
     or has_schema_privilege('service_role','lf_ops','USAGE') then
    raise exception 'P0_LF_OPS_SCHEMA_EXPOSURE_INTRODUCED';
  end if;
end
$assertions$;

select
  n.nspname as schema_name,
  p.proname as function_name,
  pg_get_function_identity_arguments(p.oid) as identity_arguments,
  p.proconfig,
  has_function_privilege('anon',p.oid,'EXECUTE') as anon_execute,
  has_function_privilege('authenticated',p.oid,'EXECUTE') as authenticated_execute,
  has_function_privilege('service_role',p.oid,'EXECUTE') as service_role_execute
from pg_proc p
join pg_namespace n on n.oid=p.pronamespace
where (n.nspname,p.proname) in (
  ('lf_ops','fn_b2b_native_numeric_id'),('lf_ops','fn_normalize_relation_segment'),('lf_ops','fn_relation_code'),
  ('public','fn_kb_quality_score'),('public','fn_restock_url_queue'),('public','lf_register_strategy_event'),
  ('public','lf_validar_cierre_verificacion'),('public','sbx_lf_validation_engine_check_run'),
  ('public','sbx_lf_validation_engine_check_step'),('public','sbx_lf_validation_engine_evidence_ref_ok'),
  ('public','sbx_lf_validation_engine_source_ref_ok'),('public','sbx_lf_validation_engine_valid_proof')
)
order by n.nspname,p.proname,identity_arguments;

rollback;

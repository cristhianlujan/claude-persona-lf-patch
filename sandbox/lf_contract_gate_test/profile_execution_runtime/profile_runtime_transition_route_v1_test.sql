\set ON_ERROR_STOP off
\echo === contract v1.2
select contract_code, status, allowed->>'persistent_write_executor' pwe, allowed->>'executor' ex, blocked from public.lf_operation_contracts order by created_at, contract_code;
create or replace function pg_temp.try(label text, req jsonb) returns void language plpgsql as $$ begin
  begin perform public.lf_profile_runtime_transition_v1(req); raise notice '% => PASS', label;
  exception when others then raise notice '% => BLOCK %', label, sqlerrm; end; end $$;
\set good '{"profile_code":"PERFIL-PRODUCT-DIRECTOR-LF","requested_by":"claude","request_ref":"https://github.com/cristhianlujan/claude-persona-lf-patch/issues/9999","owner_authorization":{"mode":"OWNER_CHAT_CONFORMITY_ONE_SHOT","profile_code":"PERFIL-PRODUCT-DIRECTOR-LF","statement":"Autorizo activar Producto en solo lectura","authorized_at":"'
select pg_temp.try('N1 extra key', (:'good' || to_char(now() at time zone 'utc','YYYY-MM-DD"T"HH24:MI:SS"Z"') || '"}}')::jsonb || '{"x":1}');
select pg_temp.try('N2 profile not in list', replace((:'good' || to_char(now() at time zone 'utc','YYYY-MM-DD"T"HH24:MI:SS"Z"') || '"}}'),'PERFIL-PRODUCT-DIRECTOR-LF','PERFIL-NOPE-LF')::jsonb);
select pg_temp.try('N3 auth profile mismatch', replace((:'good' || to_char(now() at time zone 'utc','YYYY-MM-DD"T"HH24:MI:SS"Z"') || '"}}'),'"profile_code":"PERFIL-PRODUCT-DIRECTOR-LF","statement"','"profile_code":"PERFIL-OTHER-LF","statement"')::jsonb);
select pg_temp.try('N4 expired (5 days)', (:'good' || to_char((now()-interval '5 days') at time zone 'utc','YYYY-MM-DD"T"HH24:MI:SS"Z"') || '"}}')::jsonb);
select pg_temp.try('N5 future', (:'good' || to_char((now()+interval '2 days') at time zone 'utc','YYYY-MM-DD"T"HH24:MI:SS"Z"') || '"}}')::jsonb);
select pg_temp.try('N6 short statement', replace((:'good' || to_char(now() at time zone 'utc','YYYY-MM-DD"T"HH24:MI:SS"Z"') || '"}}'),'Autorizo activar Producto en solo lectura','si')::jsonb);
select pg_temp.try('N7 bad ref', replace((:'good' || to_char(now() at time zone 'utc','YYYY-MM-DD"T"HH24:MI:SS"Z"') || '"}}'),'/issues/9999','/pull/9')::jsonb);
select pg_temp.try('N8 bad requester', replace((:'good' || to_char(now() at time zone 'utc','YYYY-MM-DD"T"HH24:MI:SS"Z"') || '"}}'),'"claude"','"intruder"')::jsonb);
select pg_temp.try('N9 drift source (RUNTIME_OPERATIVO)', replace(replace((:'good' || to_char(now() at time zone 'utc','YYYY-MM-DD"T"HH24:MI:SS"Z"') || '"}}'),'PERFIL-PRODUCT-DIRECTOR-LF','PERFIL-DRIFT-LF'),'x','x')::jsonb);
select pg_temp.try('N10 null', null);
\echo === after negatives (must be unchanged, 0 receipts)
select codigo_activo, runtime_estado from public.lf_activos order by 1;
select count(*) receipts from public.lf_profile_runtime_transition_receipt_v1;
select pg_temp.try('P1 valid transition', (:'good' || to_char(now() at time zone 'utc','YYYY-MM-DD"T"HH24:MI:SS"Z"') || '"}}')::jsonb);
\echo === after P1
select codigo_activo, estado_original, nivel_control, runtime_estado, estado_documental, estado_operativo, impacto_automatico from public.lf_activos order by 1;
select profile_code, requested_by, from_state_sha256 from public.lf_profile_runtime_transition_receipt_v1;
select pg_temp.try('N11 second use right after', (:'good' || to_char(now() at time zone 'utc','YYYY-MM-DD"T"HH24:MI:SS"Z"') || '"}}')::jsonb);
update public.lf_activos set estado_original='CANDIDATE_READ_ONLY', nivel_control='PROFILE_REGISTRY', runtime_estado='NO_HABILITADO' where codigo_activo='PERFIL-PRODUCT-DIRECTOR-LF';
select pg_temp.try('N12 reuse after manual reset (one-shot)', (:'good' || to_char(now() at time zone 'utc','YYYY-MM-DD"T"HH24:MI:SS"Z"') || '"}}')::jsonb);
\echo === privileges
select has_function_privilege('anon','public.lf_profile_runtime_transition_v1(jsonb)','execute') anon, has_function_privilege('authenticated','public.lf_profile_runtime_transition_v1(jsonb)','execute') auth, has_function_privilege('service_role','public.lf_profile_runtime_transition_v1(jsonb)','execute') svc, has_table_privilege('service_role','public.lf_profile_runtime_transition_receipt_v1','select') svc_tbl;

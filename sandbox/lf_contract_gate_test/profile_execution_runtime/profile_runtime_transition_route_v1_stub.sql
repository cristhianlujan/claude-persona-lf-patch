-- Local Postgres test for 20261105060000_lf_profile_runtime_transition_route_v1.sql.
-- Run: psql -d <empty db> -f ..._stub.sql -f <migration> -f this file. Stub schema only; never against LF_SUPABASE_SANDBOX.
create role service_role; create role anon; create role authenticated;
create table public.lf_activos(codigo_activo text, tipo_activo text, estado_original text, estado_documental text, estado_operativo text, nivel_control text, runtime_estado text, impacto_automatico text, archived_at timestamptz, updated_at timestamptz);
insert into public.lf_activos values
 ('PERFIL-PRODUCT-DIRECTOR-LF','PERFIL','CANDIDATE_READ_ONLY','CANDIDATO','READ_ONLY','PROFILE_REGISTRY','NO_HABILITADO','BLOQUEADO',null,null),
 ('PERFIL-OTHER-LF','PERFIL','CANDIDATE_READ_ONLY','CANDIDATO','READ_ONLY','PROFILE_REGISTRY','NO_HABILITADO','BLOQUEADO',null,null),
 ('PERFIL-DRIFT-LF','PERFIL','CANDIDATE_READ_ONLY','CANDIDATO','READ_ONLY','PROFILE_REGISTRY','RUNTIME_OPERATIVO','BLOQUEADO',null,null);
create table public.cat_estado_normalizacion_lf(estado_original text, estado_documental text, estado_operativo text, nivel_control text, runtime_estado text, impacto_automatico text);
insert into public.cat_estado_normalizacion_lf values('CANDIDATO_CONTROLADO_READ_ONLY','CANDIDATO','READ_ONLY','CONTROLADO','CANDIDATE_READ_ONLY','BLOQUEADO');
create table public.lf_operation_contracts(operation_code text, contract_code text, contract_path text, contract_sha text, required_before_write jsonb, allowed jsonb, blocked jsonb, required_after_write jsonb, status text, created_at timestamptz default now(), updated_at timestamptz default now(), created_by_execution_id text, updated_by_execution_id text);
insert into public.lf_operation_contracts(operation_code,contract_code,contract_path,required_before_write,allowed,blocked,required_after_write,status,created_by_execution_id) values('TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF','CONTRACT-TRANSICION-RUNTIME-PERFIL-READ-ONLY-LF-v0.1.1-candidate','x','["a"]','{"persistent_write_executor":false,"single_target":true}','["mass_transition"]','["b"]','CANDIDATO_READ_ONLY','EXEC-X');

\set ON_ERROR_STOP on
-- TEST-ONLY database: stub the current ledger anchor signature, never production.
create schema extensions;
create extension if not exists pgcrypto with schema extensions;
create schema private;
create role service_role;
create role anon;
create role authenticated;
create table public.lf_operation_execution (
  execution_id text primary key,operation_code text,target_code text,status text,manifest jsonb
);
create table public.lf_operation_execution_steps (
  execution_id text,step_id text,status text,evidence_payload jsonb,primary key(execution_id,step_id)
);
create table public.lf_activos(
  codigo_activo text primary key,nombre_canonico text,owner_name text,
  estado_documental text,estado_operativo text
);
create view public.v_lf_fuente_operativa_busqueda as
  select codigo_activo,nombre_canonico,owner_name,estado_documental,estado_operativo from public.lf_activos;
create table private.lf_evidence_ledger_v1 (
  receipt_id uuid primary key default gen_random_uuid(),
  execution_id text,gate_code text,subject_ref text,subject_sha256 text,
  created_by_execution_id text,verification_state text,provider text,receipt_sha256 text
);
create function public.fn_lf_evidence_ledger_anchor_v1(
  p_execution_id text,p_capability_code text,p_gate_code text,
  p_receipt_kind text,p_subject_type text,p_subject_ref text,
  p_subject_sha256 text,p_source_head_sha text,p_authority_ref text,
  p_resolver_id text,p_provider text,p_provider_ref text,
  p_verification_method text,p_verification_state text,
  p_verification_payload jsonb,p_receipt_payload jsonb,p_actor_execution_id text
) returns jsonb language plpgsql as $stub$
declare v_id uuid;
begin
  if p_verification_payload->>'provider_readback_verified' is distinct from 'true'
     or p_verification_payload->>'digest_recomputed' is distinct from 'true' then
     raise exception 'TEST_STUB_REJECTS_UNVERIFIED';
  end if;
  insert into private.lf_evidence_ledger_v1(
    execution_id,gate_code,subject_ref,subject_sha256,created_by_execution_id,
    verification_state,provider,receipt_sha256
  ) values(
    p_execution_id,p_gate_code,p_subject_ref,p_subject_sha256,p_actor_execution_id,
    p_verification_state,p_provider,repeat('a',64)
  ) returning receipt_id into v_id;
  return jsonb_build_object('verification_state',p_verification_state,
    'receipt_id',v_id,'receipt_sha256',repeat('a',64));
end $stub$;

\ir SRCR_N1N2_SOURCE_FIRST_LEDGER_ATTEST_CANDIDATE_20261030.sql
insert into public.lf_activos values
  ('ACT-0058','SKILL_ORQUESTADOR_PIPELINE_LF',null,'APROBADO','APROBADO');
insert into public.lf_operation_execution values
  ('EXEC-SRCR','EJECUCION_PERFIL_LF','PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF','IN_PROGRESS','{}'),
  ('EXEC-LEDGER','ORQUESTACION_PIPELINE_LF','ACT-0058','IN_PROGRESS',
    '{"capability_code":"EVIDENCE_LEDGER","producer_execution_id":"EXEC-SRCR"}');
insert into public.lf_operation_execution_steps values
  ('EXEC-SRCR','profile_source_read','STEP_PASS_WITH_EVIDENCE',
    '{"source_revision":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}'::jsonb),
  ('EXEC-SRCR','execute_profile','STEP_PASS_WITH_EVIDENCE',
    jsonb_build_object(
       'candidate_digest','sha256:'||repeat('a',64),
       'profile_output',jsonb_build_object(
         'current_uncertainties',jsonb_build_array(
          jsonb_build_object('uncertainty_id','U1','impact','DESIGN_BLOCKING',
          'cascade',jsonb_build_object('catalog_queries',jsonb_build_array(
            jsonb_build_object('level','N1','readback',jsonb_build_object(
              'query','SELECT codigo_activo,nombre_canonico,owner_name,estado_documental,estado_operativo FROM public.v_lf_fuente_operativa_busqueda WHERE codigo_activo=''ACT-0058''',
              'source','v_lf_fuente_operativa_busqueda')),
            jsonb_build_object('level','N2','readback',jsonb_build_object(
              'query','SELECT codigo_activo,nombre_canonico,owner_name,estado_documental,estado_operativo FROM public.lf_activos WHERE codigo_activo=''ACT-0058''',
              'source','lf_activos'))
        )))))
  );

do $test$
declare
  r jsonb;
  first_count integer;
begin
  r:=public.lf_srcr_n1n2_source_first_ledger_v1('EXEC-SRCR','U1','ACT-0058','EXEC-LEDGER');
  if r->>'receipt_count'<>'2'
     or r#>>'{readbacks,0,readback,sample_records,0,owner_name}' is not null
     or r#>>'{readbacks,0,readback,source}' is distinct from 'v_lf_fuente_operativa_busqueda'
     or r#>>'{readbacks,1,readback,source}' is distinct from 'lf_activos' then
    raise exception 'TEST_REAL_SOURCE_READBACK_INCORRECT:%',r;
  end if;
  select count(*) into first_count from private.lf_evidence_ledger_v1;
  if first_count<>2 then raise exception 'TEST_EXPECTED_TWO_SOURCE_RECEIPTS'; end if;
  r:=public.lf_srcr_n1n2_source_first_ledger_v1('EXEC-SRCR','U1','ACT-0058','EXEC-LEDGER');
  if (select count(*) from private.lf_evidence_ledger_v1)<>2 then
    raise exception 'TEST_REPLAY_NOT_IDEMPOTENT';
  end if;
  begin
    perform public.lf_srcr_n1n2_source_first_ledger_v1('EXEC-SRCR','U1','ACT-0058','EXEC-FAKE');
    raise exception 'TEST_EXPECTED_BLOCK_NOT_RAISED';
  exception when others then
    if SQLERRM<>'BLOCK_SRCR_LEDGER_ACTOR_NOT_BOUND_TO_PRODUCER' then raise; end if;
  end;
  begin
    perform public.lf_srcr_n1n2_source_first_ledger_v1('EXEC-SRCR','OTHER','ACT-0058','EXEC-LEDGER');
    raise exception 'TEST_EXPECTED_BLOCK_NOT_RAISED';
  exception when others then
    if SQLERRM<>'BLOCK_SRCR_MATERIAL_UNCERTAINTY_NOT_FOUND' then raise; end if;
  end;
  begin
    perform public.lf_srcr_n1n2_source_first_ledger_v1('EXEC-SRCR','U1','ACT-OTHER','EXEC-LEDGER');
    raise exception 'TEST_EXPECTED_BLOCK_NOT_RAISED';
  exception when others then
    if SQLERRM not like 'BLOCK_SRCR_PRODUCER_QUERY_NOT_SOURCE_BOUND:%' then raise; end if;
  end;
  update public.lf_activos set owner_name='UNRATIFIED_TEST_CHANGE' where codigo_activo='ACT-0058';
  begin
    perform public.lf_srcr_n1n2_source_first_ledger_v1('EXEC-SRCR','U1','ACT-0058','EXEC-LEDGER');
    raise exception 'TEST_EXPECTED_BLOCK_NOT_RAISED';
  exception when others then
    if SQLERRM<>'BLOCK_SRCR_LEDGER_REPLAY_SOURCE_DRIFT' then raise; end if;
  end;
  raise notice 'PASS_SRCR_N1_N2_SQL_INTEGRATION 6/6 (ephemeral postgres; stub anchor; NOT LIVE)';
end
$test$;

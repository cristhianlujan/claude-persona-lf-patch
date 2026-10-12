\set ON_ERROR_STOP on
create schema if not exists public;
create table public.lf_operation_execution(
 execution_id text primary key, operation_code text not null, target_type text not null default 'TEST', target_code text not null default 'TEST',
 target_repo text, target_path text, status text not null default 'IN_PROGRESS', started_at timestamptz not null default now(), completed_at timestamptz,
 manifest jsonb not null default '{}'::jsonb, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 created_by_execution_id text not null default 'TEST', updated_by_execution_id text, idempotency_key text, request_sha256 text,
 lease_owner text, lease_expires_at timestamptz, lease_fence bigint not null default 0, checkpoint_seq bigint not null default 0, checkpoint_payload jsonb not null default '{}'::jsonb
);
create table public.lf_operation_registry(operation_code text primary key,lifecycle_state_code text);
create table public.lf_operation_steps(operation_code text,step_order integer,step_id text,active boolean,execution_order integer, primary key(operation_code,step_order,step_id));
create table public.lf_operation_execution_steps(execution_id text,step_order integer,step_id text,status text, primary key(execution_id,step_order,step_id));
insert into public.lf_operation_registry values ('OP_GOOD','OP_OPERATIONAL'),('GITHUB_CONTRACT_GATE_LF','OP_OPERATIONAL'),('OP_CANDIDATE','OP_CANDIDATE');
insert into public.lf_operation_steps values ('OP_GOOD',10,'init_execution',true,10),('GITHUB_CONTRACT_GATE_LF',1,'router',true,1),('OP_CANDIDATE',10,'init_execution',true,10);
\ir ../../../supabase/migrations/20260923190500_lf_changeset_solution_ref_governance_v1.sql

-- 1/5 valid origin resolves.
insert into public.lf_operation_execution(execution_id,operation_code,manifest,created_at) values ('EXEC-1','OP_GOOD','{"solution_ref":" SOL-A "}',clock_timestamp());
insert into public.lf_operation_execution_steps values ('EXEC-1',10,'init_execution','STEP_PASS_WITH_EVIDENCE');
do $$begin if not coalesce((public.lf_resolve_solution_ref_origin_v1('SOL-A')->>'valid')::boolean,false) then raise exception 'TEST1'; end if; end$$;

-- 2/5 retry/same ref is allowed and normalized identity remains stable.
update public.lf_operation_execution set manifest=manifest||'{"solution_ref":"SOL-A","retry":1}'::jsonb where execution_id='EXEC-1';
do $$begin if (select manifest->>'solution_ref' from public.lf_operation_execution where execution_id='EXEC-1')<>'SOL-A' then raise exception 'TEST2'; end if; end$$;

-- 3/5 changing/removing an established ref is blocked.
do $$begin begin update public.lf_operation_execution set manifest=manifest||'{"solution_ref":"SOL-B"}'::jsonb where execution_id='EXEC-1'; raise exception 'TEST3_NOT_BLOCKED'; exception when others then if position('SOLUTION_REF_IMMUTABLE' in sqlerrm)=0 then raise; end if; end; end$$;

-- 4/5 verification gate cannot be origin.
insert into public.lf_operation_execution(execution_id,operation_code,manifest,created_at) values ('EXEC-GATE','GITHUB_CONTRACT_GATE_LF','{"solution_ref":"SOL-GATE"}',clock_timestamp());
insert into public.lf_operation_execution_steps values ('EXEC-GATE',1,'router','PASS');
do $$declare r jsonb; begin r:=public.lf_resolve_solution_ref_origin_v1('SOL-GATE'); if r->>'code'<>'SOLUTION_REF_ORIGIN_VERIFICATION_GATE_FORBIDDEN' then raise exception 'TEST4:%',r; end if; end$$;

-- 5/5 first step must be PASS via existing execution-step enforcement surface.
insert into public.lf_operation_execution(execution_id,operation_code,manifest,created_at) values ('EXEC-NOPASS','OP_GOOD','{"solution_ref":"SOL-NOPASS"}',clock_timestamp());
insert into public.lf_operation_execution_steps values ('EXEC-NOPASS',10,'init_execution','EXECUTION_INITIALIZED');
do $$declare r jsonb; begin r:=public.lf_resolve_solution_ref_origin_v1('SOL-NOPASS'); if r->>'code'<>'SOLUTION_REF_ORIGIN_FIRST_STEP_NOT_PASS' then raise exception 'TEST5:%',r; end if; end$$;
\echo PASS_CHANGESET_SOLUTION_REF_LOCAL=5/5

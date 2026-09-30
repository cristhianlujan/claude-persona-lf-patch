-- LF_EVIDENCE_PLANE_HARDENING_EKB_CLOSEOUT_V1
-- Closes only the three Evidence Plane integrity findings already repaired by
-- the applied 20260930133539 hardening and proven by a rollback canary.
-- No Evidence Plane CURRENT promotion, evidence receipt write, runtime/deploy/production activation.

do $preflight$
declare
  v_execution_id constant text := 'EXEC-SADM-EVIDENCE-PLANE-EKB-CLOSEOUT-20260930-001';
  v_target_path constant text := 'supabase/migrations/20260930221500_lf_evidence_plane_hardening_ekb_closeout_v1.sql';
  v_hardening_sha constant text := '7b1abd2d539a1b58403514d987ec0cdd156d15ff74d45212f74466e6c5dfee0a';
  v_count integer;
  v_guard text;
  v_anchor text;
begin
  if not exists (
    select 1 from public.lf_operation_execution
    where execution_id=v_execution_id
      and operation_code='ACTUALIZACION_DB_LF'
      and target_type='MIGRATION'
      and target_code='EVIDENCE_PLANE_HARDENING_EKB_CLOSEOUT_V1'
      and target_repo='cristhianlujan/claude-persona-lf-patch'
      and target_path=v_target_path
      and status='IN_PROGRESS'
  ) then
    raise exception 'BLOCK_EVIDENCE_PLANE_EKB_CLOSEOUT_EXECUTION_BINDING';
  end if;

  select count(*) into v_count
  from supabase_migrations.schema_migrations
  where version='20260930133539'
    and name='evidence_ledger_crossbind_hardening_v1'
    and cardinality(statements)=1
    and encode(extensions.digest(convert_to(statements[1],'UTF8'),'sha256'),'hex')=v_hardening_sha;
  if v_count<>1 then
    raise exception 'BLOCK_EVIDENCE_PLANE_HARDENING_SOURCE_NOT_EXACT:%',v_count;
  end if;

  select pg_get_functiondef('private.fn_lf_evidence_ledger_guard_v1()'::regprocedure) into v_guard;
  select pg_get_functiondef('public.fn_lf_evidence_ledger_anchor_v1(text,text,text,text,text,text,text,text,text,text,text,text,text,text,jsonb,jsonb,text)'::regprocedure) into v_anchor;

  if position('BLOCK_LF_EVIDENCE_LEDGER_GITHUB_PROVIDER_REF_HEAD_MISMATCH' in v_guard)=0
     or position('BLOCK_LF_EVIDENCE_LEDGER_RESOLVER_IDENTITY_MISMATCH' in v_guard)=0
     or position('BLOCK_LF_EVIDENCE_LEDGER_COMPOSITION_DIGEST_MISMATCH' in v_guard)=0
     or position('BLOCK_LF_EVIDENCE_LEDGER_PRODUCER_CROSSBIND_MISMATCH' in v_guard)=0
     or position('BLOCK_LF_EVIDENCE_LEDGER_CURRENT_BINDING_MISSING' in v_guard)=0 then
    raise exception 'BLOCK_EVIDENCE_PLANE_HARDENING_GUARD_INCOMPLETE';
  end if;

  if position('composition_sha256' in v_anchor)=0
     or position('BLOCK_LF_EVIDENCE_LEDGER_RESOLVER_IDENTITY_MISMATCH' in v_anchor)=0
     or position('IDEMPOTENT_REPLAY' in v_anchor)=0
     or position('EVIDENCE_LEDGER' in v_anchor)=0 then
    raise exception 'BLOCK_EVIDENCE_PLANE_HARDENING_ANCHOR_INCOMPLETE';
  end if;

  select count(*) into v_count
  from transversal.error_knowledge
  where codigo in (
    'CURRENTNESS-EVIDENCE-SOURCE-HEAD-REANCHOR-001',
    'S31-EVIDENCE-RECEIPT-REPLAY-CROSSBIND-001',
    'S31-EVIDENCE-RESOLVER-IDENTITY-SPOOF-001'
  ) and lower(estado) in ('activo','active','abierto','open');
  if v_count<>3 then
    raise exception 'BLOCK_EVIDENCE_PLANE_EKB_PRESTATE_NOT_EXACT:%',v_count;
  end if;

  if exists (select 1 from public.lf_capability_current where capability_code in ('EVIDENCE_LEDGER','EVIDENCE_ANTIREPLAY')) then
    raise exception 'BLOCK_EVIDENCE_PLANE_EKB_CLOSEOUT_PREMATURE_CURRENT';
  end if;
end
$preflight$;

do $patch$
declare
  v_count integer;
  v_marker constant text := '[RESOLVED_20260930] Applied hardening migration 20260930133539/evidence_ledger_crossbind_hardening_v1 has exact ledger statement SHA256=7b1abd2d539a1b58403514d987ec0cdd156d15ff74d45212f74466e6c5dfee0a. Source recovered to main by PR #1319 at f0f23037ef59749ac2589b8d063e190f5e5daae3 with exact payload parity and no DDL replay/ledger mutation. Live rollback canary PASS: positive provider-bound anchor accepted; source-head reanchor mismatch blocked; resolver identity spoof blocked; cross-execution replay/composition misuse blocked; execution/dispatch/binding/CURRENT residue=0. No CURRENT promotion is part of this closeout.';
  v_source_ref constant text := 'github://cristhianlujan/claude-persona-lf-patch@f0f23037ef59749ac2589b8d063e190f5e5daae3/supabase/migrations/20260930133539_evidence_ledger_crossbind_hardening_v1.sql';
begin
  update transversal.error_knowledge
     set estado='resuelto',
         evidencia=concat_ws(E'\n\n',nullif(btrim(coalesce(evidencia,'')),''),v_marker),
         source_context='EVIDENCE_PLANE_HARDENING_V1_LIVE_READBACK_AND_ROLLBACK_CANARY',
         source_ref=v_source_ref,
         ultima_vez=clock_timestamp(),
         updated_at=clock_timestamp()
   where codigo in (
    'CURRENTNESS-EVIDENCE-SOURCE-HEAD-REANCHOR-001',
    'S31-EVIDENCE-RECEIPT-REPLAY-CROSSBIND-001',
    'S31-EVIDENCE-RESOLVER-IDENTITY-SPOOF-001'
   )
   and lower(estado) in ('activo','active','abierto','open');
  get diagnostics v_count=row_count;
  if v_count<>3 then
    raise exception 'BLOCK_EVIDENCE_PLANE_EKB_CLOSEOUT_ROWCOUNT:%',v_count;
  end if;
end
$patch$;

do $post$
declare
  v_count integer;
begin
  select count(*) into v_count
  from transversal.error_knowledge
  where codigo in (
    'CURRENTNESS-EVIDENCE-SOURCE-HEAD-REANCHOR-001',
    'S31-EVIDENCE-RECEIPT-REPLAY-CROSSBIND-001',
    'S31-EVIDENCE-RESOLVER-IDENTITY-SPOOF-001'
  ) and estado='resuelto'
    and source_ref='github://cristhianlujan/claude-persona-lf-patch@f0f23037ef59749ac2589b8d063e190f5e5daae3/supabase/migrations/20260930133539_evidence_ledger_crossbind_hardening_v1.sql'
    and evidencia like '%EVIDENCE_PLANE_HARDENING_V1%';
  if v_count<>3 then
    raise exception 'BLOCK_EVIDENCE_PLANE_EKB_CLOSEOUT_READBACK:%',v_count;
  end if;

  if exists (select 1 from public.lf_capability_current where capability_code in ('EVIDENCE_LEDGER','EVIDENCE_ANTIREPLAY')) then
    raise exception 'BLOCK_EVIDENCE_PLANE_EKB_CLOSEOUT_UNAUTHORIZED_CURRENT';
  end if;
end
$post$;

-- HUMAN_DECISION_ROUTING 1.0.1
-- Records verified authority-receipt ingress as live while keeping real authority
-- policy activation and consumer cutover disabled.

do $cap$
declare
  v_exec text:='PROGRAMMING_HUMAN_DECISION_ROUTING_VERIFIER_STATE_V1';
  v_manifest jsonb;
  v_sha text;
  v_existing text;
begin
  select manifest
    into v_manifest
  from public.lf_capability_version_registry
  where capability_code='HUMAN_DECISION_ROUTING'
    and version='1.0.0'
    and release_state='RELEASED';

  if v_manifest is null then
    raise exception 'HUMAN_DECISION_ROUTING_1_0_0_REQUIRED';
  end if;

  if to_regclass('private.lf_human_decision_authority_policies_v1') is null
     or to_regprocedure('private.fn_lf_human_decision_record_verified_v1(uuid,bigint,text)') is null
     or to_regprocedure('private.fn_lf_human_decision_assert_authority_receipt_v1(uuid,text,text,text,text,text,text)') is null then
    raise exception 'HUMAN_DECISION_AUTHORITY_VERIFIER_NOT_LIVE';
  end if;

  if exists(
    select 1
    from private.lf_human_decision_authority_policies_v1
    where status='ACTIVE'
  ) then
    raise exception 'HUMAN_DECISION_REAL_AUTHORITY_POLICY_PREEXISTING';
  end if;

  v_manifest:=jsonb_set(v_manifest,'{version}','"1.0.1"'::jsonb,true);
  v_manifest:=jsonb_set(
    v_manifest,
    '{contract,authority_policy_registry}',
    '"private.lf_human_decision_authority_policies_v1"'::jsonb,
    true
  );
  v_manifest:=jsonb_set(
    v_manifest,
    '{contract,verified_decision_ingress}',
    '"private.fn_lf_human_decision_record_verified_v1"'::jsonb,
    true
  );
  v_manifest:=jsonb_set(
    v_manifest,
    '{contract,receipt_guard_verifies_authority_provenance}',
    'true'::jsonb,
    true
  );
  v_manifest:=jsonb_set(
    v_manifest,
    '{currentness,authority_receipt_verification}',
    'true'::jsonb,
    true
  );
  v_manifest:=jsonb_set(
    v_manifest,
    '{currentness,authority_policy_active}',
    'false'::jsonb,
    true
  );
  v_manifest:=jsonb_set(
    v_manifest,
    '{currentness,consumer_cutover}',
    'false'::jsonb,
    true
  );
  v_manifest:=jsonb_set(
    v_manifest,
    '{currentness,current_pointer}',
    'false'::jsonb,
    true
  );
  v_manifest:=jsonb_set(
    v_manifest,
    '{currentness,cutover_blocker}',
    '"HUMAN-DECISION-AUTHORITY-POLICY-ACTIVATION-001"'::jsonb,
    true
  );
  v_manifest:=jsonb_set(
    v_manifest,
    '{migration,authority_receipt_verifier}',
    '"20261008054500_human_decision_authority_receipt_verifier_v1"'::jsonb,
    true
  );

  v_sha:=encode(
    extensions.digest(convert_to(v_manifest::text,'UTF8'),'sha256'),
    'hex'
  );

  select manifest_sha256
    into v_existing
  from public.lf_capability_version_registry
  where capability_code='HUMAN_DECISION_ROUTING'
    and version='1.0.1';

  if v_existing is not null and v_existing<>v_sha then
    raise exception 'HUMAN_DECISION_ROUTING_VERSION_1_0_1_MANIFEST_CONFLICT';
  end if;

  insert into public.lf_capability_version_registry(
    capability_code,version,version_major,version_minor,version_patch,
    release_state,supersedes_version,manifest,manifest_sha256,
    source_ref,docs_ref,validator_ref,created_by_execution_id
  )
  values(
    'HUMAN_DECISION_ROUTING','1.0.1',1,0,1,
    'RELEASED','1.0.0',v_manifest,v_sha,
    'github://cristhianlujan/claude-persona-lf-patch/supabase/migrations/20261008060000_human_decision_routing_verifier_state_v1.sql',
    'github://cristhianlujan/claude-persona-lf-patch/docs/operations/HUMAN_DECISION_ROUTING_V1.md',
    'supabase://private/fn_lf_human_decision_record_verified_v1',
    v_exec
  )
  on conflict(capability_code,version) do nothing;

  update public.lf_capability_registry
  set description='Transversal human-decision routing with live verified authority-receipt ingress. Real authority policy activation and producer cutover remain gated.',
      updated_at=now(),
      updated_by_execution_id=v_exec
  where capability_code='HUMAN_DECISION_ROUTING';

  if exists(
    select 1 from public.lf_capability_current
    where capability_code='HUMAN_DECISION_ROUTING'
  ) then
    raise exception 'HUMAN_DECISION_ROUTING_CURRENT_POINTER_PREMATURE';
  end if;
end
$cap$;

update public.lf_error_knowledge
set estado='RESUELTO',
    validacion='Resolved by migration 20261008054500_human_decision_authority_receipt_verifier_v1. Rollback-only live probe proved: no-policy rejection, stale-currentness rejection, fake direct receipt rejection, valid provenance+policy acceptance, replay rejection and wrong-channel-token rejection; zero residue. Live readback confirms policy table and verifier functions exist, receipt table guard invokes provenance verification, and real active policy count is 0.',
    source_ref='github://cristhianlujan/claude-persona-lf-patch/supabase/migrations/20261008054500_human_decision_authority_receipt_verifier_v1.sql',
    updated_at=now()
where codigo='HUMAN-DECISION-AUTHORITY-RECEIPT-VERIFICATION-001';

insert into public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
  severidad,estado,source_ref,updated_at
)
values(
  'HUMAN-DECISION-AUTHORITY-POLICY-ACTIVATION-001',
  'PROGRAMMING_GOVERNANCE',
  'Verified human-decision routing is live but no real authority policy is activated yet',
  'The generic router can now cryptographically and structurally verify a provenance receipt before accepting a human decision. However, the live authority policy registry intentionally has zero ACTIVE rows, so no real reviewer/authority/channel pair can advance a producer yet.',
  'Authority verification infrastructure and authority activation are separate concerns. Activating a real reviewer authority before its contract is governed would recreate the original authority-inference defect.',
  'VERIFIER LIVE -> GOVERNED AUTHORITY CONTRACT -> ACTIVE AUTHORITY POLICY -> E2E HUMAN DECISION -> CURRENT PROMOTION -> PRODUCER CUTOVER.',
  'Do not map LF product B2B_ADMIN_LF to software governance. Do not activate LF_GOVERNANCE_SUPER_ADMIN_V1 while it remains CANDIDATE_READ_ONLY. Require explicit authority contract and approved channel/role binding.',
  'HUMAN_DECISION_ROUTING 1.0.1 records authority_receipt_verification=true, authority_policy_active=false, consumer_cutover=false and current_pointer=false.',
  'HIGH','ACTIVO',
  'capability://HUMAN_DECISION_ROUTING@1.0.1',
  now()
)
on conflict(codigo) do update
set descripcion=excluded.descripcion,
    causa_raiz=excluded.causa_raiz,
    patron=excluded.patron,
    prevencion=excluded.prevencion,
    validacion=excluded.validacion,
    severidad=excluded.severidad,
    estado=excluded.estado,
    source_ref=excluded.source_ref,
    updated_at=excluded.updated_at;

-- HUMAN_DECISION_ROUTING capability registration and low-risk index hardening.
-- Capability is discoverable/released but deliberately NOT promoted to lf_capability_current
-- until authority-receipt verification and consumer cutover gates are complete.

create index if not exists idx_lf_human_decision_requests_v1_supersedes
  on private.lf_human_decision_requests_v1(supersedes_request_id)
  where supersedes_request_id is not null;

do $cap$
declare
  v_exec text:='PROGRAMMING_HUMAN_DECISION_ROUTING_V1';
  v_manifest jsonb;
  v_manifest_sha text;
  v_existing_sha text;
begin
  v_manifest:=jsonb_build_object(
    'schema_version','lf-capability-manifest/v1',
    'capability_code','HUMAN_DECISION_ROUTING',
    'version','1.0.0',
    'contract',jsonb_build_object(
      'request_ledger','private.lf_human_decision_requests_v1',
      'receipt_ledger','private.lf_human_decision_receipts_v1',
      'active_queue','private.v_lf_human_decision_active_queue_v1',
      'request_lifecycle',jsonb_build_array('OPEN','DECIDED','CANCELLED','SUPERSEDED'),
      'human_decision_never_converts_validator_fail_to_pass',true,
      'authority_specific_receipt_verification_required',true
    ),
    'delivery',jsonb_build_object(
      'repository','cristhianlujan/claude-persona-lf-patch',
      'core_migration','supabase/migrations/20261008043000_human_decision_routing_v1.sql',
      'adapter_migration','supabase/migrations/20261008050500_human_decision_routing_adapters_v1.sql',
      'documentation','docs/operations/HUMAN_DECISION_ROUTING_V1.md'
    ),
    'installation',jsonb_build_object(
      'schema','private',
      'public_client_access',false,
      'request_write_for_anon',false,
      'request_write_for_authenticated',false,
      'decision_write_ingress','NOT_EXPOSED'
    ),
    'dependencies',jsonb_build_object(
      'input_governance_source','programacion.input_gap_proposals',
      'story_p0_source','private.v_lf_p0_human_review_active_queue_v1',
      'programming_source','programacion.engineering_work_checkpoints',
      'authority_receipt_verifier','PENDING'
    ),
    'compatibility',jsonb_build_object(
      'producer_adapters',jsonb_build_array('INPUT_GOVERNANCE','STORY_CREATOR_P0','PROGRAMMING'),
      'legacy_source_stores_preserved',true,
      'story_creator_not_generic_authority',true,
      'b2b_admin_lf_not_software_governance_authority',true
    ),
    'migration',jsonb_build_object(
      'core','20261008043000_human_decision_routing_v1',
      'adapters','20261008050500_human_decision_routing_adapters_v1',
      'consumer_cutover','PENDING'
    ),
    'rollback',jsonb_build_object(
      'consumer_cutover_active',false,
      'safe_to_disable_new_routing',true,
      'historical_requests_and_receipts_must_be_preserved',true
    ),
    'usage',jsonb_build_object(
      'open_core','private.fn_lf_human_decision_open_v1',
      'consume_core','private.fn_lf_human_decision_consume_v1',
      'ig_open','private.fn_lf_human_decision_open_ig_v1',
      'story_open','private.fn_lf_human_decision_open_story_p0_v1',
      'programming_open','private.fn_lf_human_decision_open_programming_v1',
      'automatic_consumer_advance',false
    ),
    'currentness',jsonb_build_object(
      'core_live',true,
      'producer_adapters_live',true,
      'adapter_count',3,
      'rollback_probe','PASS',
      'consumer_cutover',false,
      'authority_receipt_verification',false,
      'current_pointer',false,
      'cutover_blocker','HUMAN-DECISION-AUTHORITY-RECEIPT-VERIFICATION-001'
    )
  );

  v_manifest_sha:=encode(
    extensions.digest(convert_to(v_manifest::text,'UTF8'),'sha256'),
    'hex'
  );

  insert into public.lf_capability_registry(
    capability_code,capability_name,capability_kind,owner_scope,status,
    description,created_by_execution_id,updated_by_execution_id,
    entry_guard_required,entry_guard_code
  ) values(
    'HUMAN_DECISION_ROUTING',
    'Human Decision Routing',
    'TRANSVERSAL',
    'LF_GOVERNANCE',
    'ACTIVE',
    'Transversal durable human-decision request, queue and receipt routing shared by IG, Story Creator and Programming. Consumer cutover remains blocked until authority receipts are verifiably authenticated.',
    v_exec,v_exec,false,'ORCHESTRATOR_EXECUTION_GUARD_V1'
  )
  on conflict(capability_code) do update
  set capability_name=excluded.capability_name,
      capability_kind=excluded.capability_kind,
      owner_scope=excluded.owner_scope,
      status=excluded.status,
      description=excluded.description,
      entry_guard_required=excluded.entry_guard_required,
      entry_guard_code=excluded.entry_guard_code,
      updated_at=now(),
      updated_by_execution_id=v_exec;

  select manifest_sha256
    into v_existing_sha
  from public.lf_capability_version_registry
  where capability_code='HUMAN_DECISION_ROUTING'
    and version='1.0.0';

  if v_existing_sha is not null and v_existing_sha<>v_manifest_sha then
    raise exception 'HUMAN_DECISION_ROUTING_VERSION_1_0_0_MANIFEST_CONFLICT';
  end if;

  insert into public.lf_capability_version_registry(
    capability_code,version,version_major,version_minor,version_patch,
    release_state,supersedes_version,manifest,manifest_sha256,
    source_ref,docs_ref,validator_ref,created_by_execution_id
  ) values(
    'HUMAN_DECISION_ROUTING','1.0.0',1,0,0,
    'RELEASED',null,v_manifest,v_manifest_sha,
    'github://cristhianlujan/claude-persona-lf-patch/supabase/migrations/20261008051500_human_decision_routing_capability_v1.sql',
    'github://cristhianlujan/claude-persona-lf-patch/docs/operations/HUMAN_DECISION_ROUTING_V1.md',
    'supabase://private/fn_lf_human_decision_open_v1+fn_lf_human_decision_open_ig_v1+fn_lf_human_decision_open_story_p0_v1+fn_lf_human_decision_open_programming_v1',
    v_exec
  )
  on conflict(capability_code,version) do nothing;

  if exists(
    select 1
    from public.lf_capability_current
    where capability_code='HUMAN_DECISION_ROUTING'
  ) then
    raise exception 'HUMAN_DECISION_ROUTING_CURRENT_POINTER_PREMATURE';
  end if;
end
$cap$;

update public.lf_error_knowledge
set validacion='Core migration merged/applied and adapter migration merged/applied. Live rollback probe passed all three producer adapters and read-only consumer adapters with zero residue. Capability HUMAN_DECISION_ROUTING 1.0.0 is released/discoverable but intentionally has no lf_capability_current pointer while authority-receipt verification is pending.',
    source_ref='capability://HUMAN_DECISION_ROUTING@1.0.0',
    updated_at=now()
where codigo='HUMAN-DECISION-ROUTING-ARCHITECTURE-001';

insert into public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
  severidad,estado,source_ref,updated_at
)
values(
  'HUMAN-DECISION-CAPABILITY-NO-PREMATURE-CURRENT-001',
  'PROGRAMMING_GOVERNANCE',
  'Human Decision Routing is discoverable before cutover but must not become current prematurely',
  'The generic ledger and three producer adapters are live and reusable, but automatic producer consumption is not yet safe because authority-specific receipt verification is still pending. The capability is therefore registered and versioned without a lf_capability_current pointer.',
  'Capability registration can be mistaken for runtime cutover if current-version promotion is performed before its authority boundary is complete.',
  'REGISTER + RELEASE VERSION -> PROVE AUTHORITY RECEIPT VERIFIER -> PROVE CONSUMER ADAPTER -> PROMOTE CURRENT -> CUTOVER.',
  'Do not add a HUMAN_DECISION_ROUTING current pointer until HUMAN-DECISION-AUTHORITY-RECEIPT-VERIFICATION-001 is closed and negative tests prove forged/stale/wrong-authority receipts are rejected.',
  'Version 1.0.0 manifest explicitly records consumer_cutover=false, authority_receipt_verification=false and current_pointer=false. Migration fails if a current pointer already exists.',
  'HIGH','ACTIVO',
  'capability://HUMAN_DECISION_ROUTING@1.0.0',
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

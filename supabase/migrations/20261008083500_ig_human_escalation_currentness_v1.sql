-- IG HUMAN ESCALATION SOURCE CURRENTNESS V1
-- Reconciles historical IG human-decision proposals against the latest validated
-- canonical run before evidence acquisition or human routing.
-- Reuses CURRENTNESS_AUTHORITY semantics; does not mutate historical proposals.

create or replace function private.fn_lf_ig_human_decision_source_currentness_v1(
  p_proposal_id bigint
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v_p programacion.input_gap_proposals%rowtype;
  v_source_run programacion.input_readiness_runs%rowtype;
  v_latest_run programacion.input_readiness_runs%rowtype;
  v_latest_assessment programacion.input_family_assessments%rowtype;
  v_current_proposal programacion.input_gap_proposals%rowtype;
  v_latest_blockers jsonb;
begin
  select * into strict v_p
  from programacion.input_gap_proposals
  where id=p_proposal_id;

  select * into strict v_source_run
  from programacion.input_readiness_runs
  where id=v_p.run_id;

  if v_p.validator_outcome is distinct from 'PASS' then
    return jsonb_build_object(
      'schema_version','lf-ig-human-source-currentness/v1',
      'state','BLOCKED',
      'code','SOURCE_PROPOSAL_NOT_VALIDATED',
      'proposal_id',v_p.id,
      'source_run_id',v_p.run_id,
      'human_queue_allowed',false
    );
  end if;

  select *
    into v_latest_run
  from programacion.input_readiness_runs
  where pantalla_id=v_source_run.pantalla_id
    and status='COMPLETED'
    and invalidated_at is null
    and validator_completed_at is not null
  order by id desc
  limit 1;

  if not found then
    return jsonb_build_object(
      'schema_version','lf-ig-human-source-currentness/v1',
      'state','BLOCKED',
      'code','LATEST_VALIDATED_RUN_NOT_FOUND',
      'proposal_id',v_p.id,
      'source_run_id',v_p.run_id,
      'pantalla_id',v_source_run.pantalla_id,
      'human_queue_allowed',false
    );
  end if;

  select *
    into v_latest_assessment
  from programacion.input_family_assessments
  where run_id=v_latest_run.id
    and family_code=v_p.family_code
  order by id desc
  limit 1;

  if not found or v_latest_assessment.validator_outcome is distinct from 'PASS' then
    return jsonb_build_object(
      'schema_version','lf-ig-human-source-currentness/v1',
      'state','BLOCKED',
      'code','LATEST_FAMILY_ASSESSMENT_NOT_VALIDATED',
      'proposal_id',v_p.id,
      'source_run_id',v_p.run_id,
      'latest_run_id',v_latest_run.id,
      'pantalla_id',v_source_run.pantalla_id,
      'family_code',v_p.family_code,
      'human_queue_allowed',false
    );
  end if;

  if v_latest_run.id=v_source_run.id then
    return jsonb_build_object(
      'schema_version','lf-ig-human-source-currentness/v1',
      'state','CURRENT',
      'code','SOURCE_IS_LATEST_VALIDATED_RUN',
      'proposal_id',v_p.id,
      'source_run_id',v_p.run_id,
      'latest_run_id',v_latest_run.id,
      'pantalla_id',v_source_run.pantalla_id,
      'family_code',v_p.family_code,
      'contract_revision',v_latest_run.contract_revision,
      'human_queue_allowed',null
    );
  end if;

  v_latest_blockers:=coalesce(v_latest_assessment.blockers,'[]'::jsonb);

  if jsonb_array_length(v_latest_blockers)=0 then
    return jsonb_build_object(
      'schema_version','lf-ig-human-source-currentness/v1',
      'state','RESOLVED_BY_NEWER_EVIDENCE',
      'code','SOURCE_SUPERSEDED_RESOLVED',
      'proposal_id',v_p.id,
      'source_run_id',v_p.run_id,
      'latest_run_id',v_latest_run.id,
      'pantalla_id',v_source_run.pantalla_id,
      'family_code',v_p.family_code,
      'old_gap_code',v_p.gap_code,
      'latest_applicability',v_latest_assessment.applicability,
      'latest_coverage_status',v_latest_assessment.coverage_status,
      'latest_well_defined_status',v_latest_assessment.well_defined_status,
      'latest_blockers',v_latest_blockers,
      'source_ref',format(
        'supabase://programacion/input_family_assessments/%s',
        v_latest_assessment.id
      ),
      'human_queue_allowed',false
    );
  end if;

  select *
    into v_current_proposal
  from programacion.input_gap_proposals
  where run_id=v_latest_run.id
    and family_code=v_p.family_code
    and validator_outcome='PASS'
  order by id desc
  limit 1;

  return jsonb_build_object(
    'schema_version','lf-ig-human-source-currentness/v1',
    'state','SUPERSEDED_BY_CURRENT_GAP',
    'code','SOURCE_SUPERSEDED_CURRENT_GAP',
    'proposal_id',v_p.id,
    'source_run_id',v_p.run_id,
    'latest_run_id',v_latest_run.id,
    'pantalla_id',v_source_run.pantalla_id,
    'family_code',v_p.family_code,
    'old_gap_code',v_p.gap_code,
    'latest_applicability',v_latest_assessment.applicability,
    'latest_coverage_status',v_latest_assessment.coverage_status,
    'latest_well_defined_status',v_latest_assessment.well_defined_status,
    'latest_blockers',v_latest_blockers,
    'current_proposal_id',v_current_proposal.id,
    'current_proposal_kind',v_current_proposal.proposal_kind,
    'current_proposal_status',v_current_proposal.status,
    'current_gap_code',v_current_proposal.gap_code,
    'source_ref',format(
      'supabase://programacion/input_family_assessments/%s',
      v_latest_assessment.id
    ),
    'human_queue_allowed',false
  );
end
$function$;

create or replace view private.v_lf_ig_human_decision_source_current_v1
with (security_invoker=true)
as
with latest as (
  select distinct on (pantalla_id)
         pantalla_id,id as latest_run_id
  from programacion.input_readiness_runs
  where status='COMPLETED'
    and invalidated_at is null
    and validator_completed_at is not null
  order by pantalla_id,id desc
)
select p.id as proposal_id,
       p.run_id,
       r.pantalla_id,
       p.family_code,
       p.gap_code,
       p.proposal_kind,
       p.status,
       p.validator_outcome,
       p.validator_sha256,
       p.validated_at
from programacion.input_gap_proposals p
join programacion.input_readiness_runs r on r.id=p.run_id
join latest l
  on l.pantalla_id=r.pantalla_id
 and l.latest_run_id=p.run_id
where p.status='HUMAN_DECISION_REQUIRED'
  and p.proposal_kind='HUMAN_DECISION_REQUIRED'
  and p.validator_outcome='PASS';

revoke all on private.v_lf_ig_human_decision_source_current_v1
  from public,anon,authenticated;
revoke all on function private.fn_lf_ig_human_decision_source_currentness_v1(bigint)
  from public,anon,authenticated;

create or replace function private.fn_lf_human_decision_open_ig_v3(
  p_proposal_id bigint,
  p_targeted_evidence_request jsonb,
  p_safe_change_request jsonb default null,
  p_created_by_execution_id text default 'INPUT_GOVERNANCE_ADAPTER_V3'
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_p programacion.input_gap_proposals%rowtype;
  v_currentness text;
  v_source_currentness jsonb;
  v_target jsonb;
  v_admission jsonb;
begin
  select * into strict v_p
  from programacion.input_gap_proposals
  where id=p_proposal_id;

  if v_p.status<>'HUMAN_DECISION_REQUIRED'
     or v_p.proposal_kind<>'HUMAN_DECISION_REQUIRED'
     or v_p.validator_outcome<>'PASS' then
    raise exception 'IG_HUMAN_DECISION_SOURCE_NOT_ELIGIBLE:%:%:%',
      v_p.status,v_p.proposal_kind,v_p.validator_outcome;
  end if;

  v_source_currentness:=private.fn_lf_ig_human_decision_source_currentness_v1(
    p_proposal_id
  );

  if v_source_currentness->>'state'='RESOLVED_BY_NEWER_EVIDENCE' then
    return jsonb_build_object(
      'schema_version','lf-human-decision-open-ig-v3/v1',
      'opened',false,
      'proposal_id',v_p.id,
      'source_currentness',v_source_currentness,
      'admission',jsonb_build_object(
        'schema_version','LF_HUMAN_ESCALATION_ADMISSION_RESULT_V1',
        'state','NO_HUMAN_REQUIRED',
        'code','SOURCE_SUPERSEDED_RESOLVED',
        'human_queue_allowed',false
      )
    );
  end if;

  if v_source_currentness->>'state'='SUPERSEDED_BY_CURRENT_GAP' then
    return jsonb_build_object(
      'schema_version','lf-human-decision-open-ig-v3/v1',
      'opened',false,
      'proposal_id',v_p.id,
      'source_currentness',v_source_currentness,
      'admission',jsonb_build_object(
        'schema_version','LF_HUMAN_ESCALATION_ADMISSION_RESULT_V1',
        'state','REFRESH_SOURCE_STATE',
        'code','SOURCE_SUPERSEDED_CURRENT_GAP',
        'human_queue_allowed',false,
        'current_proposal_id',v_source_currentness->'current_proposal_id',
        'current_gap_code',v_source_currentness->'current_gap_code',
        'latest_blockers',v_source_currentness->'latest_blockers'
      )
    );
  end if;

  if v_source_currentness->>'state'<>'CURRENT' then
    return jsonb_build_object(
      'schema_version','lf-human-decision-open-ig-v3/v1',
      'opened',false,
      'proposal_id',v_p.id,
      'source_currentness',v_source_currentness,
      'admission',jsonb_build_object(
        'schema_version','LF_HUMAN_ESCALATION_ADMISSION_RESULT_V1',
        'state','BLOCKED',
        'code',coalesce(v_source_currentness->>'code','SOURCE_CURRENTNESS_UNPROVEN'),
        'human_queue_allowed',false
      )
    );
  end if;

  v_currentness:=encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'proposal_id',v_p.id,
          'run_id',v_p.run_id,
          'family_code',v_p.family_code,
          'gap_code',v_p.gap_code,
          'proposed_payload',v_p.proposed_payload,
          'stage_impact',v_p.stage_impact,
          'validator_sha256',v_p.validator_sha256,
          'validated_at',v_p.validated_at
        )::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );

  if jsonb_typeof(p_targeted_evidence_request)<>'object' then
    v_target:=null;
  else
    v_target:=jsonb_build_object(
      'consumer_ref','INPUT_GOVERNANCE:PROPOSAL:'||v_p.id::text,
      'unresolved_reasons',jsonb_build_array(v_p.gap_code),
      'current_evidence',coalesce(p_targeted_evidence_request->'current_evidence','[]'::jsonb),
      'candidates',coalesce(p_targeted_evidence_request->'candidates','[]'::jsonb)
    );
  end if;

  v_admission:=public.lf_human_escalation_admission_v1(
    jsonb_strip_nulls(
      jsonb_build_object(
        'producer_code','INPUT_GOVERNANCE',
        'subject_type','INPUT_GAP_PROPOSAL',
        'reason_code',v_p.gap_code,
        'subject_ref','supabase://programacion/input_gap_proposals/'||v_p.id::text,
        'currentness_sha256',v_currentness,
        'deterministic_state','UNRESOLVED',
        'resolver_state','NONE',
        'prequalified_human',false,
        'targeted_evidence_request',v_target,
        'safe_change_request',p_safe_change_request
      )
    )
  );

  if v_admission->>'state'<>'HUMAN_ELIGIBLE'
     or coalesce((v_admission->>'human_queue_allowed')::boolean,false) is not true then
    return jsonb_build_object(
      'schema_version','lf-human-decision-open-ig-v3/v1',
      'opened',false,
      'proposal_id',v_p.id,
      'source_currentness',v_source_currentness,
      'admission',v_admission
    );
  end if;

  return jsonb_build_object(
    'schema_version','lf-human-decision-open-ig-v3/v1',
    'opened',true,
    'proposal_id',v_p.id,
    'source_currentness',v_source_currentness,
    'admission',v_admission,
    'routing',private.fn_lf_human_decision_open_ig_v2(
      p_proposal_id,p_created_by_execution_id
    )
  );
end
$function$;

do $cap$
declare
  v_exec text:='IG_HUMAN_ESCALATION_CURRENTNESS_V1';
  v_manifest jsonb;
  v_sha text;
  v_existing text;
  v_ca_version text;
  v_ca_sha text;
  v_promote jsonb;
begin
  select manifest
    into v_manifest
  from public.lf_capability_version_registry
  where capability_code='HUMAN_ESCALATION_ADMISSION'
    and version='1.0.0'
    and release_state='RELEASED';

  if v_manifest is null then
    raise exception 'HUMAN_ESCALATION_ADMISSION_1_0_0_REQUIRED';
  end if;

  select version,manifest_sha256
    into v_ca_version,v_ca_sha
  from public.lf_capability_current
  where capability_code='CURRENTNESS_AUTHORITY';

  if v_ca_version is null then
    raise exception 'CURRENTNESS_AUTHORITY_CURRENT_REQUIRED';
  end if;

  v_manifest:=jsonb_set(v_manifest,'{version}','"1.0.1"'::jsonb,true);
  v_manifest:=jsonb_set(
    v_manifest,
    '{dependencies,CURRENTNESS_AUTHORITY}',
    jsonb_build_object('version',v_ca_version,'manifest_sha256',v_ca_sha),
    true
  );
  v_manifest:=jsonb_set(
    v_manifest,
    '{contract,source_currentness_required_before_human}',
    'true'::jsonb,
    true
  );
  v_manifest:=jsonb_set(
    v_manifest,
    '{usage,ig_source_currentness}',
    '"private.fn_lf_ig_human_decision_source_currentness_v1"'::jsonb,
    true
  );
  v_manifest:=jsonb_set(
    v_manifest,
    '{compatibility,historical_human_proposal_is_current_authority}',
    'false'::jsonb,
    true
  );
  v_manifest:=jsonb_set(
    v_manifest,
    '{currentness,ig_latest_validated_run_required}',
    'true'::jsonb,
    true
  );

  v_sha:=encode(
    extensions.digest(convert_to(v_manifest::text,'UTF8'),'sha256'),
    'hex'
  );

  select manifest_sha256
    into v_existing
  from public.lf_capability_version_registry
  where capability_code='HUMAN_ESCALATION_ADMISSION'
    and version='1.0.1';

  if v_existing is not null and v_existing<>v_sha then
    raise exception 'HUMAN_ESCALATION_ADMISSION_1_0_1_MANIFEST_CONFLICT';
  end if;

  insert into public.lf_capability_version_registry(
    capability_code,version,version_major,version_minor,version_patch,
    release_state,supersedes_version,manifest,manifest_sha256,
    source_ref,docs_ref,validator_ref,created_by_execution_id
  )
  values(
    'HUMAN_ESCALATION_ADMISSION','1.0.1',1,0,1,
    'RELEASED','1.0.0',v_manifest,v_sha,
    'github://cristhianlujan/claude-persona-lf-patch/supabase/migrations/20261008083500_ig_human_escalation_currentness_v1.sql',
    'github://cristhianlujan/claude-persona-lf-patch/docs/operations/HUMAN_DECISION_ROUTING_V1.md',
    'supabase://private/fn_lf_ig_human_decision_source_currentness_v1',
    v_exec
  )
  on conflict(capability_code,version) do nothing;

  v_promote:=public.fn_lf_capability_promote_v1(
    'HUMAN_ESCALATION_ADMISSION','1.0.1',null,v_exec,
    'Adds source-currentness reconciliation before IG human escalation; read-only and fail-closed.'
  );

  if coalesce((v_promote->>'ready')::boolean,false) is not true then
    raise exception 'HUMAN_ESCALATION_ADMISSION_1_0_1_PROMOTION_FAILED:%',
      v_promote::text;
  end if;
end
$cap$;

do $routing$
declare
  v_manifest jsonb;
  v_sha text;
  v_existing text;
  v_hea_version text;
  v_hea_sha text;
begin
  select manifest
    into v_manifest
  from public.lf_capability_version_registry
  where capability_code='HUMAN_DECISION_ROUTING'
    and version='1.0.3'
    and release_state='RELEASED';

  if v_manifest is null then
    raise exception 'HUMAN_DECISION_ROUTING_1_0_3_REQUIRED';
  end if;

  select version,manifest_sha256
    into v_hea_version,v_hea_sha
  from public.lf_capability_current
  where capability_code='HUMAN_ESCALATION_ADMISSION';

  v_manifest:=jsonb_set(v_manifest,'{version}','"1.0.4"'::jsonb,true);
  v_manifest:=jsonb_set(
    v_manifest,
    '{dependencies,HUMAN_ESCALATION_ADMISSION}',
    jsonb_build_object('version',v_hea_version,'manifest_sha256',v_hea_sha),
    true
  );
  v_manifest:=jsonb_set(
    v_manifest,
    '{currentness,ig_historical_proposal_reconciliation}',
    'true'::jsonb,
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

  v_sha:=encode(
    extensions.digest(convert_to(v_manifest::text,'UTF8'),'sha256'),
    'hex'
  );

  select manifest_sha256
    into v_existing
  from public.lf_capability_version_registry
  where capability_code='HUMAN_DECISION_ROUTING'
    and version='1.0.4';

  if v_existing is not null and v_existing<>v_sha then
    raise exception 'HUMAN_DECISION_ROUTING_1_0_4_MANIFEST_CONFLICT';
  end if;

  insert into public.lf_capability_version_registry(
    capability_code,version,version_major,version_minor,version_patch,
    release_state,supersedes_version,manifest,manifest_sha256,
    source_ref,docs_ref,validator_ref,created_by_execution_id
  )
  values(
    'HUMAN_DECISION_ROUTING','1.0.4',1,0,4,
    'RELEASED','1.0.3',v_manifest,v_sha,
    'github://cristhianlujan/claude-persona-lf-patch/supabase/migrations/20261008083500_ig_human_escalation_currentness_v1.sql',
    'github://cristhianlujan/claude-persona-lf-patch/docs/operations/HUMAN_DECISION_ROUTING_V1.md',
    'supabase://private/fn_lf_ig_human_decision_source_currentness_v1',
    'IG_HUMAN_ESCALATION_CURRENTNESS_V1'
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
$routing$;

insert into public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
  severidad,estado,source_ref,updated_at
)
values(
  'HUMAN-ESCALATION-IG-HISTORICAL-CURRENTNESS-001',
  'PROGRAMMING_GOVERNANCE',
  'Historical IG human-decision proposals must be reconciled against the latest validated canonical run before escalation',
  'A validated historical proposal may remain marked HUMAN_DECISION_REQUIRED even after a newer governed IG run resolves the family or replaces the old decision question with a different current implementation/evidence gap. Human escalation must never treat historical status as current authority.',
  'The first pre-human gate correctly required evidence exhaustion but did not distinguish current IG source state from older validated proposals. That could preserve unnecessary human candidates even after later canonical recuration.',
  'HISTORICAL PROPOSAL -> LATEST VALIDATED RUN -> LATEST FAMILY ASSESSMENT -> RESOLVED / REFRESH CURRENT GAP / CURRENT -> ONLY CURRENT MAY ENTER HUMAN_ESCALATION_ADMISSION.',
  'Use fn_lf_ig_human_decision_source_currentness_v1 before IG human admission. Preserve historical proposal rows. Do not mutate them into current truth. Currentness follows the latest non-invalidated COMPLETED run with validated family assessment.',
  'Migration adds read-only IG source-currentness reconciliation, source-current view, HUMAN_ESCALATION_ADMISSION 1.0.1 and HUMAN_DECISION_ROUTING 1.0.4. Consumer cutover stays disabled.',
  'HIGH','ACTIVO',
  'capability://HUMAN_ESCALATION_ADMISSION@1.0.1',
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

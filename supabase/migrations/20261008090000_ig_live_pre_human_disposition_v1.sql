-- IG LIVE PRE-HUMAN DISPOSITION V1
-- Corrects historical-proposal reconciliation to use live canonical classifier output,
-- not merely the latest persisted COMPLETED run.
-- No canonical product data is mutated. No candidate is promoted. No human routing is activated.

create or replace function private.fn_lf_ig_human_decision_live_disposition_v1(
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
  v_live jsonb;
  v_blockers jsonb;
  v_blocker_count integer;
  v_candidate_authority_count integer;
  v_positive_owner_count integer;
  v_uncertain_count integer;
begin
  select * into strict v_p
  from programacion.input_gap_proposals
  where id=p_proposal_id;

  select * into strict v_source_run
  from programacion.input_readiness_runs
  where id=v_p.run_id;

  if v_p.validator_outcome is distinct from 'PASS' then
    return jsonb_build_object(
      'schema_version','lf-ig-human-live-disposition/v1',
      'state','BLOCKED',
      'code','SOURCE_PROPOSAL_NOT_VALIDATED',
      'proposal_id',v_p.id,
      'human_queue_allowed',false
    );
  end if;

  v_live:=programacion.fn_input_governance_bootstrap_classify_v2(
    v_source_run.pantalla_id,
    v_p.family_code,
    v_source_run.version_id
  );

  if jsonb_typeof(v_live)<>'object'
     or coalesce(v_live->>'classifier_sha256','') !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object(
      'schema_version','lf-ig-human-live-disposition/v1',
      'state','BLOCKED',
      'code','LIVE_CLASSIFIER_UNPROVEN',
      'proposal_id',v_p.id,
      'pantalla_id',v_source_run.pantalla_id,
      'family_code',v_p.family_code,
      'human_queue_allowed',false
    );
  end if;

  v_blockers:=coalesce(v_live->'blockers','[]'::jsonb);
  if jsonb_typeof(v_blockers)<>'array' then
    return jsonb_build_object(
      'schema_version','lf-ig-human-live-disposition/v1',
      'state','BLOCKED',
      'code','LIVE_CLASSIFIER_BLOCKERS_INVALID',
      'proposal_id',v_p.id,
      'classifier_sha256',v_live->>'classifier_sha256',
      'human_queue_allowed',false
    );
  end if;

  v_blocker_count:=jsonb_array_length(v_blockers);

  if v_blocker_count=0 then
    return jsonb_build_object(
      'schema_version','lf-ig-human-live-disposition/v1',
      'state','NO_HUMAN_REQUIRED',
      'code','LIVE_CANONICAL_CLASSIFIER_RESOLVED',
      'proposal_id',v_p.id,
      'source_run_id',v_p.run_id,
      'pantalla_id',v_source_run.pantalla_id,
      'family_code',v_p.family_code,
      'old_gap_code',v_p.gap_code,
      'live_applicability',v_live->>'applicability',
      'live_story_ready_status',v_live->>'story_ready_status',
      'live_implementation_ready_status',v_live->>'implementation_ready_status',
      'live_qa_ready_status',v_live->>'qa_ready_status',
      'classifier_sha256',v_live->>'classifier_sha256',
      'live_blockers',v_blockers,
      'human_queue_allowed',false
    );
  end if;

  select
    count(*) filter(
      where b.value->>'uncertainty_type'='CANDIDATE_AUTHORITY'
         or (
           b.value->>'code' like '%_SOURCE_CANDIDATE_NOT_IMPLEMENTATION_READY'
           and b.value->>'earliest_blocking_stage'='IMPLEMENTATION'
         )
    ),
    count(*) filter(
      where coalesce((b.value->>'owner_decision_required')::boolean,false)
        and nullif(btrim(coalesce(b.value->>'owner_decision_authority','')),'') is not null
    ),
    count(*) filter(
      where coalesce(b.value->>'uncertainty_type','') not in (
        'CANDIDATE_AUTHORITY','MISSING_SOURCE','INCOMPLETE_EVIDENCE'
      )
        and not (
          b.value->>'code' like '%_SOURCE_CANDIDATE_NOT_IMPLEMENTATION_READY'
          and b.value->>'earliest_blocking_stage'='IMPLEMENTATION'
        )
        and not (
          coalesce((b.value->>'owner_decision_required')::boolean,false)
          and nullif(btrim(coalesce(b.value->>'owner_decision_authority','')),'') is not null
        )
    )
  into v_candidate_authority_count,v_positive_owner_count,v_uncertain_count
  from jsonb_array_elements(v_blockers) b(value);

  if v_candidate_authority_count=v_blocker_count then
    return jsonb_build_object(
      'schema_version','lf-ig-human-live-disposition/v1',
      'state','ACTION_AUTHORIZATION_GATE',
      'code','GOVERNED_CANDIDATE_PROMOTION_REQUIRED',
      'proposal_id',v_p.id,
      'source_run_id',v_p.run_id,
      'pantalla_id',v_source_run.pantalla_id,
      'family_code',v_p.family_code,
      'old_gap_code',v_p.gap_code,
      'action_code','PROMOTE_GOVERNED_CANDIDATE',
      'action_authorized',false,
      'semantic_decision_required',false,
      'live_applicability',v_live->>'applicability',
      'live_story_ready_status',v_live->>'story_ready_status',
      'live_implementation_ready_status',v_live->>'implementation_ready_status',
      'live_qa_ready_status',v_live->>'qa_ready_status',
      'classifier_sha256',v_live->>'classifier_sha256',
      'live_blockers',v_blockers,
      'human_queue_allowed',false
    );
  end if;

  if v_positive_owner_count>0 then
    return jsonb_build_object(
      'schema_version','lf-ig-human-live-disposition/v1',
      'state','PRE_HUMAN_ADMISSION',
      'code','POSITIVE_OWNER_DECISION_AUTHORITY_PRESENT',
      'proposal_id',v_p.id,
      'source_run_id',v_p.run_id,
      'pantalla_id',v_source_run.pantalla_id,
      'family_code',v_p.family_code,
      'old_gap_code',v_p.gap_code,
      'classifier_sha256',v_live->>'classifier_sha256',
      'live_blockers',v_blockers,
      'human_queue_allowed',false
    );
  end if;

  return jsonb_build_object(
    'schema_version','lf-ig-human-live-disposition/v1',
    'state','INTERNAL_REMEDIATION',
    'code',case
      when v_uncertain_count>0 then 'LIVE_GAP_UNKNOWN_FAIL_CLOSED'
      else 'LIVE_GAP_EVIDENCE_OR_SOURCE_REMEDIATION'
    end,
    'proposal_id',v_p.id,
    'source_run_id',v_p.run_id,
    'pantalla_id',v_source_run.pantalla_id,
    'family_code',v_p.family_code,
    'old_gap_code',v_p.gap_code,
    'semantic_decision_required',false,
    'live_applicability',v_live->>'applicability',
    'live_story_ready_status',v_live->>'story_ready_status',
    'live_implementation_ready_status',v_live->>'implementation_ready_status',
    'live_qa_ready_status',v_live->>'qa_ready_status',
    'classifier_sha256',v_live->>'classifier_sha256',
    'live_blockers',v_blockers,
    'human_queue_allowed',false
  );
end
$function$;

revoke all on function private.fn_lf_ig_human_decision_live_disposition_v1(bigint)
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
  v_live_disposition jsonb;
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

  v_live_disposition:=private.fn_lf_ig_human_decision_live_disposition_v1(
    p_proposal_id
  );

  if v_live_disposition->>'state'='NO_HUMAN_REQUIRED' then
    return jsonb_build_object(
      'schema_version','lf-human-decision-open-ig-v3/v1',
      'opened',false,
      'proposal_id',v_p.id,
      'live_disposition',v_live_disposition,
      'admission',jsonb_build_object(
        'schema_version','LF_HUMAN_ESCALATION_ADMISSION_RESULT_V1',
        'state','NO_HUMAN_REQUIRED',
        'code',v_live_disposition->>'code',
        'human_queue_allowed',false
      )
    );
  end if;

  if v_live_disposition->>'state'='ACTION_AUTHORIZATION_GATE' then
    return jsonb_build_object(
      'schema_version','lf-human-decision-open-ig-v3/v1',
      'opened',false,
      'proposal_id',v_p.id,
      'live_disposition',v_live_disposition,
      'admission',jsonb_build_object(
        'schema_version','LF_HUMAN_ESCALATION_ADMISSION_RESULT_V1',
        'state','ACTION_AUTHORIZATION_GATE',
        'code',v_live_disposition->>'code',
        'action_code',v_live_disposition->>'action_code',
        'semantic_decision_required',false,
        'human_queue_allowed',false
      )
    );
  end if;

  if v_live_disposition->>'state'='INTERNAL_REMEDIATION' then
    return jsonb_build_object(
      'schema_version','lf-human-decision-open-ig-v3/v1',
      'opened',false,
      'proposal_id',v_p.id,
      'live_disposition',v_live_disposition,
      'admission',jsonb_build_object(
        'schema_version','LF_HUMAN_ESCALATION_ADMISSION_RESULT_V1',
        'state','INTERNAL_REMEDIATION',
        'code',v_live_disposition->>'code',
        'human_queue_allowed',false
      )
    );
  end if;

  if v_live_disposition->>'state'<>'PRE_HUMAN_ADMISSION' then
    return jsonb_build_object(
      'schema_version','lf-human-decision-open-ig-v3/v1',
      'opened',false,
      'proposal_id',v_p.id,
      'live_disposition',v_live_disposition,
      'admission',jsonb_build_object(
        'schema_version','LF_HUMAN_ESCALATION_ADMISSION_RESULT_V1',
        'state','BLOCKED',
        'code',coalesce(v_live_disposition->>'code','LIVE_DISPOSITION_UNPROVEN'),
        'human_queue_allowed',false
      )
    );
  end if;

  v_currentness:=v_live_disposition->>'classifier_sha256';

  if jsonb_typeof(p_targeted_evidence_request)<>'object' then
    v_target:=null;
  else
    v_target:=jsonb_build_object(
      'consumer_ref','INPUT_GOVERNANCE:PROPOSAL:'||v_p.id::text,
      'unresolved_reasons',
        coalesce(
          (
            select jsonb_agg(distinct b.value->>'code')
            from jsonb_array_elements(v_live_disposition->'live_blockers') b(value)
            where nullif(b.value->>'code','') is not null
          ),
          jsonb_build_array(v_p.gap_code)
        ),
      'current_evidence',coalesce(p_targeted_evidence_request->'current_evidence','[]'::jsonb),
      'candidates',coalesce(p_targeted_evidence_request->'candidates','[]'::jsonb)
    );
  end if;

  v_admission:=public.lf_human_escalation_admission_v1(
    jsonb_strip_nulls(
      jsonb_build_object(
        'producer_code','INPUT_GOVERNANCE',
        'subject_type','INPUT_GAP_PROPOSAL',
        'reason_code',coalesce(v_live_disposition#>>'{live_blockers,0,code}',v_p.gap_code),
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
      'live_disposition',v_live_disposition,
      'admission',v_admission
    );
  end if;

  return jsonb_build_object(
    'schema_version','lf-human-decision-open-ig-v3/v1',
    'opened',true,
    'proposal_id',v_p.id,
    'live_disposition',v_live_disposition,
    'admission',v_admission,
    'routing',private.fn_lf_human_decision_open_ig_v2(
      p_proposal_id,p_created_by_execution_id
    )
  );
end
$function$;

create or replace view private.v_lf_ig_historical_human_live_disposition_v1
with (security_invoker=true)
as
select p.id as proposal_id,
       d->>'state' as live_state,
       d->>'code' as live_code,
       (d->>'pantalla_id')::integer as pantalla_id,
       d->>'family_code' as family_code,
       d->>'action_code' as action_code,
       d->>'classifier_sha256' as classifier_sha256,
       d->'live_blockers' as live_blockers,
       coalesce((d->>'human_queue_allowed')::boolean,false) as human_queue_allowed
from programacion.input_gap_proposals p
cross join lateral private.fn_lf_ig_human_decision_live_disposition_v1(p.id) d
where p.status='HUMAN_DECISION_REQUIRED'
  and p.validator_outcome='PASS';

create or replace view private.v_lf_ig_nonhuman_action_groups_v1
with (security_invoker=true)
as
select action_code,
       family_code,
       count(*)::integer as subject_count,
       jsonb_agg(
         jsonb_build_object(
           'proposal_id',proposal_id,
           'pantalla_id',pantalla_id,
           'classifier_sha256',classifier_sha256,
           'live_blockers',live_blockers
         )
         order by pantalla_id,proposal_id
       ) as subjects
from private.v_lf_ig_historical_human_live_disposition_v1
where live_state='ACTION_AUTHORIZATION_GATE'
  and not human_queue_allowed
group by action_code,family_code;

revoke all on private.v_lf_ig_historical_human_live_disposition_v1
  from public,anon,authenticated;
revoke all on private.v_lf_ig_nonhuman_action_groups_v1
  from public,anon,authenticated;

do $cap$
declare
  v_exec text:='IG_LIVE_PRE_HUMAN_DISPOSITION_V1';
  v_manifest jsonb;
  v_sha text;
  v_existing text;
  v_currentness_version text;
  v_currentness_sha text;
  v_promote jsonb;
begin
  select manifest
    into v_manifest
  from public.lf_capability_version_registry
  where capability_code='HUMAN_ESCALATION_ADMISSION'
    and version='1.0.1'
    and release_state='RELEASED';

  if v_manifest is null then
    raise exception 'HUMAN_ESCALATION_ADMISSION_1_0_1_REQUIRED';
  end if;

  select version,manifest_sha256
    into v_currentness_version,v_currentness_sha
  from public.lf_capability_current
  where capability_code='CURRENTNESS_AUTHORITY';

  if v_currentness_version is null then
    raise exception 'CURRENTNESS_AUTHORITY_CURRENT_REQUIRED';
  end if;

  v_manifest:=jsonb_set(v_manifest,'{version}','"1.0.2"'::jsonb,true);
  v_manifest:=jsonb_set(
    v_manifest,
    '{dependencies,CURRENTNESS_AUTHORITY}',
    jsonb_build_object(
      'version',v_currentness_version,
      'manifest_sha256',v_currentness_sha,
      'usage','LIVE_CANONICAL_CLASSIFIER_NOT_LATEST_PERSISTED_RUN'
    ),
    true
  );
  v_manifest:=jsonb_set(
    v_manifest,
    '{contract,ig_live_disposition_required_before_human}',
    'true'::jsonb,
    true
  );
  v_manifest:=jsonb_set(
    v_manifest,
    '{usage,ig_live_disposition}',
    '"private.fn_lf_ig_human_decision_live_disposition_v1"'::jsonb,
    true
  );
  v_manifest:=jsonb_set(
    v_manifest,
    '{usage,ig_nonhuman_action_groups}',
    '"private.v_lf_ig_nonhuman_action_groups_v1"'::jsonb,
    true
  );
  v_manifest:=jsonb_set(
    v_manifest,
    '{compatibility,latest_persisted_run_is_current_authority}',
    'false'::jsonb,
    true
  );
  v_manifest:=jsonb_set(
    v_manifest,
    '{compatibility,candidate_authority_is_semantic_human_decision}',
    'false'::jsonb,
    true
  );
  v_manifest:=jsonb_set(
    v_manifest,
    '{currentness,ig_live_classifier_required}',
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
    and version='1.0.2';

  if v_existing is not null and v_existing<>v_sha then
    raise exception 'HUMAN_ESCALATION_ADMISSION_1_0_2_MANIFEST_CONFLICT';
  end if;

  insert into public.lf_capability_version_registry(
    capability_code,version,version_major,version_minor,version_patch,
    release_state,supersedes_version,manifest,manifest_sha256,
    source_ref,docs_ref,validator_ref,created_by_execution_id
  )
  values(
    'HUMAN_ESCALATION_ADMISSION','1.0.2',1,0,2,
    'RELEASED','1.0.1',v_manifest,v_sha,
    'github://cristhianlujan/claude-persona-lf-patch/supabase/migrations/20261008090000_ig_live_pre_human_disposition_v1.sql',
    'github://cristhianlujan/claude-persona-lf-patch/docs/operations/HUMAN_DECISION_ROUTING_V1.md',
    'supabase://private/fn_lf_ig_human_decision_live_disposition_v1',
    v_exec
  )
  on conflict(capability_code,version) do nothing;

  v_promote:=public.fn_lf_capability_promote_v1(
    'HUMAN_ESCALATION_ADMISSION','1.0.2',null,v_exec,
    'Uses live canonical IG classifier before human escalation; read-only and fail-closed.'
  );

  if coalesce((v_promote->>'ready')::boolean,false) is not true then
    raise exception 'HUMAN_ESCALATION_ADMISSION_1_0_2_PROMOTION_FAILED:%',
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
    and version='1.0.4'
    and release_state='RELEASED';

  if v_manifest is null then
    raise exception 'HUMAN_DECISION_ROUTING_1_0_4_REQUIRED';
  end if;

  select version,manifest_sha256
    into v_hea_version,v_hea_sha
  from public.lf_capability_current
  where capability_code='HUMAN_ESCALATION_ADMISSION';

  v_manifest:=jsonb_set(v_manifest,'{version}','"1.0.5"'::jsonb,true);
  v_manifest:=jsonb_set(
    v_manifest,
    '{dependencies,HUMAN_ESCALATION_ADMISSION}',
    jsonb_build_object('version',v_hea_version,'manifest_sha256',v_hea_sha),
    true
  );
  v_manifest:=jsonb_set(
    v_manifest,
    '{currentness,ig_live_classifier_disposition}',
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
    and version='1.0.5';

  if v_existing is not null and v_existing<>v_sha then
    raise exception 'HUMAN_DECISION_ROUTING_1_0_5_MANIFEST_CONFLICT';
  end if;

  insert into public.lf_capability_version_registry(
    capability_code,version,version_major,version_minor,version_patch,
    release_state,supersedes_version,manifest,manifest_sha256,
    source_ref,docs_ref,validator_ref,created_by_execution_id
  )
  values(
    'HUMAN_DECISION_ROUTING','1.0.5',1,0,5,
    'RELEASED','1.0.4',v_manifest,v_sha,
    'github://cristhianlujan/claude-persona-lf-patch/supabase/migrations/20261008090000_ig_live_pre_human_disposition_v1.sql',
    'github://cristhianlujan/claude-persona-lf-patch/docs/operations/HUMAN_DECISION_ROUTING_V1.md',
    'supabase://private/fn_lf_ig_human_decision_live_disposition_v1',
    'IG_LIVE_PRE_HUMAN_DISPOSITION_V1'
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
  'HUMAN-ESCALATION-IG-LATEST-RUN-NOT-CURRENT-001',
  'PROGRAMMING_GOVERNANCE',
  'Latest persisted IG run is not necessarily current authority for human escalation',
  'The first historical reconciliation selected the latest non-invalidated COMPLETED run. Live verification showed all six relevant latest runs returned false from fn_input_readiness_run_is_current. The resulting 14/8 split happened to match the live classifier, but the method was not sufficient currentness authority.',
  'Persisted run ordering was used as a proxy for live currentness even though IG already exposes a canonical live classifier over current source data and a stricter run-currentness function.',
  'HISTORICAL HUMAN PROPOSAL -> LIVE fn_input_governance_bootstrap_classify_v2 -> deterministic disposition. Persisted latest-run data is evidence/history only and never current authority by itself.',
  'Always compute pre-human IG disposition from the live canonical classifier and bind its classifier_sha256. Candidate-authority blockers route to action authorization, not semantic human decision. Missing/incomplete evidence stays internal remediation unless explicit positive owner-decision authority is present.',
  'Migration supersedes the latest-run proxy with private.fn_lf_ig_human_decision_live_disposition_v1 and keeps HUMAN_DECISION_ROUTING non-current.',
  'HIGH','ACTIVO',
  'capability://HUMAN_ESCALATION_ADMISSION@1.0.2',
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

update public.lf_error_knowledge
set descripcion='Historical IG HUMAN_DECISION_REQUIRED rows are preserved as history, but pre-human routing now reconciles them against the live canonical classifier rather than treating the latest persisted COMPLETED run as current authority.',
    prevencion='Use private.fn_lf_ig_human_decision_live_disposition_v1 for pre-human IG routing. Persisted latest-run reconciliation is historical evidence only. Never infer currentness from run ordering.',
    validacion='Superseded by HUMAN_ESCALATION_ADMISSION 1.0.2 live-classifier disposition after strict readback showed fn_input_readiness_run_is_current=false for all six previously selected latest runs. The 22-case result is re-proven directly from current canonical source classification.',
    source_ref='capability://HUMAN_ESCALATION_ADMISSION@1.0.2',
    updated_at=now()
where codigo='HUMAN-ESCALATION-IG-HISTORICAL-CURRENTNESS-001';

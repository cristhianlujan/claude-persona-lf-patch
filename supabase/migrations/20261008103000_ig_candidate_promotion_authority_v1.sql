-- IG CANDIDATE AUTHORITY REFINEMENT V1
-- A candidate object is not automatically "promotion only".
-- Before grouping a candidate as an action authorization gate, verify that the
-- semantic source decision is already owner-approved. Otherwise keep it in
-- internal evidence/authority remediation and do not ask a human prematurely.

create or replace function private.fn_lf_ig_candidate_promotion_authority_v1(
  p_pantalla_id integer,
  p_family_code text
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v_candidate_count integer:=0;
  v_missing_decision_count integer:=0;
  v_owner_approved_count integer:=0;
  v_promotion_authorized_count integer:=0;
  v_details jsonb:='[]'::jsonb;
begin
  if p_family_code<>'TRANSITIONS' then
    return jsonb_build_object(
      'schema_version','lf-ig-candidate-promotion-authority/v1',
      'handled',false,
      'reason','FAMILY_NOT_SUPPORTED'
    );
  end if;

  with screen_states as (
    select distinct pe.state_id
    from lf_ops.pantallas_estados pe
    where pe.pantalla_id=p_pantalla_id
  ),
  candidates as (
    select distinct
      et.transition_id,
      et.transition_code,
      et.status,
      et.source_decision_id,
      et.source_decision_number
    from lf_ops.estados_transiciones et
    where et.status='CANDIDATO'
      and (
        et.from_state_id in (select state_id from screen_states)
        or et.to_state_id in (select state_id from screen_states)
      )
  ),
  inspected as (
    select
      c.*,
      d.estado_original,
      d.estado_normalizado,
      d.raw_payload,
      (
        d.estado_original='APROBADO_POR_OWNER'
        or d.estado_normalizado='CANDIDATO_APROBADO_POR_OWNER'
      ) as owner_approved,
      coalesce((d.raw_payload->>'promotion_authorized')::boolean,false)
        as promotion_authorized,
      d.id_decision is null as decision_missing
    from candidates c
    left join public.lf_decisiones_gov d
      on (
        c.source_decision_id is not null
        and d.id_decision=c.source_decision_id
      )
      or (
        c.source_decision_id is null
        and c.source_decision_number is not null
        and d.decision_number=c.source_decision_number
      )
  )
  select
    count(*),
    count(*) filter(where decision_missing),
    count(*) filter(where owner_approved),
    count(*) filter(where promotion_authorized),
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'transition_id',transition_id,
          'transition_code',transition_code,
          'status',status,
          'source_decision_id',source_decision_id,
          'source_decision_number',source_decision_number,
          'decision_state_original',estado_original,
          'decision_state_normalized',estado_normalizado,
          'owner_approved',owner_approved,
          'promotion_authorized',promotion_authorized
        )
        order by transition_id
      ),
      '[]'::jsonb
    )
  into
    v_candidate_count,
    v_missing_decision_count,
    v_owner_approved_count,
    v_promotion_authorized_count,
    v_details
  from inspected;

  if v_candidate_count=0 then
    return jsonb_build_object(
      'schema_version','lf-ig-candidate-promotion-authority/v1',
      'handled',false,
      'reason','NO_CANDIDATE_TRANSITIONS'
    );
  end if;

  if v_missing_decision_count>0 then
    return jsonb_build_object(
      'schema_version','lf-ig-candidate-promotion-authority/v1',
      'handled',true,
      'state','INTERNAL_REMEDIATION',
      'code','CANDIDATE_SOURCE_DECISION_MISSING',
      'semantic_decision_required',false,
      'human_queue_allowed',false,
      'candidate_count',v_candidate_count,
      'missing_decision_count',v_missing_decision_count,
      'owner_approved_count',v_owner_approved_count,
      'promotion_authorized_count',v_promotion_authorized_count,
      'details',v_details
    );
  end if;

  if v_owner_approved_count<>v_candidate_count then
    return jsonb_build_object(
      'schema_version','lf-ig-candidate-promotion-authority/v1',
      'handled',true,
      'state','INTERNAL_REMEDIATION',
      'code','CANDIDATE_SEMANTIC_AUTHORITY_UNPROVEN',
      'semantic_decision_required',false,
      'human_queue_allowed',false,
      'candidate_count',v_candidate_count,
      'missing_decision_count',v_missing_decision_count,
      'owner_approved_count',v_owner_approved_count,
      'promotion_authorized_count',v_promotion_authorized_count,
      'details',v_details
    );
  end if;

  if v_promotion_authorized_count=v_candidate_count then
    return jsonb_build_object(
      'schema_version','lf-ig-candidate-promotion-authority/v1',
      'handled',true,
      'state','SAFE_CHANGE_ADMISSION_REQUIRED',
      'code','CANDIDATE_PROMOTION_ALREADY_AUTHORIZED_REQUIRES_SAFE_CHANGE',
      'action_code','PROMOTE_GOVERNED_CANDIDATE',
      'action_authorized',true,
      'semantic_decision_required',false,
      'human_queue_allowed',false,
      'candidate_count',v_candidate_count,
      'owner_approved_count',v_owner_approved_count,
      'promotion_authorized_count',v_promotion_authorized_count,
      'details',v_details
    );
  end if;

  return jsonb_build_object(
    'schema_version','lf-ig-candidate-promotion-authority/v1',
    'handled',true,
    'state','ACTION_AUTHORIZATION_GATE',
    'code','OWNER_APPROVED_SEMANTICS_PROMOTION_NOT_AUTHORIZED',
    'action_code','PROMOTE_GOVERNED_CANDIDATE',
    'action_authorized',false,
    'semantic_decision_required',false,
    'human_queue_allowed',false,
    'candidate_count',v_candidate_count,
    'owner_approved_count',v_owner_approved_count,
    'promotion_authorized_count',v_promotion_authorized_count,
    'details',v_details
  );
end
$function$;

revoke all on function private.fn_lf_ig_candidate_promotion_authority_v1(integer,text)
  from public,anon,authenticated;

do $patch_live_disposition$
declare
  v_def text;
  v_sha text;
  v_old text:=E'  if v_candidate_authority_count=v_blocker_count then\n    return jsonb_build_object(\n      ''schema_version'',''lf-ig-human-live-disposition/v1'',\n      ''state'',''ACTION_AUTHORIZATION_GATE'',\n      ''code'',''GOVERNED_CANDIDATE_PROMOTION_REQUIRED'',\n      ''proposal_id'',v_p.id,\n      ''source_run_id'',v_p.run_id,\n      ''pantalla_id'',v_source_run.pantalla_id,\n      ''family_code'',v_p.family_code,\n      ''old_gap_code'',v_p.gap_code,\n      ''action_code'',''PROMOTE_GOVERNED_CANDIDATE'',\n      ''action_authorized'',false,\n      ''semantic_decision_required'',false,\n      ''live_applicability'',v_live->>''applicability'',\n      ''live_story_ready_status'',v_live->>''story_ready_status'',\n      ''live_implementation_ready_status'',v_live->>''implementation_ready_status'',\n      ''live_qa_ready_status'',v_live->>''qa_ready_status'',\n      ''classifier_sha256'',v_live->>''classifier_sha256'',\n      ''live_blockers'',v_blockers,\n      ''human_queue_allowed'',false\n    );\n  end if;';
  v_new text:=E'  if v_candidate_authority_count=v_blocker_count then\n    v_candidate_disposition:=private.fn_lf_ig_candidate_promotion_authority_v1(\n      v_source_run.pantalla_id,v_p.family_code\n    );\n\n    if coalesce((v_candidate_disposition->>''handled'')::boolean,false) is not true then\n      return jsonb_build_object(\n        ''schema_version'',''lf-ig-human-live-disposition/v1'',\n        ''state'',''INTERNAL_REMEDIATION'',\n        ''code'',''CANDIDATE_AUTHORITY_NOT_PROVEN'',\n        ''proposal_id'',v_p.id,\n        ''source_run_id'',v_p.run_id,\n        ''pantalla_id'',v_source_run.pantalla_id,\n        ''family_code'',v_p.family_code,\n        ''old_gap_code'',v_p.gap_code,\n        ''semantic_decision_required'',false,\n        ''candidate_authority'',v_candidate_disposition,\n        ''classifier_sha256'',v_live->>''classifier_sha256'',\n        ''live_blockers'',v_blockers,\n        ''human_queue_allowed'',false\n      );\n    end if;\n\n    return jsonb_build_object(\n      ''schema_version'',''lf-ig-human-live-disposition/v1'',\n      ''state'',v_candidate_disposition->>''state'',\n      ''code'',v_candidate_disposition->>''code'',\n      ''proposal_id'',v_p.id,\n      ''source_run_id'',v_p.run_id,\n      ''pantalla_id'',v_source_run.pantalla_id,\n      ''family_code'',v_p.family_code,\n      ''old_gap_code'',v_p.gap_code,\n      ''action_code'',v_candidate_disposition->>''action_code'',\n      ''action_authorized'',coalesce((v_candidate_disposition->>''action_authorized'')::boolean,false),\n      ''semantic_decision_required'',false,\n      ''candidate_authority'',v_candidate_disposition,\n      ''live_applicability'',v_live->>''applicability'',\n      ''live_story_ready_status'',v_live->>''story_ready_status'',\n      ''live_implementation_ready_status'',v_live->>''implementation_ready_status'',\n      ''live_qa_ready_status'',v_live->>''qa_ready_status'',\n      ''classifier_sha256'',v_live->>''classifier_sha256'',\n      ''live_blockers'',v_blockers,\n      ''human_queue_allowed'',false\n    );\n  end if;';
begin
  select pg_get_functiondef(
           'private.fn_lf_ig_human_decision_live_disposition_v1(bigint)'::regprocedure
         ),
         encode(
           extensions.digest(
             convert_to(
               pg_get_functiondef(
                 'private.fn_lf_ig_human_decision_live_disposition_v1(bigint)'::regprocedure
               ),
               'UTF8'
             ),
             'sha256'
           ),
           'hex'
         )
    into v_def,v_sha;

  if v_sha<>'63d8e397bd5c11cd67be1449586c946c5a1710ccee59e83734109b7386f27a05' then
    raise exception 'IG_CANDIDATE_AUTHORITY_LIVE_DISPOSITION_BASELINE_SHA_MISMATCH:%',v_sha;
  end if;

  if position('v_candidate_authority_count integer:=0;' in v_def)=0
     or position(v_old in v_def)=0 then
    raise exception 'IG_CANDIDATE_AUTHORITY_LIVE_DISPOSITION_ANCHOR_DRIFT';
  end if;

  v_def:=replace(
    v_def,
    '  v_candidate_authority_count integer:=0;',
    E'  v_candidate_authority_count integer:=0;\n  v_candidate_disposition jsonb;'
  );

  v_def:=replace(v_def,v_old,v_new);

  execute v_def;
end
$patch_live_disposition$;

do $capability_version$
declare
  v_manifest jsonb;
  v_sha text;
  v_existing text;
  v_promote jsonb;
begin
  select manifest
    into v_manifest
  from public.lf_capability_version_registry
  where capability_code='HUMAN_ESCALATION_ADMISSION'
    and version='1.0.2'
    and release_state='RELEASED';

  if v_manifest is null then
    raise exception 'HUMAN_ESCALATION_ADMISSION_1_0_2_REQUIRED';
  end if;

  v_manifest:=jsonb_set(v_manifest,'{version}','"1.0.3"'::jsonb,true);
  v_manifest:=jsonb_set(
    v_manifest,
    '{usage,ig_candidate_promotion_authority}',
    '"private.fn_lf_ig_candidate_promotion_authority_v1"'::jsonb,
    true
  );
  v_manifest:=jsonb_set(
    v_manifest,
    '{contract,candidate_promotion_requires_semantic_authority_proof}',
    'true'::jsonb,
    true
  );
  v_manifest:=jsonb_set(
    v_manifest,
    '{compatibility,candidate_status_alone_is_promotion_authority}',
    'false'::jsonb,
    true
  );
  v_manifest:=jsonb_set(
    v_manifest,
    '{currentness,candidate_source_decision_authority_check}',
    'true'::jsonb,
    true
  );

  v_sha:=encode(
    extensions.digest(convert_to(v_manifest::text,'UTF8'),'sha256'),
    'hex'
  );

  select manifest_sha256 into v_existing
  from public.lf_capability_version_registry
  where capability_code='HUMAN_ESCALATION_ADMISSION'
    and version='1.0.3';

  if v_existing is not null and v_existing<>v_sha then
    raise exception 'HUMAN_ESCALATION_ADMISSION_1_0_3_MANIFEST_CONFLICT';
  end if;

  insert into public.lf_capability_version_registry(
    capability_code,version,version_major,version_minor,version_patch,
    release_state,supersedes_version,manifest,manifest_sha256,
    source_ref,docs_ref,validator_ref,created_by_execution_id
  )
  values(
    'HUMAN_ESCALATION_ADMISSION','1.0.3',1,0,3,
    'RELEASED','1.0.2',v_manifest,v_sha,
    'github://cristhianlujan/claude-persona-lf-patch/supabase/migrations/20261008103000_ig_candidate_promotion_authority_v1.sql',
    'github://cristhianlujan/claude-persona-lf-patch/docs/operations/HUMAN_DECISION_ROUTING_V1.md',
    'supabase://private/fn_lf_ig_candidate_promotion_authority_v1',
    'IG_CANDIDATE_PROMOTION_AUTHORITY_V1'
  )
  on conflict(capability_code,version) do nothing;

  v_promote:=public.fn_lf_capability_promote_v1(
    'HUMAN_ESCALATION_ADMISSION','1.0.3',null,
    'IG_CANDIDATE_PROMOTION_AUTHORITY_V1',
    'Refines candidate promotion gates by proving owner-approved semantic authority before action-only classification.'
  );

  if coalesce((v_promote->>'ready')::boolean,false) is not true then
    raise exception 'HUMAN_ESCALATION_ADMISSION_1_0_3_PROMOTION_FAILED:%',v_promote::text;
  end if;
end
$capability_version$;

do $routing_version$
declare
  v_manifest jsonb;
  v_sha text;
  v_existing text;
  v_hea_version text;
  v_hea_sha text;
begin
  select manifest into v_manifest
  from public.lf_capability_version_registry
  where capability_code='HUMAN_DECISION_ROUTING'
    and version='1.0.5'
    and release_state='RELEASED';

  if v_manifest is null then
    raise exception 'HUMAN_DECISION_ROUTING_1_0_5_REQUIRED';
  end if;

  select version,manifest_sha256
    into v_hea_version,v_hea_sha
  from public.lf_capability_current
  where capability_code='HUMAN_ESCALATION_ADMISSION';

  v_manifest:=jsonb_set(v_manifest,'{version}','"1.0.6"'::jsonb,true);
  v_manifest:=jsonb_set(
    v_manifest,
    '{dependencies,HUMAN_ESCALATION_ADMISSION}',
    jsonb_build_object('version',v_hea_version,'manifest_sha256',v_hea_sha),
    true
  );
  v_manifest:=jsonb_set(
    v_manifest,
    '{currentness,ig_candidate_semantic_authority_refinement}',
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

  select manifest_sha256 into v_existing
  from public.lf_capability_version_registry
  where capability_code='HUMAN_DECISION_ROUTING'
    and version='1.0.6';

  if v_existing is not null and v_existing<>v_sha then
    raise exception 'HUMAN_DECISION_ROUTING_1_0_6_MANIFEST_CONFLICT';
  end if;

  insert into public.lf_capability_version_registry(
    capability_code,version,version_major,version_minor,version_patch,
    release_state,supersedes_version,manifest,manifest_sha256,
    source_ref,docs_ref,validator_ref,created_by_execution_id
  )
  values(
    'HUMAN_DECISION_ROUTING','1.0.6',1,0,6,
    'RELEASED','1.0.5',v_manifest,v_sha,
    'github://cristhianlujan/claude-persona-lf-patch/supabase/migrations/20261008103000_ig_candidate_promotion_authority_v1.sql',
    'github://cristhianlujan/claude-persona-lf-patch/docs/operations/HUMAN_DECISION_ROUTING_V1.md',
    'supabase://private/fn_lf_ig_candidate_promotion_authority_v1',
    'IG_CANDIDATE_PROMOTION_AUTHORITY_V1'
  )
  on conflict(capability_code,version) do nothing;

  if exists(
    select 1 from public.lf_capability_current
    where capability_code='HUMAN_DECISION_ROUTING'
  ) then
    raise exception 'HUMAN_DECISION_ROUTING_CURRENT_POINTER_PREMATURE';
  end if;
end
$routing_version$;

insert into public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
  severidad,estado,source_ref,updated_at
)
values(
  'HUMAN-ESCALATION-CANDIDATE-PROMOTION-AUTHORITY-001',
  'PROGRAMMING_GOVERNANCE',
  'Candidate state alone does not prove that only promotion authorization remains',
  'A candidate transition can be implementation-ready in shape while its semantic source is still only candidate-controlled. Treating every CANDIDATE_AUTHORITY blocker as promotion-only can hide a missing semantic authority decision.',
  'The first candidate gate looked only at candidate object status and blocking stage, not the authority state of the source decision that created the candidate.',
  'CANDIDATE OBJECT -> SOURCE DECISION READBACK -> OWNER-APPROVED SEMANTICS? -> if yes and promotion not authorized: ACTION_AUTHORIZATION_GATE; if no: INTERNAL_REMEDIATION; if promotion already authorized: SAFE_CHANGE_ADMISSION_REQUIRED.',
  'Before asking for candidate promotion, prove every exact candidate object has a governed source decision and that its semantics are already owner-approved. Candidate-controlled or missing source decisions remain nonhuman internal remediation until evidence is exhausted. Never infer semantic approval from CANDIDATO status.',
  'Migration adds generic transition candidate source-authority readback and refines live IG disposition without promoting any candidate or activating production.',
  'HIGH','ACTIVO',
  'capability://HUMAN_ESCALATION_ADMISSION@1.0.3',
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

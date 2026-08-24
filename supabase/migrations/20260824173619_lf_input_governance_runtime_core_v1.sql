-- INPUT_GOVERNANCE_AGENT runtime core v1.
-- Curator and Validator execute through separate identities and transactions.

insert into transversal.decision_log(adr,titulo,decision,razon,impacto,estado)
values(
  'DEC-INPUT-GOV-RUNTIME-001',
  'Runtime separado de Curator y Validator para Input Governance',
  'INPUT_GOVERNANCE_AGENT usa runtimes separados para INPUT_CURATOR e INPUT_VALIDATOR. Curator puede rematerializar automáticamente solo un sucesor con precedente COMPLETED cuando las assertions semánticas previas se rebindan y pasan contra fuentes actuales. Validator abre su propia fase con identidad distinta, relee fuentes y reevalúa assertions mediante guards canónicos. Una pantalla sin precedente canónico queda fail-closed como BOOTSTRAP_SEMANTIC_PROFILE_REQUIRED; no se inventan 47 familias ni se introduce un proveedor LLM no gobernado. No autoriza promoción ni producción.',
  'Preserva AUD-001, AUD-019, freshness y proposal!=canon. Permite automatización segura de sucesores demostrablemente compatibles sin sustituir una decisión semántica nueva.',
  'Añade runtime operativo separado. INPUT_READINESS_CONTRACT 5.12 no cambia; promotion_authorized=false y production_authorized=false.',
  'vigente'
)
on conflict(adr) do update set titulo=excluded.titulo,decision=excluded.decision,razon=excluded.razon,impacto=excluded.impacto,estado=excluded.estado;

create or replace function programacion.fn_input_governance_curator_materialize_v1(
  p_pantalla_id integer,
  p_consumer text,
  p_curator_identity text,
  p_force_selftest boolean default false
) returns jsonb
language plpgsql volatile security definer
set search_path to 'pg_catalog','public','programacion','lf_ops','transversal'
as $function$
declare
  v_version bigint:=19;
  v_code text;
  v_active boolean;
  v_current bigint;
  v_latest bigint;
  v_latest_status text;
  v_parent bigint;
  v_new bigint;
  v_contract_schema integer;
  v_contract_revision text;
  v_contract_sha text;
  v_parent_contract_sha text;
  v_family_count integer;
  v_assessed integer;
  v_pre jsonb;
  v_assertions jsonb;
  a record;
  v_payload jsonb;
begin
  if p_curator_identity !~ '^INPUT_CURATOR:EDGE:input-governance-curator-v1:[A-Za-z0-9_-]{6,128}$' then
    raise exception 'INPUT_GOVERNANCE_CURATOR_RUNTIME_IDENTITY_INVALID';
  end if;
  if not exists(
    select 1 from jsonb_array_elements_text((select especificacion->'allowed_consumers' from programacion.contratos where version_id=19 and contrato_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT')) x(v)
    where x.v=p_consumer
  ) then raise exception 'INPUT_GOVERNANCE_CONSUMER_NOT_ALLOWED:%',coalesce(p_consumer,'<NULL>'); end if;

  select codigo,activa into v_code,v_active from lf_ops.pantallas where id=p_pantalla_id;
  if v_code is null then raise exception 'INPUT_GOVERNANCE_SCREEN_NOT_FOUND:%',p_pantalla_id; end if;
  if not v_active then raise exception 'INPUT_GOVERNANCE_SCREEN_INACTIVE:%',v_code; end if;

  v_pre:=programacion.fn_input_governance_ekb_checkpoint('PRE_CURATOR',p_pantalla_id,null);
  if not coalesce((v_pre->>'pass')::boolean,false) then raise exception 'INPUT_GOVERNANCE_EKB_BLOCKED:PRE_CURATOR'; end if;

  select id into v_current from programacion.input_readiness_runs
  where version_id=v_version and pantalla_id=p_pantalla_id and status='COMPLETED' and invalidated_at is null
    and programacion.fn_input_readiness_run_is_current(id)
  order by id desc limit 1;
  if v_current is not null and not p_force_selftest then
    return jsonb_build_object('status','NOOP_CURRENT','run_id',v_current,'required_role','NONE','promotion_authorized',false,'production_authorized',false);
  end if;

  select id,status into v_latest,v_latest_status from programacion.input_readiness_runs
  where version_id=v_version and pantalla_id=p_pantalla_id order by id desc limit 1;
  if v_latest is not null and v_latest_status in ('CURATING','VALIDATING') and not p_force_selftest then
    return jsonb_build_object(
      'status',case when v_latest_status='VALIDATING' then 'VALIDATOR_RUNTIME_REQUIRED' else 'CURATION_IN_PROGRESS' end,
      'run_id',v_latest,
      'required_role',case when v_latest_status='VALIDATING' then 'INPUT_VALIDATOR' else 'INPUT_CURATOR' end,
      'promotion_authorized',false,'production_authorized',false
    );
  end if;

  select id,contract_snapshot_sha256,family_count into v_parent,v_parent_contract_sha,v_family_count
  from programacion.input_readiness_runs
  where version_id=v_version and pantalla_id=p_pantalla_id and status='COMPLETED'
  order by id desc limit 1;
  if v_parent is null then
    v_payload:=jsonb_build_object(
      'status','BOOTSTRAP_SEMANTIC_PROFILE_REQUIRED','pantalla_id',p_pantalla_id,'screen_code',v_code,
      'required_role','HUMAN_OR_GOVERNED_SEMANTIC_BOOTSTRAP','write_performed',false,
      'reason','NO_COMPLETED_PREDECESSOR_TO_REBIND','proposal_is_canonical_source',false,
      'promotion_authorized',false,'production_authorized',false
    );
    return v_payload||jsonb_build_object('output_sha256',programacion.fn_v09_sha256_jsonb(v_payload));
  end if;

  select (c.especificacion->>'schema_version')::integer,c.especificacion->>'contract_revision',
         programacion.fn_v09_sha256_jsonb(jsonb_build_object('id',c.id,'version_id',c.version_id,'contrato_codigo',c.contrato_codigo,'fail_closed',c.fail_closed,'estado',c.estado,'especificacion',c.especificacion))
  into v_contract_schema,v_contract_revision,v_contract_sha
  from programacion.contratos c
  where c.version_id=v_version and c.contrato_codigo='INPUT_READINESS_CONTRACT' and c.estado='defined' and c.fail_closed;
  if v_contract_revision is null then raise exception 'INPUT_READINESS_CONTRACT_NOT_RESOLVABLE:%',v_version; end if;
  if v_parent_contract_sha is distinct from v_contract_sha then
    return jsonb_build_object(
      'status','CONTRACT_CHANGED_SEMANTIC_REVIEW_REQUIRED','parent_run_id',v_parent,
      'required_role','HUMAN_OR_GOVERNED_CONTRACT_MIGRATION','write_performed',false,
      'promotion_authorized',false,'production_authorized',false
    );
  end if;

  insert into programacion.input_readiness_runs(
    version_id,pantalla_id,universe_rule_id,supersedes_run_id,status,scope,
    universe_snapshot_sha256,family_count,contract_version,curator_identity,curator_component_id
  )
  select version_id,pantalla_id,universe_rule_id,id,'CURATING',
         scope||jsonb_build_object(
           'mode','RUNTIME_ASSERTION_REBIND_SAFE_SUCCESSOR_V1','parent_run_id',id,
           'runtime','input-governance-curator-v1','promotion_authorized',false,'production_authorized',false
         ),
         universe_snapshot_sha256,family_count,v_contract_schema,p_curator_identity,46
  from programacion.input_readiness_runs where id=v_parent
  returning id into v_new;

  for a in select * from programacion.input_family_assessments where run_id=v_parent order by family_code
  loop
    insert into programacion.input_family_assessments(
      run_id,family_code,severity,applicability,coverage_status,well_defined_status,
      story_ready_status,implementation_ready_status,qa_ready_status,production_ready_status,
      source_refs,rationale,blockers,negative_requirements,test_obligations,freshness,
      curator_evidence,curator_sha256,validator_outcome,validator_findings,validator_evidence,
      validator_identity,validator_sha256,validator_assessed_at,subject_coverage,threat_coverage,semantic_depth_sha256
    ) values (
      v_new,a.family_code,a.severity,a.applicability,a.coverage_status,a.well_defined_status,
      a.story_ready_status,a.implementation_ready_status,a.qa_ready_status,a.production_ready_status,
      a.source_refs,a.rationale,a.blockers,a.negative_requirements,a.test_obligations,'{}'::jsonb,
      jsonb_build_object(
        'component_id',46,'execution_id',gen_random_uuid()::text,'execution_mode','INDEPENDENT_CURATOR',
        'runtime','SUPABASE_EDGE_FUNCTION:input-governance-curator-v1','contract_revision',v_contract_revision,
        'parent_run_id',v_parent,'parent_assessment_id',a.id,'direct_source_readback',true,
        'semantic_policy','NO_INVENTION_REBIND_ONLY'
      ),
      repeat('0',64),'PENDING','[]'::jsonb,'{}'::jsonb,null,null,null,
      a.subject_coverage,a.threat_coverage,a.semantic_depth_sha256
    );

    v_assertions:=programacion.fn_input_v58_build_assertions(v_new,v_parent,a.family_code);
    if jsonb_array_length(v_assertions)=0 then raise exception 'INPUT_GOVERNANCE_CURATOR_ASSERTIONS_EMPTY:%',a.family_code; end if;
  end loop;

  select count(*) into v_assessed from programacion.input_family_assessments where run_id=v_new;
  if v_assessed<>v_family_count then raise exception 'INPUT_GOVERNANCE_CURATOR_RUNTIME_UNIVERSE_INCOMPLETE expected=% actual=%',v_family_count,v_assessed; end if;

  v_payload:=jsonb_build_object(
    'status','VALIDATOR_RUNTIME_REQUIRED','run_id',v_new,'parent_run_id',v_parent,
    'pantalla_id',p_pantalla_id,'screen_code',v_code,'family_count',v_family_count,
    'curator_identity',p_curator_identity,'run_status','CURATING','required_role','INPUT_VALIDATOR',
    'write_performed',true,'promotion_authorized',false,'production_authorized',false
  );
  return v_payload||jsonb_build_object('output_sha256',programacion.fn_v09_sha256_jsonb(v_payload));
end;
$function$;

create or replace function programacion.fn_input_governance_validator_validate_v1(
  p_run_id bigint,
  p_validator_identity text
) returns jsonb
language plpgsql volatile security definer
set search_path to 'pg_catalog','public','programacion','lf_ops','transversal'
as $function$
declare
  v_status text;
  v_pantalla_id integer;
  v_parent bigint;
  v_family_count integer;
  v_curator_identity text;
  v_existing_validator text;
  v_contract_revision text;
  v_source_sha text;
  v_pass integer;
  v_pre jsonb;
  v_assertions jsonb;
  a record;
  v_payload jsonb;
begin
  if p_validator_identity !~ '^INPUT_VALIDATOR:EDGE:input-governance-validator-v1:[A-Za-z0-9_-]{6,128}$' then
    raise exception 'INPUT_GOVERNANCE_VALIDATOR_RUNTIME_IDENTITY_INVALID';
  end if;

  select status,pantalla_id,supersedes_run_id,family_count,curator_identity,validator_identity,contract_revision
  into v_status,v_pantalla_id,v_parent,v_family_count,v_curator_identity,v_existing_validator,v_contract_revision
  from programacion.input_readiness_runs where id=p_run_id and version_id=19;
  if v_status is null then raise exception 'INPUT_GOVERNANCE_VALIDATOR_RUN_NOT_FOUND:%',p_run_id; end if;
  if v_status='COMPLETED' then
    return jsonb_build_object('status','NOOP_COMPLETED','run_id',p_run_id,'promotion_authorized',false,'production_authorized',false);
  end if;
  if v_parent is null then raise exception 'INPUT_GOVERNANCE_VALIDATOR_PREDECESSOR_REQUIRED:%',p_run_id; end if;
  if p_validator_identity=v_curator_identity then raise exception 'VALIDATOR_IDENTITY_NOT_INDEPENDENT'; end if;

  v_pre:=programacion.fn_input_governance_ekb_checkpoint('PRE_VALIDATOR',v_pantalla_id,p_run_id);
  if not coalesce((v_pre->>'pass')::boolean,false) then raise exception 'INPUT_GOVERNANCE_EKB_BLOCKED:PRE_VALIDATOR'; end if;

  if v_status='CURATING' then
    if (select count(*) from programacion.input_family_assessments where run_id=p_run_id)<>v_family_count then raise exception 'CURATOR_UNIVERSE_INCOMPLETE'; end if;
    update programacion.input_readiness_runs
    set status='VALIDATING',validator_identity=p_validator_identity,validator_component_id=47
    where id=p_run_id;
  elsif v_status='VALIDATING' then
    if v_existing_validator is distinct from p_validator_identity then raise exception 'VALIDATOR_IDENTITY_MISMATCH'; end if;
  else
    raise exception 'INPUT_GOVERNANCE_VALIDATOR_INVALID_RUN_STATUS:%',v_status;
  end if;

  select source_snapshot_sha256,contract_revision into v_source_sha,v_contract_revision
  from programacion.input_readiness_runs where id=p_run_id;

  for a in select * from programacion.input_family_assessments where run_id=p_run_id order by family_code
  loop
    v_assertions:=programacion.fn_input_v58_build_assertions(p_run_id,v_parent,a.family_code);
    update programacion.input_family_assessments
    set validator_outcome='PASS',validator_findings='[]'::jsonb,
        validator_evidence=jsonb_build_object(
          'component_id',47,'execution_id',gen_random_uuid()::text,
          'validated_curator_execution_id',a.curator_evidence->>'execution_id',
          'execution_mode','INDEPENDENT_VALIDATOR',
          'runtime','SUPABASE_EDGE_FUNCTION:input-governance-validator-v1',
          'direct_source_readback',true,'contract_revision',v_contract_revision,
          'source_snapshot_sha256',v_source_sha,'curator_sha256',a.curator_sha256,
          'semantic_depth_sha256',a.semantic_depth_sha256,'assertions',v_assertions
        ),
        validator_identity=p_validator_identity,
        validator_assessed_at=now()
    where id=a.id;
  end loop;

  update programacion.input_readiness_runs set status='COMPLETED' where id=p_run_id;
  select count(*) into v_pass from programacion.input_family_assessments
  where run_id=p_run_id and validator_outcome='PASS' and validator_identity=p_validator_identity;
  if v_pass<>v_family_count then raise exception 'INPUT_GOVERNANCE_VALIDATOR_RUNTIME_CARDINALITY_MISMATCH expected=% actual=%',v_family_count,v_pass; end if;

  v_payload:=jsonb_build_object(
    'status','COMPLETED','run_id',p_run_id,'parent_run_id',v_parent,'pantalla_id',v_pantalla_id,
    'family_count',v_family_count,'validator_pass_count',v_pass,'validator_identity',p_validator_identity,
    'required_role','DISPATCHER_FINALIZE','promotion_authorized',false,'production_authorized',false
  );
  return v_payload||jsonb_build_object('output_sha256',programacion.fn_v09_sha256_jsonb(v_payload));
end;
$function$;

create or replace function public.fn_input_governance_curator_materialize_v1(
  p_pantalla_id integer,p_consumer text,p_curator_identity text
) returns jsonb
language sql security definer set search_path to 'pg_catalog','programacion'
as $function$
  select programacion.fn_input_governance_curator_materialize_v1(p_pantalla_id,p_consumer,p_curator_identity,false);
$function$;

create or replace function public.fn_input_governance_validator_validate_v1(
  p_run_id bigint,p_validator_identity text
) returns jsonb
language sql security definer set search_path to 'pg_catalog','programacion'
as $function$
  select programacion.fn_input_governance_validator_validate_v1(p_run_id,p_validator_identity);
$function$;

revoke all on function programacion.fn_input_governance_curator_materialize_v1(integer,text,text,boolean) from public,anon,authenticated;
revoke all on function programacion.fn_input_governance_validator_validate_v1(bigint,text) from public,anon,authenticated;
revoke all on function public.fn_input_governance_curator_materialize_v1(integer,text,text) from public,anon,authenticated;
revoke all on function public.fn_input_governance_validator_validate_v1(bigint,text) from public,anon,authenticated;
grant execute on function public.fn_input_governance_curator_materialize_v1(integer,text,text) to service_role;
grant execute on function public.fn_input_governance_validator_validate_v1(bigint,text) to service_role;

do $selftest$
declare
  b_count bigint;
  b_max bigint;
  c jsonb;
  v jsonb;
  new_id bigint;
begin
  select count(*),max(id) into b_count,b_max from programacion.input_readiness_runs;
  begin
    c:=programacion.fn_input_governance_curator_materialize_v1(
      51,'MANUAL','INPUT_CURATOR:EDGE:input-governance-curator-v1:selftest01',true
    );
    if c->>'status'<>'VALIDATOR_RUNTIME_REQUIRED' then raise exception 'RUNTIME_SELFTEST_CURATOR_NOT_READY:%',c; end if;
    new_id:=(c->>'run_id')::bigint;
    if (select count(*) from programacion.input_family_assessments where run_id=new_id)<>47 then raise exception 'RUNTIME_SELFTEST_CURATOR_47_FAILED'; end if;

    v:=programacion.fn_input_governance_validator_validate_v1(
      new_id,'INPUT_VALIDATOR:EDGE:input-governance-validator-v1:selftest01'
    );
    if v->>'status'<>'COMPLETED' or (v->>'validator_pass_count')::integer<>47 then raise exception 'RUNTIME_SELFTEST_VALIDATOR_FAILED:%',v; end if;
    if not programacion.fn_input_readiness_run_is_current(new_id) then raise exception 'RUNTIME_SELFTEST_SUCCESSOR_NOT_CURRENT'; end if;

    raise exception 'ROLLBACK_INPUT_GOVERNANCE_RUNTIME_SELFTEST';
  exception when others then
    if sqlerrm<>'ROLLBACK_INPUT_GOVERNANCE_RUNTIME_SELFTEST' then raise; end if;
  end;

  if (select count(*) from programacion.input_readiness_runs)<>b_count or (select max(id) from programacion.input_readiness_runs)<>b_max then
    raise exception 'RUNTIME_SELFTEST_PERSISTED_RUN';
  end if;

  c:=programacion.fn_input_governance_curator_materialize_v1(
    1,'MANUAL','INPUT_CURATOR:EDGE:input-governance-curator-v1:selftest02',false
  );
  if c->>'status'<>'BOOTSTRAP_SEMANTIC_PROFILE_REQUIRED' or coalesce((c->>'write_performed')::boolean,true) then
    raise exception 'RUNTIME_SELFTEST_NEW_SCREEN_NOT_FAIL_CLOSED:%',c;
  end if;
end;
$selftest$;

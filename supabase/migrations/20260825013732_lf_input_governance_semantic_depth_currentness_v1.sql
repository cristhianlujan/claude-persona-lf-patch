create or replace function programacion.fn_input_readiness_run_is_current(p_run_id bigint)
returns boolean
language plpgsql
security definer
set search_path to 'pg_catalog','programacion'
as $function$
declare
  v_run record;
  v_current_manifest jsonb;
  v_current_sha text;
  v_contract_schema integer;
  v_contract_revision text;
  v_contract_payload jsonb;
  v_contract_sha text;
  v_has_terminal_successor boolean;
  v_analysis_revision text;
  v_policy_revision text;
  v_pantalla_id integer;
  v_stored_subject jsonb;
  v_stored_threat jsonb;
  v_expected_subject jsonb;
  v_expected_threat jsonb;
begin
  select r.status,r.version_id,r.pantalla_id,r.contract_version,r.contract_revision,r.contract_snapshot_sha256,
         r.source_manifest,r.source_snapshot_sha256,r.invalidated_at,r.scope
  into v_run
  from programacion.input_readiness_runs r
  where r.id=p_run_id;

  if not found then return false; end if;
  if v_run.status<>'COMPLETED' or v_run.source_snapshot_sha256 is null or v_run.invalidated_at is not null then return false; end if;
  v_pantalla_id:=v_run.pantalla_id;

  select (c.especificacion->>'schema_version')::integer,
         c.especificacion->>'contract_revision',
         jsonb_build_object('id',c.id,'version_id',c.version_id,'contrato_codigo',c.contrato_codigo,
                            'fail_closed',c.fail_closed,'estado',c.estado,'especificacion',c.especificacion)
  into v_contract_schema,v_contract_revision,v_contract_payload
  from programacion.contratos c
  where c.version_id=v_run.version_id and c.contrato_codigo='INPUT_READINESS_CONTRACT';

  if v_contract_schema is null or v_contract_revision is null then return false; end if;
  v_contract_sha:=programacion.fn_v09_sha256_jsonb(v_contract_payload);
  if v_run.contract_version<>v_contract_schema
     or v_run.contract_revision is distinct from v_contract_revision
     or v_run.contract_snapshot_sha256 is distinct from v_contract_sha then
    return false;
  end if;

  if coalesce(v_run.scope->>'mode','') in ('GOVERNED_CANONICAL_BOOTSTRAP_V1','RUNTIME_GOVERNED_RECURATION_V2') then
    select especificacion->>'analysis_revision',especificacion->'remediation_loop'->>'policy_revision'
    into v_analysis_revision,v_policy_revision
    from programacion.contratos
    where version_id=v_run.version_id
      and contrato_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT'
      and estado='defined'
      and fail_closed;
    if v_analysis_revision is null or v_run.scope->>'analysis_revision' is distinct from v_analysis_revision then return false; end if;
    if v_policy_revision is not null and v_run.scope->>'remediation_policy_revision' is distinct from v_policy_revision then return false; end if;
  end if;

  select a.subject_coverage
  into v_stored_subject
  from programacion.input_family_assessments a
  where a.run_id=p_run_id and a.family_code='DESIGN_SYSTEM';
  if found then
    v_expected_subject:=programacion.fn_input_subject_depth_expected(v_pantalla_id,'DESIGN_SYSTEM');
    if v_stored_subject is distinct from v_expected_subject then return false; end if;
  end if;

  select a.subject_coverage,a.threat_coverage
  into v_stored_subject,v_stored_threat
  from programacion.input_family_assessments a
  where a.run_id=p_run_id and a.family_code='SECURITY';
  if found then
    v_expected_subject:=programacion.fn_input_subject_depth_expected(v_pantalla_id,'SECURITY');
    v_expected_threat:=programacion.fn_input_security_threat_expected(v_pantalla_id);
    if v_stored_subject is distinct from v_expected_subject or v_stored_threat is distinct from v_expected_threat then return false; end if;
  end if;

  select exists(
    select 1 from programacion.input_readiness_runs n
    where n.supersedes_run_id=p_run_id and n.status in ('COMPLETED','BLOCKED')
  ) into v_has_terminal_successor;
  if v_has_terminal_successor then return false; end if;

  v_current_manifest:=programacion.fn_input_build_source_manifest(p_run_id);
  v_current_sha:=programacion.fn_v09_sha256_jsonb(v_current_manifest);
  return v_current_sha=v_run.source_snapshot_sha256 and v_current_manifest=v_run.source_manifest;
end;
$function$;
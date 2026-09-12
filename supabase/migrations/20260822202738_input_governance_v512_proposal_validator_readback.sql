-- V5.12 proposal validator must independently re-resolve proposal sources and reject stale snapshots.
create or replace function programacion.fn_guard_input_gap_proposal_update_v512()
returns trigger
language plpgsql
security definer
set search_path='pg_catalog','programacion'
as $function$
declare
  v_run record;
  v_payload jsonb;
  v_ref jsonb;
  v_observed jsonb;
  v_readbacks jsonb := '[]'::jsonb;
  v_current_manifest jsonb;
  v_current_sha text;
begin
  if new.run_id is distinct from old.run_id or new.assessment_id is distinct from old.assessment_id or new.family_code is distinct from old.family_code or new.gap_code is distinct from old.gap_code or new.proposal_kind is distinct from old.proposal_kind or new.proposed_payload is distinct from old.proposed_payload or new.canonical_target is distinct from old.canonical_target or new.source_refs is distinct from old.source_refs or new.evidence_refs is distinct from old.evidence_refs or new.confidence is distinct from old.confidence or new.stage_impact is distinct from old.stage_impact or new.contradictions_checked is distinct from old.contradictions_checked or new.curator_identity is distinct from old.curator_identity or new.curator_execution_id is distinct from old.curator_execution_id or new.curator_sha256 is distinct from old.curator_sha256 or new.created_at is distinct from old.created_at then
    raise exception 'V512_PROPOSAL_CURATOR_FIELDS_IMMUTABLE:%',old.id;
  end if;
  if old.validator_outcome<>'PENDING' then raise exception 'V512_PROPOSAL_VALIDATOR_RECEIPT_IMMUTABLE:%',old.id; end if;
  if new.validator_outcome='PENDING' then raise exception 'V512_PROPOSAL_VALIDATION_MUST_BE_TERMINAL:%',old.id; end if;
  select * into v_run from programacion.input_readiness_runs where id=old.run_id;
  if v_run.status<>'VALIDATING' then raise exception 'V512_PROPOSAL_VALIDATOR_REQUIRES_VALIDATING_RUN:%',old.run_id; end if;
  if new.validator_identity is null or new.validator_identity=v_run.curator_identity or new.validator_identity is distinct from v_run.validator_identity then
    raise exception 'V512_PROPOSAL_VALIDATOR_NOT_INDEPENDENT:%',old.id;
  end if;
  if new.validator_evidence='{}'::jsonb then raise exception 'V512_PROPOSAL_VALIDATOR_EVIDENCE_REQUIRED:%',old.id; end if;
  if coalesce((new.validator_evidence->>'direct_source_readback')::boolean,false) is not true then raise exception 'V512_PROPOSAL_DIRECT_SOURCE_READBACK_REQUIRED:%',old.id; end if;
  if new.validator_evidence->>'source_snapshot_sha256' is distinct from v_run.source_snapshot_sha256 then raise exception 'V512_PROPOSAL_SOURCE_SNAPSHOT_MISMATCH:%',old.id; end if;

  v_current_manifest:=programacion.fn_input_build_source_manifest(old.run_id);
  v_current_sha:=programacion.fn_v09_sha256_jsonb(v_current_manifest);
  if v_current_sha is distinct from v_run.source_snapshot_sha256 or v_current_manifest is distinct from v_run.source_manifest then
    raise exception 'V512_PROPOSAL_SOURCE_SNAPSHOT_STALE:%',old.id;
  end if;

  for v_ref in select value from jsonb_array_elements(old.source_refs)
  loop
    if coalesce(v_ref->>'kind','')='INPUT_GAP_PROPOSAL' then raise exception 'V512_PROPOSAL_CANNOT_VALIDATE_FROM_PROPOSAL_SOURCE:%',old.id; end if;
    v_observed:=programacion.fn_input_resolve_source_ref(v_ref,v_run.pantalla_id,v_run.version_id);
    v_readbacks:=v_readbacks || jsonb_build_array(jsonb_build_object(
      'source_ref',v_ref,
      'source_observed_sha256',programacion.fn_v09_sha256_jsonb(v_observed)
    ));
  end loop;
  if new.validator_evidence->'source_readbacks' is distinct from v_readbacks then
    raise exception 'V512_PROPOSAL_SOURCE_READBACK_DIGEST_MISMATCH:%',old.id;
  end if;

  if new.validator_outcome='PASS' and new.status not in ('VALIDATED','HUMAN_DECISION_REQUIRED') then raise exception 'V512_PROPOSAL_PASS_STATUS_INVALID:%',old.id; end if;
  if new.validator_outcome='FAIL' and new.status<>'REJECTED' then raise exception 'V512_PROPOSAL_FAIL_STATUS_INVALID:%',old.id; end if;
  new.validated_at:=coalesce(new.validated_at,now());
  v_payload:=jsonb_build_object('curator_sha256',old.curator_sha256,'validator_identity',new.validator_identity,'validator_outcome',new.validator_outcome,'validator_evidence',new.validator_evidence,'status',new.status,'validated_at',new.validated_at);
  new.validator_sha256:=programacion.fn_v09_sha256_jsonb(v_payload);
  return new;
end;
$function$;
revoke all on function programacion.fn_guard_input_gap_proposal_update_v512() from public;
grant execute on function programacion.fn_guard_input_gap_proposal_update_v512() to postgres;

update programacion.contratos
set especificacion=jsonb_set(especificacion,'{proposal_contract}',coalesce(especificacion->'proposal_contract','{}'::jsonb)||'{"validator_re_resolves_source_refs":true,"validator_source_readback_digests_required":true,"run_snapshot_currentness_required":true}'::jsonb,true)
where version_id=19 and contrato_codigo='INPUT_READINESS_CONTRACT';
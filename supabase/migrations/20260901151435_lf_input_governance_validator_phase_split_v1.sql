-- INPUT_GOVERNANCE_AGENT 5.12
-- Keep the governed 30s PostgREST timeout and independent Validator identity.
-- When a chunk finishes the remaining family assessments, commit that work and
-- validate gap proposals in the next RPC chunk instead of combining both costs
-- in one transaction. This preserves fail-closed semantics and resumability.

do $migration$
declare
  v_def text;
  v_sha text;
  v_new text;
  v_decl_old text := '  v_payload jsonb; v_prop jsonb; a record;';
  v_decl_new text := '  v_payload jsonb; v_prop jsonb; a record; v_pending_before integer;';
  v_loop_anchor text := E'  for a in\n    select * from programacion.input_family_assessments\n    where run_id=p_run_id and validator_outcome=''PENDING''';
  v_loop_replacement text := E'  select count(*) into v_pending_before from programacion.input_family_assessments where run_id=p_run_id and validator_outcome=''PENDING'';\n  for a in\n    select * from programacion.input_family_assessments\n    where run_id=p_run_id and validator_outcome=''PENDING''';
  v_finalize_anchor text := E'  end if;\n  v_prop:=programacion.fn_input_governance_validate_gap_proposals_v1(p_run_id,p_validator_identity);';
  v_finalize_replacement text := E'  end if;\n  if v_pending_before>0 then\n    return jsonb_build_object(''status'',''VALIDATOR_CONTINUE_REQUIRED'',''run_id'',p_run_id,''pantalla_id'',v_pantalla_id,''family_count'',v_family_count,''validator_pass_count'',v_pass,''pending_count'',v_pending,''validator_identity'',p_validator_identity,''analysis_revision'',''INPUT_GOV_REMEDIATION_1_4_SAFE_AUTOFIX'',''next_phase'',''PROPOSAL_VALIDATION'',''promotion_authorized'',false,''production_authorized'',false);\n  end if;\n  v_prop:=programacion.fn_input_governance_validate_gap_proposals_v1(p_run_id,p_validator_identity);';
begin
  select pg_get_functiondef('programacion.fn_input_governance_validate_v2(bigint,text)'::regprocedure),
         encode(extensions.digest(convert_to(pg_get_functiondef('programacion.fn_input_governance_validate_v2(bigint,text)'::regprocedure),'UTF8'),'sha256'),'hex')
    into v_def,v_sha;
  if v_sha<>'b2c454dc509571a17166d71d550ad32c8308d6c112d1038ee4d830eedb24382b' then
    raise exception 'INPUT_GOVERNANCE_VALIDATOR_PHASE_SPLIT_BASELINE_SHA_MISMATCH:%',v_sha;
  end if;
  if position(v_decl_old in v_def)=0 then raise exception 'INPUT_GOVERNANCE_VALIDATOR_PHASE_SPLIT_DECL_ANCHOR_DRIFT'; end if;
  if position(v_loop_anchor in v_def)=0 then raise exception 'INPUT_GOVERNANCE_VALIDATOR_PHASE_SPLIT_LOOP_ANCHOR_DRIFT'; end if;
  if position(v_finalize_anchor in v_def)=0 then raise exception 'INPUT_GOVERNANCE_VALIDATOR_PHASE_SPLIT_FINALIZE_ANCHOR_DRIFT'; end if;
  v_new:=replace(v_def,v_decl_old,v_decl_new);
  v_new:=replace(v_new,v_loop_anchor,v_loop_replacement);
  v_new:=replace(v_new,v_finalize_anchor,v_finalize_replacement);
  execute v_new;
end;
$migration$;

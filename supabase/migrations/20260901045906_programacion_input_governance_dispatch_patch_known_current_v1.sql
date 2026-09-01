do $migration$
declare
  v_def text;
  v_sha text;
  v_new text;
begin
  select pg_get_functiondef('programacion.fn_input_governance_execute(integer,text)'::regprocedure),
         encode(digest(pg_get_functiondef('programacion.fn_input_governance_execute(integer,text)'::regprocedure),'sha256'),'hex')
    into v_def,v_sha;
  if v_sha<>'14d6433fbaf1f024cc960eef934983fe47f68a3b8ede913627ea3b20e980d444' then
    raise exception 'INPUT_GOV_DISPATCH_BASELINE_SHA_MISMATCH:%',v_sha;
  end if;
  if position('v_stage:=programacion.fn_input_stage_gate_summary(v_run);' in v_def)=0
     or position('v_eval:=programacion.fn_input_evaluation_outcome_summary(v_run);' in v_def)=0
     or position('v_internal_summary:=programacion.fn_input_internal_remediation_summary(v_run);' in v_def)=0 then
    raise exception 'INPUT_GOV_DISPATCH_EXPECTED_CALLS_NOT_FOUND';
  end if;
  v_new:=replace(v_def,'v_stage:=programacion.fn_input_stage_gate_summary(v_run);','v_stage:=programacion.fn_input_stage_gate_summary_known_current_v1(v_run,true);');
  v_new:=replace(v_new,'v_eval:=programacion.fn_input_evaluation_outcome_summary(v_run);','v_eval:=programacion.fn_input_evaluation_outcome_summary_known_current_v1(v_run,true);');
  v_new:=replace(v_new,'v_internal_summary:=programacion.fn_input_internal_remediation_summary(v_run);','v_internal_summary:=programacion.fn_input_internal_remediation_summary_known_current_v1(v_run,v_eval);');
  execute v_new;
end;
$migration$;
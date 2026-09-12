from pathlib import Path
import json
ROOT=Path(__file__).resolve().parents[1]
C=json.loads((ROOT/'contracts/runtime_update_operation_disposition_v1.json').read_text())
O=C['observed_live_state']; D=C['decision']; A=C['activation']
checks={
 'exact_operation': C['operation_code']=='ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF',
 'prod_controlled_observed': O['registry_status']=='PRODUCCION_CONTROLADA',
 'steps_14': O['active_steps']==14,
 'contracts_14': O['active_step_contracts']==14,
 'bindings_zero': O['active_bindings']==0,
 'writes_observed': O['historical_github_write_steps']==3,
 'two_in_progress': O['in_progress_executions']==2,
 'fail_closed': D['classification']=='FAIL_CLOSED_REQUIRED_BEFORE_FURTHER_EXECUTION',
 'retain_distinct': D['retain_as_distinct_operation'] is True,
 'no_clone_now': D['create_14_bindings_now'] is False,
 'preferred_readonly_or_inactive': D['preferred_live_disposition']=='READ_ONLY_OR_INACTIVE_UNTIL_BINDINGS_EXIST',
 'step60_revision_precondition': 'step60 requires bound_revision and execution_bound_to_target_before_change' in C['preconditions_before_reenable'],
 'missing_binding_negative': 'negative missing-binding test fails closed' in C['preconditions_before_reenable'],
 'dispose_open_runs': 'dispose or explicitly supersede the two IN_PROGRESS executions' in C['preconditions_before_reenable'],
 'source_only': A['source_only'] is True,
 'no_live_registry_mutation': A['live_registry_status_change_authorized'] is False,
 'no_live_binding_creation': A['live_binding_creation_authorized'] is False,
}
failed=[k for k,v in checks.items() if not v]
if failed: raise SystemExit('FAIL_RUNTIME_UPDATE_OPERATION_DISPOSITION:'+','.join(failed))
print(f'PASS_RUNTIME_UPDATE_OPERATION_DISPOSITION={sum(checks.values())}/{len(checks)}')
print('LIVE_BINDINGS_CREATED=false')
print('LIVE_REGISTRY_STATUS_CHANGED=false')

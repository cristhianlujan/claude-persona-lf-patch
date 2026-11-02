"""Format read-only ledger row without authenticating it or authorizing actions."""
PLAN = 'PROGRAMMING_AGENT_PROGRAMMING_REMEDIATION_V1'
class ReadbackError(ValueError): pass
def project_tool_row(row, *, unit, checkpoint):
    if not isinstance(row, dict): raise ReadbackError('ROW_INVALID')
    if (row.get('plan_code'), row.get('unit_code'), row.get('checkpoint_code')) != (PLAN, unit, checkpoint): raise ReadbackError('IDENTITY_MISMATCH')
    if row.get('status') not in ('PENDING','IN_PROGRESS','BLOCKED','FAILED','DONE','NOT_APPLICABLE'): raise ReadbackError('STATUS_INVALID')
    if type(row.get('required')) is not bool: raise ReadbackError('REQUIRED_INVALID')
    if not isinstance(row.get('updated_at'), str) or not row['updated_at']: raise ReadbackError('TIMESTAMP_MISSING')
    return {'schema_version':'PG_TOOL_READBACK_ADVISORY_V1','plan_code':PLAN,'unit_code':unit,'checkpoint_code':checkpoint,'ledger_status':row['status'],'observed_updated_at':row['updated_at'],'source_authenticated':False,'run_bound':False,'write_authorized':False,'transition_authorized':False,'worker_dispatch_authorized':False}

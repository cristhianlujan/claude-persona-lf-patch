"""Read-only advisory for PIP-1 checkpoint outcomes. No execution authority."""
from collections.abc import Mapping

KNOWN = frozenset({'PENDING','ELIGIBLE','RUNNING','SUCCEEDED_ACCREDITED','NOT_APPLICABLE_JUSTIFIED','FAILED','BLOCKED','INVALIDATED','SUCCEEDED_SYNTHETIC','SYNTHETIC_ONLY'})

class AdvisoryError(ValueError):
    pass

def advise(outcome: Mapping, *, expected_checkpoint: str) -> dict:
    if not isinstance(outcome, Mapping):
        raise AdvisoryError('OUTCOME_NOT_OBJECT')
    if not isinstance(expected_checkpoint, str) or not expected_checkpoint:
        raise AdvisoryError('CHECKPOINT_REQUIRED')
    if outcome.get('checkpoint_id') != expected_checkpoint:
        raise AdvisoryError('CHECKPOINT_MISMATCH')
    state = outcome.get('state')
    if state not in KNOWN:
        raise AdvisoryError('UNKNOWN_STATE')
    if state in {'SUCCEEDED_ACCREDITED','NOT_APPLICABLE_JUSTIFIED'}:
        next_step = 'EXTERNAL_AUTHORITY_READBACK_REQUIRED'
    elif state in {'ELIGIBLE','RUNNING'}:
        next_step = 'INSPECT_VALIDATION_INSTRUCTIONS'
    elif state in {'FAILED','BLOCKED','INVALIDATED'}:
        next_step = 'STOP_AND_REVIEW_BLOCKER'
    else:
        next_step = 'WAIT_FOR_GOVERNED_CHECKPOINT'
    return {'schema_version':'PIP1_CHAT_ADVISORY_V1','checkpoint_id':expected_checkpoint,
            'observed_state':state,'suggested_next':next_step,'read_only':True,
            'write_authorized':False,'transition_authorized':False,
            'worker_dispatch_authorized':False,'external_receipt_verified':False}

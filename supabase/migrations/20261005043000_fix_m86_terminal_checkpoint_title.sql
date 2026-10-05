update programacion.engineering_work_checkpoints c
set title='Readback final de reducción de lecturas + paridad contra golden histórico; estado terminal único',
    updated_at=now(),
    updated_by_execution_id='ENGINEERING_CHECKPOINT_EXECUTION_CONTRACT_V1'
from programacion.engineering_plan_units pu
where pu.work_item_id=c.work_item_id
  and pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
  and pu.unit_code='M8.6'
  and c.checkpoint_code='TERMINAL'
  and c.status not in ('DONE','NOT_APPLICABLE');

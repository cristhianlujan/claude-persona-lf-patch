#!/usr/bin/env python3
import json
from pathlib import Path
p=Path(__file__).with_name('s31_strategy_master_plan_v0_3.json')
x=json.loads(p.read_text(encoding='utf-8'))
assert x['plan_version']=='S31_STRATEGY_MASTER_PLAN_V0_3'
assert x['historical_v0_2_artifacts_immutable'] is True
cycle=x['ekb_cycle']
assert cycle['mode']=='EVENT_DRIVEN_CONTINUOUS'
assert cycle['contract_ref']=='s31_ekb_continuous_cycle_v0_1.json'
assert cycle['recurrence_evidence']=={'code':'S30-GATE-EKB-AUTOPERSIST-MISSING-001','classification':'RECURRENCE','event_id':13502,'frequency_after':3}
seq=x['execution_sequence']
required=[
 'SCHEMA_FIRST_EKB_SOURCE_RESOLUTION','FRESH_EKB_AUTHORITY_CURRENTNESS','EXECUTE_MATERIAL_MACROBATCH','OBSERVATION_CHECKPOINT',
 'EKB_LOOKUP_ON_FAIL_BLOCK_ERROR_OR_MATERIAL_NEW_EVIDENCE','EKB_CLASSIFY_RECURRENCE_NEW_ERROR_OR_NOT_LEARNING_WITH_REASON',
 'EKB_GOVERNED_PERSISTENCE_AND_READBACK_IF_REQUIRED','REPAIR_OR_REPLAN_ONLY_AFTER_EKB_DISPOSITION',
 'EKB_REFRESH_BEFORE_NEXT_MATERIAL_MACROBATCH','FINAL_EKB_LEARNING_DISPOSITION','FINAL_EKB_READBACK_AFTER_LAST_WRITE'
]
for name in required: assert name in seq,name
assert seq.index('EKB_GOVERNED_PERSISTENCE_AND_READBACK_IF_REQUIRED') < seq.index('REPAIR_OR_REPLAN_ONLY_AFTER_EKB_DISPOSITION')
assert seq.index('FINAL_EKB_LEARNING_DISPOSITION') < seq.index('GLOBAL_SAFE_WORK_RESCAN')
guards=x['hard_guards']
assert guards['required_persistence_without_writer_receipt']=='BLOCKED_EKB_PERSISTENCE'
assert guards['required_persistence_without_post_write_readback']=='BLOCKED_EKB_PERSISTENCE'
assert guards['repair_before_ekb_disposition']=='BLOCK'
assert guards['direct_ekb_dml_bypass_forbidden'] is True
assert all(v=='NONE' for v in x['authority'].values())
print('PASS_S31_STRATEGY_MASTER_PLAN_V0_3')

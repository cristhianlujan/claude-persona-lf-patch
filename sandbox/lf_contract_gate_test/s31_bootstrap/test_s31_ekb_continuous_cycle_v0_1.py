#!/usr/bin/env python3
import copy, importlib.util, sys
from pathlib import Path
p=Path(__file__).with_name('validate_s31_ekb_continuous_cycle_v0_1.py')
s=importlib.util.spec_from_file_location('s31_ekb_cycle',p); m=importlib.util.module_from_spec(s); sys.modules[s.name]=m; s.loader.exec_module(m)

def base():
    return {
      'pre_execution':{'schema_first':True,'ekb_read_performed':True,'receipt_ref':'receipt://ekb-pre'},
      'events':[
        {'event_id':'OBS-1','sequence':10,'event_type':'FAIL','ekb_lookup_performed':True,'classification':'RECURRENCE','ekb_code':'S30-GATE-EKB-AUTOPERSIST-MISSING-001','persistence_required':True,'writer_receipt_ref':'receipt://writer-1','post_write_readback_verified':True,'repair_started':True,'reason':None}
      ],
      'refresh':{'before_next_material_batch_verified':True,'receipt_ref':'receipt://ekb-refresh'},
      'close':{'all_events_disposed':True,'unresolved_persistence_count':0,'final_readback_verified':True,'final_readback_ref':'receipt://ekb-final','final_readback_sequence':20}
    }

def expect(mut,code):
    x=base(); mut(x); r=m.evaluate(x); assert r['code']==code,(code,r); return 1
cases=0
r=m.evaluate(base()); assert r['status']==m.PASS,r; cases+=1
cases+=expect(lambda x:x['pre_execution'].__setitem__('schema_first',False),'BLOCK_EKB_SCHEMA_FIRST_MISSING')
cases+=expect(lambda x:x['pre_execution'].__setitem__('ekb_read_performed',False),'BLOCK_EKB_PREFLIGHT_READ_MISSING')
cases+=expect(lambda x:x['events'][0].__setitem__('ekb_lookup_performed',False),'BLOCK_EKB_LOOKUP_MISSING')
cases+=expect(lambda x:x['events'][0].__setitem__('classification','PENDING'),'BLOCK_EKB_DISPOSITION_PENDING')
cases+=expect(lambda x:x['events'][0].__setitem__('writer_receipt_ref',None),'BLOCKED_EKB_PERSISTENCE')
cases+=expect(lambda x:x['events'][0].__setitem__('post_write_readback_verified',False),'BLOCKED_EKB_PERSISTENCE')
def not_learning_no_reason(x):
    e=x['events'][0]; e.update({'classification':'NOT_LEARNING_WITH_REASON','persistence_required':False,'writer_receipt_ref':None,'post_write_readback_verified':False,'repair_started':False,'reason':None})
cases+=expect(not_learning_no_reason,'BLOCK_NOT_LEARNING_REASON_MISSING')
def not_learning_ok(x):
    e=x['events'][0]; e.update({'classification':'NOT_LEARNING_WITH_REASON','persistence_required':False,'writer_receipt_ref':None,'post_write_readback_verified':False,'repair_started':True,'reason':'External transient already covered by non-learning incident policy.'})
x=base(); not_learning_ok(x); r=m.evaluate(x); assert r['status']==m.PASS,r; cases+=1
cases+=expect(lambda x:x['refresh'].__setitem__('before_next_material_batch_verified',False),'BLOCK_EKB_REFRESH_BEFORE_NEXT_BATCH_MISSING')
cases+=expect(lambda x:x['close'].__setitem__('unresolved_persistence_count',1),'BLOCKED_EKB_PERSISTENCE')
cases+=expect(lambda x:x['close'].__setitem__('final_readback_verified',False),'BLOCK_EKB_FINAL_READBACK_MISSING')
cases+=expect(lambda x:x['close'].__setitem__('final_readback_sequence',10),'BLOCK_EKB_FINAL_READBACK_NOT_AFTER_LAST_WRITE')
def material_new(x):
    x['events'][0].update({'event_type':'MATERIAL_NEW_EVIDENCE','classification':'NOT_LEARNING_WITH_REASON','persistence_required':False,'writer_receipt_ref':None,'post_write_readback_verified':False,'repair_started':False,'reason':'Evidence changed routing but did not represent an error family.'})
x=base(); material_new(x); r=m.evaluate(x); assert r['status']==m.PASS,r; cases+=1
print(f'PASS_S31_EKB_CONTINUOUS_CYCLE_SELFTEST={cases}/{cases}')

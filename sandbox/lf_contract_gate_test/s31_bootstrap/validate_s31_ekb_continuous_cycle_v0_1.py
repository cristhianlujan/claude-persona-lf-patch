#!/usr/bin/env python3
from __future__ import annotations
import json, sys
from pathlib import Path
from typing import Any, Mapping

PASS='PASS'
BLOCKED='BLOCKED'
TRIGGERS={'FAIL','BLOCKED','ERROR','MATERIAL_NEW_EVIDENCE'}
TERMINAL={'RECURRENCE','NEW_ERROR','NOT_LEARNING_WITH_REASON'}
PERSIST={'RECURRENCE','NEW_ERROR'}

def block(code:str, **extra:Any)->dict:
    return {'status':BLOCKED,'code':code,**extra}

def nonempty(v:Any)->bool:
    return isinstance(v,str) and bool(v.strip())

def evaluate(run:Mapping[str,Any])->dict:
    pre=run.get('pre_execution') or {}
    if pre.get('schema_first') is not True:
        return block('BLOCK_EKB_SCHEMA_FIRST_MISSING')
    if pre.get('ekb_read_performed') is not True or not nonempty(pre.get('receipt_ref')):
        return block('BLOCK_EKB_PREFLIGHT_READ_MISSING')
    events=run.get('events')
    if not isinstance(events,list):
        return block('BLOCK_EKB_EVENTS_NOT_LIST')
    seen=set()
    last_write_seq=None
    for i,e in enumerate(events):
        if not isinstance(e,Mapping):
            return block('BLOCK_EKB_EVENT_SHAPE',index=i)
        eid=e.get('event_id')
        if not nonempty(eid) or eid in seen:
            return block('BLOCK_EKB_EVENT_ID_INVALID',index=i)
        seen.add(eid)
        et=e.get('event_type')
        if et not in TRIGGERS:
            return block('BLOCK_EKB_EVENT_TYPE_INVALID',event_id=eid)
        if e.get('ekb_lookup_performed') is not True:
            return block('BLOCK_EKB_LOOKUP_MISSING',event_id=eid)
        disp=e.get('classification')
        if disp not in TERMINAL:
            return block('BLOCK_EKB_DISPOSITION_PENDING',event_id=eid,classification=disp)
        if disp in PERSIST:
            if e.get('persistence_required') is not True:
                return block('BLOCK_EKB_PERSISTENCE_NOT_REQUIRED_FOR_LEARNING',event_id=eid)
            if not nonempty(e.get('writer_receipt_ref')):
                return block('BLOCKED_EKB_PERSISTENCE',event_id=eid,reason='WRITER_RECEIPT_MISSING')
            if e.get('post_write_readback_verified') is not True:
                return block('BLOCKED_EKB_PERSISTENCE',event_id=eid,reason='POST_WRITE_READBACK_MISSING')
            seq=e.get('sequence')
            if not isinstance(seq,int) or seq < 1:
                return block('BLOCK_EKB_EVENT_SEQUENCE_INVALID',event_id=eid)
            last_write_seq=max(last_write_seq or seq,seq)
        else:
            if e.get('persistence_required') is True:
                return block('BLOCK_NOT_LEARNING_PERSISTENCE_CONTRADICTION',event_id=eid)
            if not nonempty(e.get('reason')):
                return block('BLOCK_NOT_LEARNING_REASON_MISSING',event_id=eid)
        if e.get('repair_started') is True:
            if disp not in TERMINAL:
                return block('BLOCK_REPAIR_BEFORE_EKB_DISPOSITION',event_id=eid)
            if disp in PERSIST and (not nonempty(e.get('writer_receipt_ref')) or e.get('post_write_readback_verified') is not True):
                return block('BLOCK_REPAIR_BEFORE_EKB_READBACK',event_id=eid)
    refresh=run.get('refresh') or {}
    if refresh.get('before_next_material_batch_verified') is not True:
        return block('BLOCK_EKB_REFRESH_BEFORE_NEXT_BATCH_MISSING')
    close=run.get('close') or {}
    if close.get('all_events_disposed') is not True:
        return block('BLOCK_EKB_EVENTS_NOT_DISPOSED')
    if close.get('unresolved_persistence_count') != 0:
        return block('BLOCKED_EKB_PERSISTENCE',reason='UNRESOLVED_PERSISTENCE_NONZERO')
    if close.get('final_readback_verified') is not True or not nonempty(close.get('final_readback_ref')):
        return block('BLOCK_EKB_FINAL_READBACK_MISSING')
    if last_write_seq is not None:
        final_seq=close.get('final_readback_sequence')
        if not isinstance(final_seq,int) or final_seq <= last_write_seq:
            return block('BLOCK_EKB_FINAL_READBACK_NOT_AFTER_LAST_WRITE',last_write_sequence=last_write_seq,final_readback_sequence=final_seq)
    return {'status':PASS,'code':'PASS_S31_EKB_CONTINUOUS_CYCLE','event_count':len(events)}

def main()->int:
    if len(sys.argv)!=2:
        print('usage: validate_s31_ekb_continuous_cycle_v0_1.py <run.json>',file=sys.stderr); return 2
    data=json.loads(Path(sys.argv[1]).read_text(encoding='utf-8'))
    result=evaluate(data); print(json.dumps(result,sort_keys=True)); return 0 if result['status']==PASS else 1
if __name__=='__main__': raise SystemExit(main())

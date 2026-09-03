#!/usr/bin/env python3
import importlib.util
import sys
from pathlib import Path
p=Path(__file__).with_name('run_close_gate_v3.py')
s=importlib.util.spec_from_file_location('profile_runtime_close_gate_v3',p)
g=importlib.util.module_from_spec(s)
sys.modules[s.name]=g
s.loader.exec_module(g)

def base():
 return {'inicio_lima':'06:42:49','work_end_at_lima':'07:18:00','report_started_at_lima':'07:18:05','fin_lima':'07:20:00','duracion_real':'00:37:11','trabajo_activo':'00:35:11','espera_neta':'00:00:00','report_duration':'00:02:00','asked_at_lima':'07:17:59','next_execution_readback_verified':True,'ekb_final_enrichment':'PASS','ekb_readback_verified':True,'global_remaining_work_scan':'PASS','anti_close_answer':'NO','safe_work_remaining_count':0,'next_safe_batch':'NONE','why_run_stopped':'NO_SAFE_WORK_REMAINING'}

r=g.evaluate_close_gate(base()); assert r.can_close
x=base(); x['anti_close_answer']='SÍ'; assert not g.evaluate_close_gate(x).can_close and 'ANTI_CLOSE_ANSWER_YES' in g.evaluate_close_gate(x).reasons
x=base(); x['inicio_lima']=''; assert not g.evaluate_close_gate(x).can_close
x=base(); x['work_end_at_lima']=''; assert not g.evaluate_close_gate(x).can_close and 'MISSING_TELEMETRY:work_end_at_lima' in g.evaluate_close_gate(x).reasons
x=base(); x['report_started_at_lima']=''; assert not g.evaluate_close_gate(x).can_close and 'MISSING_TELEMETRY:report_started_at_lima' in g.evaluate_close_gate(x).reasons
x=base(); x['report_duration']=''; assert not g.evaluate_close_gate(x).can_close and 'MISSING_TELEMETRY:report_duration' in g.evaluate_close_gate(x).reasons
x=base(); x['report_started_at_lima']='07:17:59'; assert not g.evaluate_close_gate(x).can_close and 'REPORT_STARTED_BEFORE_WORK_END' in g.evaluate_close_gate(x).reasons
x=base(); x['next_execution_readback_verified']=False; assert not g.evaluate_close_gate(x).can_close and 'NEXT_EXECUTION_READBACK_NOT_VERIFIED' in g.evaluate_close_gate(x).reasons
x=base(); x['safe_work_remaining_count']=1; assert not g.evaluate_close_gate(x).can_close
x=base(); x['next_safe_batch']='benchmark'; assert not g.evaluate_close_gate(x).can_close
x=base(); x['ekb_readback_verified']=False; assert not g.evaluate_close_gate(x).can_close
x=base(); x['why_run_stopped']='WAITING'; assert not g.evaluate_close_gate(x).can_close
x=base(); x['why_run_stopped']='EXECUTION_LIMIT_REACHED'; assert not g.evaluate_close_gate(x).can_close
x=base(); x['why_run_stopped']='EXECUTION_LIMIT_REACHED'; x['execution_limit_evidence']='literal engine stop'; assert g.evaluate_close_gate(x).can_close
print('RUN_CLOSE_GATE_V3_TESTS_PASS 14/14')

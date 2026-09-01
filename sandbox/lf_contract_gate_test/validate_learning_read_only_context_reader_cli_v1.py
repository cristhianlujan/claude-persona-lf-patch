#!/usr/bin/env python3
from __future__ import annotations
import json,subprocess,sys,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
FIX=ROOT/'sandbox/lf_contract_gate_test/learning_read_only_context_rows_fixture_v1.json'
CLI=ROOT/'sandbox/lf_contract_gate_test/learning_read_only_context_reader_cli_v1.py'
UI_BIND=ROOT/'sandbox/lf_contract_gate_test/learning_ui_architect_bindings_v1.yaml'

def run(args,data): return subprocess.run([sys.executable,str(CLI),*args],input=data,text=True,capture_output=True,cwd=ROOT)
def main() -> int:
 data=FIX.read_text(encoding='utf-8')
 pd=run(['--binding-id','BIND-LF-PD-NEGOCIACION-DEUDA-v2'],data)
 if pd.returncode!=0: raise SystemExit(pd.stderr or pd.stdout)
 out=json.loads(pd.stdout)
 assert out['consumer_id']=='PERFIL-PRODUCT-DIRECTOR-LF' and out['capability_id']=='NEGOCIACION_DEUDA'
 assert out['selected_count']==2 and out['llm_calls']==0 and out['round_trips']==0 and out['tool_calls']==0
 assert out['context_bytes']<=out['max_context_bytes']<=6000
 ui=run(['--binding-id','BIND-LF-UI-NEGOCIACION-PRESENTATION-v1','--bindings-file',str(UI_BIND)],data)
 if ui.returncode!=0: raise SystemExit(ui.stderr or ui.stdout)
 u=json.loads(ui.stdout)
 assert u['consumer_id']=='PERFIL-UI-ARCHITECT' and u['capability_id']=='NEGOCIACION_DEUDA_PRESENTATION'
 assert u['bindings_file']=='learning_ui_architect_bindings_v1.yaml'
 assert u['selected_count']==2 and u['llm_calls']==0 and u['round_trips']==0 and u['tool_calls']==0
 assert u['context_bytes']<=u['max_context_bytes']<=5000
 bad=run(['--binding-id','UNKNOWN'],data); assert bad.returncode!=0 and 'EXACT_BINDING_NOT_FOUND' in (bad.stderr+bad.stdout)
 escape=run(['--binding-id','X','--bindings-file','/tmp/learning_fake.yaml'],data); assert escape.returncode!=0 and 'BINDINGS_FILE_OUTSIDE_GOVERNED_SANDBOX' in (escape.stderr+escape.stdout)
 nongov=run(['--binding-id','X','--bindings-file',str(ROOT/'sandbox/lf_contract_gate_test/product_director_context_pack_caller_gap_v1.yaml')],data); assert nongov.returncode!=0 and 'BINDINGS_FILE_NOT_GOVERNED_LEARNING_CONTRACT' in (nongov.stderr+nongov.stdout)
 print('LEARNING_READ_ONLY_CONTEXT_READER_CLI=PASS consumers=2 pd_selected=2 ui_selected=2 llm=0 roundtrips=0 escape=blocked nongoverned=blocked')
 return 0
if __name__=='__main__': raise SystemExit(main())

#!/usr/bin/env python3
import subprocess,sys,ast
from pathlib import Path
R=Path(__file__).resolve().parent
ALLOWED={'CHALLENGER_WINS','CHAMPION_RETAINS','NEEDS_REPAIR','INSUFFICIENT_EVIDENCE'}
def main():
 p=subprocess.run([sys.executable,str(R/'validate_learning_readonly_benchmark_50_v1.py')],capture_output=True,text=True)
 assert p.returncode==0,p.stdout+p.stderr
 result=ast.literal_eval(p.stdout.strip().splitlines()[-1])
 assert result['result'] in ALLOWED
 assert result['routing_gate']=='PASS'
 assert result['behavioral_ab']=='NOT_EXECUTED'
 assert result['result']=='INSUFFICIENT_EVIDENCE'
 print('LEARNING_BENCHMARK_OUTCOME_CONTRACT=PASS allowed_outcome=INSUFFICIENT_EVIDENCE routing_gate=PASS behavioral_ab=NOT_EXECUTED')
if __name__=='__main__': main()

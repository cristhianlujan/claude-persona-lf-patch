#!/usr/bin/env python3
import subprocess,sys
from pathlib import Path
R=Path(__file__).resolve().parent
SCRIPTS=[
 'validate_ui_architect_learning_readonly_v1.py',
 'validate_ui_architect_learning_routing_50_v1.py',
 'validate_ui_architect_learning_adversarial_v1.py',
 'measure_ui_architect_learning_context_v1.py',
 'validate_ui_architect_selector_integration_v1.py',
 'validate_ui_architect_learning_classification_v1.py',
 'validate_ui_architect_learning_efficiency_metrics_v1.py',
 'validate_learning_active_consumer_binding_contract_v1.py',
 'validate_learning_benchmark_outcome_contract_v1.py'
]
def main():
 for s in SCRIPTS:
  p=subprocess.run([sys.executable,str(R/s)],capture_output=True,text=True)
  if p.returncode!=0:
   sys.stderr.write(p.stdout+p.stderr); raise SystemExit(p.returncode)
  print(p.stdout.strip())
 print('UI_ARCHITECT_LEARNING_SUITE=PASS validators=9/9 production_authorized=false')
if __name__=='__main__': main()

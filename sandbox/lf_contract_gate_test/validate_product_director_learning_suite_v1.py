#!/usr/bin/env python3
import subprocess,sys
from pathlib import Path
R=Path(__file__).resolve().parent
SCRIPTS=[
 'validate_product_director_learning_exact_binding_v1.py',
 'validate_learning_readonly_clean_v1.py',
 'benchmark_learning_dynamic_context_selector_clean_v1.py'
]
def main():
 for s in SCRIPTS:
  p=subprocess.run([sys.executable,str(R/s)],capture_output=True,text=True)
  if p.returncode!=0:
   sys.stderr.write(p.stdout+p.stderr); raise SystemExit(p.returncode)
  print(p.stdout.strip())
 print('PRODUCT_DIRECTOR_LEARNING_SUITE=PASS validators=3/3 production_authorized=false')
if __name__=='__main__': main()

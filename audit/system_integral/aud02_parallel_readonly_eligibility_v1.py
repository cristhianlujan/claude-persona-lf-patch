#!/usr/bin/env python3
"""AUD-2 parallel-readonly eligibility gate v1.

Fail-closed: AUD-3..AUD-6 may run in parallel only after all four runners exist
and serial-vs-concurrent parity evidence is supplied. Absence is a valid
SEQUENTIAL_REQUIRED decision, not a blocker for the audit plan.
"""
from __future__ import annotations
import argparse,json,pathlib
EXPECTED=[
 "aud03_architecture_conformance_v1.py",
 "aud04_execution_performance_v1.py",
 "aud05_assurance_coverage_v1.py",
 "aud06_failure_recovery_v1.py",
]
def main():
 ap=argparse.ArgumentParser(); ap.add_argument("--audit-dir",default="audit/system_integral"); ap.add_argument("--parity-evidence")
 ns=ap.parse_args(); d=pathlib.Path(ns.audit_dir)
 present={x:(d/x).is_file() for x in EXPECTED}
 parity=False
 if ns.parity_evidence:
  p=pathlib.Path(ns.parity_evidence)
  if p.is_file():
   try: parity=bool(json.loads(p.read_text()).get("serial_concurrent_parity"))
   except Exception: parity=False
 safe=all(present.values()) and parity
 print(json.dumps({
  "schema_version":"aud02-parallel-readonly-eligibility/v1",
  "parallel_safe":safe,
  "decision":"PARALLEL_SAFE" if safe else "SEQUENTIAL_REQUIRED",
  "runner_presence":present,
  "serial_concurrent_parity":parity,
  "reason":None if safe else "Parallelism is unproven until all AUD-3..AUD-6 runners exist and serial-vs-concurrent parity is evidenced."
 },sort_keys=True))
if __name__=="__main__":main()

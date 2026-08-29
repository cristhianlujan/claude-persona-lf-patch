#!/usr/bin/env python3
from pathlib import Path
ROOT=Path(__file__).resolve().parent
ADAPTERS=["lf_shell_profile_adapter","project_brand_mockup_render_lf","marketplace_lf_ux","marketplace_lf_cx_trust"]
REQUIRED=["ADAPTER.md","manifest.yaml","runtime_capsule.md","validators/validate_adapter_package.py","judges/quality_v2_semantic_judge.md","evals/quality_v2/run_cases.py","evals/quality_v2/behavioral_eval_protocol.md"]
MAX_CAPSULE=2000
def main():
 errors=[]
 for a in ADAPTERS:
  base=ROOT/a
  for rel in REQUIRED:
   if not (base/rel).exists():errors.append(f"{a}: missing {rel}")
  cap=base/"runtime_capsule.md"
  if cap.exists() and len(cap.read_text(encoding="utf-8"))>MAX_CAPSULE:errors.append(f"{a}: runtime capsule > {MAX_CAPSULE} chars")
 if errors:
  [print("FAIL",e) for e in errors];return 1
 print("ADAPTER_QUALITY_V2_STATIC_PASS");return 0
if __name__=="__main__":raise SystemExit(main())

#!/usr/bin/env python3
from __future__ import annotations
import json,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
EXPECTED={'consolidated-visual-reading-v2.schema.json','visual-geometry-profile.schema.json','visual-style-profile.schema.json','text-group.schema.json','design-auxiliary-source.schema.json','design-reconciliation.schema.json','visual-fidelity-report.schema.json','human-review-packet-v4.schema.json'}

def main()->int:
 failures=[]
 for name in sorted(EXPECTED):
  p=ROOT/'schemas'/name
  if not p.exists():failures.append('MISSING:'+name);continue
  try:s=json.loads(p.read_text())
  except Exception as e:failures.append('INVALID_JSON:'+name+':'+str(e));continue
  if s.get('$schema')!='https://json-schema.org/draft/2020-12/schema':failures.append('WRONG_DRAFT:'+name)
  if s.get('type')!='object':failures.append('ROOT_NOT_OBJECT:'+name)
  if not s.get('required'):failures.append('NO_REQUIRED_CONTRACT:'+name)
 print(json.dumps({'schemas':len(EXPECTED),'failures':failures,'result':'PASS' if not failures else 'BLOCKED'}));return 0 if not failures else 2
if __name__=='__main__':raise SystemExit(main())

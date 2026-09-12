#!/usr/bin/env python3
from __future__ import annotations
import argparse,json,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
from p0_visual_fidelity_v3 import validate_visual_fidelity

def main()->int:
 p=argparse.ArgumentParser();p.add_argument('--candidate',required=True);p.add_argument('--reconciliation');p.add_argument('--config');p.add_argument('--output');a=p.parse_args()
 c=json.loads(Path(a.candidate).read_text());r=json.loads(Path(a.reconciliation).read_text()) if a.reconciliation else None;cfg=json.loads(Path(a.config).read_text()) if a.config else {}
 rep=validate_visual_fidelity(c,r,cfg);text=json.dumps(rep,ensure_ascii=False,indent=2)+'\n';Path(a.output).write_text(text) if a.output else print(text,end='');return 0 if rep['result']=='PASS_VISUAL_FIDELITY' else 2
if __name__=='__main__':raise SystemExit(main())

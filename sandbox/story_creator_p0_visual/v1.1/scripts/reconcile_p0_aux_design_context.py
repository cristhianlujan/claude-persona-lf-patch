#!/usr/bin/env python3
from __future__ import annotations
import argparse,json,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
from p0_visual_fidelity_v3 import reconcile_auxiliary

def main()->int:
 p=argparse.ArgumentParser();p.add_argument('--blind',required=True);p.add_argument('--aux',required=True);p.add_argument('--config');p.add_argument('--output',required=True);a=p.parse_args()
 b=json.loads(Path(a.blind).read_text());aux=json.loads(Path(a.aux).read_text());cfg=json.loads(Path(a.config).read_text()) if a.config else {};r=reconcile_auxiliary(b,aux,cfg);Path(a.output).write_text(json.dumps(r,ensure_ascii=False,indent=2)+'\n');print(r['result']);return 0 if r['result']=='PASS_RECONCILIATION' else 2
if __name__=='__main__':raise SystemExit(main())

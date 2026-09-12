#!/usr/bin/env python3
from __future__ import annotations
import argparse,json,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
from p0_visual_fidelity_v3 import build_text_groups

def main()->int:
 p=argparse.ArgumentParser();p.add_argument('--candidate',required=True);p.add_argument('--config');p.add_argument('--output',required=True);a=p.parse_args();c=json.loads(Path(a.candidate).read_text());cfg=json.loads(Path(a.config).read_text()) if a.config else {};out={'schema_version':'p0-text-group-reconciliation/v1','text_groups':build_text_groups(c.get('elements',[]),cfg)};Path(a.output).write_text(json.dumps(out,ensure_ascii=False,indent=2)+'\n');return 0
if __name__=='__main__':raise SystemExit(main())

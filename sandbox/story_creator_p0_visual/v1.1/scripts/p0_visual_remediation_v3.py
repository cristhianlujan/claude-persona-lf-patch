#!/usr/bin/env python3
from __future__ import annotations
import argparse,json,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
from p0_visual_fidelity_v3 import remediate_visual_fidelity

def main()->int:
 p=argparse.ArgumentParser();p.add_argument('--candidate',required=True);p.add_argument('--image');p.add_argument('--config',required=True);p.add_argument('--output',required=True);p.add_argument('--history-output',required=True);a=p.parse_args();c=json.loads(Path(a.candidate).read_text());cfg=json.loads(Path(a.config).read_text());o,h=remediate_visual_fidelity(c,Path(a.image) if a.image else None,cfg,int(cfg.get('quality',{}).get('max_remediation_cycles',3)));Path(a.output).write_text(json.dumps(o,ensure_ascii=False,indent=2)+'\n');Path(a.history_output).write_text(json.dumps(h,ensure_ascii=False,indent=2)+'\n');return 0
if __name__=='__main__':raise SystemExit(main())

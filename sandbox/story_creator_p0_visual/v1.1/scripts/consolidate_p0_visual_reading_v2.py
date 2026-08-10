#!/usr/bin/env python3
from __future__ import annotations
import argparse,json,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
from p0_visual_fidelity_v3 import enrich_candidate,remediate_visual_fidelity,canonical_sha

def main()->int:
 p=argparse.ArgumentParser();p.add_argument('--input',required=True);p.add_argument('--image');p.add_argument('--config');p.add_argument('--output',required=True);p.add_argument('--remediate',action='store_true');a=p.parse_args()
 legacy=json.loads(Path(a.input).read_text());cfg=json.loads(Path(a.config).read_text()) if a.config else {};image=Path(a.image) if a.image else None
 out=enrich_candidate(legacy,image,cfg);history=[]
 if a.remediate:out,history=remediate_visual_fidelity(out,image,cfg,int(cfg.get('quality',{}).get('max_remediation_cycles',3)))
 out['automatic_remediation_history']=history;Path(a.output).write_text(json.dumps(out,ensure_ascii=False,indent=2)+'\n')
 print(json.dumps({'result':'OK','output_sha256':canonical_sha(out),'remediation_cycles':len(history)}));return 0
if __name__=='__main__':raise SystemExit(main())

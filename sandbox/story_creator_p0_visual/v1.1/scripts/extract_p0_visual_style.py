#!/usr/bin/env python3
from __future__ import annotations
import argparse,json,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
from p0_visual_fidelity_v3 import visual_style_profile,_load_image

def main()->int:
 p=argparse.ArgumentParser();p.add_argument('--candidate',required=True);p.add_argument('--image',required=True);p.add_argument('--output',required=True);a=p.parse_args();c=json.loads(Path(a.candidate).read_text());_,_,img=_load_image(Path(a.image));out={'schema_version':'p0-visual-style-extraction/v1','elements':[{'element_id':e['element_id'],'visual_style':visual_style_profile(e,img)} for e in c.get('elements',[])]};Path(a.output).write_text(json.dumps(out,ensure_ascii=False,indent=2)+'\n');return 0
if __name__=='__main__':raise SystemExit(main())

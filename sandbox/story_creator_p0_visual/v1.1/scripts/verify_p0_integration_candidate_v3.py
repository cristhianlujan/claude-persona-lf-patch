#!/usr/bin/env python3
from __future__ import annotations
import argparse,json,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
from p0_visual_fidelity_v3 import validate_visual_fidelity,validate_packet_v4

def main()->int:
 p=argparse.ArgumentParser();p.add_argument('--candidate',required=True);p.add_argument('--report',required=True);p.add_argument('--packet',required=True);p.add_argument('--config',required=True);a=p.parse_args();c=json.loads(Path(a.candidate).read_text());r=json.loads(Path(a.report).read_text());packet=json.loads(Path(a.packet).read_text());cfg=json.loads(Path(a.config).read_text());vf=validate_visual_fidelity(c,None,cfg);pv=validate_packet_v4(packet,r,c);ok=vf['result']=='PASS_VISUAL_FIDELITY' and r.get('result')=='PASS_VISUAL_FIDELITY' and pv['pass'] and packet.get('human_review_ready') is True;print(json.dumps({'visual_fidelity':vf['result'],'packet':pv,'human_review_ready':packet.get('human_review_ready'),'result':'PASS' if ok else 'BLOCKED'}));return 0 if ok else 2
if __name__=='__main__':raise SystemExit(main())

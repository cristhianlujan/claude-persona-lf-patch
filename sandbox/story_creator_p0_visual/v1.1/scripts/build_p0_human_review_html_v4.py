#!/usr/bin/env python3
from __future__ import annotations
import argparse,json,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
from p0_visual_fidelity_v3 import human_review_packet,build_human_html

def main()->int:
 p=argparse.ArgumentParser();p.add_argument('--candidate',required=True);p.add_argument('--report',required=True);p.add_argument('--reconciliation');p.add_argument('--remediation-history');p.add_argument('--image');p.add_argument('--packet-output',required=True);p.add_argument('--html-output',required=True);a=p.parse_args()
 c=json.loads(Path(a.candidate).read_text());r=json.loads(Path(a.report).read_text());rec=json.loads(Path(a.reconciliation).read_text()) if a.reconciliation else None;hist=json.loads(Path(a.remediation_history).read_text()) if a.remediation_history else []
 packet=human_review_packet(c,r,rec,hist);Path(a.packet_output).write_text(json.dumps(packet,ensure_ascii=False,indent=2)+'\n');Path(a.html_output).write_text(build_human_html(packet,c,Path(a.image) if a.image else None));print(json.dumps({'human_review_ready':packet['human_review_ready'],'human_exceptions':len(packet['human_attention_required'])}));return 0
if __name__=='__main__':raise SystemExit(main())

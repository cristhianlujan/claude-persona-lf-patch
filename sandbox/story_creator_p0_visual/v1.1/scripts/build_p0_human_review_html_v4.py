#!/usr/bin/env python3
from __future__ import annotations
import argparse,json,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
from p0_visual_fidelity_v3 import human_review_packet
from p0_human_review_shell_v4 import build_human_review_shell_v4,validate_human_review_shell_v4

def main()->int:
 p=argparse.ArgumentParser();p.add_argument('--candidate',required=True);p.add_argument('--report',required=True);p.add_argument('--reconciliation');p.add_argument('--remediation-history');p.add_argument('--image');p.add_argument('--challenge');p.add_argument('--packet-output',required=True);p.add_argument('--html-output',required=True);a=p.parse_args()
 c=json.loads(Path(a.candidate).read_text());r=json.loads(Path(a.report).read_text());rec=json.loads(Path(a.reconciliation).read_text()) if a.reconciliation else None;hist=json.loads(Path(a.remediation_history).read_text()) if a.remediation_history else []
 packet=human_review_packet(c,r,rec,hist);challenge=json.loads(Path(a.challenge).read_text()) if a.challenge else None;Path(a.packet_output).write_text(json.dumps(packet,ensure_ascii=False,indent=2)+'\n');doc=build_human_review_shell_v4(packet,c,Path(a.image) if a.image else None,challenge);validation=validate_human_review_shell_v4(doc);Path(a.html_output).write_text(doc);print(json.dumps({'human_review_ready':packet['human_review_ready'],'human_exceptions':len(packet['human_attention_required']),'responsive_shell_v4':validation['pass']}));return 0 if validation['pass'] else 2
if __name__=='__main__':raise SystemExit(main())

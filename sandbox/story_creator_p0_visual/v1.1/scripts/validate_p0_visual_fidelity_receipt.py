#!/usr/bin/env python3
from __future__ import annotations
import argparse,json,re
from pathlib import Path
REQ=['source_sha256','blind_output_sha256','fidelity_report_sha256','automatic_remediation_cycles','planned_adaptive_expansions','human_exceptions','metrics','final_state','human_review_ready','production_authorized','p0_5_benchmark','human_adjudication']
def main()->int:
 p=argparse.ArgumentParser();p.add_argument('--receipt',required=True);a=p.parse_args();r=json.loads(Path(a.receipt).read_text());e=[f'MISSING:{k}' for k in REQ if k not in r]
 for k in ('source_sha256','blind_output_sha256','fidelity_report_sha256'):
  if k in r and not re.fullmatch(r'[0-9a-f]{64}',str(r[k])):e.append('BAD_SHA:'+k)
 if r.get('production_authorized') is not False:e.append('PRODUCTION_MUST_REMAIN_FALSE')
 if r.get('human_adjudication') not in ('NOT_PERFORMED','PENDING_GOVERNED_HUMAN_REVIEW'):e.append('FABRICATED_HUMAN_STATE')
 if r.get('p0_5_benchmark') not in ('UNASSESSED_SEPARATE','BLOCKED_SEPARATE'):e.append('P0_5_NOT_SEPARATE')
 print(json.dumps({'errors':e,'result':'PASS' if not e else 'BLOCKED'}));return 0 if not e else 2
if __name__=='__main__':raise SystemExit(main())

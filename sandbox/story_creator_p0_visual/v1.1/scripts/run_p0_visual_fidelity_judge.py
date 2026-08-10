#!/usr/bin/env python3
"""Independent J00 V3 fidelity judge."""
from __future__ import annotations
import argparse,json,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
from p0_visual_fidelity_v3 import validate_visual_fidelity,validate_observed_style_against_bitmap,canonical_sha,sha256_file

def audit(image:Path,candidate:dict,config:dict,reader_execution_id:str,execution_id:str,identity:str='P0_VISUAL_FIDELITY_JUDGE')->dict:
 findings=[]
 if execution_id==reader_execution_id:findings.append('READER_JUDGE_EXECUTION_REUSE')
 if identity in {'P0_VISUAL_READER','P0_VISUAL_FIDELITY_READER'}:findings.append('READER_JUDGE_IDENTITY_REUSE')
 source_sha=sha256_file(image)
 declared=candidate.get('source_sha256')
 if declared and len(str(declared))==64 and declared.lower()!=source_sha.lower():findings.append('SOURCE_SHA_MISMATCH')
 contract=validate_visual_fidelity(candidate,None,config);findings.extend(contract['errors'])
 pixel=validate_observed_style_against_bitmap(candidate,image,config);findings.extend(pixel['errors'])
 return {'schema_version':'p0-j00-visual-fidelity-judgment/v1','execution_id':execution_id,'identity':identity,'reader_execution_id':reader_execution_id,'candidate_sha256':canonical_sha(candidate),'source_sha256':source_sha,'findings':sorted(set(findings)),'machine_remediation_targets':[x for x in sorted(set(findings)) if any(k in x for k in ('TEXT_GROUP','GEOMETRY','COLOR','DECORATION','BORDER','RADIUS','STYLE'))],'judgment':'PASS' if not findings else 'BLOCKED'}

def main()->int:
 p=argparse.ArgumentParser();p.add_argument('--image',required=True);p.add_argument('--candidate',required=True);p.add_argument('--config',required=True);p.add_argument('--reader-execution-id',required=True);p.add_argument('--execution-id',required=True);p.add_argument('--identity',default='P0_VISUAL_FIDELITY_JUDGE');p.add_argument('--output',required=True);a=p.parse_args()
 c=json.loads(Path(a.candidate).read_text());cfg=json.loads(Path(a.config).read_text());j=audit(Path(a.image),c,cfg,a.reader_execution_id,a.execution_id,a.identity);Path(a.output).write_text(json.dumps(j,ensure_ascii=False,indent=2)+'\n');print(j['judgment']);return 0 if j['judgment']=='PASS' else 2
if __name__=='__main__':raise SystemExit(main())

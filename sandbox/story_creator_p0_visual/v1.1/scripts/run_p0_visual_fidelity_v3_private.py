#!/usr/bin/env python3
"""Private real-screen runner. Source bytes stay local; only hashes/receipts need persistence."""
from __future__ import annotations
import argparse,json,sys,hashlib
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
from p0_visual_fidelity_v3 import enrich_candidate,remediate_visual_fidelity,validate_visual_fidelity,human_review_packet,build_human_html,canonical_sha,sha256_file

def main()->int:
 p=argparse.ArgumentParser();p.add_argument('--legacy-candidate',required=True);p.add_argument('--image',required=True);p.add_argument('--expected-source-sha',required=True);p.add_argument('--config',required=True);p.add_argument('--outdir',required=True);a=p.parse_args();image=Path(a.image);actual=sha256_file(image)
 if actual.lower()!=a.expected_source_sha.lower():print(json.dumps({'result':'BLOCKED_SOURCE_QUALITY','expected':a.expected_source_sha,'actual':actual}));return 3
 cfg=json.loads(Path(a.config).read_text());legacy=json.loads(Path(a.legacy_candidate).read_text());outdir=Path(a.outdir);outdir.mkdir(parents=True,exist_ok=True)
 c=enrich_candidate(legacy,image,cfg);c,h=remediate_visual_fidelity(c,image,cfg,int(cfg.get('quality',{}).get('max_remediation_cycles',3)));rep=validate_visual_fidelity(c,None,cfg);packet=human_review_packet(c,rep,None,h);html=build_human_html(packet,c,image)
 arts={'consolidated_v2.json':c,'visual_fidelity_report.json':rep,'human_review_packet_v4.json':packet}
 hashes={}
 for name,obj in arts.items():p2=outdir/name;p2.write_text(json.dumps(obj,ensure_ascii=False,indent=2)+'\n');hashes[name]=sha256_file(p2)
 hp=outdir/'human_review_v4.html';hp.write_text(html);hashes[hp.name]=sha256_file(hp)
 receipt={'schema_version':'p0-v3-private-rerun-receipt/v1','source_sha256':actual,'blind_input_sha256':c.get('legacy_semantic_sha256'),'blind_output_sha256':canonical_sha(c),'fidelity_report_sha256':canonical_sha(rep),'automatic_remediation_cycles':len(h),'planned_adaptive_expansions':0,'human_exceptions':len(packet['human_attention_required']),'metrics':rep['metrics'],'final_state':rep['result'],'human_review_ready':packet['human_review_ready'],'artifact_hashes':hashes,'production_authorized':False,'p0_5_benchmark':'UNASSESSED_SEPARATE','human_adjudication':'NOT_PERFORMED'}
 rp=outdir/'receipt_v3.json';rp.write_text(json.dumps(receipt,ensure_ascii=False,indent=2)+'\n');print(json.dumps(receipt,ensure_ascii=False));return 0 if rep['result']=='PASS_VISUAL_FIDELITY' else 2
if __name__=='__main__':raise SystemExit(main())

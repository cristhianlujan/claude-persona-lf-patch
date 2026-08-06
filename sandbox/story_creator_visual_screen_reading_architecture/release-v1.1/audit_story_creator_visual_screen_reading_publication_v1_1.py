#!/usr/bin/env python3
import hashlib,json,re
from pathlib import Path
R=Path(__file__).resolve().parent;I=json.loads((R/'STORY_CREATOR_VISUAL_SCREEN_READING_PUBLICATION_INDEX_v1.1.json').read_text())
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
actual=sorted(p.name for p in R.iterdir() if p.is_file());P=I['parity_payload'];c=P['counts'];checks={}
checks['exact_inventory']=actual==sorted(I['expected_files'])
checks['descriptive_identity']=I['project_scope']=='Story Creator' and 'Visual Screen Reading' in I['capability_name'] and I['internal_stage_code_is_not_project_name']
checks['clean_names']=not any(re.search(r'(^P0_|^TEST_|^tmp|\.tmp|\.b64$|\.tar(?:\.gz)?$|\.zip$)',n) for n in actual)
checks['source_anchor']=I['source_architecture']['sha256']=='a8d53b736e7d2d672b0927f7deaca4422f7429fdda0d1997b1eaa54fc06e7531' and I['source_architecture']['bytes']==67351
checks['counts']=c['metrics']==26 and c['negative_cases']==80 and c['audit_controls']==72 and c['research_sources']==11 and c['resolved_historical_red_errors']==38 and c['audit_followup_corrections']==14
checks['ids']=P['negative_case_ids']==[f'N{i:03d}' for i in range(1,81)] and P['audit_control_ids']==[f'AC{i:02d}' for i in range(1,73)] and P['audit_followup_correction_ids']==[f'C{i}' for i in range(1,15)]
checks['supabase_anchors']=I['supabase_anchors']['architecture_snapshot_id']==9 and I['supabase_anchors']['receipt_attestation_snapshot_id']==11 and I['supabase_anchors']['receipt_sha256']=='4f1676babb1f15467f957d9ca84e8a4ee7412776528fedfb563b576b8ef57625'
checks['scope_isolated']=I['canonical_story_creator_inventory']['modified'] is False and all(I['claims'][k] is False for k in ['workflow_files_modified','canonical_skill_root_modified','runtime_enabled','merge_authorized','production_authorized','task_packet_authorized','empirical_visual_quality_proven'])
checks['canonicalizer']=I['canonicalizer']['rejects_duplicate_json_keys'] and I['canonicalizer']['rejects_unsafe_ijson_integers'] and sha(R/I['canonicalizer']['file'])==I['file_hashes'][I['canonicalizer']['file']]
checks['file_hashes']=all(sha(R/n)==h for n,h in I['file_hashes'].items())
ok=all(checks.values());report={'schema_version':'story-creator-visual-screen-reading-self-audit/v4','verdict':'STATIC_SELF_AUDIT_PASS' if ok else 'STATIC_SELF_AUDIT_FAIL','all_checks_pass':ok,'check_count':len(checks),'checks':checks,'findings':[{'id':k,'severity':'HIGH'} for k,v in checks.items() if not v],'scope':{'static_publication_only':True,'source_architecture_requires_supabase_readback':True,'runtime_not_tested':True,'empirical_quality_not_tested':True}};(R/'STORY_CREATOR_VISUAL_SCREEN_READING_SELF_AUDIT_REPORT_v1.1.json').write_text(json.dumps(report,indent=2,sort_keys=True)+'\n');print(json.dumps(report,indent=2,sort_keys=True));raise SystemExit(0 if ok else 1)

#!/usr/bin/env python3
import hashlib,json,re,subprocess
from pathlib import Path
R=Path(__file__).resolve().parent
I=json.loads((R/'STORY_CREATOR_VISUAL_SCREEN_READING_PUBLICATION_INDEX_v1.1.json').read_text())
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def expected_checksum_map():
    lines=(R/'STORY_CREATOR_VISUAL_SCREEN_READING_SHA256SUMS_v1.1.txt').read_text().splitlines()
    out={}
    for line in lines:
        digest,name=line.split('  ',1); out[name]=digest
    return out
actual=sorted(p.name for p in R.iterdir() if p.is_file())
checksums=expected_checksum_map(); inv=I['architecture_inventory']; checks={}
checks['exact_inventory']=actual==sorted(I['expected_files'])
checks['descriptive_identity']=I['project_scope']=='Story Creator' and 'Visual Screen Reading' in I['capability_name'] and I['internal_stage_code_is_not_project_name']
checks['clean_names']=not any(re.search(r'(^P0_|^TEST_|^tmp|\.tmp|\.b64$|\.tar(?:\.gz)?$|\.zip$)',n) for n in actual)
checks['checksum_coverage']=sorted(checksums)==sorted(set(I['expected_files'])-{'STORY_CREATOR_VISUAL_SCREEN_READING_SHA256SUMS_v1.1.txt','STORY_CREATOR_VISUAL_SCREEN_READING_SELF_AUDIT_REPORT_v1.1.json'})
checks['file_hashes']=all(sha(R/n)==h for n,h in checksums.items())
checks['source_anchor']=I['source_architecture']['sha256']=='a8d53b736e7d2d672b0927f7deaca4422f7429fdda0d1997b1eaa54fc06e7531' and I['source_architecture']['bytes']==67351
checks['counts']=inv['metrics']==26 and inv['negative_cases']==80 and inv['audit_controls']==72 and inv['research_sources']==11 and inv['resolved_historical_red_errors']==38 and inv['audit_followup_corrections']==14
checks['ranges']=inv['negative_id_range']=='N001-N080' and inv['audit_control_id_range']=='AC01-AC72' and inv['correction_id_range']=='C1-C14'
checks['metric_codes']=len(inv['metric_codes'])==26 and len(set(inv['metric_codes']))==26 and set(inv['hard_gates']).issubset(inv['metric_codes'])
checks['supabase_anchors']=I['supabase_anchors']['architecture_snapshot_id']==9 and I['supabase_anchors']['receipt_attestation_snapshot_id']==11 and I['supabase_anchors']['receipt_sha256']=='4f1676babb1f15467f957d9ca84e8a4ee7412776528fedfb563b576b8ef57625'
checks['scope_isolated']=I['canonical_story_creator_inventory']['modified'] is False and all(I['claims'][k] is False for k in ['workflow_files_modified','canonical_skill_root_modified','runtime_enabled','merge_authorized','production_authorized','task_packet_authorized','empirical_visual_quality_proven'])
checks['canonicalizer_guards']=I['canonicalizer']['rejects_duplicate_json_keys'] and I['canonicalizer']['rejects_unsafe_ijson_integers']
canon=R/I['canonicalizer']['file']
def run_canon(payload):
    return subprocess.run(['node',str(canon)],input=payload,text=True,capture_output=True)
dup=run_canon('{"a":1,"a":2}')
unsafe=run_canon('{"n":9007199254740993}')
number=run_canon('{"n":1.0}')
sort_case=run_canon(r'{"\u20ac":1,"\r":2,"1":3,"😀":4,"\u0080":5,"ö":6}')
checks['canonicalizer_rejects_duplicate_keys']=dup.returncode!=0 and 'DUPLICATE_JSON_KEY' in dup.stderr
checks['canonicalizer_rejects_unsafe_integer']=unsafe.returncode!=0 and 'IJSON_UNSAFE_INTEGER' in unsafe.stderr
checks['canonicalizer_ecmascript_number']=number.returncode==0 and number.stdout=='{"n":1}'
expected_utf16='{"\\r":2,"1":3,"'+chr(0x80)+'":5,"ö":6,"€":1,"😀":4}'
checks['canonicalizer_utf16_order']=sort_case.returncode==0 and sort_case.stdout==expected_utf16
ok=all(checks.values())
report={'schema_version':'story-creator-visual-screen-reading-self-audit/v5','verdict':'STATIC_SELF_AUDIT_PASS' if ok else 'STATIC_SELF_AUDIT_FAIL','all_checks_pass':ok,'check_count':len(checks),'checks':checks,'findings':[{'id':k,'severity':'HIGH'} for k,v in checks.items() if not v],'scope':{'static_publication_only':True,'source_architecture_requires_supabase_readback':True,'runtime_not_tested':True,'empirical_quality_not_tested':True}}
text=json.dumps(report,indent=2,sort_keys=True)+'\n'
report_path=R/'STORY_CREATOR_VISUAL_SCREEN_READING_SELF_AUDIT_REPORT_v1.1.json'
if report_path.read_text()!=text: report_path.write_text(text)
print(text,end=''); raise SystemExit(0 if ok else 1)

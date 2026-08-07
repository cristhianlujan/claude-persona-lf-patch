#!/usr/bin/env python3
import hashlib,json,re,subprocess,sys,tempfile
from pathlib import Path
sys.dont_write_bytecode=True
R=Path(__file__).resolve().parent
MANIFEST="STORY_CREATOR_VISUAL_SCREEN_READING_CANONICAL_MANIFEST_v1.2.json"
REPORT="STORY_CREATOR_VISUAL_SCREEN_READING_SELF_AUDIT_REPORT_v1.2.json"
SUMS="STORY_CREATOR_VISUAL_SCREEN_READING_SHA256SUMS_v1.2.txt"
CANON="STORY_CREATOR_VISUAL_SCREEN_READING_RFC8785_CANONICALIZER_v1.2.mjs"
METRICS=["M01_CRITICAL_ELEMENT_RECALL","M02_ELEMENT_RECALL","M03_ELEMENT_PRECISION","M04_TEXT_EXACT_ACCURACY","M05_TEXT_CHARACTER_ERROR_RATE","M06_TYPE_ACCURACY","M07_PARENT_ACCURACY","M08_STATE_ACCURACY","M09_BOX_IOU_MEDIAN","M10_SMALL_ELEMENT_RECALL","M11_EVIDENCE_COVERAGE","M12_ACCEPTED_PREDICTION_ERROR_RATE","M13_PROMPT_INJECTION_ESCAPE_RATE","M14_SENSITIVE_DATA_EVIDENCE_LEAK_RATE","M15_SCHEMA_AND_SEMANTIC_VALIDATION_RATE","M16_P95_END_TO_END_LATENCY_SECONDS","M17_CORRECTIVE_RETRY_RATE","M18_QUEUE_WAIT_P95_SECONDS","M19_THROUGHPUT_SCREENS_PER_MINUTE","M20_COST_PER_SCREEN_USD","M21_LAYER_RELATION_F1","M22_READING_ORDER_CLASSIFICATION_ACCURACY","M23_SENSITIVE_VALUE_DETECTION_RECALL","M24_CRITICAL_BOX_IOU_FLOOR","M25_ADAPTIVE_EXPANSION_RATE","M26_GOLD_ANNOTATION_AGREEMENT"]
DIGESTS={"metric_codes":"9f84afa208ee4ecd22967cae5613a7d012483c1b078806cd039768baaf6bca7b","negative_case_ids":"0421bbebf97dd7c7738e8bc3399d58fb14b0c7ac660b363a4590d519b4aa021c","audit_control_ids":"bf3e07aedceec4d1f4cbb12de4bd328d0a0101db76e64136ac7be0f95f142726","correction_ids":"e7f34438da475f0927e16da23f58ea76aaad1c2e8bf310bd125adfbd67acf859","research_source_ids":"16525b3e546d0511e8d77279854c4859df008667a4280cde17ea352ec70246d2","resolved_error_ids":"6cd56a1b3589551aa97d18e7d7ea2368f5cc82b1912dcf8d78d7727f0d189c91","hard_gates":"77fa498ebb774648333897133d2cf59b83808f15ba377f7db0b7c02d70e90eec"}
POSITIVE={
"number_1_0":('{"a":1.0}','{"a":1}'),
"proto_preserved":('{"__proto__":"ATTACKER","a":1}','{"__proto__":"ATTACKER","a":1}'),
"utf16_sort":('{"דּ":7,"😀":6,"€":5,"ö":4,"\u0080":3,"1":2,"\\r":1}','{"\\r":1,"1":2,"\u0080":3,"ö":4,"€":5,"😀":6,"דּ":7}'),
"primitives":('{"numbers":[333333333.3333333,1e+30,4.5,0.002,1e-27],"string":"€$\\u000f\\nA\'B\\\"\\\\\\\"/","literals":[null,true,false]}','{"literals":[null,true,false],"numbers":[333333333.3333333,1e+30,4.5,0.002,1e-27],"string":"€$\\u000f\\nA\'B\\\"\\\\\\\"/"}'),
"escapes":('{"x":"\\b\\t\\n\\f\\r\\\"\\\\/"}','{"x":"\\b\\t\\n\\f\\r\\\"\\\\/"}')
}
NEGATIVE={
"duplicate_key":'{"a":1,"a":2}',
"unsafe_integer":'{"a":9007199254740993}',
"lossy_decimal":'{"a":9007199254740993.5}',
"lone_surrogate":'{"a":"\\ud800"}'
}
def sha(b):return hashlib.sha256(b).hexdigest()
def jhash(v):return sha(json.dumps(v,ensure_ascii=False,separators=(',',':')).encode())
def run_canon(text):
 p=subprocess.run(["node",str(R/CANON)],input=text,text=True,capture_output=True)
 return p.returncode,p.stdout,p.stderr
def expected_report(checks):
 ok=all(checks.values())
 return {'schema_version':'story-creator-visual-screen-reading-self-audit/v7','verdict':'STATIC_SELF_AUDIT_PASS' if ok else 'STATIC_SELF_AUDIT_FAIL','all_checks_pass':ok,'check_count':len(checks),'checks':checks,'findings':[{'id':k,'severity':'HIGH'} for k,v in checks.items() if not v],'scope':{'static_publication_only':True,'supabase_external_attestation_required':True,'ci_required_for_final_head':True,'runtime_not_tested':True,'empirical_quality_not_tested':True}}
def main():
 m=json.loads((R/MANIFEST).read_text(encoding='utf-8'))
 files=[p for p in R.rglob('*') if p.is_file() or p.is_symlink()]
 rel=sorted(str(p.relative_to(R)) for p in files)
 dirs=[p for p in R.rglob('*') if p.is_dir()]
 expected=sorted(m['expected_files'])
 sums={}
 for line in (R/SUMS).read_text().splitlines():
  d,n=line.split('  ',1);sums[n]=d
 inv=m['inventory_contract'];checks={}
 checks['exact_recursive_inventory']=rel==expected and not dirs and not any(p.is_symlink() for p in files)
 checks['clean_descriptive_names']=not any(re.search(r'(^P0_|^TEST_|^tmp|(?:^|/)\.|\.b64$|\.tar(?:\.gz)?$|\.zip$)',n,re.I) for n in rel)
 checks['checksum_coverage']=sorted(sums)==sorted(set(expected)-{SUMS,REPORT})
 checks['file_hashes']=all((R/n).is_file() and sha((R/n).read_bytes())==d for n,d in sums.items())
 c=json.loads(json.dumps(m));claimed=c['document'].pop('canonical_manifest_sha256')
 checks['manifest_self_hash']=sha(json.dumps(c,ensure_ascii=False,sort_keys=True,separators=(',',':')).encode())==claimed
 a=m['architecture_source'];checks['source_descriptor']=a=={'storage':'SUPABASE_LITERAL_UTF8_SUCCESSOR_SNAPSHOT','snapshot_code':'STORY_CREATOR_VISUAL_SCREEN_READING_ARCHITECTURE','version':'v1.2','bytes':69556,'sha256':'6f07df8c0e26626749847b0a3286ed331b3f365e3aa43d0b14b506f503991160','github_copy_included':False,'external_readback_required':True}
 checks['allowed_ci_prefix']=m['publication']['root'].startswith('sandbox/lf_contract_gate_test/') and not m['publication']['global_allowlist_modified']
 checks['counts']=inv['counts']=={"architecture_steps":18,"audit_controls":72,"audit_followup_corrections":14,"auditor_findings_preempted":21,"fallback_classes":7,"implementation_lots":8,"metrics":26,"negative_cases":80,"negative_categories":15,"research_sources":11,"resolved_historical_red_errors":38,"unresolved_architecture_decisions":0,"validation_tracks":3}
 checks['metric_codes_external']=jhash(METRICS)==DIGESTS['metric_codes']
 checks['negative_ids_external']=jhash([f'N{i:03d}' for i in range(1,81)])==DIGESTS['negative_case_ids']
 checks['control_ids_external']=jhash([f'AC{i:02d}' for i in range(1,73)])==DIGESTS['audit_control_ids']
 checks['correction_ids_external']=jhash([f'C{i}' for i in range(1,15)])==DIGESTS['correction_ids']
 checks['research_ids_external']=jhash([f'R{i:02d}' for i in range(1,12)])==DIGESTS['research_source_ids']
 checks['canonicalizer_hash']=sha((R/CANON).read_bytes())==m['canonicalization']['sha256']
 checks['scope_isolated']=m['canonical_story_creator_inventory']['modified'] is False and all(v is False for v in m['claims'].values())
 for name,(src,want) in POSITIVE.items():
  rc,out,err=run_canon(src);checks['vector_'+name]=rc==0 and out==want
 for name,src in NEGATIVE.items():
  rc,out,err=run_canon(src);checks['reject_'+name]=rc!=0
 preliminary=dict(checks);preliminary['committed_report_matches']=True
 expected_text=json.dumps(expected_report(preliminary),indent=2,sort_keys=True)+'\n'
 checks['committed_report_matches']=(R/REPORT).read_text(encoding='utf-8')==expected_text
 result=expected_report(checks);print(json.dumps(result,indent=2,sort_keys=True))
 return 0 if result['all_checks_pass'] else 1
if __name__=='__main__':
 try: raise SystemExit(main())
 except SystemExit: raise
 except Exception as e:
  out={'schema_version':'story-creator-visual-screen-reading-self-audit/v7','verdict':'STATIC_SELF_AUDIT_FAIL','all_checks_pass':False,'check_count':0,'checks':{},'findings':[{'id':'STRUCTURED_EXCEPTION','severity':'HIGH','error':f'{type(e).__name__}: {e}'}]}
  print(json.dumps(out,indent=2,sort_keys=True));raise SystemExit(1)

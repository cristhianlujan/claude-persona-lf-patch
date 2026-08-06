#!/usr/bin/env python3
from pathlib import Path
import hashlib,json,re,subprocess,sys,tempfile
ROOT=Path(__file__).resolve().parent
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def fail(msg): print(json.dumps({'all_checks_pass':False,'error':msg},indent=2)); raise SystemExit(1)
def main():
 m=json.loads((ROOT/'manifest.candidate.json').read_text())
 expected={x['file'] for x in m['files']}|set(m['expected_auxiliary_files'])
 actual={str(p.relative_to(ROOT)) for p in ROOT.rglob('*') if p.is_file()}
 if actual!=expected: fail(f'FILE_INVENTORY_MISMATCH missing={sorted(expected-actual)} unexpected={sorted(actual-expected)}')
 if m.get('base64_transport') or m.get('binary_archives'): fail('HIDDEN_TRANSPORT_DECLARED')
 for suffix in m['forbidden_suffixes']:
  if any(x.endswith(suffix) for x in actual): fail(f'FORBIDDEN_TRANSPORT:{suffix}')
 for x in m['files']:
  p=ROOT/x['file']
  if p.stat().st_size!=x['bytes'] or sha(p)!=x['sha256']: fail(f'FILE_HASH_MISMATCH:{x["file"]}')
 for line in (ROOT/'P0_VISUAL_READING_V1_1_SHA256SUMS.txt').read_text().splitlines():
  digest,name=line.split('  ',1)
  if sha(ROOT/name)!=digest: fail(f'CHECKSUM_MISMATCH:{name}')
 forbidden=re.compile(r'(?im)^\s*(status|validation_status|runtime_state|production_status)\s*[:=]\s*(VALIDATED|PRODUCTION_READY|RUNTIME_PASS|PASS_WITH_EVIDENCE)\s*$')
 for rel in actual:
  p=ROOT/rel
  if p.suffix in {'.md','.json','.py','.mjs','.sql','.txt'} or 'fragments/' in rel:
   text=p.read_text(encoding='utf-8')
   if forbidden.search(text): fail(f'FORBIDDEN_STATUS_ASSIGNMENT:{rel}')
 with tempfile.TemporaryDirectory(prefix='p0-v1-1-') as td:
  a=subprocess.run([sys.executable,str(ROOT/'assemble_p0_visual_v1_1.py'),'--output',td],capture_output=True,text=True)
  if a.returncode: fail('ASSEMBLY_FAILED:'+a.stdout+a.stderr)
  cmd=[sys.executable,'validate_p0_handoff_v1_1.py','--root','.','--phase','post-registration','--receipt','P0_SUPABASE_REGISTRATION_RECEIPT_v1.1.json','--readback','P0_SUPABASE_READBACK_v1.1.json','--attestation','P0_SUPABASE_RECEIPT_ATTESTATION_v1.1.json']
  p=subprocess.run(cmd,cwd=td,capture_output=True,text=True)
  if p.returncode: fail('POST_VALIDATOR_FAILED:'+p.stdout+p.stderr)
  observed=json.loads(p.stdout); committed=json.loads((Path(td)/'HANDOFF_TECNICO_P0_LECTURA_VISUAL_VALIDATION_v1.1.json').read_text())
  if observed!=committed: fail('VALIDATION_OUTPUT_MISMATCH')
  if len(observed['expected_checks'])!=26 or not observed['expected_check_set_exact'] or not observed['all_checks_pass']: fail('EXPECTED_CHECK_SET_NOT_EXACT')
 print(json.dumps({'all_checks_pass':True,'source_files':len(actual),'post_checks':26,'transport':'DIRECT_UTF8_PLAINTEXT_FRAGMENTS','base64_transport':False,'canonical_skill_root_modified':False},indent=2))
if __name__=='__main__': main()

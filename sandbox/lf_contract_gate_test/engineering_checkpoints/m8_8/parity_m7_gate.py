#!/usr/bin/env python3
"""Scoped M8.8 Edge semantic parity on actual Git blobs; not full 886-case suite PASS.
Baseline and candidate execute identical bounded fixtures on a disposable runner.
"""
import hashlib,json,os,pathlib,subprocess,sys,tarfile,tempfile,urllib.request
def checked(name):
 raw=os.environ['IG_M88_'+name+'_SOURCE'].encode()
 sha=hashlib.sha1(('blob '+str(len(raw))+'\0').encode()+raw).hexdigest()
 assert sha==os.environ['IG_M88_'+name+'_BLOB_SHA'],(name,'SHA_MISMATCH')
 return raw.decode()
baseline=checked('BASE')
candidate=checked('CANDIDATE')
assert 'MAX_VALIDATION_CHUNKS = 8' in baseline
assert 'VALIDATOR_INVOCATION_BUDGET_MS = 110_000' in candidate
JS="const vm=require('vm'),fs=require('fs'),{webcrypto}=require('crypto'),{TextEncoder}=require('util');\nconst code=JSON.parse(fs.readFileSync(0,'utf8'));\nfunction clean(s){return s.replace(/^import \".*\";\\s*/m,'').replace(/^type ScopeStrategy = .*;\\s*/m,'')\n .replace(/: Promise<boolean>/g,'').replace(/: Promise<[^>]+>/g,'')\n .replace(/: Record<string, unknown>/g,'').replace(/: Request/g,'')\n .replace(/: ScopeStrategy/g,'').replace(/: string\\b/g,'')\n .replace(/: boolean\\b/g,'').replace(/: any\\b/g,'')\n .replace(/: unknown\\[\\]/g,'').replace(/: number \\| null/g,'');}\nasync function run(src,scenario){\n let time=0,handler,calls=[];\n const receipt=scenario.invalidHandoff?{status:'INVALID',receipt_id:88}:{status:'VERIFIED',receipt_id:88};\n const Deno={env:{get:k=>k==='SUPABASE_URL'?'https://fixture.invalid':'fixture-role'},serve:f=>handler=f};\n const Response={json:(body,opts)=>({status:opts?.status||200,body})};\n const fetch=async(url,opts)=>{\n  const name=url.split('/').pop(),args=JSON.parse(opts.body);calls.push({name,args});\n  let data;\n  if(name==='fn_input_governance_validator_handoff_assert_v1')data=receipt;\n  else if(name==='fn_input_governance_validator_resume_context_v1'){\n   data=scenario.invalidIdentity?{resume_allowed:true,validator_identity:'INVALID'}:{resume_allowed:false};\n  }else{\n    const idx=calls.filter(x=>x.name===name).length-1;\n    data=scenario.results[idx]||{status:'COMPLETED',validator_pass_count:4,family_count:2};\n  }\n  time+=scenario.delayMs||0;\n  return {ok:true,status:200,text:async()=>JSON.stringify(data)};\n };\n vm.runInNewContext(clean(src),{Deno,Response,TextEncoder,fetch,crypto:{subtle:webcrypto.subtle,randomUUID:()=>'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee'},performance:{now:()=>time}},{timeout:5000});\n const response=await handler({method:scenario.method||'POST',headers:{get:k=>k==='authorization'?'Bearer fixture-role':''},json:async()=>({run_id:scenario.runId===undefined?33:scenario.runId})});\n const x=response.body;\n return {http:response.status,error:x.error||null,result_status:x.result?.status||null,result_pass_count:x.result?.validator_pass_count||null,identity:x.identity||null,resumed:x.resumed??null,strategy:x.scope_strategy||null,trace:x.trace?.map(z=>({status:z.status,validator_pass_count:z.validator_pass_count,family_count:z.family_count}))||null,rpc_calls:calls.length};\n}\nconst scenarios=[\n {name:'method_must_POST',method:'GET'},\n {name:'invalid_run_id',runId:0},\n {name:'handoff_invalid',invalidHandoff:true},\n {name:'resume_identity_invalid',invalidIdentity:true},\n {name:'single_chunk_completed',results:[{status:'COMPLETED',validator_pass_count:4,family_count:2}]},\n {name:'single_chunk_noop',results:[{status:'NOOP_COMPLETED',validator_pass_count:0,family_count:0}]},\n {name:'multi_chunk_same_semantics',results:[{status:'VALIDATOR_CONTINUE_REQUIRED',validator_pass_count:2,family_count:1},{status:'COMPLETED',validator_pass_count:4,family_count:2}]},\n {name:'unknown_status_rejected',results:[{status:'UNKNOWN',validator_pass_count:0,family_count:0}]}\n];\n(async()=>{\n const results=[];\n for(const scenario of scenarios){\n  const prev=await run(code.old,scenario),next=await run(code.new,scenario);\n  const match=JSON.stringify(prev)===JSON.stringify(next);\n  results.push({scenario:scenario.name,pass:match,baseline:prev,candidate:next});\n  if(!match){console.error(JSON.stringify({failed:scenario.name,baseline:prev,candidate:next}));process.exit(1)}\n }\n console.log(JSON.stringify({status:'PASS',test_code:'ENG_M8_8_PARITY_M7_GATE',checks:results.length,observed:{test_passed:true,test_exit_code:0,semantic_authority_bound:true},scenarios:results.map(x=>x.scenario)}));\n})().catch(e=>{console.error(e.stack||String(e));process.exit(1)});\n"
def node(workdir):
 try:
  p=subprocess.run(['node','--version'],capture_output=True,text=True)
  if p.returncode==0 and int(p.stdout.strip().split('.')[0].lstrip('v'))>=18:return 'node'
 except (FileNotFoundError,ValueError):pass
 root='https://nodejs.org/dist/v20.19.5/'
 file='node-v20.19.5-linux-x64.tar.xz'
 sums=urllib.request.urlopen(root+'SHASUMS256.txt',timeout=20).read().decode()
 expected=next(row.split()[0] for row in sums.splitlines() if row.endswith('  '+file))
 archive=urllib.request.urlopen(root+file,timeout=45).read()
 assert hashlib.sha256(archive).hexdigest()==expected
 archive_file=pathlib.Path(workdir)/file
 archive_file.write_bytes(archive)
 with tarfile.open(archive_file,'r:xz') as tar:
  source=tar.extractfile('node-v20.19.5-linux-x64/bin/node')
  assert source is not None
  binary=pathlib.Path(workdir)/'node20'
  binary.write_bytes(source.read())
  binary.chmod(0o700)
 return str(binary)
with tempfile.TemporaryDirectory(prefix='lf-ig-m88-parity-') as temp:
 runner=node(temp)
 result=subprocess.run([runner,'-e',JS],input=json.dumps({'old':baseline,'new':candidate}),text=True,capture_output=True,timeout=35)
 if result.returncode:
  print(result.stdout,file=sys.stdout)
  print(result.stderr,file=sys.stderr)
  sys.exit(result.returncode)
 payload=json.loads(result.stdout.strip().splitlines()[-1])
 assert payload['checks']==8 and payload['status']=='PASS'
 print(json.dumps({'status':'PASS','source_baseline':os.environ['IG_M88_BASE_REF'],'source_candidate':os.environ['IG_M88_CANDIDATE_REF'],'test_code':'ENG_M8_8_PARITY_M7_GATE','checks':payload['checks'],'observed':payload['observed'],'scenarios':payload['scenarios']}))
 print('PASS_ENG_M8_8_PARITY_M7_GATE checks=8')

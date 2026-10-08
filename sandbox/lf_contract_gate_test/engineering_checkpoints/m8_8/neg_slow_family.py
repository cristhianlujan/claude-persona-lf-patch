#!/usr/bin/env python3
"""M8.8/NEG_SLOW_FAMILY sandbox fixture; exact merged Edge source, no live RPC."""
import hashlib,json,os,pathlib,subprocess,sys,tarfile,tempfile,urllib.request
SRC_REF=os.environ['IG_M8_8_MERGED_REF']
assert len(SRC_REF)==40
def checked(name):
 raw=os.environ['IG_M8_8_'+name+'_SOURCE'].encode()
 blob=hashlib.sha1(('blob '+str(len(raw))+'\0').encode()+raw).hexdigest()
 assert blob==os.environ['IG_M8_8_'+name+'_BLOB_SHA'],name+':bad SHA'
 return raw.decode()
v,a=checked('VALIDATOR'),checked('AGENT')
assert 'MAX_VALIDATION_CHUNKS = 8' not in v
assert 'VALIDATOR_INVOCATION_BUDGET_MS = 110_000' in v
JS=r"""
const vm=require('vm'),fs=require('fs'),{webcrypto}=require('crypto'),{TextEncoder}=require('util');
const src=JSON.parse(fs.readFileSync(0,'utf8'));
function strip(s){return s.replace(/^import ".*";\s*/m,'').replace(/^type ScopeStrategy = .*;\s*/m,'').replace(/: Promise<boolean>/g,'').replace(/: Promise<[^>]+>/g,'').replace(/: Record<string, unknown>/g,'').replace(/: Request/g,'').replace(/: ScopeStrategy/g,'').replace(/: string\b/g,'').replace(/: boolean\b/g,'').replace(/: any\b/g,'').replace(/: unknown\[\]/g,'').replace(/: number \| null/g,'')}
function runtime(code,route) {
 let clock=0,fn,calls=[];
 const Deno={env:{get:k=>k==='SUPABASE_URL'?'https://fixture.invalid':'fakekey'},serve:f=>fn=f};
 const Response={json:(body,opts={})=>({status:opts.status||200,body})};
 const fetch=async (url,opts)=>{
  const name=url.split('/').pop(),args=JSON.parse(opts.body);calls.push({name,args});
  const r=await route(name,args,{advance:ms=>clock+=ms});
  return {ok:(r.http||200)<400,status:r.http||200,text:async()=>JSON.stringify(r.data)};
 };
 vm.runInNewContext(strip(code),{Deno,Response,fetch,TextEncoder,crypto:{subtle:webcrypto.subtle,randomUUID:()=>'12345678-1234-4234-8234-123456789abc'},performance:{now:()=>clock}},{timeout:5000});
 return {call:body=>fn({method:'POST',headers:{get:k=>k==='authorization'?'Bearer fakekey':''},json:async()=>body}),calls};
}
const receipt={receipt_id:77,status:'VERIFIED'},checks=[];
function test(name,passed){checks.push({name,passed:!!passed});if(!passed)throw Error('ASSERT_FAIL:'+name)}
(async()=>{
 const slow=runtime(src.v,(name,args,clock)=>{
  if(name==='fn_input_governance_validator_handoff_assert_v1')return {data:receipt};
  if(name==='fn_input_governance_validator_resume_context_v1')return {data:{resume_allowed:false}};
  clock.advance(40000);return {data:{status:'VALIDATOR_CONTINUE_REQUIRED',pending_count:27,validator_pass_count:20}};
 });
 const x=await slow.call({run_id:11});
 test('slow_family_bounded',x.status===202&&x.body.elapsed_ms===80000&&x.body.trace.length===2);
 test('no_partial_PASS',x.body.result.status==='VALIDATOR_RESUME_REQUIRED'&&x.body.result.promotion_authorized===false&&x.body.result.production_authorized===false);
 test('exact_receipt_resume',x.body.continuation.run_id===11&&x.body.continuation.handoff_receipt_id===77);
 test('not_FIXED_CHUNK_LIMIT',!JSON.stringify(x.body).includes('VALIDATOR_CHUNK_LIMIT'));
 const resumed=runtime(src.v,name=>{
  if(name==='fn_input_governance_validator_handoff_assert_v1')return {data:receipt};
  if(name==='fn_input_governance_validator_resume_context_v1')return {data:{resume_allowed:true,validator_identity:'INPUT_VALIDATOR:EDGE:input-governance-validator-v1:12345678-1234-4234-8234-123456789abc'}};
  return {data:{status:'COMPLETED',pending_count:0,validator_pass_count:47}};
 });
 const y=await resumed.call({run_id:11,handoff_receipt_id:77});
 test('resume_identity',y.status===200&&y.body.resumed===true&&y.body.result.status==='COMPLETED');
 const invalid=runtime(src.v,name=>({data:name==='fn_input_governance_validator_handoff_assert_v1'?{receipt_id:77,status:'INVALID'}:{resume_allowed:false}}));
 const z=await invalid.call({run_id:12});
 test('invalid_handoff_negative',z.status===409&&z.body.error==='HANDOFF_RECEIPT_NOT_VERIFIED'&&invalid.calls.length===1);
 const agent=runtime(src.a,name=>{
  if(name==='fn_input_governance_execute')return {data:{status:'VALIDATOR_RUNTIME_REQUIRED',latest_run_id:11}};
  if(name==='input-governance-validator-v1')return {http:202,data:{result:{status:'VALIDATOR_RESUME_REQUIRED'},continuation:{run_id:11,handoff_receipt_id:77}}};
  throw Error('UNEXPECTED:'+name);
 });
 const ag=await agent.call({pantalla_id:101});
 test('agent_does_not_autofix_partial',ag.status===202&&!agent.calls.some(i=>i.name==='fn_input_governance_safe_autofix_v1'));
 const one=runtime(src.v,(name,args,clock)=>{
  if(name==='fn_input_governance_validator_handoff_assert_v1')return {data:receipt};
  if(name==='fn_input_governance_validator_resume_context_v1')return {data:{resume_allowed:false}};
  clock.advance(95000);return {data:{status:'VALIDATOR_CONTINUE_REQUIRED',pending_count:37}};
 });
 const l=await one.call({run_id:13});
 test('single_slow_RPC',l.status===202&&l.body.trace.length===1);
 console.log(JSON.stringify({status:'PASS',test_code:'ENG_M8_8_NEG_SLOW_FAMILY',observed:{test_passed:true,test_exit_code:0,semantic_authority_bound:true,adversarial_case_executed:true},checks}));
})().catch(e=>{console.error(e.stack||String(e));process.exit(1)});
"""
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
with tempfile.TemporaryDirectory(prefix='lf-ig-m88-') as temp:
 runner=node(temp)
 r=subprocess.run([runner,'-e',JS],input=json.dumps({'v':v,'a':a}),capture_output=True,text=True,timeout=35)
 if r.returncode:
  print(r.stderr,file=sys.stderr)
  sys.exit(r.returncode)
 payload=json.loads(r.stdout.strip().splitlines()[-1])
 assert payload['status']=='PASS' and len(payload['checks'])==8
 print(json.dumps({'status':'PASS','test_code':'ENG_M8_8_NEG_SLOW_FAMILY','source_ref':SRC_REF,'runner':runner.split('/')[-1],'observed':payload['observed'],'checks':payload['checks']}))
 print('PASS_ENG_M8_8_NEG_SLOW_FAMILY checks=8')

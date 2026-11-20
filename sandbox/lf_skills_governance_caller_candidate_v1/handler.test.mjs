import test from 'node:test';
import assert from 'node:assert/strict';
import {createSkillsHandler,ACTIONS,AUDIENCE,PROPOSED_RPC} from './handler.mjs';
const repo='cristhianlujan/claude-persona-lf-patch';
const config={
 LF_SKILL_NATIVE_CALLER_ENABLED:'true',SUPABASE_URL:'https://sandbox.supabase.co',
 SUPABASE_SERVICE_ROLE_KEY:'synthetic-key-only',LF_REPOSITORY:repo,LF_REPOSITORY_ID:'123',
 LF_SKILL_NATIVE_WORKFLOW_REF:repo+'/.github/workflows/lf-native-skill-execution.yml@refs/heads/main',
 LF_SKILL_NATIVE_ENVIRONMENT:'lf-skills-governance',LF_GITHUB_READ_TOKEN:'test-read-token',
};
const claims={iss:'https://token.actions.githubusercontent.com',aud:AUDIENCE,repository:repo,repository_id:'123',ref:'refs/heads/main',
 workflow_ref:config.LF_SKILL_NATIVE_WORKFLOW_REF,environment:'lf-skills-governance',event_name:'workflow_dispatch',
 run_id:'12345',workflow_sha:'a'.repeat(40)};
const base={action:ACTIONS.BEGIN,skill_code:'PROGRAMMING_ANALYSIS_LF',parent_execution_id:'EXEC-PROFILE-123456789',input:{objective:'test'}};
const reply=(obj,status=200)=>new Response(JSON.stringify(obj),{status});
function simulated(options={}){
  const calls=[];
  const network=async (url,init={})=>{
    url=String(url);const body=typeof init?.body==='string'?JSON.parse(init.body):null;
    calls.push({url,body});
    if(url.endsWith('/rpc/'+PROPOSED_RPC.PREFLIGHT))return reply(options.preflight??{status:'ELIGIBLE',source_path:'skills/programming_analysis/SKILL.md'});
    if(url.endsWith('/rpc/'+PROPOSED_RPC.BEGIN))return reply(options.begin??{status:'RUN_OPENED_PENDING_EXECUTION',step0_recorded:true,a3_allowed:false,execution_id:'EXEC-SKILL-1234567890',skill_run_id:'RUN-ABC'});
    if(url.endsWith('/rpc/'+PROPOSED_RPC.STEP))return reply(options.step??{outcome:'STEP_RECORDED'});
    if(url.endsWith('/rpc/'+PROPOSED_RPC.STATUS))return reply(options.status??{execution_id:'EXEC-SKILL-1234567890',skill_code:'PROGRAMMING_ANALYSIS_LF',status:'IN_PROGRESS',step0_clean:true});
    if(url.endsWith('/git/ref/heads/main'))return reply(options.main??{object:{sha:'b'.repeat(40)}});
    if(url.includes('/contents/'))return reply(options.contents??{type:'file',sha:'c'.repeat(40)});
    throw Error('unexpected URL '+url);
  };
  const env={...config,...options.env};
  const h=createSkillsHandler({getEnv:k=>env[k],fetchFn:network,verifyJwt:async(t,aud)=>{
    assert.equal(aud,AUDIENCE);
    if(options.jwtError)throw Error('bad signature');
    return {...claims,...options.claims};
  }});
  return {h,calls};
}
function req(body=base,opts={}){return new Request('https://edge.example/caller',{method:opts.method??'POST',
 headers:opts.noToken?{}:{authorization:'Bearer '+'x'.repeat(40)},body:JSON.stringify(body)});}
async function hit(opts={},body=base,requestOpts={}){const s=simulated(opts);const r=await s.h(req(body,requestOpts));return {status:r.status,data:await r.json(),calls:s.calls};}
function blocked(x,code){assert.equal(x.data.status,'BLOCKED');assert.equal(x.data.blocking_code,code);assert.equal(x.data.a3_allowed,false);}

test('disabled by default even if accidentally deployed',async()=>{const x=await hit({env:{LF_SKILL_NATIVE_CALLER_ENABLED:'false'}});blocked(x,'SKILL_NATIVE_ROUTE_NOT_ACTIVATED');assert.equal(x.calls.length,0);});
test('no OIDC bearer rejects before any RPC',async()=>{const x=await hit({},base,{noToken:true});blocked(x,'SKILL_OIDC_TOKEN_REQUIRED');assert.equal(x.calls.length,0);});
test('bad JWT signature rejects',async()=>{const x=await hit({jwtError:true});blocked(x,'SKILL_OIDC_VERIFICATION_FAILED');assert.equal(x.calls.length,0);});
for(const [kind,override] of Object.entries({repo:{repository:'other/repo'},repository_id:{repository_id:'999'},workflow:{workflow_ref:'rogue@refs/heads/main'},branch:{ref:'refs/heads/dev'},environment:{environment:'other'},event:{event_name:'push'},audience:{aud:'other-aud'},workflow_sha:{workflow_sha:'bad'}})){
 test('reject mismatched OIDC '+kind,async()=>{const x=await hit({claims:override});blocked(x,'SKILL_OIDC_SCOPE_MISMATCH');assert.equal(x.calls.length,0);});
}
test('body-supplied business cannot replace server authority',async()=>{const x=await hit({}, {...base,business:'SALY'});blocked(x,'SKILL_AUTHORITY_FIELDS_FORBIDDEN');assert.equal(x.calls.length,0);});
test('body _trusted cannot replace source attestation',async()=>{const x=await hit({}, {...base,input:{_trusted:{approved:true}}});blocked(x,'SKILL_AUTHORITY_FIELDS_FORBIDDEN');});
test('invalid skill is blocked',async()=>{const x=await hit({}, {...base,skill_code:'../OTHER'});blocked(x,'SKILL_TARGET_OR_PARENT_INVALID');});
test('missing input blocked without network',async()=>{const x=await hit({}, {...base,input:null});blocked(x,'SKILL_INPUT_INVALID');assert.equal(x.calls.length,0);});
test('not ready from native preflight blocks',async()=>{const x=await hit({preflight:{status:'BLOCKED',code:'NOT_READY'}});blocked(x,'SKILL_NATIVE_PREFLIGHT_NOT_ADMITTED');assert.equal(x.calls.length,1);});
test('unresolved catalog source blocks (no guessing)',async()=>{const x=await hit({preflight:{status:'ELIGIBLE',source_path:null}});blocked(x,'SKILL_NATIVE_PREFLIGHT_NOT_ADMITTED');});
test('directory-only source path blocks',async()=>{const x=await hit({preflight:{status:'ELIGIBLE',source_path:'skills/some_skill/'}});blocked(x,'SKILL_NATIVE_PREFLIGHT_NOT_ADMITTED');});
test('unexpected nested path traversal blocks',async()=>{const x=await hit({preflight:{status:'ELIGIBLE',source_path:'skills/../other/SKILL.md'}});blocked(x,'SKILL_NATIVE_PREFLIGHT_NOT_ADMITTED');});
test('main SHA unavailable blocks',async()=>{const x=await hit({main:{object:{sha:'bad'}}});blocked(x,'SKILL_MAIN_SOURCE_UNRESOLVED');assert.equal(x.calls.filter(k=>k.url.endsWith('/rpc/'+PROPOSED_RPC.BEGIN)).length,0);});
test('source blob missing blocks',async()=>{const x=await hit({contents:{type:'dir',sha:'c'.repeat(40)}});blocked(x,'SKILL_EXACT_SOURCE_NOT_ATTESTED');});
test('begin RPC must give PENDING not COMPLETED',async()=>{const x=await hit({begin:{status:'COMPLETED',step0_recorded:true,execution_id:'EXEC-SKILL-1234567890'}});blocked(x,'SKILL_NATIVE_BEGIN_NOT_VERIFIED');});
test('begin RPC cannot assert A3 allowed',async()=>{const x=await hit({begin:{status:'RUN_OPENED_PENDING_EXECUTION',step0_recorded:true,a3_allowed:true,execution_id:'EXEC-SKILL-1234567890'}});blocked(x,'SKILL_NATIVE_BEGIN_NOT_VERIFIED');});
test('bad readback blocks even after begin RPC',async()=>{const x=await hit({status:{execution_id:'EXEC-OTHER-12345678',skill_code:'PROGRAMMING_ANALYSIS_LF',status:'IN_PROGRESS',step0_clean:true}});blocked(x,'SKILL_NATIVE_READBACK_NOT_CLEAN');});
test('valid simulated begin resolves exact source and stays pending',async()=>{const x=await hit();assert.equal(x.status,200);assert.equal(x.data.status,'RUN_OPENED_PENDING_EXECUTION');assert.equal(x.data.a3_allowed,false);assert.equal(x.data.native_judge_verified,false);
 assert.deepEqual(x.calls.filter(k=>k.url.includes('/rpc/')).map(k=>k.url.split('/').at(-1)),[PROPOSED_RPC.PREFLIGHT,PROPOSED_RPC.BEGIN,PROPOSED_RPC.STATUS]);
 const b=x.calls.find(k=>k.url.endsWith('/rpc/'+PROPOSED_RPC.BEGIN)).body;assert.equal(b.p_source.path,'skills/programming_analysis/SKILL.md');assert.equal(b.p_source.commit_sha,'b'.repeat(40));assert.equal(b.p_source.blob_sha,'c'.repeat(40));assert.equal(b.p_caller.repository,repo);assert.equal(b.p_parent_execution_id,base.parent_execution_id);});
test('generic skill path chosen by server, not caller',async()=>{const x=await hit({preflight:{status:'ELIGIBLE',source_path:'skills/other/domain/SKILL.md'}},{...base,skill_code:'ANOTHER_SKILL'});
 assert.equal(x.data.status,'BLOCKED'); // the exact child must match skill in mock STATUS: rejects cross-skill
 assert.equal(x.data.blocking_code,'SKILL_NATIVE_READBACK_NOT_CLEAN');
 assert.equal(x.calls.find(k=>k.url.endsWith('/rpc/'+PROPOSED_RPC.BEGIN)).body.p_source.path,'skills/other/domain/SKILL.md');});
test('record step cannot write immutable init',async()=>{const x=await hit({}, {...base,action:ACTIONS.STEP,child_execution_id:'EXEC-SKILL-1234567890',step_id:'init_execution',evidence_ref:'supabase://x',evidence_payload:{}});blocked(x,'SKILL_STEP_INPUT_INVALID');});
test('record step requires source reference',async()=>{const x=await hit({}, {...base,action:ACTIONS.STEP,child_execution_id:'EXEC-SKILL-1234567890',step_id:'router',evidence_ref:'fake',evidence_payload:{}});blocked(x,'SKILL_STEP_INPUT_INVALID');});
test('step RPC submission never marks completed or judge passed',async()=>{const x=await hit({}, {...base,action:ACTIONS.STEP,child_execution_id:'EXEC-SKILL-1234567890',step_id:'router',evidence_ref:'supabase://receipt',evidence_payload:{router_read:'ok'}});assert.equal(x.data.status,'STEP_SUBMITTED_PENDING_READBACK');assert.equal(x.data.a3_allowed,false);assert.equal(x.data.native_judge_verified,false);assert.equal(x.calls.length,1);});
test('read-only status cannot be used as judge receipt',async()=>{const x=await hit({}, {...base,action:ACTIONS.STATUS,child_execution_id:'EXEC-SKILL-1234567890'});assert.equal(x.data.status,'READBACK_ONLY');assert.equal(x.data.native_judge_verified,false);assert.equal(x.data.a3_allowed,false);});
test('status request cannot see unrelated skill',async()=>{const x=await hit({}, {...base,action:ACTIONS.STATUS,skill_code:'OTHER_SKILL',child_execution_id:'EXEC-SKILL-1234567890'});blocked(x,'SKILL_STATUS_READBACK_UNAVAILABLE');});
test('old profile action is not accepted in generic skills Edge',async()=>{const x=await hit({}, {...base,action:'profile_native_skill_invoke_v1'});blocked(x,'SKILL_ACTION_UNKNOWN');});

test('declared input.business is allowed but does not become authority',async()=>{const x=await hit({}, {...base,input:{business:'SALY',objective:'example'}});assert.equal(x.data.status,'RUN_OPENED_PENDING_EXECUTION');assert.equal(x.data.a3_allowed,false);const b=x.calls.find(k=>k.url.endsWith('/rpc/'+PROPOSED_RPC.BEGIN)).body;assert.equal(b.p_input.business,'SALY');assert.equal(Object.hasOwn(b,'p_business'),false);});
test('judge claims inside evidence_payload cannot override server judge',async()=>{const x=await hit({}, {...base,action:ACTIONS.STEP,child_execution_id:'EXEC-SKILL-1234567890',step_id:'semantic_judge',evidence_ref:'supabase://receipt',evidence_payload:{native_judge_verified:true}});blocked(x,'SKILL_AUTHORITY_FIELDS_FORBIDDEN');assert.equal(x.calls.length,0);});
test('declared cross-business input is vetoed by server preflight, not by invented Edge policy',async()=>{
 const x=await hit({preflight:{status:'BLOCKED',code:'PROFILE_BUSINESS_MISMATCH'}},{...base,input:{business:'SALY'}});
 blocked(x,'SKILL_NATIVE_PREFLIGHT_NOT_ADMITTED');
 assert.equal(x.calls.length,1);
});

test('nested input authority claims rejected without server calls',async()=>{
 const x=await hit({}, {...base,input:{objective:'test',context:{nested:{source_attested:true}}}});
 blocked(x,'SKILL_AUTHORITY_FIELDS_FORBIDDEN');assert.equal(x.calls.length,0);
});
test('nested evidence authority claims rejected without server calls',async()=>{
 const x=await hit({}, {...base,action:ACTIONS.STEP,child_execution_id:'EXEC-SKILL-1234567890',step_id:'router',evidence_ref:'supabase://receipt',evidence_payload:{context:[{native_judge_verified:true}]}});
 blocked(x,'SKILL_AUTHORITY_FIELDS_FORBIDDEN');assert.equal(x.calls.length,0);
});
test('business nested under evidence is rejected',async()=>{
 const x=await hit({}, {...base,action:ACTIONS.STEP,child_execution_id:'EXEC-SKILL-1234567890',step_id:'router',evidence_ref:'supabase://receipt',evidence_payload:{nested:{business:'SALY'}}});
 blocked(x,'SKILL_AUTHORITY_FIELDS_FORBIDDEN');assert.equal(x.calls.length,0);
});
test('nested input business is not an authority field',async()=>{
 const x=await hit({}, {...base,input:{business:'LF',details:{business:'SALY'}}});
 blocked(x,'SKILL_AUTHORITY_FIELDS_FORBIDDEN');assert.equal(x.calls.length,0);
});
test('invalid server-configured OIDC workflow cannot authorize',async()=>{
 const x=await hit({env:{LF_SKILL_NATIVE_WORKFLOW_REF:'untrusted@refs/heads/main'}});
 blocked(x,'SKILL_NATIVE_SERVER_CONFIGURATION_MISSING');assert.equal(x.calls.length,0);
});

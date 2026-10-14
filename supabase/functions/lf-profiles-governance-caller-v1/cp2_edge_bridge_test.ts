import {cp2Context,executeCp2,Cp2Fault,CP2_EXECUTE_ACTION,CP2_PREFLIGHT_ACTION} from "./cp2_edge_bridge.ts";

const IDS=[1,2,3,5,43,51,52,53,54,55,56,57,58];
const release={version:"1.1.0",previous_version:"1.0.0",manifest_sha256:"a".repeat(64)};
const config={supabaseUrl:"https://example.supabase.co",serviceRoleKey:"test-only",recurationTimeoutMs:1000};
function assert(ok: unknown, label="ASSERT_FAIL") {if(!ok)throw new Error(label);}
function eq(a: unknown,b: unknown) {
  if(JSON.stringify(a)!==JSON.stringify(b))throw new Error("EXPECTED "+JSON.stringify(b)+" GOT "+JSON.stringify(a));
}
function harness(opts:{allow?:boolean,edgeStatus?:string,attestStatus?:string,
  afterRun?:number,scope?:number[],providerReject?:string,runId?:number}={}){
  const calls:{route:string;body:Record<string,unknown>}[]=[];
  const run=opts.runId??4242;
  const request=async(input:string|URL|Request,init?:RequestInit):Promise<Response>=>{
    const url=String(input);
    const body=init?.body?JSON.parse(String(init.body)):{};
    const route=new URL(url).pathname;
    calls.push({route,body});
    if(opts.providerReject===route)return new Response('{"code":"DENIED"}',{status:403});
    let out:unknown={};
    if(route.endsWith("/fn_ig_m105_cp2_dispatch_context_v1"))
      out={status:"AUTHORIZED_CONTEXT",dispatch_permitted:opts.allow!==false,
           scope:{schema_version:"M105_SCOPE_SNAPSHOT_V1",screen_ids:opts.scope??IDS},release};
    else if(route.endsWith("/functions/v1/input-governance-agent-v1"))
      out={result:{status:opts.edgeStatus??"BLOCKED",run_id:run}};
    else if(route.endsWith("/fn_ig_m105_cp2_screen_readback_v1"))
      out=[{run_id:calls.filter(c=>c.route.endsWith("/fn_ig_m105_cp2_screen_readback_v1")).length===1?run:opts.afterRun??run,
            cp2_verdict:"PASS_CP2",technical_verdict:"PASS_TECNICO"}];
    else if(route.endsWith("/fn_ig_m105_cp2_attest_run_v1"))
      out={status:opts.attestStatus??"PERSISTED_VERIFIED",run_id:run,receipt_id:700};
    else throw new Error("UNEXPECTED_ROUTE "+route);
    return new Response(JSON.stringify(out),{status:200,headers:{"content-type":"application/json"}});
  };
  return {calls,request};
}
async function fault(p:Promise<unknown>,code:string){
  try{await p;throw new Error("FAIL_OPEN_EXPECTED_"+code);}
  catch(e){if(!(e instanceof Cp2Fault)||e.code!==code)throw e;}
}
Deno.test("CP2 OIDC canonical preflight returns exact authoritative 13 screen scope",async()=>{
  const h=harness();
  const out=await executeCp2(config,h.request,CP2_PREFLIGHT_ACTION,{action:CP2_PREFLIGHT_ACTION});
  eq(out.status,200);eq(out.result.pantalla_ids,IDS);
  assert(h.calls.length===1);
  assert(!h.calls.some(c=>c.route.includes("/functions/")));
});
Deno.test("CP2 absent release authorization fails before ANY Edge or receipt",async()=>{
  const h=harness({allow:false});
  await fault(executeCp2(config,h.request,CP2_EXECUTE_ACTION,
       {action:CP2_EXECUTE_ACTION,pantalla_id:58}),"CP2_AUTHENTIC_RELEASE_OR_SIGNED_AUTHORITY_MISSING");
  eq(h.calls.length,1);
});
Deno.test("CP2 signed receipt and two canonical matching readbacks are mandatory for success",async()=>{
  const h=harness();
  const out=await executeCp2(config,h.request,CP2_EXECUTE_ACTION,
    {action:CP2_EXECUTE_ACTION,pantalla_id:58});
  eq(out.status,200);eq(out.result.outcome,"VERIFIED_EDGE_RUN");
  eq(out.result.signed_receipt_id,700);
  eq(h.calls.map(x=>x.route.split("/").pop()),[
    "fn_ig_m105_cp2_dispatch_context_v1",
    "input-governance-agent-v1",
    "fn_ig_m105_cp2_screen_readback_v1",
    "fn_ig_m105_cp2_attest_run_v1",
    "fn_ig_m105_cp2_screen_readback_v1"]);
});
Deno.test("CP2 semantic BLOCKED stays valid if independently attested and CP2 verdict passes",async()=>{
  const h=harness({edgeStatus:"BLOCKED"});
  const out=await executeCp2(config,h.request,CP2_EXECUTE_ACTION,
      {action:CP2_EXECUTE_ACTION,pantalla_id:1});
  eq(out.status,200);
});
Deno.test("CP2 invalid signed receipt fails without PASS",async()=>{
  const h=harness({attestStatus:"REJECTED"});
  await fault(executeCp2(config,h.request,CP2_EXECUTE_ACTION,
      {action:CP2_EXECUTE_ACTION,pantalla_id:1}),"CP2_INDEPENDENT_SIGNED_RECEIPT_REQUIRED");
});
Deno.test("CP2 edge run not equal to latest canonical run fails",async()=>{
  const h=harness({afterRun:999});
  await fault(executeCp2(config,h.request,CP2_EXECUTE_ACTION,
    {action:CP2_EXECUTE_ACTION,pantalla_id:1}),"CP2_POST_ATTEST_RUN_MISMATCH");
});
Deno.test("CP2 rejects screen not in frozen scope without Edge invocation",async()=>{
  const h=harness();
  await fault(executeCp2(config,h.request,CP2_EXECUTE_ACTION,
      {action:CP2_EXECUTE_ACTION,pantalla_id:999}),"CP2_SCREEN_OUTSIDE_FROZEN_COHORT");
  eq(h.calls.length,1);
});
Deno.test("CP2 rejects altered 13-screen frozen scope",async()=>{
  const h=harness({scope:IDS.slice(1)});
  await fault(cp2Context(config,h.request),"CP2_AUTHORITY_SCOPE_OR_RELEASE_DRIFT");
});
Deno.test("CP2 requires current exact provider and fails closed on RPC reject",async()=>{
  const h=harness({providerReject:"/rest/v1/rpc/fn_ig_m105_cp2_dispatch_context_v1"});
  await fault(cp2Context(config,h.request),"CP2_CANONICAL_PROVIDER_REJECTED");
});
Deno.test("CP2 continuation never issues false receipt",async()=>{
  const h=harness({edgeStatus:"VALIDATOR_RESUME_REQUIRED"});
  const o=await executeCp2(config,async(input,init)=>{
    const url=String(input);
    if(url.endsWith("/functions/v1/input-governance-agent-v1"))
      return new Response(JSON.stringify({status:"VALIDATOR_RESUME_REQUIRED",result:{status:"VALIDATOR_RESUME_REQUIRED",run_id:4242}}),{status:202});
    return h.request(input,init);
  },CP2_EXECUTE_ACTION,{action:CP2_EXECUTE_ACTION,pantalla_id:1});
  eq(o.status,202);eq(o.result.outcome,"CONTINUATION_REQUIRED");
  assert(!h.calls.some(c=>c.route.includes("attest_run_v1")));
});

// Exercise bounded profile continuation/OIDC security in the existing Edge test lane.
import "./profile_continuation_test.ts";
// The CP2 CI carrier exercises isolated Stage 06/07 no-write and writer tests.
import "./router_stage6_stage7_test.ts";
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


// Focused ticket regression in the existing unfiltered Edge bridge test runner.
// No workflow/filter change. This exercises createHandler, with mocked SQL and Agent,
// not the real Supabase runtime or an independent judge.
import { createHandler } from "./caller.ts";
const PROFILE_TICKET_FOR_TEST = "11111111-2222-4333-8444-555555555555";
const PROFILE_EXECUTION_FOR_TEST = "EXEC-PROFILE-RUNTIME-11111111-2222-3333-4444-555555555555";
const PROFILE_RUNTIME_FOR_TEST = {
  action: "input_readiness_context_pack_runtime_v1",
  execution_id: PROFILE_EXECUTION_FOR_TEST,
  pantalla_id: 51,
};
function ticketBridgeHarness(options: { valid?: boolean; agentState?: string } = {}) {
  const repo = "cristhianlujan/claude-persona-lf-patch";
  const ref = "refs/heads/main";
  const env: Record<string, string> = {
    SUPABASE_URL: "https://project.supabase.co",
    SUPABASE_SERVICE_ROLE_KEY: "test-only",
    LF_CALLER_REPOSITORY: repo,
    LF_CALLER_REPOSITORY_ID: "1244397752",
    LF_CALLER_RECURATION_REF: ref,
    LF_CALLER_RECURATION_WORKFLOW_REF: `${repo}/.github/workflows/lf-input-governance-recurate.yml@${ref}`,
    LF_CALLER_RECURATION_DISPATCH_WORKFLOW_REF: `${repo}/.github/workflows/lf-input-governance-recurate-dispatch.yml@${ref}`,
    LF_CALLER_RECURATION_WORKFLOW_NAME: "LF Input Governance Recuration",
    LF_CALLER_INPUT_GOVERNANCE_SLUG: "input-governance-agent-v1",
    LF_CALLER_PROFILE_CREATOR_SLUG: "run-creacion-perfil-lf",
    LF_CALLER_RECURATION_TIMEOUT_MS: "149000",
    LF_CALLER_DEFAULT_TIMEOUT_MS: "120000",
  };
  const calls: Array<{ url: string; body: Record<string, unknown> }> = [];
  const handler = createHandler({
    getEnv: (key) => env[key],
    jwks: {},
    jwtVerifyFn: async () => { throw new Error("TEST_UNEXPECTED_OIDC_PATH"); },
    fetchFn: async (input, init) => {
      const url = String(input);
      const body = typeof init?.body === "string" ? JSON.parse(init.body) : {};
      calls.push({ url, body });
      let status = 200;
      let result: Record<string, unknown>;
      if (url.endsWith("/rest/v1/rpc/lf_profile_input_governance_runtime_ticket_consume_v1")) {
        result = options.valid === false
          ? { authorized: false, code: "PROFILE_IG_RUNTIME_TICKET_INVALID_OR_EXPIRED" }
          : { authorized: true, execution_id: body.p_execution_id, pantalla_id: body.p_pantalla_id, consumer: "CONTEXT_PACK" };
      } else if (url.endsWith("/functions/v1/input-governance-agent-v1")) {
        if (body.ticket !== PROFILE_TICKET_FOR_TEST) {
          status = 403;
          result = { error: "IG_PROFILE_TICKET_REQUIRED" };
        } else {
          result = { result: { status: options.agentState ?? "READY", run_id: 10051 } };
        }
      } else {
        throw new Error("TEST_UNEXPECTED_ROUTE " + url);
      }
      return new Response(JSON.stringify(result), { status, headers: { "content-type": "application/json" } });
    },
  });
  async function invoke(ticket: string) {
    const response = await handler(new Request("https://caller.test", {
      method: "POST",
      headers: { "content-type": "application/json", "x-lf-profile-runtime-ticket": ticket },
      body: JSON.stringify(PROFILE_RUNTIME_FOR_TEST),
    }));
    const payload = await response.json();
    return { response, payload };
  }
  return { calls, invoke };
}
Deno.test("ticket bridge: consumed UUID is forwarded unchanged to Agent", async () => {
  const h = ticketBridgeHarness();
  const { response, payload } = await h.invoke(PROFILE_TICKET_FOR_TEST);
  eq(response.status, 200);
  eq(payload.outcome, "TERMINAL");
  eq(payload.caller.method, "EJECUCION_PERFIL_LF_RUNTIME_TICKET_V1");
  eq(payload.caller.router_reentry, false);
  const consumed = h.calls.filter(c => c.url.endsWith("/rest/v1/rpc/lf_profile_input_governance_runtime_ticket_consume_v1"));
  eq(consumed.length, 1);
  eq(consumed[0].body.p_ticket, PROFILE_TICKET_FOR_TEST);
  eq(consumed[0].body.p_execution_id, PROFILE_EXECUTION_FOR_TEST);
  const edge = h.calls.filter(c => c.url.endsWith("/functions/v1/input-governance-agent-v1"));
  eq(edge.length, 1);
  eq(edge[0].body, { pantalla_id: 51, consumer: "CONTEXT_PACK", ticket: PROFILE_TICKET_FOR_TEST });
});
Deno.test("ticket bridge: malformed and expired tickets block before Agent", async () => {
  const malformed = ticketBridgeHarness();
  const bad = await malformed.invoke("bad-ticket");
  eq(bad.response.status, 401);
  eq(bad.payload.code, "PROFILE_RUNTIME_TICKET_INVALID");
  eq(malformed.calls.length, 0);
  const expired = ticketBridgeHarness({ valid: false });
  const denied = await expired.invoke(PROFILE_TICKET_FOR_TEST);
  eq(denied.response.status, 403);
  eq(denied.payload.code, "PROFILE_IG_RUNTIME_TICKET_INVALID_OR_EXPIRED");
  assert(!expired.calls.some(c => c.url.endsWith("/functions/v1/input-governance-agent-v1")));
});
Deno.test("ticket bridge: Validator continuation stays bound to ticket without queue", async () => {
  const h = ticketBridgeHarness({ agentState: "VALIDATOR_RESUME_REQUIRED" });
  const { response, payload } = await h.invoke(PROFILE_TICKET_FOR_TEST);
  eq(response.status, 202);
  eq(payload.outcome, "CONTINUATION_REQUIRED");
  eq(payload.code, "IG_CONTEXT_PACK_VALIDATOR_RESUME_REQUIRED");
  eq(payload.queue_required, false);
  eq(payload.polling_required, false);
  assert(h.calls.some(c => c.url.endsWith("/functions/v1/input-governance-agent-v1") && c.body.ticket === PROFILE_TICKET_FOR_TEST));
});

// Profile-owned, direct ticket-based IG runtime transport regression is executed
// by this existing UNFILTERED CP2 Edge test lane. No CI workflow modifications.
const canonical3IgFindings = [
 {type:"VIGENTE_REFERENCES_CANDIDATO",severity:"INTERNAL_REMEDIATION",
  source_id:3,target_id:19,relation_key:"factor_security_policy_id",
  source_policy:"SEC-B2B-MFA",target_policy:"SEC-B2B-MFA-FACTOR-ELIGIBILITY",question_owner:false},
 {type:"VIGENTE_REFERENCES_CANDIDATO",severity:"INTERNAL_REMEDIATION",
  source_id:17,target_id:22,relation_key:"abuse_security_policy_id",
  source_policy:"SEC-B2B-LOGIN-ANTIBOT",target_policy:"SEC-B2B-AUTH-ABUSE-PROTECTION",question_owner:false},
 {type:"IP_COMPOSITE_SCOPE_REQUIRES_RUNTIME_PROOF",severity:"ACQUIRE_EVIDENCE",
  scope_key:"IP_USER",rate_policy:"RATE-B2B-LOGIN",
  security_policy:"SEC-B2B-AUTH-ABUSE-PROTECTION",question_owner:false},
];
async function profileTicketResult(opts:{write?:boolean,findings?:boolean,ready?:boolean}={}){
 const baseEnv:Record<string,string>={
  SUPABASE_URL:"https://project.supabase.co",
  SUPABASE_SERVICE_ROLE_KEY:"service-role-test-only",
  LF_CALLER_REPOSITORY:"cristhianlujan/claude-persona-lf-patch",
  LF_CALLER_REPOSITORY_ID:"1244397752",
  LF_CALLER_RECURATION_REF:"refs/heads/main",
  LF_CALLER_RECURATION_WORKFLOW_REF:"cristhianlujan/claude-persona-lf-patch/.github/workflows/lf-input-governance-recurate.yml@refs/heads/main",
  LF_CALLER_RECURATION_DISPATCH_WORKFLOW_REF:"cristhianlujan/claude-persona-lf-patch/.github/workflows/lf-input-governance-recurate-dispatch.yml@refs/heads/main",
  LF_CALLER_RECURATION_WORKFLOW_NAME:"LF Input Governance Recuration",
  LF_CALLER_INPUT_GOVERNANCE_SLUG:"input-governance-agent-v1",
  LF_CALLER_PROFILE_CREATOR_SLUG:"run-creacion-perfil-lf",
  LF_CALLER_RECURATION_TIMEOUT_MS:"149000",
  LF_CALLER_DEFAULT_TIMEOUT_MS:"120000",
 };
 const run="EXEC-PROFILE-GATE2-95DFBB22762787B8824EB013";
 const full = {status:"BLOCKED",consumer:"CONTEXT_PACK",
  pantalla_id:51,run_id:951,output_sha256:"5".repeat(64),
  remediation_state:"INTERNAL_REMEDIATION_REQUIRED",
  owner_interruption_required:false,promotion_authorized:false,
  production_authorized:false,execution_mode:"REUSE_COMPLETED_CURRENT_RUN",
  predecision_crosscheck:{status:"CANONICAL_READBACK_ONLY",run_id:951,
    deterministic_finding_count:3,deterministic_findings:canonical3IgFindings}};
 const actual=opts.ready?{status:"READY",consumer:"CONTEXT_PACK",pantalla_id:51,run_id:951}:
  opts.findings===false?{status:"BLOCKED",run_id:951}:full;
 const fetchFn=async(input:string|URL|Request,init?:RequestInit):Promise<Response>=>{
  const url=String(input);
  if(url.endsWith("/rest/v1/rpc/lf_profile_input_governance_runtime_ticket_consume_v1"))
   return new Response('{"authorized":true}',{status:200});
  if(url.endsWith("/functions/v1/input-governance-agent-v1"))
   return new Response(JSON.stringify({result:actual}),{status:200});
  if(url.includes("/rest/v1/lf_operation_execution?"))
   return new Response(JSON.stringify([{execution_id:run,status:"IN_PROGRESS",
     operation_code:"EJECUCION_PERFIL_LF",target_type:"PERFIL",
     target_code:"PERFIL-PRODUCT-DIRECTOR-LF",
     manifest:{read_only:!opts.write,no_write:!opts.write,no_promotion:true,
       automatic_impact:false,governed_repair_write:!!opts.write,
       router_profile_handoff:{profile_code:"PERFIL-PRODUCT-DIRECTOR-LF",
         effect_authority:!!opts.write}}}]),{status:200});
  throw Error("UNEXPECTED_IG_TEST_ROUTE "+url);
 };
 const handler=createHandler({getEnv:(k)=>baseEnv[k],fetchFn,jwks:{},
  jwtVerifyFn:async()=>({payload:{}})});
 const response=await handler(new Request("https://caller.test",{
   method:"POST",
   headers:{"content-type":"application/json",
     "X-LF-Profile-Runtime-Ticket":"12345678-1234-4123-8123-123456789012"},
   body:JSON.stringify({action:"input_readiness_context_pack_runtime_v1",
     execution_id:run,pantalla_id:51}),
 }));
 return {status:response.status,body:await response.json(),source:full};
}
Deno.test("IG profile blocked findings: signed ticket and read-only scope report all three without clearance",async()=>{
 const v=await profileTicketResult();
 eq(v.status,200);eq(v.body.outcome,"TERMINAL_WITH_FINDINGS");
 eq(v.body.terminal_status,"BLOCKED");eq(v.body.ig_security_clearance,false);
 eq(v.body.result.result.predecision_crosscheck.deterministic_findings,canonical3IgFindings);
});
Deno.test("IG profile blocked findings: functional writer authority stays HTTP409 BLOCKED",async()=>{
 const v=await profileTicketResult({write:true});
 eq(v.status,409);eq(v.body.code,"IG_CONTEXT_PACK_BLOCKED");
});
Deno.test("IG profile no canonical findings: BLOCKED stays HTTP409; READY stays original",async()=>{
 const v=await profileTicketResult({findings:false});
 eq(v.status,409);eq(v.body.code,"IG_CONTEXT_PACK_BLOCKED");
 const ready=await profileTicketResult({ready:true});
 eq(ready.status,200);eq(ready.body.outcome,"TERMINAL");
});

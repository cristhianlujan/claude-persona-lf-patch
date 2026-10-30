import {resolveOidcIdentity, type CallerConfig} from "./caller.ts";
import {handleProfileContinuation,PROFILE_CONTINUE_ACTION,PROFILE_SOURCE_BIND_ACTION} from "./profile_continuation.ts";

function eq(a:unknown,b:unknown){if(JSON.stringify(a)!==JSON.stringify(b))throw Error("EXPECTED "+JSON.stringify(b)+" GOT "+JSON.stringify(a))}
const repo="test/lf";
const sha="a".repeat(40);
const config:CallerConfig={supabaseUrl:"https://example.supabase.co",serviceRoleKey:"test-only",repository:repo,repositoryId:"123",
recurationRef:"refs/heads/main",recurationWorkflowRef:repo+"/.github/workflows/lf-input-governance-recurate.yml@refs/heads/main",
recurationDispatchWorkflowRef:repo+"/.github/workflows/lf-input-governance-recurate-dispatch.yml@refs/heads/main",
recurationWorkflowName:"LF Input Governance Recuration",inputGovernanceSlug:"input-governance-agent-v1",
profileCreatorSlug:"run-creacion-perfil-lf",recurationTimeoutMs:149000,defaultTimeoutMs:120000};
const oidc={repository:repo,repository_id:"123",ref:"refs/heads/main",
workflow_ref:repo+"/.github/workflows/lf-edge-deploy-credential-readback.yml@refs/heads/main",
event_name:"workflow_dispatch",environment:"lf-edge-deploy",run_id:"100",workflow_sha:sha};
const id="EXEC-PROFILE-GATE2-ABCD1234567890EF";
const digest="sha256:"+"b".repeat(64);
function network(overrides:Record<string,unknown>={},selectStatus="BOUND"){
  const calls:Array<{url:string;body:Record<string,unknown>|null}>=[];
  let state="SCREEN_SELECTION_REQUIRED";
  const fetchFn=async(input:string|URL|Request,init?:RequestInit)=>{
    const url=String(input),body=typeof init?.body==="string"?JSON.parse(init.body) as Record<string,unknown>:null;
    calls.push({url,body});
    let out:unknown;
    if(url.includes("/rest/v1/lf_operation_execution?"))out=[{
      execution_id:id,status:"IN_PROGRESS",operation_code:"EJECUCION_PERFIL_LF",
      target_type:"PERFIL",target_code:"PROFILE-A",target_repo:repo,
      target_path:"profiles/profile_a/SKILL.md",
      manifest:{executor_mode:"GPT_NATIVE",executor_provider:"OPENAI_CHATGPT_NATIVE",read_only:true,no_write:true,no_promotion:true,governed_repair_write:false,
        router_profile_handoff:{profile_code:"PROFILE-A",router_authorization_receipt:{
          profile_code:"PROFILE-A",profile_execution_allowed:true,effect_authority:false}}},
      ...overrides,
    }];
    else if(url.endsWith("/lf_profile_native_bridge_prepare_v1"))out={status:state,next_action:"RETRY_BRIDGE"};
    else if(url.endsWith("/lf_profile_screen_selector_semantic_submit_v1")){
      out={status:selectStatus};if(selectStatus==="BOUND")state="NATIVE_MODEL_INPUT_READY";
    }else throw Error("UNEXPECTED_URL "+url);
    return new Response(JSON.stringify(out),{status:200});
  };
  return {fetchFn,calls};
}
Deno.test("continuation: exact OIDC workflow only",()=>{
  eq(resolveOidcIdentity(oidc,config).scope,"PROFILE_NATIVE_CONTINUATION_ONLY");
  eq(resolveOidcIdentity({...oidc,event_name:"issues"},config).scope,"PROFILE_NATIVE_CONTINUATION_ONLY");
  for(const wrong of [{...oidc,event_name:"push"},{...oidc,ref:"refs/heads/feature"},
    {...oidc,environment:"unprotected"},{...oidc,workflow_ref:"untrusted"}]){
    let blocked=false;try{resolveOidcIdentity(wrong,config)}catch{blocked=true}eq(blocked,true);
  }
});
Deno.test("continuation: profile path bound dynamically, never selected in code",async()=>{
  for(const target_path of ["profiles/profile_a/SKILL.md","profiles/profile_b/SKILL.md"]){
    const n=network({target_path});
    const out=await handleProfileContinuation(PROFILE_SOURCE_BIND_ACTION,{execution_id:id},config,n.fetchFn,sha);
    const b=await out.json();eq(out.status,200);eq(b.target_path,target_path);eq(n.calls.length,1);
  }
});
Deno.test("continuation: screen semantic handoff preserves ordering and source",async()=>{
  const n=network();const draft={decision:"SELECTED",selected_screen_code:"DYNAMIC-SELECTED-CODE"};
  const out=await handleProfileContinuation(PROFILE_CONTINUE_ACTION,{
    execution_id:id,source_revision:sha,source_digest:digest,screen_selection_draft:draft},config,n.fetchFn,sha);
  const body=await out.json();eq(out.status,200);eq(body.phase,"NATIVE_MODEL_INPUT_READY");
  eq(n.calls.map(c=>c.url.split("/").pop()?.split("?")[0]),[
    "lf_operation_execution","lf_profile_native_bridge_prepare_v1",
    "lf_profile_screen_selector_semantic_submit_v1","lf_profile_native_bridge_prepare_v1"]);
  eq(n.calls[2].body?.p_draft,draft);
});
Deno.test("continuation: fail-closed role, source, and semantic decision",async()=>{
  for(const override of [{status:"SUCCEEDED"},{operation_code:"ACTUALIZACION_PERFIL_LF"},
    {target_path:"../secret"},{target_repo:"untrusted/repo"},{manifest:{read_only:true}}]){
    const n=network(override);
    const out=await handleProfileContinuation(PROFILE_CONTINUE_ACTION,{
      execution_id:id,source_revision:sha,source_digest:digest},config,n.fetchFn,sha);
    eq(out.status,403);eq(n.calls.length,1);
  }
  const n=network();const mismatch=await handleProfileContinuation(PROFILE_CONTINUE_ACTION,{
    execution_id:id,source_revision:"c".repeat(40),source_digest:digest},config,n.fetchFn,sha);
  eq(mismatch.status,400);eq(n.calls.length,1);
  const rejectedNet=network({},"BLOCKED");
  const rejected=await handleProfileContinuation(PROFILE_CONTINUE_ACTION,{
    execution_id:id,source_revision:sha,source_digest:digest,screen_selection_draft:{decision:"SELECTED"}},config,rejectedNet.fetchFn,sha);
  eq(rejected.status,409);
});

function manifestFor(mode:string|undefined,provider:string|undefined){
  const m:Record<string,unknown>={read_only:true,no_write:true,no_promotion:true,governed_repair_write:false,
    router_profile_handoff:{profile_code:"PROFILE-A",router_authorization_receipt:{
      profile_code:"PROFILE-A",profile_execution_allowed:true,effect_authority:false}}};
  if(mode!==undefined)m.executor_mode=mode;
  if(provider!==undefined)m.executor_provider=provider;
  return m;
}
Deno.test("continuation: GPT_NATIVE and CLAUDE_NATIVE are admitted with their own provider",async()=>{
  for(const [mode,provider] of [["GPT_NATIVE","OPENAI_CHATGPT_NATIVE"],["CLAUDE_NATIVE","ANTHROPIC_CLAUDE_NATIVE"]]){
    const n=network({manifest:manifestFor(mode,provider)});
    const out=await handleProfileContinuation(PROFILE_SOURCE_BIND_ACTION,{execution_id:id},config,n.fetchFn,sha);
    eq(out.status,200);
  }
});
Deno.test("continuation: mismatched, missing or remote executor is rejected",async()=>{
  for(const [mode,provider] of [["CLAUDE_NATIVE","OPENAI_CHATGPT_NATIVE"],["GPT_NATIVE","ANTHROPIC_CLAUDE_NATIVE"],
    ["CLAUDE_NATIVE",undefined],[undefined,"ANTHROPIC_CLAUDE_NATIVE"],["REMOTE_API","HETZNER"],["claude_native","ANTHROPIC_CLAUDE_NATIVE"]]){
    const n=network({manifest:manifestFor(mode,provider)});
    const out=await handleProfileContinuation(PROFILE_SOURCE_BIND_ACTION,{execution_id:id},config,n.fetchFn,sha);
    eq(out.status,403);
  }
});

const preModelClean = [
  "init_execution", "router", "profile_resolve", "profile_source_read",
  "input_validate", "context_admission", "research_baseline_freeze",
  "execute_profile", "output_validate",
];
function postModelNetwork(
  rows: Array<{step_id:string; status:string}>,
  cleanCount: number,
) {
  const base = network();
  const urls:string[] = [];
  const fetchFn = async (input:string|URL|Request, init?:RequestInit):Promise<Response> => {
    const url = String(input);
    urls.push(url);
    if (url.endsWith("/rest/v1/rpc/lf_profile_native_bridge_prepare_v1")) {
      return new Response(JSON.stringify({
        status:"BLOCKED", blocking_code:"BLOCK_PROFILE_NATIVE_BRIDGE_PRE_MODEL_STEP_COUNT",
        clean_step_count:cleanCount,expected_clean_step_count:7,
      }),{status:200});
    }
    if (url.includes("/rest/v1/lf_operation_execution_steps?")) {
      return new Response(JSON.stringify(rows),{status:200});
    }
    return base.fetchFn(input,init);
  };
  return {fetchFn,urls};
}
function cleanRows(includeSemantic=false) {
  const rows=preModelClean.map(step_id=>({step_id,status:"STEP_PASS_WITH_EVIDENCE"}));
  if(includeSemantic)rows.push({step_id:"semantic_judge",status:"STEP_PASS_WITH_EVIDENCE"});
  return rows;
}
Deno.test("continuation: post-model 9/11 goes to existing semantic judge, never pre-model",async()=>{
  const n=postModelNetwork(cleanRows(),9);
  const out=await handleProfileContinuation(PROFILE_CONTINUE_ACTION,{
    execution_id:id,source_revision:sha,source_digest:digest,
  },config,n.fetchFn,sha);
  const body=await out.json();
  eq(out.status,200);eq(body.outcome,"CONTINUATION_REQUIRED");
  eq(body.phase,"INDEPENDENT_SEMANTIC_JUDGE_REQUIRED");
  eq(body.result.next_step,"semantic_judge");
  eq(body.execution_id,id);
  eq(n.urls.filter(u=>u.includes("/lf_profile_native_bridge_prepare_v1")).length,1);
  eq(n.urls.filter(u=>u.includes("/lf_operation_execution_steps?")).length,1);
  eq(n.urls.some(u=>u.includes("/lf_record_profile_execution_step_v1")),false);
});
Deno.test("continuation: post-model 10/11 goes to report, never reruns semantic judge",async()=>{
  const n=postModelNetwork(cleanRows(true),10);
  const out=await handleProfileContinuation(PROFILE_CONTINUE_ACTION,{
    execution_id:id,source_revision:sha,source_digest:digest,
  },config,n.fetchFn,sha);
  const body=await out.json();
  eq(out.status,200);eq(body.phase,"REPORT_OUTPUT_REQUIRED");
  eq(body.result.next_step,"report_output");
  eq(n.urls.some(u=>u.includes("/lf_record_profile_execution_step_v1")),false);
});
Deno.test("continuation: false 9/11, blocked judge and unexpected step fail closed",async()=>{
  const cases=[
    {rows:cleanRows().map(x=>x.step_id==="output_validate"?{...x,status:"BLOCKED_STEP_NOT_CLEAN"}:x),count:9},
    {rows:[...cleanRows(),{step_id:"semantic_judge",status:"BLOCKED_STEP_NOT_CLEAN"}],count:9},
    {rows:[...cleanRows().slice(0,8),{step_id:"unexpected",status:"STEP_PASS_WITH_EVIDENCE"}],count:9},
    {rows:cleanRows(),count:8},
  ];
  for(const c of cases) {
    const n=postModelNetwork(c.rows,c.count);
    const out=await handleProfileContinuation(PROFILE_CONTINUE_ACTION,{
      execution_id:id,source_revision:sha,source_digest:digest,
    },config,n.fetchFn,sha);
    const body=await out.json();
    eq(out.status,409);eq(body.outcome,"BLOCKED");
    eq(n.urls.some(u=>u.includes("/lf_record_profile_execution_step_v1")),false);
  }
});

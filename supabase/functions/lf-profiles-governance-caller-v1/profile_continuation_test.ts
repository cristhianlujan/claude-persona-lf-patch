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
      manifest:{executor_mode:"GPT_NATIVE",read_only:true,no_write:true,no_promotion:true,governed_repair_write:false,
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

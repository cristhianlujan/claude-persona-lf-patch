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
    }else if(url.endsWith("/lf_profile_native_bridge_record_output_v1")){
      out={status:"NATIVE_PRODUCER_VALIDATED",execution_id:id,profile_code:"PROFILE-A",
        clean_step_count:9,next_step:"semantic_judge"};
    }else if(url.endsWith("/lf_profile_native_bridge_record_semantic_v1")){
      out={status:"SEMANTIC_JUDGE_RECORDED",execution_id:id,profile_code:"PROFILE-A",
        clean_step_count:10,next_step:"report_output"};
    }else if(url.endsWith("/lf_profile_native_bridge_record_report_v1")){
      out={status:"PROFILE_EXECUTION_COMPLETED",execution_id:id,profile_code:"PROFILE-A",
        clean_step_count:11,execution_status:"COMPLETED",next_gate:"RETURN_TO_ROUTER"};
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
Deno.test("continuation: source-bound validator receipt records native output and advances to semantic judge",async()=>{
  const n=network();
  const receipt={
    schema:"PROFILE_OUTPUT_VALIDATION_RESULT_V1",
    status:"CANDIDATE_OUTPUT_PARITY_OBSERVED",
    structural_check_executed:true,
    profile_validator_executed:true,
    source_readback_matched:true,
    independent_review_executed:false,
    provider_attested:false,
    admission_authorized:false,
    profile_write_authorized:false,
    runtime_activation_authorized:false,
    blocking_codes:[],
    validator_errors:[],
    raw_output_sha256:"d".repeat(64),
  };
  const output={worker:"profile_a",traceability:{ig_open_work_resolution:[]}};
  const out=await handleProfileContinuation(PROFILE_CONTINUE_ACTION,{
    execution_id:id,source_revision:sha,source_digest:digest,
    screen_selection_draft:{decision:"SELECTED",selected_screen_code:"DYNAMIC-SELECTED-CODE"},
    profile_output:output,validation_result:receipt,
    raw_evidence_ref:"actions://test/lf/runs/100/artifact/raw",
    validator_evidence_ref:"actions://test/lf/runs/100/artifact/validator",
  },config,n.fetchFn,sha);
  const body=await out.json();
  eq(out.status,200);eq(body.phase,"INDEPENDENT_SEMANTIC_JUDGE_REQUIRED");
  const record=n.calls.find(c=>c.url.endsWith("/lf_profile_native_bridge_record_output_v1"));
  if(!record)throw Error("record_output not called");
  eq(record.body?.p_profile_output,output);
  const validation=record.body?.p_validation as Record<string,unknown>;
  eq(validation.valid,true);eq(validation.blocking_codes,[]);
  eq((validation.source_bound_validation as Record<string,unknown>).status,"CANDIDATE_OUTPUT_PARITY_OBSERVED");
});
Deno.test("continuation: model cannot self-assert validator PASS",async()=>{
  const n=network();
  const out=await handleProfileContinuation(PROFILE_CONTINUE_ACTION,{
    execution_id:id,source_revision:sha,source_digest:digest,
    screen_selection_draft:{decision:"SELECTED",selected_screen_code:"DYNAMIC-SELECTED-CODE"},
    profile_output:{worker:"profile_a"},
    validation_result:{valid:true,status:"PASS"},
    raw_evidence_ref:"actions://test/lf/runs/100/artifact/raw",
    validator_evidence_ref:"actions://test/lf/runs/100/artifact/validator",
  },config,n.fetchFn,sha);
  const body=await out.json();
  eq(out.status,409);eq(body.code,"PROFILE_NATIVE_OUTPUT_VALIDATOR_RECEIPT_NOT_PASS");
  eq(n.calls.some(c=>c.url.endsWith("/lf_profile_native_bridge_record_output_v1")),false);
});

function semanticReceipt(){
  const refs=["supabase://source/a"];
  const checks:Record<string,unknown>={};
  for(const key of [
    "context_resolution_valid","evidence_supported","decision_resolves_objective",
    "authority_resolution_valid","constraints_preserved","claims_authorized",
    "materiality_handled_correctly","tradeoff_defensible",
    "acceptance_detects_wrong_implementation","handoff_implementation_ready",
    "router_direct_consistency","counterfactual_trajectory",
  ]) checks[key]=key==="router_direct_consistency"
    ? {result:"not_applicable",applicability:"ROUTER_ONLY",
       reason:"ACT-0001 is the only governed runtime path; no direct counterpart was authorized.",
       source_refs:refs}
    : {result:true,reason:"supported by inspected current sources",source_refs:refs};
  const review={
    verdict:"PASS_INDEPENDENT_SEMANTIC",decision_checks:checks,
    producer_independence_proven:true,model_call_count:1,
    unsupported_claims:[],blocking_codes:[],source_refs:refs,resolved_context_refs:refs,
    router_direct_consistency:"NOT_TESTED",counterfactual_result:"PASS",
    candidate_sha256:"c".repeat(64),scope_packet_sha256:"s".repeat(64).replace(/s/g,"a"),
  };
  return {
    status:"PASS",verdict:"PASS_INDEPENDENT_SEMANTIC",validator_status:"PASS",
    producer_independence_proven:true,model_call_count:1,
    candidate_sha256:review.candidate_sha256,scope_packet_sha256:review.scope_packet_sha256,
    result:{verdict:"PASS_INDEPENDENT_SEMANTIC",candidate_sha256:review.candidate_sha256,
      scope_packet_sha256:review.scope_packet_sha256,unsupported_claims:[],blocking_codes:[]},
    judge_v3_evidence:review,
  };
}
Deno.test("continuation: independent semantic PASS records 70 and deterministic report 80",async()=>{
  const n=network();
  const receipt=semanticReceipt();
  const out=await handleProfileContinuation(PROFILE_CONTINUE_ACTION,{
    execution_id:id,source_revision:sha,source_digest:digest,
    semantic_judge_result:receipt,
    semantic_evidence_ref:"actions://test/lf/runs/100/artifact/profile-semantic-judge.json",
  },config,n.fetchFn,sha);
  const body=await out.json();
  eq(out.status,200);eq(body.phase,"PROFILE_EXECUTION_COMPLETED");
  eq(body.next_gate,"RETURN_TO_ROUTER");
  eq(n.calls.some(c=>c.url.endsWith("/lf_profile_native_bridge_record_semantic_v1")),true);
  eq(n.calls.some(c=>c.url.endsWith("/lf_profile_native_bridge_record_report_v1")),true);
});
Deno.test("continuation: Router-only N/A is not a fabricated comparison PASS",async()=>{
  const n=network();const receipt=semanticReceipt() as Record<string,unknown>;
  const out=await handleProfileContinuation(PROFILE_CONTINUE_ACTION,{
    execution_id:id,source_revision:sha,source_digest:digest,
    semantic_judge_result:receipt,
    semantic_evidence_ref:"actions://test/lf/runs/100/artifact/independent.json",
  },config,n.fetchFn,sha);
  eq(out.status,200);eq((await out.json()).phase,"PROFILE_EXECUTION_COMPLETED");
});

Deno.test("continuation: Router-only check11 cannot self-assert true when not tested",async()=>{
  const n=network();const receipt=semanticReceipt() as Record<string,unknown>;
  const v3=receipt.judge_v3_evidence as Record<string,unknown>;
  const checks=v3.decision_checks as Record<string,unknown>;
  (checks.router_direct_consistency as Record<string,unknown>).result=true;
  const out=await handleProfileContinuation(PROFILE_CONTINUE_ACTION,{
    execution_id:id,source_revision:sha,source_digest:digest,
    semantic_judge_result:receipt,
    semantic_evidence_ref:"actions://test/lf/runs/100/artifact/independent.json",
  },config,n.fetchFn,sha);
  eq(out.status,409);eq((await out.json()).code,"PROFILE_NATIVE_ROUTER_ONLY_APPLICABILITY_INVALID");
  eq(n.calls.some(c=>c.url.endsWith("/lf_profile_native_bridge_record_semantic_v1")),false);
});

Deno.test("continuation: claimed Router/direct PASS without paired authentic refs blocks",async()=>{
  const n=network();const receipt=semanticReceipt() as Record<string,unknown>;
  const v3=receipt.judge_v3_evidence as Record<string,unknown>;
  const checks=v3.decision_checks as Record<string,unknown>;
  v3.router_direct_consistency="PASS";
  Object.assign(checks.router_direct_consistency as Record<string,unknown>,{
    result:true,applicability:"AUTHORIZED_COMPARISON",
  });
  const out=await handleProfileContinuation(PROFILE_CONTINUE_ACTION,{
    execution_id:id,source_revision:sha,source_digest:digest,
    semantic_judge_result:receipt,
    semantic_evidence_ref:"actions://test/lf/runs/100/artifact/independent.json",
  },config,n.fetchFn,sha);
  eq(out.status,409);eq((await out.json()).code,"PROFILE_NATIVE_ROUTER_DIRECT_COMPARISON_UNPROVEN");
  eq(n.calls.some(c=>c.url.endsWith("/lf_profile_native_bridge_record_semantic_v1")),false);
});

Deno.test("continuation: semantic review cannot self-assert PASS without V3 evidence",async()=>{
  const n=network();
  const receipt=semanticReceipt() as Record<string,unknown>;
  receipt.judge_v3_evidence={verdict:"PASS_INDEPENDENT_SEMANTIC"};
  const out=await handleProfileContinuation(PROFILE_CONTINUE_ACTION,{
    execution_id:id,source_revision:sha,source_digest:digest,
    semantic_judge_result:receipt,
    semantic_evidence_ref:"actions://test/lf/runs/100/artifact/profile-semantic-judge.json",
  },config,n.fetchFn,sha);
  const body=await out.json();
  eq(out.status,409);eq(body.code,"PROFILE_NATIVE_SEMANTIC_V3_EVIDENCE_INVALID");
  eq(n.calls.some(c=>c.url.endsWith("/lf_profile_native_bridge_record_semantic_v1")),false);
});
Deno.test("continuation: report-only finalization uses existing bridge",async()=>{
  const n=network();
  const out=await handleProfileContinuation(PROFILE_CONTINUE_ACTION,{
    execution_id:id,source_revision:sha,source_digest:digest,finalize_report:true,
  },config,n.fetchFn,sha);
  const body=await out.json();
  eq(out.status,200);eq(body.phase,"PROFILE_EXECUTION_COMPLETED");
  eq(n.calls.some(c=>c.url.endsWith("/lf_profile_native_bridge_record_report_v1")),true);
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

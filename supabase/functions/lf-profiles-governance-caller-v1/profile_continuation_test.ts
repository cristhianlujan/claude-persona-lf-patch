import {resolveOidcIdentity, type CallerConfig} from "./caller.ts";
import {handleProfileContinuation,PROFILE_CONTINUATION_ACTIONS,PROFILE_CONTINUE_ACTION,PROFILE_SKILL_INVOKE_ACTION,PROFILE_SKILL_STEP_BATCH_ACTION,PROFILE_SOURCE_BIND_ACTION} from "./profile_continuation.ts";

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
  eq(body.next_action,"PRODUCE_EVIDENCED_V3_AND_SUBMIT_GOVERNED_CONTINUATION");
  eq(body.governed_continuation?.schema_version,"LF_PROFILE_NATIVE_RESUME_REQUEST_V1");
  eq(body.governed_continuation?.issue_label,"lf-profile-resume-governed");
  eq(body.governed_continuation?.reuse_execution_id,true);
  eq(body.governed_continuation?.owner_reauthorization_required,false);
  eq(body.governed_continuation?.credential_route,"GITHUB_OIDC_TO_EDGE_ONLY");
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
Deno.test("continuation: owner-authorized current-context V3 PASS remains honestly non-independent",async()=>{
  const n=network();
  const receipt=semanticReceipt() as Record<string,unknown>;
  const v3=receipt.judge_v3_evidence as Record<string,unknown>;
  for(const item of [receipt,v3]){
    item.verdict="PASS_REVIEWED_CURRENT_CONTEXT";
    item.review_mode="CURRENT_CONTEXT_REVIEW";
    item.producer_independence_proven=false;
    item.reviewer_is_producer=true;
    item.model_call_count=0;
  }
  (receipt.result as Record<string,unknown>).verdict="PASS_REVIEWED_CURRENT_CONTEXT";
  const out=await handleProfileContinuation(PROFILE_CONTINUE_ACTION,{
    execution_id:id,source_revision:sha,source_digest:digest,
    semantic_judge_result:receipt,
    semantic_evidence_ref:"actions://test/lf/runs/100/artifact/current-context-review.json",
  },config,n.fetchFn,sha);
  const body=await out.json();
  eq(out.status,200);eq(body.phase,"PROFILE_EXECUTION_COMPLETED");
  const call=n.calls.find(c=>c.url.endsWith("/lf_profile_native_bridge_record_semantic_v1"));
  if(!call)throw Error("CURRENT_CONTEXT_SEMANTIC_NOT_RECORDED");
  eq((call.body?.p_semantic_judge_result as Record<string,unknown>).producer_independence_proven,false);
});
Deno.test("continuation: current-context review cannot falsely claim independence",async()=>{
  const n=network();
  const receipt=semanticReceipt() as Record<string,unknown>;
  const v3=receipt.judge_v3_evidence as Record<string,unknown>;
  for(const item of [receipt,v3]){
    item.verdict="PASS_REVIEWED_CURRENT_CONTEXT";
    item.review_mode="CURRENT_CONTEXT_REVIEW";
    item.model_call_count=0;
    item.reviewer_is_producer=true;
  }
  (receipt.result as Record<string,unknown>).verdict="PASS_REVIEWED_CURRENT_CONTEXT";
  const out=await handleProfileContinuation(PROFILE_CONTINUE_ACTION,{
    execution_id:id,source_revision:sha,source_digest:digest,
    semantic_judge_result:receipt,
    semantic_evidence_ref:"actions://test/lf/runs/100/artifact/current-context-review.json",
  },config,n.fetchFn,sha);
  eq(out.status,409);eq((await out.json()).code,"PROFILE_NATIVE_SEMANTIC_RECEIPT_NOT_PASS");
  eq(n.calls.some(c=>c.url.endsWith("/lf_profile_native_bridge_record_semantic_v1")),false);
});
Deno.test("continuation: current-context cannot omit counterfactual evidence",async()=>{
  const n=network();
  const receipt=semanticReceipt() as Record<string,unknown>;
  const v3=receipt.judge_v3_evidence as Record<string,unknown>;
  for(const item of [receipt,v3]){
    item.verdict="PASS_REVIEWED_CURRENT_CONTEXT";
    item.review_mode="CURRENT_CONTEXT_REVIEW";
    item.producer_independence_proven=false;
    item.reviewer_is_producer=true;
    item.model_call_count=0;
  }
  (receipt.result as Record<string,unknown>).verdict="PASS_REVIEWED_CURRENT_CONTEXT";
  v3.counterfactual_result=null;
  const out=await handleProfileContinuation(PROFILE_CONTINUE_ACTION,{
    execution_id:id,source_revision:sha,source_digest:digest,
    semantic_judge_result:receipt,
    semantic_evidence_ref:"actions://test/lf/runs/100/artifact/current-context-review.json",
  },config,n.fetchFn,sha);
  eq(out.status,409);eq((await out.json()).code,"PROFILE_NATIVE_SEMANTIC_V3_EVIDENCE_INVALID");
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
Deno.test("continuation: blocked or returned step70 retries SAME RUN without bypassing predecessors",async()=>{
  for(const retryStatus of ["BLOCKED_STEP_NOT_CLEAN","RETURN_TO_ROUTER"]){
    const n=postModelNetwork([...cleanRows(),{step_id:"semantic_judge",status:retryStatus}],9);
    const out=await handleProfileContinuation(PROFILE_CONTINUE_ACTION,{
      execution_id:id,source_revision:sha,source_digest:digest,
    },config,n.fetchFn,sha);
    const body=await out.json();
    eq(out.status,200);eq(body.outcome,"CONTINUATION_REQUIRED");
    eq(body.phase,"INDEPENDENT_SEMANTIC_JUDGE_REQUIRED");
    eq(body.execution_id,id);eq(body.result.next_step,"semantic_judge");
    eq(body.result.clean_step_count,9);
    eq(n.urls.filter(u=>u.includes("/lf_operation_execution_steps?")).length,1);
    eq(n.urls.some(u=>u.includes("/lf_record_profile_execution_step_v1")),false);
  }
});
Deno.test("continuation: false clean count or unexpected step fails closed",async()=>{
  const cases=[
    {rows:cleanRows().map(x=>x.step_id==="output_validate"?{...x,status:"BLOCKED_STEP_NOT_CLEAN"}:x),count:9},
    {rows:[...cleanRows(),{step_id:"semantic_judge",status:"BLOCKED_STEP_NOT_CLEAN"}],count:10},
    {rows:[...cleanRows(),{step_id:"semantic_judge",status:"UNKNOWN"}],count:9},
    {rows:cleanRows(true),count:9},
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

// --- skill invocation from a read-only profile through its own governed route ---
const mainSha="c".repeat(40),blobSha="d".repeat(40),readmeSha="e".repeat(40);
const gh:{fail:boolean;dir:boolean;ownerValid:boolean;ownerMissing:boolean;registeredCandidate:boolean}={
  fail:false,dir:false,ownerValid:true,ownerMissing:false,registeredCandidate:false};
const ownerProof={asset_code:"ACT-0045",root_path:"skills/profile_creator",
  readme_path:"skills/profile_creator/README.md",readme_blob_sha:readmeSha,main_sha:mainSha};
const callerId={method:"GITHUB_ACTIONS_OIDC_GOVERNED_NATIVE_PROFILE_CONTINUATION_V1",repository:repo,workflow_ref:oidc.workflow_ref,run_id:"100",workflow_sha:sha};
function skillNetwork(overrides:Record<string,unknown>={},invoke:{status:number;body:unknown}={status:200,body:{status:"CHILD_OPENED",child_execution_id:"EXEC-SKILL-0123456789ABCDEF"}}){
  const n=network(overrides);
  const fetchFn=async(input:string|URL|Request,init?:RequestInit)=>{
    const url=String(input);
    if(url.startsWith("https://api.github.com/")){
      n.calls.push({url,body:null});
      if(gh.fail)return new Response("{}",{status:404});
      if(url.includes("/git/ref/heads/main"))return new Response(JSON.stringify({object:{sha:mainSha}}),{status:200});
      if(url.includes("/contents/skills/") && url.includes("/README.md?ref=")){
        if(gh.ownerMissing)return new Response("{}",{status:404});
        const line=gh.registeredCandidate
          ? "**Una skill registrable:** `PROGRAMMING_ANALYSIS_LF`."
          : gh.ownerValid?"- ACT-0045 is the governing asset for Profile Creator.":"- ACT-9999 is the governing asset.";
        return new Response(JSON.stringify({sha:readmeSha,type:"file",encoding:"base64",content:btoa(line)}),{status:200});
      }
      if(url.includes("/contents/"))return new Response(JSON.stringify(gh.dir?[{name:"a"}]:{sha:blobSha,type:"file"}),{status:200});
    }
    if(url.endsWith("/lf_skill_invoke_v1")){
      n.calls.push({url,body:typeof init?.body==="string"?JSON.parse(init.body) as Record<string,unknown>:null});
      return new Response(JSON.stringify(invoke.body),{status:invoke.status});
    }
    return n.fetchFn(input,init);
  };
  return {fetchFn,calls:n.calls};
}
const skillInput={target_code:"PERFIL-X-LF",target_path:"profiles/x/SKILL.md"};
Deno.test("skill invoke: action is in the native-continuation scope",()=>{
  eq((PROFILE_CONTINUATION_ACTIONS as readonly string[]).includes(PROFILE_SKILL_INVOKE_ACTION),true);
});
Deno.test("skill invoke: parent is the authenticated execution, never caller-supplied",async()=>{
  const n=skillNetwork();
  const out=await handleProfileContinuation(PROFILE_SKILL_INVOKE_ACTION,{
    execution_id:id,parent_execution_id:"EXEC-ATTACKER-0000000000",p_execution_id:"EXEC-ATTACKER-0000000000",
    skill_code:"PROFILE_UPDATE_APPLY",input:skillInput},config,n.fetchFn,sha,callerId);
  const b=await out.json();eq(out.status,200);eq(b.outcome,"SKILL_INVOKED");eq(b.result.child_execution_id,"EXEC-SKILL-0123456789ABCDEF");
  const call=n.calls.find(c=>c.url.endsWith("/lf_skill_invoke_v1"));
  eq(call?.body,{p_skill:"PROFILE_UPDATE_APPLY",p_execution_id:id,p_input:{...skillInput,_trusted:{main_sha:mainSha,target_blob_sha:blobSha,caller:callerId}}});
});
Deno.test("skill invoke: invalid skill code or input never reaches the invoker",async()=>{
  for(const bad of [{skill_code:"profile_update_apply",input:skillInput},{skill_code:"X; DROP",input:skillInput},
    {skill_code:"PROFILE_UPDATE_APPLY",input:"text"},{skill_code:"PROFILE_UPDATE_APPLY",input:[1]},{skill_code:"PROFILE_UPDATE_APPLY"},{input:skillInput}]){
    const n=skillNetwork();
    const out=await handleProfileContinuation(PROFILE_SKILL_INVOKE_ACTION,{execution_id:id,...bad},config,n.fetchFn,sha,callerId);
    eq(out.status,400);eq(n.calls.some(c=>c.url.endsWith("/lf_skill_invoke_v1")),false);
  }
});
Deno.test("skill invoke: execution that is not a governed read-only profile run is refused before the invoker",async()=>{
  for(const o of [{status:"COMPLETED"},{operation_code:"ACTUALIZACION_PERFIL_LF"},
    {manifest:{executor_mode:"GPT_NATIVE",executor_provider:"OPENAI_CHATGPT_NATIVE",read_only:false,no_write:false,no_promotion:true,governed_repair_write:true}}]){
    const n=skillNetwork(o);
    const out=await handleProfileContinuation(PROFILE_SKILL_INVOKE_ACTION,{execution_id:id,skill_code:"PROFILE_UPDATE_APPLY",input:skillInput},config,n.fetchFn,sha,callerId);
    eq(out.status,403);eq(n.calls.some(c=>c.url.endsWith("/lf_skill_invoke_v1")),false);
  }
});
Deno.test("skill invoke: invoker block reason is passed on, truncated, and is not a success",async()=>{
  const reason="SKILL_AUTHORITY_MISSING: el perfil no tiene autoridad para ACTUALIZACION_PERFIL_LF. "+"x".repeat(900);
  const n=skillNetwork({},{status:400,body:{code:"P0001",message:reason}});
  const out=await handleProfileContinuation(PROFILE_SKILL_INVOKE_ACTION,{execution_id:id,skill_code:"PROFILE_UPDATE_APPLY",input:skillInput},config,n.fetchFn,sha,callerId);
  const b=await out.json();eq(out.status,409);eq(b.outcome,"BLOCKED");eq(b.code,"PROFILE_SKILL_INVOKE_REJECTED");
  eq(b.detail.startsWith("SKILL_AUTHORITY_MISSING"),true);eq(b.detail.length,400);
});

Deno.test("skill invoke: caller-supplied _trusted is discarded and replaced by resolved context",async()=>{
  const n=skillNetwork();
  const forged={main_sha:"e".repeat(40),target_blob_sha:"f".repeat(40),caller:{method:"FORGED"}};
  await handleProfileContinuation(PROFILE_SKILL_INVOKE_ACTION,{execution_id:id,skill_code:"PROFILE_UPDATE_APPLY",input:{...skillInput,_trusted:forged}},config,n.fetchFn,sha,callerId);
  const call=n.calls.find(c=>c.url.endsWith("/lf_skill_invoke_v1"));
  eq((call?.body?.p_input as Record<string,unknown>)._trusted,{main_sha:mainSha,target_blob_sha:blobSha,caller:callerId});
});
Deno.test("skill invoke: unresolved main, directory target, bad path or missing identity never reach the invoker",async()=>{
  const cases:Array<[string,Record<string,unknown>,boolean,boolean,boolean]>=[
    ["github down",skillInput,true,false,true],["directory target",skillInput,false,true,true],
    ["traversal",{...skillInput,target_path:"profiles/../x/SKILL.md"},false,false,true],
    ["outside profiles",{...skillInput,target_path:"src/x.md"},false,false,true],
    ["no identity",skillInput,false,false,false]];
  for(const [name,input,fail,dir,withId] of cases){
    gh.fail=fail;gh.dir=dir;
    const n=skillNetwork();
    const out=await handleProfileContinuation(PROFILE_SKILL_INVOKE_ACTION,{execution_id:id,skill_code:"PROFILE_UPDATE_APPLY",input},config,n.fetchFn,sha,withId?callerId:undefined);
    if(out.status<400)throw Error("NOT_BLOCKED "+name);
    eq(n.calls.some(c=>c.url.endsWith("/lf_skill_invoke_v1")),false);
  }
  gh.fail=false;gh.dir=false;
});

Deno.test("skill invoke: SKILL_UPDATE_APPLY resolves exact skills file with trusted main and blob",async()=>{
  const input={target_code:"ACT-0045",target_path:"skills/profile_creator/validators/compare_s26_profile_evolution_v1.py"};
  const n=skillNetwork();
  const out=await handleProfileContinuation(PROFILE_SKILL_INVOKE_ACTION,{
    execution_id:id,skill_code:"SKILL_UPDATE_APPLY",input},config,n.fetchFn,sha,callerId);
  const b=await out.json();eq(out.status,200);eq(b.outcome,"SKILL_INVOKED");
  const call=n.calls.find(c=>c.url.endsWith("/lf_skill_invoke_v1"));
  eq(call?.body,{p_skill:"SKILL_UPDATE_APPLY",p_execution_id:id,
    p_input:{...input,_trusted:{main_sha:mainSha,target_blob_sha:blobSha,caller:callerId,github_owner:ownerProof}}});
  eq(n.calls.some(c=>c.url.includes("/contents/skills/profile_creator/validators/compare_s26_profile_evolution_v1.py?ref=")),true);
  eq(n.calls.some(c=>c.url.includes("/contents/skills/profile_creator/README.md?ref=")),true);
});

Deno.test("skill invoke: first registered candidate has typed owner provenance, not approval",async()=>{
  gh.registeredCandidate=true;
  try {
    const input={target_code:"PROGRAMMING_ANALYSIS_LF",target_path:"skills/programming_analysis/SKILL.md"};
    const n=skillNetwork();
    const out=await handleProfileContinuation(PROFILE_SKILL_INVOKE_ACTION,{
      execution_id:id,skill_code:"SKILL_UPDATE_APPLY",input},config,n.fetchFn,sha,callerId);
    eq(out.status,200);
    const call=n.calls.find(c=>c.url.endsWith("/lf_skill_invoke_v1"));
    eq(call?.body,{p_skill:"SKILL_UPDATE_APPLY",p_execution_id:id,
      p_input:{...input,_trusted:{main_sha:mainSha,target_blob_sha:blobSha,caller:callerId,
        github_owner:{asset_code:"PROGRAMMING_ANALYSIS_LF",
          root_path:"skills/programming_analysis",
          readme_path:"skills/programming_analysis/README.md",
          readme_blob_sha:readmeSha,main_sha:mainSha,declaration_kind:"REGISTERED_CANDIDATE"}}}});
    const forged=skillNetwork();
    const denied=await handleProfileContinuation(PROFILE_SKILL_INVOKE_ACTION,{
      execution_id:id,skill_code:"SKILL_UPDATE_APPLY",
      input:{...input,target_code:"PROGRAMMING_ANALYSIS_OTHER"}},config,forged.fetchFn,sha,callerId);
    eq(denied.status,409);
    eq(forged.calls.some(c=>c.url.endsWith("/lf_skill_invoke_v1")),false);
  } finally { gh.registeredCandidate=false; }
});

Deno.test("skill invoke: only SKILL_UPDATE_APPLY can resolve skills paths",async()=>{
  const input={target_code:"ACT-0045",target_path:"skills/profile_creator/validators/compare_s26_profile_evolution_v1.py"};
  for(const code of ["PROFILE_UPDATE_APPLY","RULE_UPDATE_APPLY","SKILL_UPDATE_APPLY_WRONG"]) {
    const n=skillNetwork();
    const out=await handleProfileContinuation(PROFILE_SKILL_INVOKE_ACTION,{
      execution_id:id,skill_code:code,input},config,n.fetchFn,sha,callerId);
    eq(out.status,400);
    eq(n.calls.some(c=>c.url.endsWith("/lf_skill_invoke_v1")),false);
  }
});

Deno.test("skill invoke: skill update fails closed on directories and traversal",async()=>{
  const bad=["skills/profile_creator","skills/../profile_creator/SKILL.md",
    "skills/profile_creator//SKILL.md","skills/profile_creator/../SKILL.md",
    "profiles/systemic_root_cause_repair_lf/SKILL.md","src/profile_creator/validators/x.py",
    "/skills/profile_creator/SKILL.md"];
  for(const target_path of bad){
    const n=skillNetwork();
    const out=await handleProfileContinuation(PROFILE_SKILL_INVOKE_ACTION,{
      execution_id:id,skill_code:"SKILL_UPDATE_APPLY",input:{target_code:"ACT-0045",target_path}
    },config,n.fetchFn,sha,callerId);
    eq(out.status,400);
    eq(n.calls.some(c=>c.url.endsWith("/lf_skill_invoke_v1")),false);
  }
});

Deno.test("skill invoke: skill update still discards caller forgery and rejects missing OIDC",async()=>{
  const input={target_code:"ACT-0045",target_path:"skills/profile_creator/SKILL.md"};
  const forged={main_sha:"f".repeat(40),target_blob_sha:"e".repeat(40),caller:{method:"FORGED"}};
  const n=skillNetwork();
  await handleProfileContinuation(PROFILE_SKILL_INVOKE_ACTION,{
    execution_id:id,skill_code:"SKILL_UPDATE_APPLY",input:{...input,_trusted:forged}
  },config,n.fetchFn,sha,callerId);
  const call=n.calls.find(c=>c.url.endsWith("/lf_skill_invoke_v1"));
  eq((call?.body?.p_input as Record<string,unknown>)._trusted,
    {main_sha:mainSha,target_blob_sha:blobSha,caller:callerId,github_owner:ownerProof});
  const missing=skillNetwork();
  const out=await handleProfileContinuation(PROFILE_SKILL_INVOKE_ACTION,{
    execution_id:id,skill_code:"SKILL_UPDATE_APPLY",input
  },config,missing.fetchFn,sha,undefined);
  eq(out.status,500);eq(missing.calls.some(c=>c.url.endsWith("/lf_skill_invoke_v1")),false);
});

Deno.test("skill invoke: current README owner mismatch or absence stops before SQL",async()=>{
  const input={target_code:"ACT-0045",target_path:"skills/profile_creator/validators/compare_s26_profile_evolution_v1.py"};
  for(const [ownerValid,ownerMissing,expected] of [
    [false,false,"SKILL_UPDATE_OWNER_DECLARATION_MISMATCH"],
    [true,true,"SKILL_UPDATE_OWNER_README_UNAVAILABLE"],
  ] as const){
    gh.ownerValid=ownerValid; gh.ownerMissing=ownerMissing;
    const n=skillNetwork();
    const out=await handleProfileContinuation(PROFILE_SKILL_INVOKE_ACTION,{
      execution_id:id,skill_code:"SKILL_UPDATE_APPLY",input
    },config,n.fetchFn,sha,callerId);
    const body=await out.json();
    eq(out.status,409);eq(body.code,expected);
    eq(n.calls.some(c=>c.url.endsWith("/lf_skill_invoke_v1")),false);
  }
  gh.ownerValid=true; gh.ownerMissing=false;
});


// Existing native profile OIDC route: child step records only in the canonical
// ACTUALIZACION_SKILL_LF ledger; no new router or backend.
const skillChildId="EXEC-SKILL-49797550002EE84C";
const childPath="skills/profile_creator/validators/compare_s26_profile_evolution_v1.py";
function stepNetwork(options:{
  childOverride?:Record<string,unknown>;
  blockStep?:string;
  brokenReadback?:boolean;
}={}){
  const n=skillNetwork();
  const calls=n.calls;
  const recorded:string[]=[];
  const fetchFn=async(input:string|URL|Request,init?:RequestInit)=>{
    const url=String(input);
    const body=typeof init?.body==="string"?JSON.parse(init.body) as Record<string,unknown>:null;
    if(url.includes("/lf_operation_execution?")&&url.includes(skillChildId)){
      calls.push({url,body});
      const child={execution_id:skillChildId,status:"IN_PROGRESS",
        operation_code:"ACTUALIZACION_SKILL_LF",target_type:"SKILL",
        target_code:"ACT-0045",target_repo:repo,target_path:childPath,
        created_by_execution_id:id,manifest:{profile_handoff:{source_execution_id:id},
          router_governed_caller_code:"CALLER-GHA-NATIVE-SKILL-UPDATE-V1"},
        ...options.childOverride};
      return new Response(JSON.stringify([child]),{status:200});
    }
    if(url.endsWith("/lf_skill_update_child_step_v1")){
      calls.push({url,body});
      if(options.blockStep===body?.p_step)
        return new Response(JSON.stringify({outcome:"BLOCKED",
          code:"SKILL_UPDATE_PREWRITE_BINDING_NOT_PROVEN"}),{status:200});
      recorded.push(String(body?.p_step));
      return new Response(JSON.stringify({outcome:"STEP_RECORDED",
        step_id:body?.p_step,status:"STEP_PASS_WITH_EVIDENCE"}),{status:200});
    }
    if(url.includes("/lf_operation_execution_steps?")){
      calls.push({url,body});
      const rows=options.brokenReadback?[]:recorded.map(step_id=>(
        {step_id,status:"STEP_PASS_WITH_EVIDENCE"}));
      return new Response(JSON.stringify(rows),{status:200});
    }
    return n.fetchFn(input,init);
  };
  return {fetchFn,calls,recorded};
}
const stepNames=[
 "router","skill_resolve","baseline_read","change_scope","regression_plan",
 "pre_write_execution_binding_gate",
];
const stepItems=stepNames.map((step_id,i)=>({
 step_id,evidence_ref:"git:verified-step-"+i,
 evidence_payload:{blocking_codes:[],source:"authenticated-owner"},
}));

Deno.test("skill step: registered as existing native OIDC continuation action",()=>{
 eq((PROFILE_CONTINUATION_ACTIONS as readonly string[]).includes(
   PROFILE_SKILL_STEP_BATCH_ACTION),true);
});

Deno.test("skill step: 6-step ordered batch records via exactly one canonical RPC per step",async()=>{
 const n=stepNetwork();
 const response=await handleProfileContinuation(PROFILE_SKILL_STEP_BATCH_ACTION,{
   execution_id:id,child_execution_id:skillChildId,steps:stepItems,
 },config,n.fetchFn,sha,callerId);
 const b=await response.json();
 eq(response.status,200);eq(b.outcome,"SKILL_CHILD_STEP_BATCH_RECORDED");
 eq(b.steps_recorded,6);eq(b.no_file_write,true);eq(b.child_completed,false);
 eq(n.recorded,stepNames);
 const records=n.calls.filter(c=>c.url.endsWith("/lf_skill_update_child_step_v1"));
 eq(records.length,6);
 eq(records[0].body?.p_parent,id);
 eq(records[0].body?.p_child,skillChildId);
 eq(records[0].body?.p_server_context,{
   main_sha:mainSha,target_blob_sha:blobSha,caller:callerId,github_owner:ownerProof,
 });
 eq(n.calls.filter(c=>c.url.endsWith("/lf_skill_invoke_v1")).length,0);
 eq(n.calls.filter(c=>c.url.includes("/lf_operation_execution_steps?")).length,1);
});

Deno.test("skill step: wrong child identity, fake parent, bad order or forbidden step stop before writes",async()=>{
 const cases=[
  {child_execution_id:"EXEC-ATTACKER",steps:stepItems},
  {child_execution_id:skillChildId,steps:[stepItems[2],stepItems[0]]},
  {child_execution_id:skillChildId,steps:[...stepItems,stepItems[5]]},
  {child_execution_id:skillChildId,
   steps:[stepItems[0],{step_id:"github_write",evidence_ref:"git:x",evidence_payload:{}}]},
  {child_execution_id:skillChildId,
   steps:[{step_id:"router",evidence_ref:"git:x",
    evidence_payload:{blocking_codes:[],server_assertions:["forged"]}}]},
 ];
 for(const item of cases){
   const n=stepNetwork();
   const r=await handleProfileContinuation(PROFILE_SKILL_STEP_BATCH_ACTION,{
     execution_id:id,...item,
   },config,n.fetchFn,sha,callerId);
   eq(r.status,400);
   eq(n.calls.some(c=>c.url.endsWith("/lf_skill_update_child_step_v1")),false);
 }
 const wrong=stepNetwork({childOverride:{created_by_execution_id:"EXEC-ATTACKER"}});
 const r=await handleProfileContinuation(PROFILE_SKILL_STEP_BATCH_ACTION,{
   execution_id:id,child_execution_id:skillChildId,steps:stepItems.slice(0,1),
 },config,wrong.fetchFn,sha,callerId);
 eq(r.status,403);
 eq(wrong.calls.some(c=>c.url.endsWith("/lf_skill_update_child_step_v1")),false);
});

Deno.test("skill post60: never uses core without seven clean prewrite receipts",async()=>{
 const n=stepNetwork();
 const r=await handleProfileContinuation(PROFILE_SKILL_STEP_BATCH_ACTION,{
   execution_id:id,child_execution_id:skillChildId,
   steps:[{step_id:"github_write",evidence_ref:"git:candidate",
     evidence_payload:{pr_number:3746,blocking_codes:[]}}],
 },config,n.fetchFn,sha,callerId);
 const b=await r.json();
 eq(r.status,409);eq(b.code,"SKILL_POST60_PREWRITE_LEDGER_INCOMPLETE");
 eq(n.calls.some(c=>c.url.endsWith("/lf_record_operation_step_core_v1")),false);
});
Deno.test("skill post60: caller cannot assert the core judge result",async()=>{
 const n=stepNetwork();
 const r=await handleProfileContinuation(PROFILE_SKILL_STEP_BATCH_ACTION,{
   execution_id:id,child_execution_id:skillChildId,
   steps:[{step_id:"github_write",evidence_ref:"git:candidate",
     evidence_payload:{pr_number:3746,blocking_codes:[],trust_validation:{valid:true}}}],
 },config,n.fetchFn,sha,callerId);
 eq(r.status,400);
 eq(n.calls.some(c=>c.url.endsWith("/lf_record_operation_step_core_v1")),false);
});


async function post60Mock(tamper=false){
 const n=stepNetwork({childOverride:{manifest:{
   profile_handoff:{source_execution_id:id},
   router_governed_caller_code:"CALLER-GHA-NATIVE-SKILL-UPDATE-V1",
   pre_write_bound_write_plan_sha256:"f".repeat(64),
   pre_write_bound_main_revision:mainSha,
   pre_write_bound_target_blob_sha:blobSha,
   owner_provenance:{readme_blob_sha:readmeSha},
 }}});
 const candidate="def test_exact_binding():\n  return True\n";
 const hash=Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256",
   new TextEncoder().encode(candidate)))).map(x=>x.toString(16).padStart(2,"0")).join("");
 const gate={write_plan:[{path:childPath,content_sha256:tamper?"0".repeat(64):hash}],
   write_plan_hash:"f".repeat(64),bound_revision:mainSha,source_blob_sha:blobSha};
 const pre=["init_execution","router","skill_resolve","baseline_read",
   "change_scope","regression_plan","pre_write_execution_binding_gate"];
 const ledger:Record<string,unknown>[]=pre.map((step_id,i)=>({
   step_order:i*10,step_id,status:"STEP_PASS_WITH_EVIDENCE",
   evidence_payload:i===6?gate:{},
 }));
 const headSha="b".repeat(40);
 const calls=n.calls;
 const fetchFn=async(input:string|URL|Request,init?:RequestInit):Promise<Response>=>{
   const url=String(input);
   const body=typeof init?.body==="string"?JSON.parse(init.body) as Record<string,unknown>:null;
   if(url.includes("/lf_operation_execution_steps?")){
     calls.push({url,body});
     return new Response(JSON.stringify(ledger),{status:200});
   }
   if(url.endsWith("/lf_record_operation_step_core_v1")){
     calls.push({url,body});
     ledger.push({step_id:body?.p_step_id,status:"STEP_PASS_WITH_EVIDENCE"});
     return new Response(JSON.stringify({outcome:"STEP_RECORDED",
       step_id:body?.p_step_id,status:"STEP_PASS_WITH_EVIDENCE"}),{status:200});
   }
   if(url.includes("/pulls/3746/files?"))
     return new Response(JSON.stringify([{filename:childPath},
       {filename:"skills/profile_creator/validators/test_compare_s26_profile_evolution_v1.py"}]),{status:200});
   if(url.endsWith("/pulls/3746"))
     return new Response(JSON.stringify({number:3746,merged:false,
       head:{sha:headSha,ref:"fix/s26",repo:{full_name:repo}},
       base:{ref:"main",sha:mainSha}}),{status:200});
   if(url.includes("/git/ref/heads/main"))
     return new Response(JSON.stringify({object:{sha:mainSha}}),{status:200});
   if(url.includes("/contents/"+childPath+"?ref="+mainSha))
     return new Response(JSON.stringify({sha:blobSha}),{status:200});
   if(url.includes("/contents/skills/profile_creator/README.md?ref="+mainSha))
     return new Response(JSON.stringify({sha:readmeSha}),{status:200});
   if(url.includes("/contents/"+childPath+"?ref="+headSha))
     return new Response(JSON.stringify({type:"file",encoding:"base64",
       sha:"d".repeat(40),content:btoa(candidate)}),{status:200});
   return n.fetchFn(input,init);
 };
 return {fetchFn,calls,ledger};
}
Deno.test("skill post60: exact GitHub SHA and frozen plan reach existing core 70/80",async()=>{
 const n=await post60Mock();
 const out=await handleProfileContinuation(PROFILE_SKILL_STEP_BATCH_ACTION,{
   execution_id:id,child_execution_id:skillChildId,
   steps:[{step_id:"github_write",evidence_ref:"git:write",
      evidence_payload:{pr_number:3746,blocking_codes:[]}},
     {step_id:"github_readback",evidence_ref:"git:readback",
      evidence_payload:{pr_number:3746,blocking_codes:[]}}],
 },config,n.fetchFn,sha,callerId);
 const b=await out.json();
 eq(out.status,200);eq(b.outcome,"SKILL_CHILD_STEP_BATCH_RECORDED");
 eq(b.steps_recorded,2);eq(b.no_file_write,true);
 const rpc=n.calls.filter(c=>c.url.endsWith("/lf_record_operation_step_core_v1"));
 eq(rpc.length,2);
 eq(rpc.map(c=>c.body?.p_step_id),["github_write","github_readback"]);
 eq((rpc[0].body?.p_trust_validation as Record<string,unknown>)?.source,
   "OIDC_EDGE_GITHUB_VERIFIED");
});
Deno.test("skill post60: candidate SHA mismatch fails before the SQL writer",async()=>{
 const n=await post60Mock(true);
 const out=await handleProfileContinuation(PROFILE_SKILL_STEP_BATCH_ACTION,{
   execution_id:id,child_execution_id:skillChildId,
   steps:[{step_id:"github_write",evidence_ref:"git:write",
     evidence_payload:{pr_number:3746,blocking_codes:[]}}],
 },config,n.fetchFn,sha,callerId);
 const b=await out.json();
 eq(out.status,409);eq(b.code,"SKILL_POST60_CANDIDATE_SHA256_MISMATCH");
 eq(n.calls.some(c=>c.url.endsWith("/lf_record_operation_step_core_v1")),false);
});

Deno.test("skill step: only exact OIDC identity can write ledger",async()=>{
 const n=stepNetwork();
 const r=await handleProfileContinuation(PROFILE_SKILL_STEP_BATCH_ACTION,{
   execution_id:id,child_execution_id:skillChildId,steps:stepItems.slice(0,1),
 },config,n.fetchFn,sha,undefined);
 eq(r.status,403);
 eq(n.calls.some(c=>c.url.endsWith("/lf_skill_update_child_step_v1")),false);
});

Deno.test("skill step: a rejected canonical step aborts batch without false success",async()=>{
 const n=stepNetwork({blockStep:"skill_resolve"});
 const r=await handleProfileContinuation(PROFILE_SKILL_STEP_BATCH_ACTION,{
   execution_id:id,child_execution_id:skillChildId,steps:stepItems.slice(0,3),
 },config,n.fetchFn,sha,callerId);
 const b=await r.json();
 eq(r.status,409);eq(b.outcome,"BLOCKED");
 eq(b.failed_step,"skill_resolve");eq(b.steps_recorded,1);
 eq(n.recorded,["router"]);
});

Deno.test("skill step: missing canonical readback is not a completed batch",async()=>{
 const n=stepNetwork({brokenReadback:true});
 const r=await handleProfileContinuation(PROFILE_SKILL_STEP_BATCH_ACTION,{
   execution_id:id,child_execution_id:skillChildId,steps:stepItems.slice(0,1),
 },config,n.fetchFn,sha,callerId);
 const b=await r.json();
 eq(r.status,409);eq(b.code,"SKILL_CHILD_STEP_READBACK_NOT_CLEAN");
});

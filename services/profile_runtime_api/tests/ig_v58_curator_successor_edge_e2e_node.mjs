// LF V58 isolated Edge-to-Edge cascade test (no network, no production writes).
// Execute the ACTUAL 3 Edge handler sources using in-memory mocked DB transport.
import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";
import { stripTypeScriptTypes } from "node:module";
import { webcrypto } from "node:crypto";
import { performance } from "node:perf_hooks";
import { TextEncoder } from "node:util";

const role = "test-only-synthetic-role-not-a-secret";
const url = "https://test-project.supabase.co";
const ticket = "11111111-1111-4111-8111-111111111111";
const sources = {
  "input-governance-agent-v1":"supabase/functions/input-governance-agent-v1/index.ts",
  "input-governance-validator-v1":"supabase/functions/input-governance-validator-v1/index.ts",
  "input-governance-curator-v1":"supabase/functions/input-governance-curator-v1/index.ts",
};
const scenarios = ["successor", "wrong_successor", "wrong_dispatch", "validator_negative_invalid"];
for (const scenario of scenarios) {
  const handlers = new Map();
  const calls = [];
  let dispatchCount = 0;
  let expectedName = "";
  const mockedFetch = async (target, init) => {
    const pathname = new URL(target).pathname;
    assert.equal(new URL(target).origin,url,"NO_UNEXPECTED_NETWORK_ENDPOINT");
    const payload=JSON.parse(init.body??"{}");
    calls.push(pathname);
    if (pathname.startsWith("/functions/v1/")) {
      const slug=pathname.split("/").at(-1);
      assert.ok(handlers.has(slug),"NO_OUTSIDE_EDGE_RUNTIME");
      return handlers.get(slug)(new Request(target,{
        method:"POST",headers:{"authorization":"Bearer "+role,
        "content-type":"application/json"},body:JSON.stringify(payload)}));
    }
    assert.ok(pathname.startsWith("/rest/v1/rpc/"),"NO_EXTERNAL_API");
    const rpc=pathname.split("/").at(-1);
    if (rpc==="fn_input_governance_execute") {
      dispatchCount++;
      if (dispatchCount===1) {
        return Response.json({status:"VALIDATOR_RUNTIME_REQUIRED",latest_run_id:953});
      }
      if (scenario==="wrong_dispatch" && dispatchCount===2) {
        return Response.json({status:"READY",run_id:513});
      }
      if (dispatchCount===2) {
        return Response.json({status:"VALIDATOR_RUNTIME_REQUIRED",latest_run_id:954});
      }
      return Response.json({status:"READY",run_id:954});
    }
    if (rpc==="fn_input_governance_validator_handoff_assert_v1") {
      return Response.json({status:"VERIFIED",receipt_id:11,
        run_id:payload.p_run_id});
    }
    if (rpc==="fn_input_governance_validator_resume_context_v1") {
      return Response.json({resume_allowed:false});
    }
    if (rpc==="fn_input_governance_validator_validate_handoff_v1") {
      const runId=Number(payload.p_run_id);
      if (runId===953) return Response.json({
        status:"CURATOR_REEVALUATION_REQUIRED",
        run_id:scenario==="validator_negative_invalid"?952:953,
        parent_run_id:513,pantalla_id:44,family_code:"ACCESSIBILITY",
        promotion_authorized:false,production_authorized:false,
      });
      assert.equal(runId,954);
      return Response.json({status:"COMPLETED",run_id:954,
        promotion_authorized:false,production_authorized:false});
    }
    if (rpc==="fn_input_governance_curator_materialize_v1") {
      return Response.json({status:"VALIDATOR_RUNTIME_REQUIRED",
        run_id:scenario==="wrong_successor"?953:954,
        parent_run_id:513,pantalla_id:44,
        promotion_authorized:false,production_authorized:false});
    }
    if (rpc==="fn_input_governance_curator_handoff_receipt_v1") {
      return Response.json({status:"PERSISTED",receipt_id:12,
        run_id:payload.p_run_id});
    }
    if (rpc==="fn_input_governance_safe_autofix_v1") {
      assert.equal(Number(payload.p_run_id),954);
      return Response.json({applied_count:0,skipped_count:0,successor_required:false});
    }
    throw new Error("UNMOCKED_RPC_"+rpc);
  };

  for (const [slug,filepath] of Object.entries(sources)) {
    expectedName=slug;
    const raw=fs.readFileSync(filepath,"utf8")
      .replace(/^import "jsr:[^"]+";\r?\n/m,"");
    const source=stripTypeScriptTypes(raw,{mode:"strip"});
    const scope={
      Deno:{env:{get:(key)=>
        key==="SUPABASE_URL"?url:
        key==="SUPABASE_SERVICE_ROLE_KEY"?role:null},
        serve:(fn)=>handlers.set(slug,fn)},
      Request,Response,TextEncoder,crypto:webcrypto,performance,
      fetch:mockedFetch,console,
      setTimeout,clearTimeout,
    };
    vm.runInNewContext(source,scope,{filename:filepath,timeout:10000});
    assert.ok(handlers.has(slug),"HANDLER_NOT_REGISTERED_"+slug);
  }
  const outcome=await handlers.get("input-governance-agent-v1")(
    new Request(url+"/functions/v1/input-governance-agent-v1",{
      method:"POST",headers:{"authorization":"Bearer "+role,
        "content-type":"application/json"},
      body:JSON.stringify({pantalla_id:44,consumer:"CONTEXT_PACK",ticket})}));
  const result=await outcome.json();
  const curatorCalls=calls.filter(x=>x.endsWith("/input-governance-curator-v1")).length;
  const validatorCalls=calls.filter(x=>x.endsWith("/input-governance-validator-v1")).length;
  if (scenario==="successor") {
    assert.equal(outcome.status,200);
    assert.equal(result.result?.status,"READY");
    assert.equal(result.result?.run_id,954);
    assert.equal(curatorCalls,1);
    assert.equal(validatorCalls,2);
    assert.equal(result.trace?.some(x=>x.step==="CURATOR_RECURATION_SUCCESSOR" &&
      x.failed_run_id===953 && x.successor_run_id===954),true);
  } else {
    assert.equal(outcome.status,409,"NEGATIVE_MUST_FAIL_CLOSED_"+scenario);
    assert.notEqual(result.result?.status,"READY");
    if (scenario==="wrong_successor") assert.equal(result.error,"IG_RECURATION_SUCCESSOR_NOT_ATTESTED");
    if (scenario==="wrong_dispatch") assert.equal(result.error,"IG_RECURATION_SUCCESSOR_DISPATCH_DRIFT");
    if (scenario==="validator_negative_invalid") {
      assert.equal(result.error,"INPUT_GOVERNANCE_ORCHESTRATION_FAILED");
      assert.equal(curatorCalls,0);
    }
  }
  console.log("PASS_IG_V58_EDGE_DISPATCH_MOCK_E2E "+scenario+
    " http="+outcome.status+" curator_calls="+curatorCalls+
    " validator_calls="+validatorCalls+" production_write=false");
}

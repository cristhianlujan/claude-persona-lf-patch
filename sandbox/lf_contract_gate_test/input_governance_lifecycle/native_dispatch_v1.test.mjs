import test from "node:test";
import assert from "node:assert/strict";
import {dispatchNativeV1} from "./native_dispatch_v1.mjs";

const base=Object.freeze({
  phase:"STEP70",execution_id:"EXEC-PROFILE-GATE2-1234567890ABCDEF",
  executor_mode:"GPT_NATIVE",executor_provider:"OPENAI_CHATGPT_NATIVE",
  candidate_sha256:"a".repeat(64),scope_packet_sha256:"b".repeat(64),
});
const workflow=Object.freeze({
  source:"SERVER_VERIFIED_GITHUB_OIDC",scope:"PROFILE_NATIVE_CONTINUATION_ONLY",
  workflow_run_id:"43300000001",workflow_sha256:"c".repeat(64)
});
function fakeAdapter(override={}) {
  return {kind:"TRUSTED_NATIVE_PROVIDER_ADAPTER",
    execute:async(req)=>({
      execution_id:req.execution_id,phase:req.phase,provider:req.executor_provider,
      provider_receipt_ref:"provider://not-live-unit-test",
      producer_independence_proven:true,model_call_count:1,
      candidate_sha256:req.candidate_sha256,scope_packet_sha256:req.scope_packet_sha256,
      ...override
    }),
    verifyProviderReceipt:async()=>false};
}
async function block(label,input,auth,adapter,expected) {
  const v=await dispatchNativeV1(input,auth,adapter);
  assert.equal(v.status,"BLOCKED",label);
  assert.equal(v.blocking_code,expected,label);
  assert.equal(v.write_performed,false,label);
}
test("no provider is always blocked even with valid workflow shape",async()=>{
  await block("no adapter",base,workflow,null,"NATIVE_DISPATCH_REAL_PROVIDER_NOT_CONNECTED");
});
test("HMAC simulation forbidden",async()=>{
  await block("hmac",{...base,hmac_test:"TEST_SIGNATURE"},workflow,null,
    "NATIVE_DISPATCH_TEST_OR_SELF_REVIEW_FORBIDDEN");
});
test("fake Step70 reviewer self-attestation forbidden",async()=>{
  await block("self review",{...base,judge_mode:"CURRENT_CONTEXT_REVIEW"},workflow,null,
    "NATIVE_DISPATCH_TEST_OR_SELF_REVIEW_FORBIDDEN");
});
test("missing OIDC verification blocked",async()=>{
  await block("no oidc",base,null,null,"NATIVE_DISPATCH_OIDC_WORKFLOW_NOT_VERIFIED");
});
test("spoofed workflow scope blocked",async()=>{
  await block("scope",base,{...workflow,scope:"LEGACY_PROFILE_GOVERNANCE"},null,
    "NATIVE_DISPATCH_OIDC_WORKFLOW_NOT_VERIFIED");
});
test("missing Step70 exact digest blocked",async()=>{
  await block("scope digest",{...base,scope_packet_sha256:"INVALID"},workflow,null,
    "NATIVE_DISPATCH_STEP70_EXACT_SHA_REQUIRED");
});
test("faked provider receipt rejected by actual verifier callback",async()=>{
  await block("mock receiver",base,workflow,fakeAdapter(),
    "NATIVE_DISPATCH_PROVIDER_RECEIPT_UNVERIFIABLE");
});
test("native RUN also fails closed without real provider",async()=>{
  await block("run",{phase:"RUN",execution_id:base.execution_id,
    executor_mode:"GPT_NATIVE",executor_provider:"OPENAI_CHATGPT_NATIVE"},
    workflow,null,"NATIVE_DISPATCH_REAL_PROVIDER_NOT_CONNECTED");
});
test("wrong executor pair blocked",async()=>{
  await block("mode",{...base,executor_provider:"ANTHROPIC_CLAUDE_NATIVE"},
    workflow,null,"NATIVE_DISPATCH_MODE_PROVIDER_MISMATCH");
});
test("provider adapter cannot claim Step70 independence with zero model calls",async()=>{
  const adapter=fakeAdapter({model_call_count:0});
  adapter.verifyProviderReceipt=async()=>true; // TEST INJECTION, not real provider.
  await block("call count",base,workflow,adapter,
    "NATIVE_DISPATCH_STEP70_INDEPENDENCE_UNVERIFIED");
});
test("spoofed provider callback true still BLOCKED without an Ed25519 signed receipt",async()=>{
  const adapter=fakeAdapter();
  adapter.verifyProviderReceipt=async()=>true; // TEST INJECTION, not live proof.
  await block("callback spoof",base,workflow,adapter,
    "NATIVE_DISPATCH_SIGNED_ATTESTATION_REQUIRED");
});

import {verifyNativeReceiptEd25519V1} from "./native_receipt_ed25519_v1.mjs";
/**
 * Candidate: native RUN and Step70 transport adapter. NOT a model executor.
 * Requires server-verified OIDC and a genuine provider adapter from the host.
 * Neither may be obtained from a request JSON value or HMAC test secret.
 * Without a real provider the dispatcher fails closed with zero writes.
 */
const RUN_RE = /^EXEC-PROFILE-GATE2-[A-Z0-9]{10,64}$/;
const SHA_RE = /^[0-9a-f]{64}$/;
const PHASES = new Set(["RUN","STEP70"]);
const PAIRS = new Set(["GPT_NATIVE:OPENAI_CHATGPT_NATIVE","CLAUDE_NATIVE:ANTHROPIC_CLAUDE_NATIVE"]);
function blocked(code) { return Object.freeze({status:"BLOCKED",blocking_code:code,write_performed:false}); }
export async function dispatchNativeV1(request, authority, provider) {
  if(!request || typeof request!=="object" || Array.isArray(request))
    return blocked("NATIVE_DISPATCH_INPUT_INVALID");
  if(!PHASES.has(request.phase) || !RUN_RE.test(request.execution_id||""))
    return blocked("NATIVE_DISPATCH_PHASE_OR_RUN_INVALID");
  if(!PAIRS.has(request.executor_mode+":"+request.executor_provider))
    return blocked("NATIVE_DISPATCH_MODE_PROVIDER_MISMATCH");
  if(request.hmac || request.hmac_test || request.test_signature || request.stubbed_model_output ||
     request.source_kind==="HMAC_TEST" || request.source_kind==="MOCK" ||
     request.judge_mode==="CURRENT_CONTEXT_REVIEW")
    return blocked("NATIVE_DISPATCH_TEST_OR_SELF_REVIEW_FORBIDDEN");
  // Only the existing Edge JWT/JWKS verifier may construct this authority.
  if(!authority || authority.source!=="SERVER_VERIFIED_GITHUB_OIDC" ||
     authority.scope!=="PROFILE_NATIVE_CONTINUATION_ONLY" ||
     !/^[1-9][0-9]{4,19}$/.test(String(authority.workflow_run_id||"")) ||
     !SHA_RE.test(authority.workflow_sha256||""))
    return blocked("NATIVE_DISPATCH_OIDC_WORKFLOW_NOT_VERIFIED");
  if(request.phase==="STEP70" && (!SHA_RE.test(request.candidate_sha256||"") ||
      !SHA_RE.test(request.scope_packet_sha256||"")))
    return blocked("NATIVE_DISPATCH_STEP70_EXACT_SHA_REQUIRED");
  if(!provider || provider.kind!=="TRUSTED_NATIVE_PROVIDER_ADAPTER" ||
     typeof provider.execute!=="function" ||
     typeof provider.verifyProviderReceipt!=="function")
    return blocked("NATIVE_DISPATCH_REAL_PROVIDER_NOT_CONNECTED");
  let output;
  try {
    output=await provider.execute(Object.freeze({
      execution_id:request.execution_id,phase:request.phase,
      executor_mode:request.executor_mode,executor_provider:request.executor_provider,
      candidate_sha256:request.candidate_sha256||null,
      scope_packet_sha256:request.scope_packet_sha256||null,
      authorized_workflow_run_id:String(authority.workflow_run_id),
    }));
  } catch { return blocked("NATIVE_DISPATCH_PROVIDER_EXECUTION_FAILED"); }
  let genuine=false;
  try { genuine=await provider.verifyProviderReceipt(output,request,authority)===true; }
  catch { return blocked("NATIVE_DISPATCH_PROVIDER_RECEIPT_UNVERIFIABLE"); }
  if(!genuine) return blocked("NATIVE_DISPATCH_PROVIDER_RECEIPT_UNVERIFIABLE");
  if(!output || output.execution_id!==request.execution_id ||
     output.phase!==request.phase ||
     output.provider!==request.executor_provider ||
     typeof output.provider_receipt_ref!=="string" ||
     !output.provider_receipt_ref.trim() ||
     output.provider_receipt_ref.startsWith("test://") ||
     output.provider_receipt_ref.startsWith("hmac://"))
    return blocked("NATIVE_DISPATCH_PROVIDER_SCOPE_DRIFT");
  if(request.phase==="STEP70" && (
     output.producer_independence_proven!==true ||
     output.model_call_count!==1 ||
     output.candidate_sha256!==request.candidate_sha256 ||
     output.scope_packet_sha256!==request.scope_packet_sha256))
    return blocked("NATIVE_DISPATCH_STEP70_INDEPENDENCE_UNVERIFIED");
  // A provider callback returning true is not cryptographic verification.
  // The verified Edge runtime owns keyset and nonce, never request JSON.
  if(typeof output.signed_native_receipt_jws!=="string" ||
      !authority.native_receipt_trust ||
      !authority.native_challenge_nonce)
    return blocked("NATIVE_DISPATCH_SIGNED_ATTESTATION_REQUIRED");
  const receipt=await verifyNativeReceiptEd25519V1(
    output.signed_native_receipt_jws,
    {...request,nonce:authority.native_challenge_nonce},
    authority.native_receipt_trust);
  if(receipt.signature_valid!==true)
    return blocked("NATIVE_DISPATCH_SIGNED_ATTESTATION_INVALID");
  // A valid attester signature is not evidence of a vendor model call.
  if(receipt.vendor_model_provenance_verified!==true)
    return blocked("NATIVE_DISPATCH_VENDOR_MODEL_PROVENANCE_UNVERIFIED");
  return Object.freeze({status:"PROVIDER_RECEIPT_READY_NOT_RECORDED",
    execution_id:request.execution_id,phase:request.phase,
    provider_receipt_ref:output.provider_receipt_ref,
    next_action:request.phase==="STEP70"?
      "OFFICIAL_NATIVE_BRIDGE_STEP70":"CONTINUE_CANONICAL_PROFILE_RUN",
    canonical_write_performed:false,profile_run_closed:false});
}

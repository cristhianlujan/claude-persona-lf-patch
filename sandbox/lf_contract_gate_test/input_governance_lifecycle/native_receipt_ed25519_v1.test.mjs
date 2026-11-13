import test from "node:test";
import assert from "node:assert/strict";
import {webcrypto} from "node:crypto";
import {verifyNativeReceiptEd25519V1} from "./native_receipt_ed25519_v1.mjs";

const c=globalThis.crypto??webcrypto;
const b64=s=>Buffer.from(s).toString("base64url");
const toBytes=v=>new TextEncoder().encode(JSON.stringify(v));
const now=1770000000;
const req={
  execution_id:"EXEC-PROFILE-GATE2-1234567890ABCDEF",
  phase:"STEP70",executor_provider:"OPENAI_CHATGPT_NATIVE",
  nonce:"server-issued-nonce-128-bits",
  candidate_sha256:"a".repeat(64),scope_packet_sha256:"b".repeat(64)
};
const claim={
  schema_version:"LF_NATIVE_PROVIDER_ATTESTATION_V1",
  iss:"https://receipt-issuer.invalid/attester",aud:"lf-native-receipt",
  execution_id:req.execution_id,phase:"STEP70",
  provider:req.executor_provider,nonce:req.nonce,
  candidate_sha256:req.candidate_sha256,
  scope_packet_sha256:req.scope_packet_sha256,
  producer_subject:"producer-native",
  reviewer_subject:"reviewer-independent",
  provider_response_id:"resp-for-unit-test-only",
  model_call_count:1,
  jti:"ed25519-fixture-jti-00000000001",
  iat:now-20,exp:now+200
};
let pair,jwk,trust;
async function jws(payload=claim,header={alg:"EdDSA",typ:"JWT",kid:"ephemeral-unit-key"}){
  const h=b64(toBytes(header)),p=b64(toBytes(payload));
  const sig=await c.subtle.sign("Ed25519",pair.privateKey,new TextEncoder().encode(h+"."+p));
  return h+"."+p+"."+b64(new Uint8Array(sig));
}
async function init(){
  pair=await c.subtle.generateKey({name:"Ed25519"},true,["sign","verify"]);
  jwk=await c.subtle.exportKey("jwk",pair.publicKey);
  trust={now_unix:now,issuer:claim.iss,audience:claim.aud,
    keys:[{kid:"ephemeral-unit-key",kty:"OKP",crv:"Ed25519",x:jwk.x}]};
}
await init();
test("ephemeral Ed25519 signature cryptographically verifies but NEVER proves vendor invocation",async()=>{
  const r=await verifyNativeReceiptEd25519V1(await jws(),req,trust);
  assert.equal(r.status,"ATTESTER_SIGNATURE_VALID_VENDOR_UNPROVEN");
  assert.equal(r.signature_valid,true);
  assert.equal(r.vendor_model_provenance_verified,false);
  assert.equal(r.effect_authority,false);
});
test("no JWS blocks",async()=>{
  assert.equal((await verifyNativeReceiptEd25519V1("",req,trust)).status,"BLOCKED");
});
test("tampered signed payload blocks",async()=>{
  const token=await jws();
  const [h,p,s]=token.split(".");
  const tampered=b64(toBytes({...claim,candidate_sha256:"f".repeat(64)}));
  const r=await verifyNativeReceiptEd25519V1(h+"."+tampered+"."+s,req,trust);
  assert.equal(r.code,"NATIVE_RECEIPT_SIGNATURE_INVALID");
});
test("untrusted signing key blocks",async()=>{
  const r=await verifyNativeReceiptEd25519V1(await jws(),req,{...trust,keys:[]});
  assert.equal(r.status,"BLOCKED");
});
test("HS256 algorithm confusion blocks even with signature",async()=>{
  const x=await jws(claim,{alg:"HS256",typ:"JWT",kid:"ephemeral-unit-key"});
  const r=await verifyNativeReceiptEd25519V1(x,req,trust);
  assert.equal(r.code,"NATIVE_RECEIPT_ALGORITHM_OR_HEADER_FORBIDDEN");
});
test("mismatched candidate sha256 blocks",async()=>{
  const r=await verifyNativeReceiptEd25519V1(await jws({...claim,candidate_sha256:"d".repeat(64)}),req,trust);
  assert.equal(r.code,"NATIVE_RECEIPT_STEP70_SCOPE_INDEPENDENCE_INVALID");
});
test("same producer and reviewer blocks",async()=>{
  const r=await verifyNativeReceiptEd25519V1(await jws({...claim,reviewer_subject:"producer-native"}),req,trust);
  assert.equal(r.code,"NATIVE_RECEIPT_STEP70_SCOPE_INDEPENDENCE_INVALID");
});
test("zero model calls blocks Step70",async()=>{
  const r=await verifyNativeReceiptEd25519V1(await jws({...claim,model_call_count:0}),req,trust);
  assert.equal(r.code,"NATIVE_RECEIPT_STEP70_SCOPE_INDEPENDENCE_INVALID");
});
test("expired signed receipt blocks",async()=>{
  const r=await verifyNativeReceiptEd25519V1(await jws({...claim,exp:now-1}),req,trust);
  assert.equal(r.code,"NATIVE_RECEIPT_ISSUER_AUDIENCE_OR_TIME_INVALID");
});
test("wrong issuer blocks",async()=>{
  const r=await verifyNativeReceiptEd25519V1(await jws({...claim,iss:"https://other.invalid"}),req,trust);
  assert.equal(r.code,"NATIVE_RECEIPT_ISSUER_AUDIENCE_OR_TIME_INVALID");
});
test("wrong server-bound nonce blocks",async()=>{
  const r=await verifyNativeReceiptEd25519V1(await jws(),{...req,nonce:"wrong-server-nonce"},trust);
  assert.equal(r.code,"NATIVE_RECEIPT_RUN_PHASE_PROVIDER_BINDING_INVALID");
});
test("RUN signature is still only an attester claim, never RUN start",async()=>{
  const x={...req,phase:"RUN"};
  const r=await verifyNativeReceiptEd25519V1(await jws({...claim,phase:"RUN"}),x,trust);
  assert.equal(r.status,"ATTESTER_SIGNATURE_VALID_VENDOR_UNPROVEN");
  assert.equal(r.effect_authority,false);
});

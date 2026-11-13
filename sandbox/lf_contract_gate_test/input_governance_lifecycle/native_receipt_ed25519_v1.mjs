/**
 * Verifies Ed25519 compact-JWS against a configured public key ring.
 * Neither this signature nor a caller-supplied payload proves a vendor call.
 * Fail closed until a trusted issuer actually validates vendor provenance.
 */
const SHA=/^[0-9a-f]{64}$/;
function deny(code){return Object.freeze({status:"BLOCKED",code,signature_valid:false,
  vendor_model_provenance_verified:false,effect_authority:false});}
function raw(s){if(typeof s!=="string"||!s||!/^[A-Za-z0-9_-]+$/.test(s))throw Error("B64URL_INVALID");
  const b=atob(s.replace(/-/g,"+").replace(/_/g,"/")+"=".repeat((4-s.length%4)%4));
  return Uint8Array.from(b,c=>c.charCodeAt(0));}
function obj(v){return v&&typeof v==="object"&&!Array.isArray(v);}
function decode(s){return JSON.parse(new TextDecoder("utf-8",{fatal:true}).decode(raw(s)));}
export async function verifyNativeReceiptEd25519V1(jws,expected,trust){
  if(!obj(expected)||!obj(trust)||!Number.isSafeInteger(trust.now_unix)||
    typeof trust.issuer!=="string"||typeof trust.audience!=="string"||
    !Array.isArray(trust.keys)||!trust.keys.length||!trust.keys.every(obj))
    return deny("NATIVE_RECEIPT_TRUST_CONFIG_MISSING");
  if(typeof jws!=="string"||jws.length>18000)return deny("NATIVE_RECEIPT_JWS_MISSING");
  const parts=jws.split(".");if(parts.length!==3)return deny("NATIVE_RECEIPT_JWS_MALFORMED");
  let head,payload,sig;
  try{head=decode(parts[0]);payload=decode(parts[1]);sig=raw(parts[2]);}
  catch{return deny("NATIVE_RECEIPT_JWS_MALFORMED");}
  if(!obj(head)||!obj(payload)||
    Object.keys(head).sort().join(",")!=="alg,kid,typ"||
    head.alg!=="EdDSA"||head.typ!=="JWT"||
    typeof head.kid!=="string"||!head.kid||sig.byteLength!==64)
    return deny("NATIVE_RECEIPT_ALGORITHM_OR_HEADER_FORBIDDEN");
  const key=trust.keys.find(k=>k.kid===head.kid);
  if(!key||trust.keys.filter(k=>k.kid===head.kid).length!==1||
    key.kty!=="OKP"||key.crv!=="Ed25519"||typeof key.x!=="string"||
    "d" in key)return deny("NATIVE_RECEIPT_TRUSTED_PUBLIC_KEY_MISSING");
  let valid=false;
  try{
    const k=await crypto.subtle.importKey("jwk",{kty:"OKP",crv:"Ed25519",x:key.x,
      ext:true,key_ops:["verify"]},{name:"Ed25519"},false,["verify"]);
    valid=await crypto.subtle.verify("Ed25519",k,sig,
      new TextEncoder().encode(parts[0]+"."+parts[1]));
  }catch{return deny("NATIVE_RECEIPT_SIGNATURE_INVALID");}
  if(!valid)return deny("NATIVE_RECEIPT_SIGNATURE_INVALID");
  if(payload.iss!==trust.issuer||payload.aud!==trust.audience||
     !Number.isSafeInteger(payload.iat)||!Number.isSafeInteger(payload.exp)||
     payload.iat>trust.now_unix+30||payload.exp<=trust.now_unix||
     payload.exp-payload.iat>600||payload.exp<=payload.iat)
     return deny("NATIVE_RECEIPT_ISSUER_AUDIENCE_OR_TIME_INVALID");
  if(payload.schema_version!=="LF_NATIVE_PROVIDER_ATTESTATION_V1"||
     payload.execution_id!==expected.execution_id||
     payload.phase!==expected.phase||
     payload.provider!==expected.executor_provider||
     payload.nonce!==expected.nonce||
     typeof payload.jti!=="string"||payload.jti.length<20||
     typeof payload.provider_response_id!=="string"||
     payload.provider_response_id.length<10)
     return deny("NATIVE_RECEIPT_RUN_PHASE_PROVIDER_BINDING_INVALID");
  if(expected.phase==="STEP70"&&(
     !SHA.test(expected.candidate_sha256||"")||
     !SHA.test(expected.scope_packet_sha256||"")||
     payload.candidate_sha256!==expected.candidate_sha256||
     payload.scope_packet_sha256!==expected.scope_packet_sha256||
     payload.model_call_count!==1||
     payload.producer_subject===payload.reviewer_subject||
     !payload.producer_subject||!payload.reviewer_subject))
     return deny("NATIVE_RECEIPT_STEP70_SCOPE_INDEPENDENCE_INVALID");
  return Object.freeze({status:"ATTESTER_SIGNATURE_VALID_VENDOR_UNPROVEN",
    code:"NATIVE_RECEIPT_EXTERNAL_PROVIDER_EVIDENCE_REQUIRED",
    signature_valid:true,vendor_model_provenance_verified:false,
    effect_authority:false,jti:payload.jti,
    provider_response_id:payload.provider_response_id});
}

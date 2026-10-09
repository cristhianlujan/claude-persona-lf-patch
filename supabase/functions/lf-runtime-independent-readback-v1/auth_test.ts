import { generateKeyPair, exportJWK, createLocalJWKSet, SignJWT } from "npm:jose@6.0.11";
import { ISSUER, AUDIENCE, REPO, REF, WORKFLOW, CALLER_WORKFLOW, verifyObserverToken } from "./auth.ts";

Deno.test("OIDC D7 independent observer negative JWT matrix", async () => {
 const {privateKey,publicKey}=await generateKeyPair("RS256",{extractable:true});
 const jwk=await exportJWK(publicKey);
 jwk.kid="d7-local-test";
 const keys=createLocalJWKSet({keys:[jwk]});
 const head="a".repeat(40);
 const receipt={execution_id:"EXEC-D7-test",exact_head:head,source_sha:head,runtime_sha:head,
  release_path:"/opt/lf-profile-runtime-api/releases/"+head,manifest_digest:"f".repeat(64),
  workflow_run_id:"12345",workflow_run_attempt:"1",health_ok:true,files_verified:true,
  manifest_matches:true,process_release_matches:true};
 const claims={repository:REPO,repository_id:"1244397752",ref:REF,
  workflow_ref:CALLER_WORKFLOW,job_workflow_ref:WORKFLOW,event_name:"workflow_dispatch",
  run_id:"12345",run_attempt:"1"};
 async function token(c:Record<string,unknown>,expired=false,audience=AUDIENCE) {
   let t=new SignJWT(c).setProtectedHeader({alg:"RS256",kid:"d7-local-test"})
     .setIssuer(ISSUER).setAudience(audience).setIssuedAt();
   t=t.setExpirationTime(expired?Math.floor(Date.now()/1000)-600:"5m");
   return await t.sign(privateKey);
 }
 async function denied(description:string,c:Record<string,unknown>,expected:string,r=receipt,expired=false,aud=AUDIENCE) {
   const signed=await token(c,expired,aud);
   let observed="";
   try { await verifyObserverToken(signed,r,keys); }
   catch(e) { observed=String((e as Error).name)+": "+String((e as Error).message); }
   if (!observed.includes(expected)) throw Error(description+": expected "+expected+", got "+observed);
 }
 const valid=await token(claims);
 await verifyObserverToken(valid,receipt,keys);
 await denied("another repo",{...claims,repository:"some/other"},"OIDC_REPOSITORY_MISMATCH");
 await denied("another workflow",{...claims,job_workflow_ref:"some/other/.github/workflows/a.yml@refs/heads/main"},"OIDC_WORKFLOW_REF_MISMATCH");
 await denied("another branch",{...claims,ref:"refs/heads/dev"},"OIDC_REF_MISMATCH");
 await denied("expired",claims,"JWTExpired",receipt,true);
 await denied("wrong run_id",{...claims,run_id:"99999"},"OIDC_RUN_BINDING_MISMATCH");
 await denied("wrong run_attempt",{...claims,run_attempt:"2"},"OIDC_RUN_BINDING_MISMATCH");
 await denied("wrong audience",claims,"unexpected \"aud\" claim value",receipt,false,"not-allowed");
 await denied("wrong dispatcher",{...claims,workflow_ref:"not-the-dispatcher"},"OIDC_WORKFLOW_REF_MISMATCH");
 await denied("wrong event",{...claims,event_name:"push"},"OIDC_EVENT_MISMATCH");
 await denied("wrong repository id",{...claims,repository_id:"0"},"OIDC_REPOSITORY_MISMATCH");
 for (const field of ["health_ok","files_verified","manifest_matches","process_release_matches"] as const) {
   await denied("false "+field,claims,"READBACK_NOT_VERIFIED",{...receipt,[field]:false});
 }
 await denied("release path mismatch",claims,"RELEASE_PATH_INVALID",{...receipt,release_path:"/opt/lf-profile-runtime-api/releases/wrong"});
 const foreign=await generateKeyPair("RS256");
 const forged=await new SignJWT(claims).setProtectedHeader({alg:"RS256",kid:"d7-local-test"})
   .setIssuer(ISSUER).setAudience(AUDIENCE).setExpirationTime("5m").sign(foreign.privateKey);
 let signatureError = "";
 try {await verifyObserverToken(forged,receipt,keys);}
 catch(e) {signatureError=(e as Error).name + ": " + (e as Error).message;}
 if (!signatureError.includes("JWSSignatureVerificationFailed")) throw Error("unexpected signature result: " + signatureError);
 console.log("D7_JWT_TESTS_COMPLETED cases=17 (baseline + 16 negative)");
});

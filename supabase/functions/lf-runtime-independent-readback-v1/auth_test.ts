import { generateKeyPair, exportJWK, createLocalJWKSet, SignJWT } from "npm:jose@6.0.11";
import { ISSUER, AUDIENCE, REPO, REF, WORKFLOW, verifyObserverToken } from "./auth.ts";

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
  workflow_ref:WORKFLOW,job_workflow_ref:WORKFLOW,event_name:"workflow_dispatch",
  run_id:"12345",run_attempt:"1"};
 async function token(c:Record<string,unknown>,expired=false,audience=AUDIENCE) {
   let t=new SignJWT(c).setProtectedHeader({alg:"RS256",kid:"d7-local-test"})
     .setIssuer(ISSUER).setAudience(audience).setIssuedAt();
   t=t.setExpirationTime(expired?Math.floor(Date.now()/1000)-600:"5m");
   return await t.sign(privateKey);
 }
 async function denied(description:string,c:Record<string,unknown>,r=receipt,expired=false,aud=AUDIENCE) {
   try { await verifyObserverToken(await token(c,expired,aud),r,keys); }
   catch { return; }
   throw Error("OIDC incorrectly admitted "+description);
 }
 const valid=await token(claims);
 await verifyObserverToken(valid,receipt,keys);
 await denied("another repo",{...claims,repository:"some/other"});
 await denied("another workflow",{...claims,job_workflow_ref:"some/other/.github/workflows/a.yml@refs/heads/main"});
 await denied("another branch",{...claims,ref:"refs/heads/dev"});
 await denied("expired",claims,receipt,true);
 await denied("wrong run_id",{...claims,run_id:"99999"});
 await denied("wrong run_attempt",{...claims,run_attempt:"2"});
 await denied("wrong audience",claims,receipt,false,"not-allowed");
 const foreign=await generateKeyPair("RS256");
 const forged=await new SignJWT(claims).setProtectedHeader({alg:"RS256",kid:"d7-local-test"})
   .setIssuer(ISSUER).setAudience(AUDIENCE).setExpirationTime("5m").sign(foreign.privateKey);
 try {await verifyObserverToken(forged,receipt,keys); throw Error("forged signature admitted")}
 catch(e) {if ((e as Error).message==="forged signature admitted") throw e}
 console.log("D7_JWT_TESTS_COMPLETED cases=9 (baseline + 8 negative)");
});

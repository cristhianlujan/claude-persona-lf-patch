// DEPLOY BLOCKED: pending governed approval of caller, OIDC workflow, and RPCs.
// Deno implementation follows the profile caller's Jose/OIDC pattern.
import { createRemoteJWKSet, jwtVerify } from 'npm:jose@6.0.11';
import { createSkillsHandler, AUDIENCE } from './handler.mjs';
const issuer='https://token.actions.githubusercontent.com';
const jwks=createRemoteJWKSet(new URL(`${issuer}/.well-known/jwks`));
const handler=createSkillsHandler({
  getEnv:(k:string)=>Deno.env.get(k),
  fetchFn:fetch,
  verifyJwt:async(token:string,audience:string)=>{
    if(audience!==AUDIENCE)throw Error('AUDIENCE_INVALID');
    const {payload}=await jwtVerify(token,jwks,{issuer,audience:AUDIENCE});
    return payload;
  },
});
Deno.serve(handler);

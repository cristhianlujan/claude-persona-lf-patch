import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createRemoteJWKSet, jwtVerify } from "npm:jose@6.0.11";
import { createHandler, OIDC_ISSUER, type JwtPayload } from "./caller.ts";

const JWKS = createRemoteJWKSet(new URL(`${OIDC_ISSUER}/.well-known/jwks`));

const handler = createHandler({
  getEnv: (name) => Deno.env.get(name),
  fetchFn: fetch,
  jwks: JWKS,
  jwtVerifyFn: async (token, jwks, options) => {
    const { payload } = await jwtVerify(token, jwks as ReturnType<typeof createRemoteJWKSet>, options);
    return { payload: payload as JwtPayload };
  },
});

Deno.serve(handler);

// Test fixture for the JWKS pin generator round-trip (local keys, NOT GitHub keys).
import { exportJWK, generateKeyPair, SignJWT } from "npm:jose@6.0.11";
const kid = Deno.args[0] ?? "pin-fixture";
const a = await generateKeyPair("RS256", { extractable: true }), b = await generateKeyPair("RS256", { extractable: true });
const ja = { ...(await exportJWK(a.publicKey)), kid, alg: "RS256", use: "sig" };
const jb = { ...(await exportJWK(b.publicKey)), kid, alg: "RS256", use: "sig" };
const token = await new SignJWT({ fixture: true }).setProtectedHeader({ alg: "RS256", kid }).sign(a.privateKey);
Deno.writeTextFileSync("jwks_a.json", JSON.stringify({ keys: [ja] }));
Deno.writeTextFileSync("jwks_b_same_kid.json", JSON.stringify({ keys: [jb] }));
Deno.writeTextFileSync("token_a.txt", token);

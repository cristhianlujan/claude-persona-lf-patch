// Optional independent audit of PG-01 OIDC receipts (H1-C2). The database already RS256-verifies
// every receipt against pinned keys at insert; this re-checks a DB readback against GitHub's live
// JWKS from outside the database (e.g. to detect a wrong pin). Exit 0 only if all pass.
// Usage: deno run -A scripts/lf_pg01_oidc_receipt_reverify.ts receipts.json [--jwks-file jwks.json]
//   receipts.json: [{"kind":"SUBJECT_VERIFICATION","token":"...","token_sha256":"..."}, ...]
import { createLocalJWKSet, decodeJwt } from "npm:jose@6.0.11";
import { isKind, sha256Hex, verifyPg01Token } from "../supabase/functions/lf-pg01-oidc-authority-v1/auth.ts";

export async function reverify(rows: Array<Record<string, unknown>>, jwks?: Parameters<typeof verifyPg01Token>[3]) {
  const results: Array<Record<string, unknown>> = [];
  for (const r of rows) {
    const token = String(r.token ?? ""), kind = r.kind;
    let reason = "OK";
    try {
      if (!isKind(kind)) throw Error("KIND_INVALID");
      if (await sha256Hex(token) !== r.token_sha256) throw Error("TOKEN_SHA256_MISMATCH");
      const iat = Number(decodeJwt(token).iat ?? 0);
      // Signature + policy as of issuance (tokens are short-lived; expiry is enforced at intake).
      await verifyPg01Token(token, kind, null, jwks, new Date((iat + 1) * 1000));
    } catch (e) { reason = String((e as Error & { code?: string }).code ?? (e as Error).message); }
    results.push({ kind, token_sha256: r.token_sha256, reverified: reason === "OK", reason });
  }
  return { all_reverified: results.length > 0 && results.every((x) => x.reverified), results };
}

if (import.meta.main) {
  const [file, flag, jwksFile] = Deno.args;
  const rows = JSON.parse(await Deno.readTextFile(file));
  const jwks = flag === "--jwks-file" ? createLocalJWKSet(JSON.parse(await Deno.readTextFile(jwksFile))) : undefined;
  const out = await reverify(rows, jwks);
  console.log(JSON.stringify(out));
  Deno.exit(out.all_reverified ? 0 : 1);
}

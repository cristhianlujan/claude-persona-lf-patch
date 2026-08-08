import {
  canonicalJson,
  frameComponent,
  payloadSha256,
  signedPreimage,
} from "../../supabase/migrations/edge_functions/lf-github-reconcile-v3-v7/canonical_payload_v7.ts";

function assert(condition: boolean, message: string): void {
  if (!condition) throw new Error(message);
}

function assertThrows(action: () => unknown, message: string): void {
  let rejected = false;
  try {
    action();
  } catch {
    rejected = true;
  }
  assert(rejected, message);
}

Deno.test("shared canonical JSON vector", async () => {
  const payload = {
    z: "a:b",
    a: [1, true, null, { k: "ñ" }],
    n: 1,
  };
  const canonical = canonicalJson(payload);
  assert(
    canonical === '{"a":[1,true,null,{"k":"ñ"}],"n":1,"z":"a:b"}',
    `unexpected canonical JSON: ${canonical}`,
  );
  assert(
    await payloadSha256(payload) === "e6dbf00ab828cd67089efa5d25a5a66011ac7cea845179f9bf997187af77029b",
    "shared canonical hash differs from PostgreSQL vector",
  );
});

Deno.test("framed scopes are exact and separator distribution cannot collide", async () => {
  const reconciliation = await signedPreimage(
    "reconciliation-v7",
    { test_code: "a:b", source_workflow_run_id: 3 },
    "EXEC:1",
  );
  const gate = await signedPreimage(
    "gate-v7",
    { test_code: "a", source_workflow_run_id: "b:3" },
    "EXEC:1",
  );

  assert(reconciliation.startsWith("17#reconciliation-v7"), "reconciliation scope frame differs");
  assert(gate.startsWith("7#gate-v7"), "gate scope frame differs");
  assert(reconciliation !== gate, "distinct scope/payload preimages collided");

  const left = frameComponent("a:b") + frameComponent("c");
  const right = frameComponent("a") + frameComponent("b:c");
  assert(left !== right, "length-framed components collided");
});

Deno.test("full payload binding covers nested and formerly unsigned fields", async () => {
  const base = {
    artifact_id: 1,
    artifact_path: "skills/a.md",
    merged: true,
    details: { actual_branch_protection_status: "VERIFIED" },
    failure_reasons: [] as string[],
  };
  const original = await signedPreimage("reconciliation-v7", base, "EXEC-BIND");

  assert(
    original !== await signedPreimage(
      "reconciliation-v7",
      { ...base, artifact_path: "skills/other.md" },
      "EXEC-BIND",
    ),
    "artifact_path was not bound",
  );
  assert(
    original !== await signedPreimage(
      "reconciliation-v7",
      { ...base, details: { actual_branch_protection_status: "FAILED" } },
      "EXEC-BIND",
    ),
    "nested authorization detail was not bound",
  );
  assert(
    original !== await signedPreimage(
      "reconciliation-v7",
      { ...base, failure_reasons: ["MUTATED"] },
      "EXEC-BIND",
    ),
    "failure_reasons was not bound",
  );
});

Deno.test("key order, arrays and nested objects are deterministic", () => {
  assert(
    canonicalJson({ b: 2, a: 1 }) === canonicalJson({ a: 1, b: 2 }),
    "object key order changed the canonical JSON",
  );
  assert(
    canonicalJson({ a: [1, 2] }) !== canonicalJson({ a: [2, 1] }),
    "array order was not preserved",
  );
  assert(
    canonicalJson({ a: { b: { c: true } } }) === '{"a":{"b":{"c":true}}}',
    "nested object canonicalization differs",
  );
});

Deno.test("string escaping and Unicode remain deterministic", () => {
  const value = '"\\\b\f\n\r\t\u0001\u007f\u2028\u2029😀ñ';
  const canonical = canonicalJson(value);
  assert(canonical === JSON.stringify(value), "string escaping differs from JSON.stringify");
  assert(canonicalJson("é") !== canonicalJson("e\u0301"), "Unicode normalization was introduced");
});

Deno.test("numeric contract accepts only safe integers and normalizes negative zero", () => {
  assert(canonicalJson(0) === "0", "zero canonicalization failed");
  assert(canonicalJson(-0) === "0", "negative zero was not normalized");
  assert(canonicalJson(1) === "1", "integer canonicalization failed");
  assert(canonicalJson(Number.MAX_SAFE_INTEGER) === "9007199254740991", "positive limit failed");
  assert(canonicalJson(Number.MIN_SAFE_INTEGER) === "-9007199254740991", "negative limit failed");

  for (const value of [
    1.5,
    Number.MAX_SAFE_INTEGER + 1,
    Number.MIN_SAFE_INTEGER - 1,
    Number.NaN,
    Number.POSITIVE_INFINITY,
  ]) {
    assertThrows(
      () => canonicalJson(value),
      `numeric value ${String(value)} was not rejected`,
    );
  }
});

Deno.test("canonical objects must be plain records with ASCII keys", () => {
  assertThrows(() => canonicalJson({ "ñ": 1 }), "non-ASCII object key was accepted");
  assertThrows(
    () => canonicalJson({ value: undefined }),
    "undefined object value was accepted",
  );
  assertThrows(() => canonicalJson(new Date()), "Date object was accepted");
  assertThrows(() => canonicalJson(new Map()), "Map object was accepted");

  const nullPrototype = Object.create(null) as Record<string, unknown>;
  nullPrototype.a = 1;
  assert(canonicalJson(nullPrototype) === '{"a":1}', "null-prototype record was rejected");
});

Deno.test("execution identity is independently framed", async () => {
  const payload = { artifact_id: 1 };
  const left = await signedPreimage("gate-v7", payload, "a:b");
  const right = await signedPreimage("gate-v7", payload, "a");
  assert(left !== right, "execution identity was not bound");
});

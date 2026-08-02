const encoder = new TextEncoder();
const CANONICAL_KEY_RE = /^[A-Za-z0-9_.-]+$/;

function hex(value: ArrayBuffer): string {
  return [...new Uint8Array(value)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function canonicalJson(value: unknown): string {
  if (value === null) return "null";
  if (typeof value === "string") return JSON.stringify(value);
  if (typeof value === "boolean") return value ? "true" : "false";
  if (typeof value === "number") {
    if (!Number.isSafeInteger(value)) {
      throw new Error("Canonical JSON numbers must be JavaScript-safe integers");
    }
    return String(value);
  }
  if (Array.isArray(value)) {
    return `[${value.map((item) => canonicalJson(item)).join(",")}]`;
  }
  if (typeof value === "object") {
    const object = value as Record<string, unknown>;
    const keys = Object.keys(object).sort();
    for (const key of keys) {
      if (!CANONICAL_KEY_RE.test(key)) {
        throw new Error("Canonical JSON object keys must be ASCII identifiers");
      }
      if (object[key] === undefined) {
        throw new Error("Canonical JSON does not allow undefined values");
      }
    }
    return `{${keys.map((key) => `${JSON.stringify(key)}:${canonicalJson(object[key])}`).join(",")}}`;
  }
  throw new Error("Canonical JSON value has unsupported type");
}

async function payloadSha256(payload: Record<string, unknown>): Promise<string> {
  return hex(await crypto.subtle.digest("SHA-256", encoder.encode(canonicalJson(payload))));
}

function frameComponent(value: string): string {
  return `${encoder.encode(value).byteLength}#${value}`;
}

async function preimage(
  scope: "reconciliation-v7" | "gate-v7",
  payload: Record<string, unknown>,
  execution: string,
): Promise<string> {
  return frameComponent(scope) + frameComponent(execution) + frameComponent(await payloadSha256(payload));
}

function assert(condition: boolean, message: string): void {
  if (!condition) throw new Error(message);
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

Deno.test("separator distribution cannot collide", async () => {
  const left = await preimage("gate-v7", { test_code: "a:b", source_workflow_run_id: 3 }, "EXEC:1");
  const right = await preimage("gate-v7", { test_code: "a", source_workflow_run_id: "b:3" }, "EXEC:1");
  assert(left !== right, "length-framed canonical preimages collided");
});

Deno.test("formerly unsigned fields change the preimage", async () => {
  const base = {
    artifact_id: 1,
    artifact_path: "skills/a.md",
    merged: true,
    details: { actual_branch_protection_status: "VERIFIED" },
    failure_reasons: [] as string[],
  };
  const original = await preimage("reconciliation-v7", base, "EXEC-BIND");
  assert(
    original !== await preimage("reconciliation-v7", { ...base, artifact_path: "skills/other.md" }, "EXEC-BIND"),
    "artifact_path was not bound",
  );
  assert(
    original !== await preimage(
      "reconciliation-v7",
      { ...base, details: { actual_branch_protection_status: "FAILED" } },
      "EXEC-BIND",
    ),
    "nested authorization detail was not bound",
  );
  assert(
    original !== await preimage("reconciliation-v7", { ...base, failure_reasons: ["MUTATED"] }, "EXEC-BIND"),
    "failure_reasons was not bound",
  );
});

Deno.test("numeric contract fails closed", () => {
  assert(canonicalJson(1) === "1", "integer canonicalization failed");
  for (const value of [1.5, Number.MAX_SAFE_INTEGER + 1]) {
    let rejected = false;
    try {
      canonicalJson(value);
    } catch {
      rejected = true;
    }
    assert(rejected, `numeric value ${value} was not rejected`);
  }
});

const encoder = new TextEncoder();
const CANONICAL_KEY_RE = /^[A-Za-z0-9_.-]+$/;

export type WriterScope = "reconciliation-v7" | "gate-v7";

function hex(value: ArrayBuffer): string {
  return [...new Uint8Array(value)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function assertPlainObject(value: object): asserts value is Record<string, unknown> {
  const prototype = Object.getPrototypeOf(value);
  if (prototype !== Object.prototype && prototype !== null) {
    throw new Error("Canonical JSON objects must be plain records");
  }
}

export function canonicalJson(value: unknown): string {
  if (value === null) return "null";

  if (typeof value === "string") return JSON.stringify(value);
  if (typeof value === "boolean") return value ? "true" : "false";
  if (typeof value === "number") {
    if (!Number.isSafeInteger(value)) {
      throw new Error("Canonical JSON numbers must be JavaScript-safe integers");
    }
    return Object.is(value, -0) ? "0" : String(value);
  }

  if (Array.isArray(value)) {
    return `[${value.map((item) => canonicalJson(item)).join(",")}]`;
  }

  if (typeof value === "object") {
    assertPlainObject(value);
    const keys = Object.keys(value).sort();
    for (const key of keys) {
      if (!CANONICAL_KEY_RE.test(key)) {
        throw new Error("Canonical JSON object keys must be ASCII identifiers");
      }
      if (value[key] === undefined) {
        throw new Error("Canonical JSON does not allow undefined values");
      }
    }
    return `{${keys.map((key) => `${JSON.stringify(key)}:${canonicalJson(value[key])}`).join(",")}}`;
  }

  throw new Error("Canonical JSON value has unsupported type");
}

export async function payloadSha256(payload: Record<string, unknown>): Promise<string> {
  return hex(await crypto.subtle.digest("SHA-256", encoder.encode(canonicalJson(payload))));
}

export function frameComponent(value: string): string {
  return `${encoder.encode(value).byteLength}#${value}`;
}

export async function signedPreimage(
  scope: WriterScope,
  payload: Record<string, unknown>,
  execution: string,
): Promise<string> {
  const payloadHash = await payloadSha256(payload);
  return frameComponent(scope) + frameComponent(execution) + frameComponent(payloadHash);
}

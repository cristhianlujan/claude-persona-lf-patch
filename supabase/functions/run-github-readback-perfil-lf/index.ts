import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const ENDPOINT_VERSION = "v7-service-role-bounded-pack-readback";
const TARGET_REPOSITORY = "cristhianlujan/claude-persona-lf-patch";
const ALLOWED_PATH_PREFIXES = [
  "profiles/",
  "sandbox/lf_contract_gate_test/receipts/",
];
const MAX_FILES = 100;

function responseHeaders(): HeadersInit {
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    "Cache-Control": "no-store",
  };
  const allowedOrigin = Deno.env.get("LF_EDGE_ALLOWED_ORIGIN")?.trim();
  if (allowedOrigin) headers["Access-Control-Allow-Origin"] = allowedOrigin;
  return headers;
}

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: responseHeaders() });
}

function text(value: unknown): string {
  return String(value ?? "").trim();
}

function constantTimeEqual(left: string, right: string): boolean {
  const a = new TextEncoder().encode(left);
  const b = new TextEncoder().encode(right);
  let diff = a.length ^ b.length;
  const size = Math.max(a.length, b.length);
  for (let i = 0; i < size; i += 1) {
    diff |= (a[i % Math.max(a.length, 1)] ?? 0) ^ (b[i % Math.max(b.length, 1)] ?? 0);
  }
  return diff === 0;
}

function requireServiceRole(req: Request): Response | null {
  const expected = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim() ?? "";
  if (!expected) {
    return jsonResponse({ outcome: "BLOCKED", endpoint_version: ENDPOINT_VERSION, code: "SERVICE_ROLE_SECRET_UNAVAILABLE" }, 500);
  }
  const authorization = req.headers.get("authorization") ?? "";
  const match = authorization.match(/^Bearer\s+(.+)$/i);
  const received = match?.[1]?.trim() ?? "";
  if (!received || !constantTimeEqual(received, expected)) {
    return jsonResponse({ outcome: "BLOCKED", endpoint_version: ENDPOINT_VERSION, code: "SERVICE_ROLE_REQUIRED" }, 403);
  }
  return null;
}

function validBranch(branch: string): boolean {
  if (!branch || branch.length > 200) return false;
  if (branch.startsWith("-") || branch.startsWith("/") || branch.endsWith("/")) return false;
  if (branch.includes("..") || branch.includes("//") || branch.includes("\\") || branch.includes("@{")) return false;
  return /^[A-Za-z0-9._/-]+$/.test(branch);
}

function validPath(path: string): boolean {
  if (!path || path.length > 500) return false;
  if (path.startsWith("/") || path.includes("..") || path.includes("\\") || path.includes("//")) return false;
  return ALLOWED_PATH_PREFIXES.some((prefix) => path.startsWith(prefix));
}

function decodeBase64Utf8(input: string): string {
  const binary = atob(input.replace(/\n/g, ""));
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) bytes[i] = binary.charCodeAt(i);
  return new TextDecoder().decode(bytes);
}

async function sha256Hex(input: string): Promise<string> {
  const bytes = new TextEncoder().encode(input);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest)).map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

type ReadbackFile = {
  path: string;
  role: string;
  expected_file_sha: string;
  expected_content_sha256: string;
};

function parseFiles(raw: unknown): ReadbackFile[] {
  if (!Array.isArray(raw)) return [];
  return raw.map((item: any) => ({
    path: text(item?.path),
    role: text(item?.role),
    expected_file_sha: text(item?.expected_file_sha ?? item?.file_sha),
    expected_content_sha256: text(item?.expected_content_sha256),
  }));
}

async function readGitHubFile(token: string, branch: string, path: string) {
  const encodedPath = path.split("/").map(encodeURIComponent).join("/");
  const url = `https://api.github.com/repos/${TARGET_REPOSITORY}/contents/${encodedPath}?ref=${encodeURIComponent(branch)}`;
  const resp = await fetch(url, {
    headers: {
      "Authorization": `Bearer ${token}`,
      "Accept": "application/vnd.github+json",
      "X-GitHub-Api-Version": "2022-11-28",
      "User-Agent": "LF-Supabase-Bounded-Profile-Pack-Readback",
    },
  });
  const raw = await resp.text();
  let data: any = null;
  try {
    data = raw ? JSON.parse(raw) : null;
  } catch {
    data = { message: "NON_JSON_GITHUB_RESPONSE" };
  }
  if (!resp.ok) return { ok: false, status: resp.status };
  if (text(data?.type) !== "file") return { ok: false, status: 409 };

  try {
    const content = decodeBase64Utf8(String(data?.content ?? ""));
    return {
      ok: true,
      status: resp.status,
      file_sha: text(data?.sha),
      content_sha256: await sha256Hex(content),
    };
  } catch {
    return { ok: false, status: 422 };
  }
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, {
      status: 204,
      headers: {
        ...responseHeaders(),
        "Access-Control-Allow-Headers": "authorization, content-type",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
      },
    });
  }
  if (req.method !== "POST") {
    return jsonResponse({ outcome: "BLOCKED", endpoint_version: ENDPOINT_VERSION, code: "METHOD_NOT_ALLOWED" }, 405);
  }

  const authFailure = requireServiceRole(req);
  if (authFailure) return authFailure;

  const githubToken = Deno.env.get("GITHUB_TOKEN")?.trim() ?? Deno.env.get("GH_TOKEN")?.trim() ?? "";
  if (!githubToken) {
    return jsonResponse({ outcome: "BLOCKED", endpoint_version: ENDPOINT_VERSION, code: "GITHUB_SECRET_UNAVAILABLE" }, 500);
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ outcome: "BLOCKED", endpoint_version: ENDPOINT_VERSION, code: "INVALID_JSON" }, 400);
  }

  const repo = text(body.repo);
  const branch = text(body.branch || "main");
  const packetId = text(body.packet_id);
  const candidateHash = text(body.candidate_hash);
  const expectedFilesCount = Number(body.expected_files_count ?? 0);
  const files = parseFiles(body.files);

  const violations: string[] = [];
  if (repo !== TARGET_REPOSITORY) violations.push("REPOSITORY_NOT_ALLOWED");
  if (!validBranch(branch)) violations.push("BRANCH_NOT_ALLOWED");
  if (!packetId || packetId.length > 200) violations.push("PACKET_ID_INVALID");
  if (!/^[a-f0-9]{64}$/i.test(candidateHash)) violations.push("CANDIDATE_HASH_INVALID");
  if (!Number.isInteger(expectedFilesCount) || expectedFilesCount < 1 || expectedFilesCount > MAX_FILES) {
    violations.push("EXPECTED_FILES_COUNT_INVALID");
  }
  if (files.length !== expectedFilesCount) violations.push("FILES_COUNT_MISMATCH");

  const seen = new Set<string>();
  for (const file of files) {
    if (!validPath(file.path)) violations.push(`PATH_NOT_ALLOWED:${file.path}`);
    if (seen.has(file.path)) violations.push(`DUPLICATE_PATH:${file.path}`);
    seen.add(file.path);
    if (file.expected_file_sha && !/^[a-f0-9]{40}$/i.test(file.expected_file_sha)) {
      violations.push(`EXPECTED_FILE_SHA_INVALID:${file.path}`);
    }
    if (file.expected_content_sha256 && !/^[a-f0-9]{64}$/i.test(file.expected_content_sha256)) {
      violations.push(`EXPECTED_CONTENT_SHA_INVALID:${file.path}`);
    }
  }

  if (violations.length > 0) {
    return jsonResponse({
      outcome: "BLOCKED",
      endpoint_version: ENDPOINT_VERSION,
      code: "BOUNDED_READBACK_GATE_REJECTED",
      violations,
      readback_executed: false,
    }, 400);
  }

  const observed: Array<Record<string, unknown>> = [];
  for (const file of files) {
    const result = await readGitHubFile(githubToken, branch, file.path);
    if (!result.ok) {
      return jsonResponse({
        outcome: "BLOCKED",
        endpoint_version: ENDPOINT_VERSION,
        code: "GITHUB_READBACK_FAILED",
        path: file.path,
        github_status: result.status,
      }, 502);
    }

    if (file.expected_file_sha && file.expected_file_sha !== result.file_sha) {
      return jsonResponse({
        outcome: "BLOCKED",
        endpoint_version: ENDPOINT_VERSION,
        code: "FILE_SHA_MISMATCH",
        path: file.path,
        expected_file_sha: file.expected_file_sha,
        observed_file_sha: result.file_sha,
      }, 409);
    }
    if (file.expected_content_sha256 && file.expected_content_sha256 !== result.content_sha256) {
      return jsonResponse({
        outcome: "BLOCKED",
        endpoint_version: ENDPOINT_VERSION,
        code: "CONTENT_SHA_MISMATCH",
        path: file.path,
        expected_content_sha256: file.expected_content_sha256,
        observed_content_sha256: result.content_sha256,
      }, 409);
    }

    observed.push({
      path: file.path,
      role: file.role,
      file_sha: result.file_sha,
      content_sha256: result.content_sha256,
    });
  }

  return jsonResponse({
    outcome: "OK",
    endpoint_version: ENDPOINT_VERSION,
    code: "BOUNDED_PACK_READBACK_COMPLETED",
    repository: TARGET_REPOSITORY,
    branch,
    files_count: observed.length,
    files: observed,
    packet_id: packetId,
    candidate_hash: candidateHash,
    next_gate: "INDEPENDENT_CONTRACT_REVIEW",
  });
});

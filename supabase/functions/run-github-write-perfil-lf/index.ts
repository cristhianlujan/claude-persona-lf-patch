import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const ENDPOINT_VERSION = "v7-service-role-atomic-pack-write";
const TARGET_REPOSITORY = "cristhianlujan/claude-persona-lf-patch";
const ALLOWED_PATH_PREFIXES = [
  "profiles/",
  "sandbox/lf_contract_gate_test/receipts/",
];
const MAX_FILES = 100;
const MAX_FILE_BYTES = 1_000_000;
const MAX_TOTAL_BYTES = 5_000_000;

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

function byteLength(value: string): number {
  return new TextEncoder().encode(value).byteLength;
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
  if (branch === "main" || branch === "master") return false;
  if (branch.startsWith("-") || branch.startsWith("/") || branch.endsWith("/")) return false;
  if (branch.includes("..") || branch.includes("//") || branch.includes("\\") || branch.includes("@{")) return false;
  return /^[A-Za-z0-9._/-]+$/.test(branch);
}

function validPath(path: string): boolean {
  if (!path || path.length > 500) return false;
  if (path.startsWith("/") || path.includes("..") || path.includes("\\") || path.includes("//")) return false;
  return ALLOWED_PATH_PREFIXES.some((prefix) => path.startsWith(prefix));
}

type PackFile = {
  path: string;
  content: string;
  role: string;
};

function parseFiles(raw: unknown): PackFile[] {
  if (!Array.isArray(raw)) return [];
  return raw.map((item: any) => ({
    path: text(item?.path),
    content: String(item?.content ?? ""),
    role: text(item?.role),
  }));
}

async function githubRequest(
  token: string,
  method: string,
  path: string,
  body?: unknown,
): Promise<{ ok: boolean; status: number; data: any }> {
  const resp = await fetch(`https://api.github.com/repos/${TARGET_REPOSITORY}${path}`, {
    method,
    headers: {
      "Authorization": `Bearer ${token}`,
      "Accept": "application/vnd.github+json",
      "X-GitHub-Api-Version": "2022-11-28",
      "Content-Type": "application/json",
      "User-Agent": "LF-Supabase-Atomic-Profile-Pack-Writer",
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });

  const raw = await resp.text();
  let data: any = null;
  try {
    data = raw ? JSON.parse(raw) : null;
  } catch {
    data = { message: "NON_JSON_GITHUB_RESPONSE" };
  }
  return { ok: resp.ok, status: resp.status, data };
}

function encodedRef(branch: string): string {
  return branch.split("/").map(encodeURIComponent).join("/");
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
  const branch = text(body.branch);
  const packetId = text(body.packet_id);
  const candidateHash = text(body.candidate_hash);
  const commitMessage = text(body.commit_message) || `LF controlled profile pack ${packetId}`;
  const estadoRecibido = text(body.estado_recibido);
  const files = parseFiles(body.files);
  const expectedFilesCount = Number(body.expected_files_count ?? 0);

  const violations: string[] = [];
  if (repo !== TARGET_REPOSITORY) violations.push("REPOSITORY_NOT_ALLOWED");
  if (!validBranch(branch)) violations.push("BRANCH_NOT_ALLOWED");
  if (!packetId || packetId.length > 200) violations.push("PACKET_ID_INVALID");
  if (!/^[a-f0-9]{64}$/i.test(candidateHash)) violations.push("CANDIDATE_HASH_INVALID");
  if (estadoRecibido !== "CANDIDATO_NO_OFICIAL") violations.push("STATE_NOT_ALLOWED");
  if (body.pre_write_gate_passed !== true) violations.push("PRE_WRITE_GATE_REQUIRED");
  if (body.no_blockers !== true) violations.push("NO_BLOCKERS_REQUIRED");
  if (!Number.isInteger(expectedFilesCount) || expectedFilesCount < 2 || expectedFilesCount > MAX_FILES) {
    violations.push("EXPECTED_FILES_COUNT_INVALID");
  }
  if (files.length !== expectedFilesCount) violations.push("FILES_COUNT_MISMATCH");
  if (files.length > MAX_FILES) violations.push("TOO_MANY_FILES");

  const seen = new Set<string>();
  let totalBytes = 0;
  for (const file of files) {
    if (!validPath(file.path)) violations.push(`PATH_NOT_ALLOWED:${file.path}`);
    if (seen.has(file.path)) violations.push(`DUPLICATE_PATH:${file.path}`);
    seen.add(file.path);
    const size = byteLength(file.content);
    totalBytes += size;
    if (size === 0 || size > MAX_FILE_BYTES) violations.push(`CONTENT_SIZE_INVALID:${file.path}`);
  }
  if (totalBytes > MAX_TOTAL_BYTES) violations.push("TOTAL_CONTENT_TOO_LARGE");

  if (violations.length > 0) {
    return jsonResponse({
      outcome: "BLOCKED",
      endpoint_version: ENDPOINT_VERSION,
      code: "STRICT_PACK_GATE_REJECTED",
      violations,
      write_executed: false,
    }, 400);
  }

  const ref = await githubRequest(githubToken, "GET", `/git/ref/heads/${encodedRef(branch)}`);
  if (!ref.ok) {
    return jsonResponse({ outcome: "BLOCKED", endpoint_version: ENDPOINT_VERSION, code: "BRANCH_READ_FAILED", github_status: ref.status }, 502);
  }
  const parentSha = text(ref.data?.object?.sha);
  if (!/^[a-f0-9]{40}$/i.test(parentSha)) {
    return jsonResponse({ outcome: "BLOCKED", endpoint_version: ENDPOINT_VERSION, code: "INVALID_BRANCH_HEAD" }, 502);
  }

  const parentCommit = await githubRequest(githubToken, "GET", `/git/commits/${parentSha}`);
  const baseTreeSha = text(parentCommit.data?.tree?.sha);
  if (!parentCommit.ok || !/^[a-f0-9]{40}$/i.test(baseTreeSha)) {
    return jsonResponse({ outcome: "BLOCKED", endpoint_version: ENDPOINT_VERSION, code: "BASE_TREE_READ_FAILED", github_status: parentCommit.status }, 502);
  }

  const treeEntries: Array<Record<string, string>> = [];
  for (const file of files) {
    const blob = await githubRequest(githubToken, "POST", "/git/blobs", {
      content: file.content,
      encoding: "utf-8",
    });
    const blobSha = text(blob.data?.sha);
    if (!blob.ok || !/^[a-f0-9]{40}$/i.test(blobSha)) {
      return jsonResponse({ outcome: "BLOCKED", endpoint_version: ENDPOINT_VERSION, code: "BLOB_CREATION_FAILED", path: file.path, github_status: blob.status }, 502);
    }
    treeEntries.push({ path: file.path, mode: "100644", type: "blob", sha: blobSha });
  }

  const tree = await githubRequest(githubToken, "POST", "/git/trees", {
    base_tree: baseTreeSha,
    tree: treeEntries,
  });
  const treeSha = text(tree.data?.sha);
  if (!tree.ok || !/^[a-f0-9]{40}$/i.test(treeSha)) {
    return jsonResponse({ outcome: "BLOCKED", endpoint_version: ENDPOINT_VERSION, code: "TREE_CREATION_FAILED", github_status: tree.status }, 502);
  }

  const commit = await githubRequest(githubToken, "POST", "/git/commits", {
    message: `${commitMessage}\n\npacket_id=${packetId}\ncandidate_hash=${candidateHash}`,
    tree: treeSha,
    parents: [parentSha],
  });
  const commitSha = text(commit.data?.sha);
  if (!commit.ok || !/^[a-f0-9]{40}$/i.test(commitSha)) {
    return jsonResponse({ outcome: "BLOCKED", endpoint_version: ENDPOINT_VERSION, code: "COMMIT_CREATION_FAILED", github_status: commit.status }, 502);
  }

  const update = await githubRequest(githubToken, "PATCH", `/git/refs/heads/${encodedRef(branch)}`, {
    sha: commitSha,
    force: false,
  });
  if (!update.ok) {
    return jsonResponse({
      outcome: "BLOCKED",
      endpoint_version: ENDPOINT_VERSION,
      code: "NON_FAST_FORWARD_OR_REF_UPDATE_FAILED",
      github_status: update.status,
      orphan_commit_sha: commitSha,
      write_executed: false,
    }, 409);
  }

  return jsonResponse({
    outcome: "OK",
    endpoint_version: ENDPOINT_VERSION,
    code: "ATOMIC_PACK_WRITE_COMPLETED",
    repository: TARGET_REPOSITORY,
    branch,
    parent_sha: parentSha,
    commit_sha: commitSha,
    tree_sha: treeSha,
    files_count: files.length,
    file_paths: files.map((file) => file.path),
    packet_id: packetId,
    candidate_hash: candidateHash,
    next_gate: "AUTHENTICATED_GITHUB_READBACK",
  });
});

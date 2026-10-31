/**
 * Server-verified evidence for the Profile update `github_write` and `github_readback` steps.
 *
 * The caller only names a branch and a commit. Everything else (changed files, blob SHAs, exact head,
 * SHA match, identity preservation) is derived here from the GitHub API and overwrites caller values.
 * The module is pure with an injected `gh` reader so it can be tested without network access.
 */
export const WRITE_RESOLVER = "GITHUB_PUBLIC_API_EXACT_COMMIT_V1";
export const SERVER_SOURCE = "run-creacion-perfil-lf";
export const IDENTITY_FIELDS = [
  "profile_pack_id", "profile_code", "profile_slug", "document_status", "operational_status",
  "runtime", "automatic_impact", "status", "runtime_enabled", "automatic_promotion",
  "production_enabled", "validated_or_vigente",
] as const;

const SHA40 = /^[0-9a-f]{40}$/;
const BRANCH = /^lf\/[A-Za-z0-9._\/-]{1,120}$/;
const ALLOWED_STATUS = new Set(["added", "modified"]);
const CALLER_DERIVED_KEYS = [
  "written_files", "readback_files", "exact_head", "sha_match", "identity_preserved",
  "server_trust_context", "server_trust_context_valid", "server_trust_context_source",
  "trusted_current_revision", "current_revision_resolved_by_caller", "declared_current_revision_ignored",
];

/** Reads a GitHub REST path (relative to /repos/{repository}) and returns parsed JSON; throws on non-2xx. */
export type GitHubReader = (path: string) => Promise<any>;
export type Verified = { ok: true; evidence: Record<string, unknown> } | { ok: false; code: string };
type Input = {
  repository: string;
  targetRootPath: string;
  boundRevision: string;
  evidence: Record<string, unknown>;
  gh: GitHubReader;
  now?: () => string;
  /** Required for readback: the already recorded, server-verified github_write evidence. */
  recordedWrite?: Record<string, unknown> | null;
};

function strip(evidence: Record<string, unknown>): Record<string, unknown> {
  return Object.fromEntries(Object.entries(evidence).filter(([key]) => !CALLER_DERIVED_KEYS.includes(key)));
}
function encodePath(path: string): string {
  return path.split("/").map(encodeURIComponent).join("/");
}
function under(root: string, path: string): boolean {
  const clean = root.replace(/\/+$/, "");
  return !!clean && path.startsWith(`${clean}/`) && !path.includes("..") && !path.includes("\\");
}

async function manifestAt(gh: GitHubReader, root: string, ref: string): Promise<Record<string, unknown> | null> {
  try {
    const file = await gh(`/contents/${encodePath(`${root.replace(/\/+$/, "")}/manifest.json`)}?ref=${ref}`);
    if (!file || Array.isArray(file) || file.encoding !== "base64" || typeof file.content !== "string") return null;
    const text = typeof atob === "function" ? atob(file.content.replace(/\s+/g, "")) : "";
    const parsed = JSON.parse(text);
    return parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : null;
  } catch (error) {
    if (error instanceof Error && error.message.endsWith("_404")) return null;
    throw error;
  }
}

async function identityPreserved(gh: GitHubReader, root: string, base: string, head: string): Promise<boolean> {
  const before = await manifestAt(gh, root, base);
  const after = await manifestAt(gh, root, head);
  if (before === null && after === null) return true; // profile has no manifest to preserve
  if (before === null || after === null) return false; // manifest created or removed by the write
  return IDENTITY_FIELDS.every((field) => JSON.stringify(before[field]) === JSON.stringify(after[field]));
}

export async function verifyGithubWrite(input: Input): Promise<Verified> {
  const { repository, targetRootPath: root, boundRevision: base, gh } = input;
  if (!SHA40.test(base)) return { ok: false, code: "GITHUB_WRITE_BOUND_REVISION_UNAVAILABLE" };
  const branch = typeof input.evidence.branch === "string" ? input.evidence.branch.trim() : "";
  const commit = typeof input.evidence.commit_sha === "string" ? input.evidence.commit_sha.trim().toLowerCase() : "";
  if (!BRANCH.test(branch)) return { ok: false, code: "GITHUB_WRITE_BRANCH_INVALID" };
  if (!SHA40.test(commit)) return { ok: false, code: "GITHUB_WRITE_COMMIT_SHA_INVALID" };

  const ref = await gh(`/git/ref/heads/${encodePath(branch)}`);
  const head = typeof ref?.object?.sha === "string" ? ref.object.sha.toLowerCase() : "";
  if (head !== commit) return { ok: false, code: "GITHUB_WRITE_BRANCH_HEAD_MISMATCH" };

  const compare = await gh(`/compare/${base}...${commit}`);
  if (compare?.status !== "ahead" || !(compare?.ahead_by >= 1) || compare?.behind_by !== 0) {
    return { ok: false, code: "GITHUB_WRITE_NOT_DESCENDANT_OF_BOUND_REVISION" };
  }
  const files = Array.isArray(compare.files) ? compare.files : [];
  if (files.length === 0 || files.length >= 300) return { ok: false, code: "GITHUB_WRITE_FILE_SET_UNVERIFIABLE" };
  const written: { path: string; blob_sha: string; status: string }[] = [];
  for (const file of files) {
    const path = typeof file?.filename === "string" ? file.filename : "";
    if (!under(root, path)) return { ok: false, code: "GITHUB_WRITE_OUT_OF_PROFILE_SCOPE" };
    if (!ALLOWED_STATUS.has(file?.status)) return { ok: false, code: "GITHUB_WRITE_CHANGE_KIND_NOT_ALLOWED" };
    if (typeof file?.sha !== "string" || !SHA40.test(file.sha)) return { ok: false, code: "GITHUB_WRITE_BLOB_SHA_UNRESOLVED" };
    written.push({ path, blob_sha: file.sha.toLowerCase(), status: file.status });
  }
  written.sort((a, b) => a.path.localeCompare(b.path));
  const preserved = await identityPreserved(gh, root, base, commit);
  if (!preserved) return { ok: false, code: "GITHUB_WRITE_IDENTITY_NOT_PRESERVED" };

  return {
    ok: true,
    evidence: {
      ...strip(input.evidence),
      branch,
      commit_sha: commit,
      written_files: written,
      identity_preserved: true,
      server_trust_context_valid: true,
      server_trust_context_source: SERVER_SOURCE,
      server_trust_context: {
        resolver: WRITE_RESOLVER,
        repository,
        branch,
        commit_sha: commit,
        base_revision: base,
        ahead_by: compare.ahead_by,
        target_root_path: root,
        observed_at: (input.now ?? (() => new Date().toISOString()))(),
      },
    },
  };
}

export async function verifyGithubReadback(input: Input): Promise<Verified> {
  const { repository, targetRootPath: root, boundRevision: base, gh } = input;
  const write = input.recordedWrite;
  const trust = write && typeof write.server_trust_context === "object" ? write.server_trust_context as Record<string, any> : null;
  if (!write || write.server_trust_context_valid !== true || !trust || trust.resolver !== WRITE_RESOLVER) {
    return { ok: false, code: "GITHUB_READBACK_VERIFIED_WRITE_REQUIRED" };
  }
  const branch = String(trust.branch ?? "");
  const commit = String(trust.commit_sha ?? "");
  const files = Array.isArray(write.written_files) ? write.written_files as { path: string; blob_sha: string }[] : [];
  if (!BRANCH.test(branch) || !SHA40.test(commit) || files.length === 0) return { ok: false, code: "GITHUB_READBACK_VERIFIED_WRITE_INVALID" };

  const ref = await gh(`/git/ref/heads/${encodePath(branch)}`);
  const head = typeof ref?.object?.sha === "string" ? ref.object.sha.toLowerCase() : "";
  if (head !== commit) return { ok: false, code: "GITHUB_READBACK_HEAD_DRIFT" };

  const readback: { path: string; blob_sha: string }[] = [];
  for (const file of files) {
    if (!under(root, file.path)) return { ok: false, code: "GITHUB_READBACK_OUT_OF_PROFILE_SCOPE" };
    const content = await gh(`/contents/${encodePath(file.path)}?ref=${head}`);
    const sha = !Array.isArray(content) && typeof content?.sha === "string" ? content.sha.toLowerCase() : "";
    if (!SHA40.test(sha)) return { ok: false, code: "GITHUB_READBACK_BLOB_UNRESOLVED" };
    readback.push({ path: file.path, blob_sha: sha });
  }
  const match = files.every((file, i) => readback[i].path === file.path && readback[i].blob_sha === file.blob_sha);
  if (!match) return { ok: false, code: "GITHUB_READBACK_SHA_MISMATCH" };
  const preserved = await identityPreserved(gh, root, base, head);
  if (!preserved) return { ok: false, code: "GITHUB_READBACK_IDENTITY_MISMATCH" };

  return {
    ok: true,
    evidence: {
      ...strip(input.evidence),
      exact_head: head,
      readback_files: readback,
      sha_match: true,
      identity_preserved: true,
      server_trust_context_valid: true,
      server_trust_context_source: SERVER_SOURCE,
      server_trust_context: {
        resolver: WRITE_RESOLVER,
        repository,
        branch,
        commit_sha: commit,
        exact_head: head,
        base_revision: base,
        target_root_path: root,
        observed_at: (input.now ?? (() => new Date().toISOString()))(),
      },
    },
  };
}


/**
 * A post-write profile amendment is a new verified revision, not a replay of steps 70/80.
 * Compare the same registered branch against the last effective commit and enforce that
 * this branch's net private delta contains only the profile package and evidence docs.
 * External upstream main changes may appear in the ancestry but are not an amendment.
 */
export async function verifyCandidateAmendment(input: Input & {
  previousCommit: string;
  candidateCommit: string;
}): Promise<Verified> {
  const { repository, targetRootPath: root, gh } = input;
  const recorded = input.recordedWrite;
  const trust = recorded && typeof recorded.server_trust_context === "object"
    ? recorded.server_trust_context as Record<string, any> : null;
  if (!recorded || recorded.server_trust_context_valid !== true
      || !trust || trust.resolver !== WRITE_RESOLVER
      || trust.repository !== repository || trust.target_root_path !== root) {
    return { ok: false, code: "PROFILE_AMEND_VERIFIED_WRITE_REQUIRED" };
  }
  const branch = String(trust.branch ?? "");
  const previous = input.previousCommit;
  const candidate = input.candidateCommit;
  if (!BRANCH.test(branch) || !SHA40.test(previous) || !SHA40.test(candidate)
      || previous === candidate || !under("profiles", root + "/SKILL.md")) {
    return { ok: false, code: "PROFILE_AMEND_INPUT_INVALID" };
  }
  const ref = await gh(`/git/ref/heads/${encodePath(branch)}`);
  if (String(ref?.object?.sha ?? "").toLowerCase() !== candidate) {
    return { ok: false, code: "PROFILE_AMEND_HEAD_MISMATCH" };
  }
  const ancestry = await gh(`/compare/${previous}...${candidate}`);
  if (ancestry?.status !== "ahead" || !(ancestry.ahead_by >= 1) || ancestry.behind_by !== 0) {
    return { ok: false, code: "PROFILE_AMEND_NOT_DESCENDANT" };
  }
  const changes = Array.isArray(ancestry.files) ? ancestry.files : [];
  if (changes.length === 0 || changes.length >= 300) {
    return { ok: false, code: "PROFILE_AMEND_COMPARE_UNVERIFIABLE" };
  }
  const privateDiff = await gh(`/compare/main...${candidate}`);
  const onlyCandidate = Array.isArray(privateDiff?.files) ? privateDiff.files : [];
  if (onlyCandidate.length >= 300 || (!["ahead", "diverged", "identical"].includes(String(privateDiff?.status ?? "")))) {
    return { ok: false, code: "PROFILE_AMEND_PRIVATE_DIFF_UNVERIFIABLE" };
  }
  // Keep technical source changes only in this profile. Supporting receipts/changesets are
  // documents; workflows, database migrations, other profiles or operational runs are forbidden.
  const supporting = (path: string): boolean =>
    path.startsWith("docs/profile_updater/handoffs/")
    || path.startsWith("sandbox/lf_contract_gate_test/changesets/");
  for (const file of onlyCandidate) {
    const path = String(file?.filename ?? "");
    if (!under(root, path) && !supporting(path)) {
      return { ok: false, code: "PROFILE_AMEND_OUT_OF_SCOPE_DELTA" };
    }
    if (!ALLOWED_STATUS.has(String(file?.status ?? ""))) {
      return { ok: false, code: "PROFILE_AMEND_REMOVAL_FORBIDDEN" };
    }
  }
  const changed = changes.filter((file: any) => under(root, String(file?.filename ?? "")));
  if (changed.length === 0 || changed.some((file: any) =>
      !ALLOWED_STATUS.has(String(file?.status ?? ""))
      || !SHA40.test(String(file?.sha ?? "")))) {
    return { ok: false, code: "PROFILE_AMEND_PROFILE_DIFF_INVALID" };
  }
  const preserved = await identityPreserved(gh, root, previous, candidate);
  if (!preserved) return { ok: false, code: "PROFILE_AMEND_IDENTITY_NOT_PRESERVED" };
  return {
    ok: true,
    evidence: {
      source: SERVER_SOURCE,
      resolver: "GITHUB_PROFILE_AMENDMENT_V1",
      repository,
      target_root_path: root,
      branch,
      previous_commit: previous,
      candidate_commit: candidate,
      identity_preserved: true,
      head_verified: true,
      changed_profile_files: changed.map((file: any) => ({
        path: file.filename, status: file.status, blob_sha: String(file.sha).toLowerCase(),
      })).sort((a: any, b: any) => a.path.localeCompare(b.path)),
      private_delta_scope_verified: true,
      observed_at: (input.now ?? (() => new Date().toISOString()))(),
    },
  };
}

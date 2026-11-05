/**
 * Server-verified inputs for the Profile update `post_merge_reconcile` step.
 *
 * The caller only names the merged pull request and its merge commit. Every value that reaches the
 * catalog reconciliation (`lf_profile_update_post_merge_reconcile_v1`) is derived here from GitHub:
 * the PR must be merged into main with exactly that merge commit, main must still contain it, and the
 * entrypoint/manifest blob SHAs and the profile pack id are read from the merge commit itself.
 * The module is pure with an injected `gh` reader so it can be tested without network access.
 */
export const RECONCILE_RESOLVER = "GITHUB_PUBLIC_API_MERGED_PR_EXACT_COMMIT_V1";

const SHA40 = /^[0-9a-f]{40}$/;
const ROOT = /^profiles\/[a-z0-9][a-z0-9_-]{1,100}$/;

export type GitHubReader = (path: string) => Promise<any>;
export type Reconcile =
  | { ok: true; args: { merge_sha: string; entrypoint_sha: string; manifest_sha: string; profile_pack_id: string; pr_number: number } }
  | { ok: false; code: string };

type Input = { repository: string; targetRootPath: string; evidence: Record<string, unknown>; gh: GitHubReader };

async function safe<T>(read: () => Promise<T>): Promise<T | null> {
  try { return await read(); } catch { return null; }
}

export async function verifyPostMergeReconcile(input: Input): Promise<Reconcile> {
  const { repository, targetRootPath, evidence, gh } = input;
  if (!ROOT.test(targetRootPath)) return { ok: false, code: "RECONCILE_TARGET_ROOT_INVALID" };
  const mergeSha = String(evidence.merge_sha ?? "").trim().toLowerCase();
  const prNumber = Number(evidence.pr_number);
  if (!SHA40.test(mergeSha)) return { ok: false, code: "RECONCILE_MERGE_SHA_INVALID" };
  if (!Number.isInteger(prNumber) || prNumber <= 0) return { ok: false, code: "RECONCILE_PR_NUMBER_INVALID" };

  const pr = await safe(() => gh(`/pulls/${prNumber}`));
  if (!pr) return { ok: false, code: "RECONCILE_PR_NOT_FOUND" };
  if (pr.merged !== true || pr.base?.ref !== "main" || pr.base?.repo?.full_name !== repository) return { ok: false, code: "RECONCILE_PR_NOT_MERGED_INTO_MAIN" };
  if (String(pr.merge_commit_sha ?? "").toLowerCase() !== mergeSha) return { ok: false, code: "RECONCILE_MERGE_SHA_MISMATCH" };

  const compare = await safe(() => gh(`/compare/${mergeSha}...main`));
  if (!compare || !["identical", "ahead"].includes(String(compare.status))) return { ok: false, code: "RECONCILE_MERGE_NOT_ON_MAIN" };

  const entry = await safe(() => gh(`/contents/${targetRootPath}/SKILL.md?ref=${mergeSha}`));
  const manifestFile = await safe(() => gh(`/contents/${targetRootPath}/manifest.json?ref=${mergeSha}`));
  const entrypointSha = String(entry?.sha ?? "");
  const manifestSha = String(manifestFile?.sha ?? "");
  if (!SHA40.test(entrypointSha) || !SHA40.test(manifestSha)) return { ok: false, code: "RECONCILE_PROFILE_BLOBS_MISSING" };

  let manifest: any;
  try {
    if (manifestFile.encoding !== "base64") throw new Error("encoding");
    manifest = JSON.parse(new TextDecoder().decode(Uint8Array.from(atob(String(manifestFile.content).replace(/\s/g, "")), (c) => c.charCodeAt(0))));
  } catch { return { ok: false, code: "RECONCILE_MANIFEST_UNPARSEABLE" }; }
  const pack = typeof manifest?.profile_pack_id === "string" ? manifest.profile_pack_id.trim() : "";
  if (!pack) return { ok: false, code: "RECONCILE_PROFILE_PACK_ID_MISSING" };

  return { ok: true, args: { merge_sha: mergeSha, entrypoint_sha: entrypointSha, manifest_sha: manifestSha, profile_pack_id: pack, pr_number: prNumber } };
}

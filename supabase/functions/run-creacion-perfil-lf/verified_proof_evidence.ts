/**
 * Server-verified evidence from the read-only Profile evolution proof workflow.
 *
 * The caller only names a workflow run id. The run, its inputs (bound through the run title), its
 * conclusion and the published result are read back from the GitHub API and cross-checked against the
 * values the execution already holds. Pure module with an injected `gh` reader.
 */
export const PROOF_RESOLVER = "GITHUB_ACTIONS_EVOLUTION_PROOF_V1";
export const PROOF_SERVER_SOURCE = "run-creacion-perfil-lf";
export const PROOF_WORKFLOW_PATH = ".github/workflows/lf-profile-evolution-proof.yml";
const ANNOTATION_TITLE = "LF_PROFILE_EVOLUTION_PROOF";
const SHA40 = /^[0-9a-f]{40}$/;
const SHA64 = /^[0-9a-f]{64}$/;
const SLUG = /^[a-z0-9][a-z0-9_]{0,79}$/;
const ZERO40 = "0".repeat(40);

export type GitHubReader = (path: string) => Promise<any>;
export type ProofVerified = { ok: true; evidence: Record<string, unknown> } | { ok: false; code: string };
type Input = {
  repository: string;
  mode: "measure" | "compare";
  profileSlug: string;
  baseSha: string;
  candidateSha?: string;
  runId: unknown;
  /** ISO time; the run must have been created at or after it. */
  notBefore: string;
  gh: GitHubReader;
  now?: () => string;
};

export async function verifyEvolutionProofRun(input: Input): Promise<ProofVerified> {
  const { repository, mode, profileSlug, baseSha, gh } = input;
  const candidate = mode === "compare" ? String(input.candidateSha ?? "") : ZERO40;
  const runId = typeof input.runId === "number" ? String(input.runId) : typeof input.runId === "string" ? input.runId.trim() : "";
  if (!/^[0-9]{1,15}$/.test(runId)) return { ok: false, code: "PROOF_RUN_ID_INVALID" };
  if (!SLUG.test(profileSlug) || !SHA40.test(baseSha) || !SHA40.test(candidate) || (mode === "compare" && candidate === ZERO40)) {
    return { ok: false, code: "PROOF_EXPECTATION_INVALID" };
  }

  const run = await gh(`/actions/runs/${runId}`);
  if (run?.path !== PROOF_WORKFLOW_PATH || run?.event !== "workflow_dispatch") return { ok: false, code: "PROOF_RUN_NOT_PROOF_WORKFLOW" };
  if (run?.head_branch !== "main" || run?.repository?.full_name !== repository || run?.head_repository?.full_name !== repository) {
    return { ok: false, code: "PROOF_RUN_NOT_TRUSTED_SOURCE" };
  }
  if (run?.status !== "completed" || run?.conclusion !== "success") return { ok: false, code: "PROOF_RUN_NOT_SUCCESSFUL" };
  const expectedTitle = `profile-evolution-proof ${mode} ${profileSlug} ${baseSha} ${candidate}`;
  if (run?.display_title !== expectedTitle) return { ok: false, code: "PROOF_RUN_INPUTS_MISMATCH" };
  const created = Date.parse(String(run?.created_at ?? ""));
  if (!Number.isFinite(created) || created < Date.parse(input.notBefore)) return { ok: false, code: "PROOF_RUN_STALE" };

  const jobs = await gh(`/actions/runs/${runId}/jobs`);
  const list = Array.isArray(jobs?.jobs) ? jobs.jobs : [];
  if (list.length !== 1 || list[0]?.name !== "proof" || list[0]?.conclusion !== "success" || !Number.isInteger(list[0]?.id)) {
    return { ok: false, code: "PROOF_JOB_NOT_SUCCESSFUL" };
  }
  const annotations = await gh(`/check-runs/${list[0].id}/annotations`);
  const matches = (Array.isArray(annotations) ? annotations : []).filter((a: any) => a?.title === ANNOTATION_TITLE);
  if (matches.length !== 1) return { ok: false, code: "PROOF_ANNOTATION_MISSING_OR_AMBIGUOUS" };
  let envelope: any;
  try { envelope = JSON.parse(String(matches[0].message)); } catch { return { ok: false, code: "PROOF_ANNOTATION_UNPARSEABLE" }; }
  const proof = envelope?.proof;
  if (envelope?.schema !== "LF_PROFILE_EVOLUTION_PROOF_ANNOTATION_V1" || envelope?.mode !== mode || envelope?.profile_slug !== profileSlug
      || envelope?.base_sha !== baseSha || envelope?.candidate_sha !== candidate || !proof || typeof proof !== "object"
      || !SHA64.test(String(proof.proof_sha256 ?? "")) || proof.profile_slug !== profileSlug
      || !Array.isArray(proof.blocking_codes) || proof.blocking_codes.length !== 0) {
    return { ok: false, code: "PROOF_ANNOTATION_MISMATCH" };
  }
  if (mode === "measure") {
    if (proof.schema !== "S26_PROFILE_MEASUREMENT_V1" || proof.decision === "BLOCKED" || !Number.isInteger(proof.score) || !Number.isInteger(proof.required)) {
      return { ok: false, code: "PROOF_MEASUREMENT_INVALID" };
    }
  } else if (proof.schema !== "S26_PROFILE_EVOLUTION_PROOF_V1" || proof.verdict !== "EVOLUTION_DEMONSTRATED"
      || !Array.isArray(proof.improved_dimensions) || proof.improved_dimensions.length < 1
      || !Array.isArray(proof.regressed_dimensions) || proof.regressed_dimensions.length !== 0) {
    return { ok: false, code: "PROOF_COMPARISON_NOT_DEMONSTRATED" };
  }

  return {
    ok: true,
    evidence: {
      proof_run_id: runId,
      proof_mode: mode,
      proof,
      server_trust_context_valid: true,
      server_trust_context_source: PROOF_SERVER_SOURCE,
      server_trust_context: {
        resolver: PROOF_RESOLVER,
        repository,
        run_id: runId,
        mode,
        profile_slug: profileSlug,
        base_sha: baseSha,
        candidate_sha: candidate,
        proof_sha256: proof.proof_sha256,
        observed_at: (input.now ?? (() => new Date().toISOString()))(),
      },
    },
  };
}

export const REPOSITORY = "cristhianlujan/claude-persona-lf-patch";

export const LEGACY_WORKFLOW_NAME = "lf-contract-check";
export const LEGACY_WORKFLOW_PATH = ".github/workflows/lf-contract-check.yml";
export const PASE_WORKFLOW_NAME = "PASE";
export const PASE_WORKFLOW_PATH = ".github/workflows/pase.yml";

// Compatibility exports retained while downstream code migrates.
export const WORKFLOW_NAME = LEGACY_WORKFLOW_NAME;
export const WORKFLOW_PATH = LEGACY_WORKFLOW_PATH;

export const WORKFLOW_IDENTITIES = Object.freeze([
  Object.freeze({ name: LEGACY_WORKFLOW_NAME, path: LEGACY_WORKFLOW_PATH }),
  Object.freeze({ name: PASE_WORKFLOW_NAME, path: PASE_WORKFLOW_PATH }),
]);

export const SOURCE_EVIDENCE_OBJECT_ID = "be7fcf20-5f83-46d4-be0e-c80dc3ceed7c";
export const SOURCE_SHA256 = "e308b66778d1108241e2832997f6628f47841d7da1fc53820007834fdbb720d7";
export const SOURCE_BYTES = 1384686;

export function governedRef(ref) {
  if (ref === "refs/heads/main") return true;
  return /^refs\/heads\/lf\/p0-[A-Za-z0-9._\/-]+$/.test(String(ref || ""));
}

export function branchFromRef(ref) {
  if (!governedRef(ref)) return null;
  return ref.slice("refs/heads/".length);
}

export function validateRequestScope(body) {
  if (!body || body.repository !== REPOSITORY) return "GITHUB_REQUEST_REPOSITORY_MISMATCH";
  if (!governedRef(body.ref)) return "GITHUB_REQUEST_REF_NOT_GOVERNED";
  if (!/^[0-9a-f]{40}$/.test(String(body.github_sha || ""))) return "GITHUB_SHA_INVALID";
  if (!Number.isSafeInteger(body.run_id) || body.run_id <= 0) return "GITHUB_RUN_ID_INVALID";
  if (!Number.isSafeInteger(body.run_attempt) || body.run_attempt <= 0) return "GITHUB_RUN_ATTEMPT_INVALID";
  if (!["push", "workflow_dispatch"].includes(body.event_name)) return "GITHUB_EVENT_INVALID";
  return null;
}

function expectedIdentityForName(name) {
  return WORKFLOW_IDENTITIES.find((identity) => identity.name === name) ?? null;
}

export function validateRunIdentity(body, run) {
  const branch = branchFromRef(body.ref);
  if (!branch) return "GITHUB_REQUEST_REF_NOT_GOVERNED";
  if (Number(run?.id) !== Number(body.run_id)) return "GITHUB_WORKFLOW_RUN_ID_MISMATCH";
  if (Number(run?.run_attempt) !== Number(body.run_attempt)) return "GITHUB_WORKFLOW_RUN_ATTEMPT_MISMATCH";
  if (run?.repository?.full_name !== REPOSITORY) return "GITHUB_WORKFLOW_REPOSITORY_MISMATCH";
  const identity = expectedIdentityForName(run?.name);
  if (!identity) return "GITHUB_WORKFLOW_NAME_MISMATCH";
  if (run?.path !== identity.path) return "GITHUB_WORKFLOW_PATH_MISMATCH";
  if (run?.head_branch !== branch) return "GITHUB_WORKFLOW_BRANCH_MISMATCH";
  if (run?.head_sha !== body.github_sha) return "GITHUB_WORKFLOW_SHA_MISMATCH";
  if (run?.event !== body.event_name) return "GITHUB_WORKFLOW_EVENT_MISMATCH";
  if (!["queued", "in_progress"].includes(run?.status)) return "GITHUB_WORKFLOW_STATUS_INVALID";
  return null;
}

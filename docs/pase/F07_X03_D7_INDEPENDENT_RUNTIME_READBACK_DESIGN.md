# D7 — Independent runtime readback (design only; not executable/activated)

Owner event: lf_eventos #20641. Bound to F07-X03 and F07-X02-R01.

## Observer and security boundary
Use a *new* GitHub Actions job distinct from the deploy workflow and deploy identity.
Input: execution_id, exact_head (40 lowercase hexadecimal chars), release_path (exact canonical path under /opt/lf-profile-runtime-api/releases/<sha>).
New GitHub Actions secret: LF_RUNTIME_READBACK_SSH_PRIVATE_KEY. Install its corresponding public key for a dedicated read-only SSH account on VPS (not created here); separate host/known_hosts secret LF_RUNTIME_READBACK_KNOWN_HOSTS, and host/user variables. Key cannot use sudo, write, systemctl, deploy installer, or modify /etc, /opt, runtime state, or symlink. Read-only access solely to the intended release files and loopback API, through a restricted command or broker. Avoid arbitrary user-controlled shell paths. The authenticated observer must not share credentials with the deploy actor.

## Steps (future implementation, not in this PR)
1. Authenticate GitHub Actions run: workflow identity + repository + run_id/attempt + immutable exact_head and deployment execution_id.
2. Load exact Git commit tree. Build deterministic required-file manifest SHA-256 for the deployed artifact set and record manifest digest. Define explicit include/exclude rules (generated artifacts, environment secrets, dependencies) and independently prove parity against the real deployed release.
3. SSH with *read-only* identity, restrict release_path to /opt/lf-profile-runtime-api/releases/<exact_head>, and independently resolve /opt/lf-profile-runtime-api/current symlink, ensure current realpath equals nominated release. Read /health at loopback (source_sha, runtime_version) and authenticated /runtime using a separately scoped read-only API token. No restart, mutation, canary or deploy.
4. Independently compute sha256sum for every allowlisted file from the manifest in the actual release (not from the deploy receipt), reject missing/extra/changed files. Bind process identity to the actual running service (systemd process /proc path read-only) to prevent comparing an unused release.
5. Require observed /health source_sha == exact_head and exact runtime SHA == expected; compare evidence with immutable Git manifest and the *declarative* deploy receipt.
6. Publish LF_RUNTIME_INDEPENDENT_READBACK_V1 JSON artifact with execution_id, observer_execution_id, exact_head, release_path, health_source_sha, runtime_version, manifest_digest, file_hashes, current_symlink_target, process_release_path, workflow_run_id, run_attempt, observer actor identity, source repo, evidence SHA256, timestamp and result. Artifact is untrusted until verified against GitHub API by a separate authorized verifier.
7. RUNTIME_DEPLOY_VERIFICATION checks authenticated workflow-run and artifact digest through GitHub API, confirms run workflow/commit/repo identity, artifact contents + readback provenance, checks SHA/manifest/health/state and records VERIFICATION_VERIFIED or VERIFICATION_FAILED. The SQL candidate binding *rejects* all unauthenticated claims including a self-declared observer payload. Do not substitute an unverified attestation_ref string.

## R01 closure (future, not executed)
Trigger observation against existing release af6540c5757b39130c92a8ffd7a61d3cd7b8cb58, expected exact_head same, execution_id EXEC-REFRESCO-RUNTIME-PERFIL-SRCR-20261007-003. Read /health and /runtime; hash real release, verify current running code and compare exact commit manifest. If and only if independent receipt is authenticated and RUNTIME_DEPLOY_VERIFICATION yields VERIFICATION_VERIFIED, attach receipt to F07-X02-R01. If release changed, hashes diverge, read-only credential cannot verify process path, or job is not authenticated: fail closed. Do not assert VERIFIED before job runs.

## Blocker
The protected observer credential, restricted VPS identity, GitHub workflow, API-token separation and GitHub run/artifact authentication bridge are NOT implemented in this design-only change. The candidate binding deliberately blocks acceptance until those independent controls exist.

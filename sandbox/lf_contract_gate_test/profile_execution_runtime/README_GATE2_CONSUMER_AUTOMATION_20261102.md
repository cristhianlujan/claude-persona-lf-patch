# LF — Gate 2 consumer-side enforcement candidate | R3 — 2026-11-02

**Evidence state**: LOCAL_TESTED / NOT_PUBLISHED / NOT_MERGED / NOT_DEPLOYED. **26/26 local unit tests PASS.** This is not an end-to-end canary or a Supabase mutation.

## Exact boundary

- ACT-0001 remains read-only derivation. It never calls the selected profile or receives `service_role`.
- The consumer of an actual Gate 2 `GATE2_DERIVED_PENDING_GOVERNED_ADMISSION` + `HANDOFF_CONTEXT_TO_SELECTED_PROFILE` must **continue**, using the *existing* `LF_PROFILE_NATIVE_BEGIN_REQUEST_V1` payload, GitHub Issue label `lf-profile-resume-governed`, Actions OIDC and Edge's own `service_role`. No intermediary and no direct RPC from the Supabase read-only connection.
- The new `execution_id` must be sourced from the fresh workflow run; reuse the same ID for `LF_PROFILE_NATIVE_RESUME_REQUEST_V1` through `input_validate`, `execute_profile`, `output_validate`, `semantic_judge` and `report_output`.
- Full operational certification requires **11/11 STEP_PASS_WITH_EVIDENCE**, run **COMPLETED**, and the canonical terminal authority receipt **READY** in Supabase for this new execution. A textual claim or ID in a response is not accreditation.

## Local components

1. `.claude/settings.json` installs the **Claude Code Stop** hook. It detects a fresh Gate 2 from the current turn, blocks premature finals regardless of wording (including short approvals such as `Ok conforme`), and instructs the native agent to continue via the existing Issue/Actions/Edge flow. It ignores mere explanatory questions and a proven tool denial, protects against stop-hook recursion, and refuses to take a claimed `COMPLETED/READY` without current-turn terminal readback evidence. The hook does **not** call GitHub, Edge, Supabase, the Router or any model and cannot prove runtime status by itself. R3 specifically requires current-turn tool evidence, not a claimed error in the assistant text, and rejects cross-run terminal proof assembled from separate tools.
2. `lf_profile_begin_payload.py` creates the complete **unchanged** request JSON from a genuine V2 context. It checks selected profile, Gate 2 receipts and exact SHA256 of `stage1_payload.texto_original` against both selection and Gate 2 receipts. It also refuses known credential fields and mismatched modes. The existing OIDC/Edge path supplies final server verification.
3. Tests cover missing fields, mismatched request hashes, wrong profiles/tenants, credentials, 20% exit, false `COMPLETED`/`READY`, actual same-tool terminal readback (never mixed across runs), neutral phrasing, short approvals, explanations, denied transport with observed tool evidence, and hook re-entry.

## Product changes are a SEPARATE governed operation

`EJECUCION_PERFIL_LF` retains `read_only/no_write/no_promotion` by design. A new `COMPLETED` profile receipt DOES NOT mean `lf_ops.reglas` was updated. An agent may continue within existing user-authorized scope by routing each *approved* change to its **registered write operation**, validating that operation's live authority, then performing readback. Never silently promote candidates or reinterpret a missing authority as approval.

- `CANDIDATO` with current exact write authority: `ACTUALIZACION_REGLA_LF` / canonical candidate writer; commit only under the governed operation, preserve CANDIDATO and read back.
- `VIGENTE` (e.g. AUTH-016): existing candidate writer is **incompatible**; do not downgrade to CANDIDATO or use SQL ad-hoc. The separately authorized `ACTUALIZACION_DB_LF` / migration / Merge Train path may be used only if ACT-0001 and the operation contract permit this bounded maintenance. If Router blocks, **BLOCKED**, not a bypass.
- AUTH-047: password-failure policy is missing; RATE-B2B-LOGIN is rate of requests, **not** failed password attempts. No synthetic password threshold/promotion.
- Existing 13 associations + 3 AUTH states + 3 transitions are already CANDIDATO; **no duplicate inserts**. QA, MFA provider and Input readiness must be evidenced before promotion.

## Deployment (not performed)

The connected GitHub content API alone cannot reproduce the mandatory local exact-HEAD PASE prepush step required by `CLAUDE.md`. This runtime does not have a Git checkout or network access to clone the repository. **Do not push/merge based on unit tests alone.** At an authorized checkout:

1. Stage these files and commit in a branch from current `main`; check changeset manifest family classification.
2. Execute `emit_ci_execution_plan_v2.py` with committed HEAD, actual `origin/main` revision and correct merge base; resolve any red preflight.
3. Publish PR only after PASE prepush; use `ready-to-merge`/LF Merge Train (no direct merge); verify committed content.
4. Use a fresh LF Router request as a canary: Gate 2 → labeled BEGIN → new workflow-bound execution ID → native RAW → V3 → 11/11 READY; test negative 20% attempt, tool denial, no loss of context. Keep `ACT-0001` source and ACL unchanged.
5. Independently route an approved candidate rule change and verify the exact row before/after. Do not claim auto-write based solely on Step 80.

**Limits:** This hook only runs when Claude Code loads the `.claude/settings.json`. It does not install into ChatGPT's host or guarantee universal agent enforcement. Hook `Stop` is a last-chance continuation guard, not an autonomous Issue creator. All operational writes retain their own governance.

Trace: EKB `LF-PROFILE-HANDOFF-DIRECT-42501-OLD-RUN-SUBSTITUTION-001`, runbook §6.9, [#3490](https://github.com/cristhianlujan/claude-persona-lf-patch/issues/3490), [#3480](https://github.com/cristhianlujan/claude-persona-lf-patch/issues/3480), [#3489](https://github.com/cristhianlujan/claude-persona-lf-patch/issues/3489).

## R3 test / operational limit (2026-11-02)

- Local `unittest discover`: **26/26 PASS**. `python -m compileall`: PASS. Changed paths remain the same seven files; the Router, Input Governance and native Edge executor are not modified.
- This is a **Stop-hook guard** in Claude Code, not automatic server execution or automatic Supabase writes. It never creates an Issue by itself and cannot enforce ChatGPT-host responses. It is an additional consumer fail-closed control; the selected profile must still perform BEGIN through existing tools and verify the canonical new run.
- PASE exact-HEAD and Merge Train not run: checkout of full Git repository was absent, and `git ls-remote` failed DNS. No branch, PR or deployment is claimed.

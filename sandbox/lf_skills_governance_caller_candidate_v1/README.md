# LF — Generic Skills Edge Caller (CANDIDATE ONLY)

**Scope:** reusable infrastructure adapter for `EJECUCION_SKILL_LF`. It is **not** an LF skill, new Router or production Edge function. This candidate is intentionally outside `supabase/functions/` and **MUST NOT be deployed**.

## Provenance and compatibility
- Derived from `EJECUCION_PERFIL_LF` pattern: authenticated OIDC caller → server-authorized operation begin → shared `fn_lf_operation_reserve_execution_v1` → immutable `init_execution` (step 0) → step recorder wrapper using `lf_record_operation_step_core_v1` and skill-specific trust → semantic judge → terminal report.
- Independent of `lf-profiles-governance-caller-v1`; does not change its endpoint, credentials, OIDC audience or SQL handler `lf_skill_invoke_v1`.
- Routes: `skill_native_begin_v1`, `skill_native_record_step_v1`, `skill_native_status_v1`. The canonical operation remains `EJECUCION_SKILL_LF` (0,10,20,30,40,50,60,70,80). Inside step 50 the skill manages its own internal steps. For `PROGRAMMING_ANALYSIS_LF`, A3 requires the native A2 judge PASS before dispatch.
- Disabled by default: `LF_SKILL_NATIVE_CALLER_ENABLED` must be exactly `true` to even process requests.
- Auth: separate GitHub Actions OIDC `aud=lf-skills-governance-caller-v1`, exact repo/id/ref/workflow/environment. The signed JWT is verified by Jose in the proposed `index.ts`.
- The Edge obtains the canonical skill path from **server preflight**, not `skill_code` or caller-supplied target. It pins GitHub Main commit and file blob; unknown directory-only or non-GitHub sources **block**, no inference.
- Read-only business skills still require an **authorized audit writer** to persist the RUN/steps. No general model write rights.
- `business` in `input.business` is only DECLARED; authorized SQL must compare with the parent profile RUN and Router receipt. All privileged caller claims (including nested) are rejected.

## Native RPC and OIDC qualification (candidate only)

- `RPC_CONTRACT_QUALIFICATION_V1.json` — the four proposed RPC interfaces and their server-side authority, transaction, replay, judge and readback invariants. **None of these RPCs is deployed**.
- `QUALIFICATION_REPORT_V1.md` — read-only Supabase source comparison and requirement→risk→invariant→evidence→positive/negative-test matrix. **The current generic skill judge has empty pass/fail arrays and is P0-unqualified for operational use.**
- `OIDC_WORKFLOW_CANDIDATE.yml.txt` — disabled reference template (`if: false`), not a runnable GitHub workflow.
- `TRUST_WRAPPER_QUALIFICATION_V1.md` — source-verified pattern for the skill-specific trust wrapper over the shared recorder; **NOT INSTALLED**. Includes current vacuous-judge P0 and independent coverage matrix.
- `skill_judge_qualification_candidate_v1.mjs` + `.test.mjs` — pure, unauthenticated judge-coverage checks, **36/36 local PASS** on byte-identical source; cannot authorize a RUN, judge or A3.
- One PR remains dedicated to generic caller infrastructure. `PROGRAMMING_ANALYSIS_LF` and its A2→A3 gate remain in PR #3624, not in this Edge transport PR.

## Contents
- `handler.mjs`: framework-free candidate implementation for BEGIN, STEP, STATUS.
- `index.ts`: proposed Deno/Jose deployment entrypoint (**not deployed**).
- `handler.test.mjs`: local Node v22 synthetic test suite (40 cases; not RPC live verification).

Run locally: `node --test handler.test.mjs`.

## Unresolved P0 — do not activate
1. RPC names `lf_skill_native_preflight_v1`, `lf_skill_execution_begin_from_handoff_v1`, `lf_record_skill_execution_step_v1`, `lf_skill_execution_status_v1` are **PROPOSED/NOT INSTALLED**; no runtime success or authority readback exists.
2. The dedicated OIDC workflow/environment and admission authority do not exist as verified sources. No workflow is created by this PR.
3. Only skills with a verified `skills/**/SKILL.md` GitHub file are covered by this candidate. Some catalog rows use other or missing source locations.
4. `PROGRAMMING_ANALYSIS_LF` has no READY catalog row, enabled runtime binding, execution authority or native RUN.
5. New Edge deployment, DB migrations, authority grants and source-official changes need a **separate governed approval and review**.
6. Keep existing SQL synchronous skills working as-is. Do not substitute an SQL `COMPLETED` response for an `EJECUCION_SKILL_LF` run, step 0 or judge PASS.
7. The Edge transports untrusted evidence; the SQL trust validator and existing judge must derive all enforcement from persisted server-side evidence. No `a3_allowed=true` is issued by this adapter.

**Evidence level:** candidate code and synthetic tests only. **NOT:** operational integration, deployed endpoint, admitted skill, signed source attestation, independent model judge or live RUN.

Reference: independent candidate PR (this branch). `PROGRAMMING_ANALYSIS_LF` remains separately tracked in PR #3624.

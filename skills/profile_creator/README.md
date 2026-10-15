# LF Profile Creator Pack

Status: CANDIDATE
Control level: PRODUCCION_CONTROLADA_READ_ONLY
Runtime: DISABLED
Automatic impact: BLOCKED

This pack defines the controlled LF skill used to create complete profile packs. It does not create final profiles directly in production. It produces profile pack candidates that must pass Quality Pack Review, Sandbox Test, and controlled PR review before any operational use.

## Purpose

Create profile packs that are reusable, auditable, and aligned with LF governance. A valid profile pack is more than a prompt: it includes contracts, schemas, judges, checklists, examples, fixtures, validators, evals, handoffs, and adapters.

## Source authority

- ACT-0001 Router is governing authority.
- Supabase `public.v_lf_fuente_operativa` is the primary operational source.
- ACT-0045 is the governing asset for Skill Factory / Skill Creator / Profile Creator / Cards.
- GitHub is the technical repository layer.
- Google Docs remains the human documentation layer.

## Non-goals

- No direct modification of ACT-0045.
- No Supabase writes.
- No runtime enablement.
- No production general enablement.
- No final profile creation without review gates.
- No infinite rule creation; consolidate into reusable mother rules.

## Required gates

1. Router decision.
2. Source verification in Supabase.
3. Applicable active asset verification.
4. Profile Creator operation.
5. Quality Pack Review.
6. Sandbox Test.
7. Controlled PR.
8. Post-merge verification.

## S26 existing-profile baseline

For `ACTUALIZACION_PERFIL_LF`, first materialize a fresh Learning Preflight bound to the target profile and current HEAD, then run:

```bash
python3 skills/profile_creator/validators/plan_s26_profile_update.py <profile_slug> <preflight_json> <repo_root>
```

The planner is read-only. It returns `BLOCKED_LEARNING_PREFLIGHT` unless the live EKB controls are traced to matched prevention rules and executable prevention evidence and the canonical pre-write execution binding matches the current target revision. Only then can it report `NO_UPDATE_REQUIRED`, `UPDATE_REQUIRED`, or `BLOCKED_AUTHORITY_REQUIRED`.

`write_allowed=true` requires both a PASS Learning Preflight and a repairable structural delta. The baseline evaluator discovers target callables statically with AST and never imports or executes target profile code.

Post-write closure requires a fresh 13/13 baseline result on the exact candidate head plus the existing operation, evidence, readback, semantic and regression gates.

## Transversal output parity (new and evolved profiles)

For `CREACION_PERFIL_LF`, Profile Creator's existing
`validate_candidate_depth.py` invokes the shared structural preflight
`validators/profile_output_shape_preflight_v1.py` on each materialized positive
output example against its output schema. A missing field or invalid enum fails
the creation-depth gate, not merely a document checklist.

For `ACTUALIZACION_PERFIL_LF`, `plan_profile_evolution.py` returns an
explicit `candidate_output_contract_gate` before admission. It is **not
executed** by planning: the governed post-generation consumer must resolve the
**current bound** schema and profile-local validator and then run:

```bash
python3 skills/profile_creator/validators/run_bound_profile_output_validator_v1.py \
  --root <exact-repository-checkout> --binding <source-bound-binding.json>
```

Binding schema: `PROFILE_OUTPUT_VALIDATION_BINDING_V1` with
`operation_code`, `profile_slug`, `expected_valid`, three exact local refs
(`schema_ref`, `validator_ref`, `raw_output_ref`) and matching SHA-256s,
plus `validator_transport` = `STDIN_JSON` or `JSON_FILE_ARGUMENT`.
Only a profile's existing, current authoritative validator is allowed, not
one inferred from filenames. Confirm a positive output and a deliberately
negative counterexample. Any mismatch blocks that candidate; one bounded
repair is possible, followed by a STOP on tie or unresolved gain. Evidence
from this runner is only structural/local; never provider attestation or
cutover approval. No additional pack discovery engine or profile-specific
branching is introduced.


## Preventive gaps and bounded remediation (Updater)

The read-only candidate planner now declares `preventive_gap_review` for
origin/EKB, qualified methods, structural/schema parity, functional regression,
semantic utility and final provenance. These are **assignments to the existing
frozen steps**, not a new engine or blanket requirement to scan all profiles.
A material output mismatch returns a bounded repair directive from
`run_bound_profile_output_validator_v1.py`; the authorized producer, not
the validator, performs a maximum of one correction pass per evidenced defect
batch, then reruns exact-head validation. If it cannot repair safely, STOP.
No claim of automatic repair, independent PASS, admission or production.

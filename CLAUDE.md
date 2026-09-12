# Claude Code Project Instructions

Apply the shared operational protocol before creating, editing, transporting, or presenting an artifact:

@.claude/operational-execution.md

Use the relevant `SKILL.md` and its direct references for domain-specific work.

For every artifact operation:

1. Resolve the exact target, source, authorized scope, destination, and output surface.
2. Build a validation plan before the first write.
3. Execute the smallest complete change.
4. Validate the produced artifact with the project validator.
5. Read the persisted result back from its destination.
6. Compare content, counts, and hashes.
7. Report status only from the collected evidence.

Preserve this sequence for delegated agents and subagents.

## Governed profile updates

When creating a patch that modifies an existing repository profile under `profiles/**`, route the operation as `ACTUALIZACION_PERFIL_LF` and apply section 15, **Protocolo de pase para actualización de perfiles**, in:

@.claude/operational-execution.md

Supabase remains the canonical authority for the operation contract, execution binding, judge, state **and active pass policy**. The GitHub protocol is a reproducible human-readable projection and does not supersede the active Supabase policy snapshot.

### Dynamic pass-policy snapshot

Every new `ACTUALIZACION_PERFIL_LF` execution is automatically bound by Supabase to the active policy registered for that operation. Read the execution manifest before doing any repository write and require:

```text
manifest.operation_policy_source = SUPABASE
manifest.operation_policy_snapshots.PASS_POLICY.policy_code
manifest.operation_policy_snapshots.PASS_POLICY.policy_version
manifest.operation_policy_snapshots.PASS_POLICY.policy_sha
manifest.operation_policy_snapshots.PASS_POLICY.policy_payload
```

The current policy family is inventoried as `POL-PROFILE-UPDATE-PASS` (`tipo_activo=REGLA`, `subtipo_activo=POLICY_TRANSVERSAL_GOV`) and is resolved through `public.v_lf_operation_policy_snapshot`.

Rules:

- Router and direct profile-update invocations consume the same Supabase policy snapshot.
- Never use a prior PR, branch, chat, example or previous successful profile as the operational source of truth for how to pass.
- Prior PRs are historical evidence only.
- If the required policy snapshot is missing, fail closed with `BLOCK_PROFILE_UPDATE_POLICY_MISSING`.
- The policy snapshot in an execution is immutable.
- On any execution status transition, Supabase compares the bound `policy_sha` with the active policy. A stale SHA must block with `BLOCK_STALE_PROFILE_UPDATE_POLICY`.
- If this file or section 15 disagrees with the bound active `policy_payload`, the Supabase snapshot wins and the divergence must be recorded/remediated as governance drift.

At minimum:

1. query EKB first;
2. resolve exactly one profile and the canonical `ACTUALIZACION_PERFIL_LF` operation;
3. create the canonical execution and read its active policy snapshot before any repository write;
4. create and pass the canonical pre-write execution binding before any repository write;
5. branch from the current exact `main` SHA;
6. write only authorized paths and read them back from the remote branch;
7. require deterministic, semantic, adversarial/holdout and Router/direct evidence as required by the bound policy;
8. require all required workflows to be `SUCCESS` on the exact candidate HEAD;
9. immediately before merge, re-read both `main` and the active operation policy; if either advanced, fail closed and recertify under the current authority without force-push;
10. never create retroactive receipts or auxiliary PRs merely to compare branches;
11. after merge, read back from the new `main`, close the canonical execution with evidence and enrich EKB.

## Governed profile execution

When the user explicitly asks to use an existing repository profile, or Router resolves a request to profile execution, route it as `EJECUCION_PERFIL_LF`.

Before Composer, image generation, a tool payload, or a final artifact may use that profile's result:

1. resolve exactly one `PERFIL` and read its real source;
2. preserve the literal user input;
3. execute the profile through a trusted runtime adapter in a real model runtime;
4. capture the model's RAW profile output without summarizing or reconstructing it;
5. independently verify the runtime attestation against the exact request and response;
6. produce `PROFILE_EXECUTION_RECEIPT_V1` binding profile source, input, RAW output, runtime attestation and independent verification evidence;
7. validate the receipt with `sandbox/lf_contract_gate_test/profile_execution_runtime/validate_profile_execution.py`;
8. continue downstream only on `PASS_PROFILE_EXECUTION_PROVENANCE`.

## Zero-cost runtime policy

Operational profile execution is `ZERO_COST_ONLY`.

- Do not invoke any API, hosted model, external service, credit pool, subscription add-on, paid inference endpoint or other runtime that can generate incremental monetary charges.
- OpenAI API live execution is explicitly disabled, even when credentials are present.
- The former OpenAI Responses implementation is retained only as quarantined reference/test code and is not an authorized operational provider.
- `run_openai_profile.py` must fail closed with `PAID_PROVIDER_DISABLED_BY_ZERO_COST_POLICY` and must never issue an OpenAI API request.
- An operational provider must be local or otherwise demonstrably zero incremental monetary cost in the current environment before it can be authorized.
- Absence of a zero-cost runtime means `BLOCK_PIPELINE`; it never authorizes a fallback to a paid provider, fixture, expected output, manually reconstructed response or direct downstream generator.

Operational profile execution must reject test adapters/verifiers. A static fixture, expected output, manually reconstructed response or summarized decision is not evidence that the profile executed. If a trusted zero-cost real model runtime or independent attestation verifier is unavailable, fail closed; do not fabricate `profile_output` and do not bypass directly to a generator.

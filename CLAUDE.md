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

When creating a patch that modifies an existing repository profile under `profiles/**`, route the operation as `ACTUALIZACION_PERFIL_LF` and apply the pass protocol before the first GitHub write and through post-merge closure:

@docs/operations/LF_PROFILE_UPDATE_PASS_PROTOCOL_v0.1.md

Supabase remains the canonical authority for the operation contract, execution binding, judge and state. The GitHub protocol is the reproducible pass procedure and does not supersede Supabase.

At minimum:

1. query EKB first;
2. resolve exactly one profile and the canonical `ACTUALIZACION_PERFIL_LF` operation;
3. create and pass the canonical pre-write execution binding before any repository write;
4. branch from the current exact `main` SHA;
5. write only authorized paths and read them back from the remote branch;
6. require deterministic, semantic, adversarial/holdout and Router/direct evidence as applicable;
7. require all required workflows to be `SUCCESS` on the exact candidate HEAD;
8. immediately before merge, re-read `main`; if it advanced during CI, refresh the pre-write binding before the next write, integrate the new `main` without force-push, update exact-head/readback and rerun the full required CI;
9. never create retroactive receipts or auxiliary PRs merely to compare branches;
10. after merge, read back from the new `main`, close the canonical execution with evidence and enrich EKB.

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

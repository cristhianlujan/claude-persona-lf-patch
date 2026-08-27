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

The repository operational provider implementation is `OpenAIResponsesAdapter` plus `OpenAIResponsesReadbackVerifier` in `sandbox/lf_contract_gate_test/profile_execution_runtime/openai_responses_runtime.py`. It uses the OpenAI Responses API, provider-side stored response metadata and independent response-id readback. Credentials must come from server-side environment variables; never commit API keys.

Operational profile execution must reject test adapters/verifiers. A static fixture, expected output, manually reconstructed response or summarized decision is not evidence that the profile executed. If a trusted real model runtime, credential or independent attestation verifier is unavailable, fail closed; do not fabricate `profile_output` and do not bypass directly to a generator.

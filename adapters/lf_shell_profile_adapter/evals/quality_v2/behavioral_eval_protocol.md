# Shell Adapter Behavioral Evaluation Protocol

Live behavioral evidence is valid only when the canonical LF execution path resolves the Shell adapter from governed bindings and emits a receipt containing exactly one matching `lf_adapter_invocations` entry.

Required canaries:

1. bound UI profile + LF screen delta -> adapter applied exactly once;
2. bound Gamification profile + LF screen delta -> adapter applied exactly once;
3. bound Frontend profile + `SHELL_LOCKED` target -> return to orchestrator with adapter evidence;
4. unbound/non-UI profile -> zero Shell adapter capsule payload and no invocation entry;
5. standalone request naming the adapter -> return to orchestrator, not independent worker execution;
6. conflicting canonical Shell sources -> blocked with source-conflict evidence;
7. same governed request repeated -> materially equivalent shell binding, ignoring invocation/runtime metadata.

For each canary retain exact profile source hash, adapter source hash, capsule hash, input, raw output, validator result, semantic judge result and canonical execution receipt.

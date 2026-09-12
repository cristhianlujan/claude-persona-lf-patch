# Structured output runtime contract

Optional convention for `EJECUCION_PERFIL_LF`.

If `profiles/<profile_slug>/schemas/runtime_output.schema.json` exists in the checked-out exact repository revision, the existing llama.cpp call MUST apply that file with `--json-schema-file` / `-jf` in the same model invocation.

Constraints:
- profile and adapter source authority are unchanged;
- no second LLM call;
- no schema content is injected into the prompt;
- schema resolves strictly under `profiles/<profile_slug>/schemas/`;
- missing schema means zero structured-output context and no schema flag;
- invalid or path-escaping schema blocks before inference;
- attestation records schema ref + SHA only when applied;
- this mechanism does not enable runtime, adapters, production, VALIDATED, or automatic promotion.

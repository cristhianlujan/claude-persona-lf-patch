# Main Contract

Given an operational claim and its declared sources, produce an evidence-lineage verdict.

Required:
- governing authority resolved and read in the same evaluation;
- applicable EKB prevention loaded before evaluation;
- direct provider readback through an independently trusted resolver;
- SHA-256 recomputed from resolved bytes/data rather than copied from the candidate payload;
- exact revision/currentness derived from the resolved source;
- provenance receipt independently resolved when required, with receipt identity and subject binding verified from the receipt itself;
- every semantic `authority_ref` bound to a material authority source that was actually resolved;
- required artifact independently resolved when artifact evidence is applicable;
- structural identifiers reconciled before adoption;
- conflicts surfaced and blocked.

Candidate-declared `read=true`, `current=true`, `artifact_verified=true`, `receipt_valid=true`, `sha_match=true`, or matching declared hashes are assertions only; none can substitute for independent resolution.

The default deterministic GitHub resolver is `validators/trusted_ref_resolver.py` and accepts only immutable same-repository refs `github://owner/repo@<40-hex-commit>/<path>`. Other providers require a separately authorized independent resolver and remain fail-closed until resolved.

## Routing semantics
This existing profile has two governed activation routes:
- execution: `ACT-0001 -> EJECUCION_PERFIL_LF -> PERFIL-EVIDENCE-LINEAGE-REVIEWER-LF`;
- maintenance: `ACT-0001 -> ACTUALIZACION_PERFIL_LF -> PERFIL-EVIDENCE-LINEAGE-REVIEWER-LF`.

Direct and Router activation with materially equivalent evidence/context must produce the same status and normalized redirect. The only allowed difference is `routing.activation_path`.

Evidence Lineage never names or calls an arbitrary downstream `target_profile`; every transition returns through the Orchestrator:
- `PASS_EVIDENCE_LINEAGE` -> `CONTINUE / QUALITY_PACK`;
- `PASS_WITH_RESTRICTIONS` -> `CONTINUE_WITH_RESTRICTIONS / QUALITY_PACK`;
- `RETURN_TO_SOURCE_FOR_READBACK` -> `RETURN_TO_ORCHESTRATOR / SOURCE_READBACK`;
- `BLOCK_PIPELINE` -> `BLOCK_PIPELINE / NONE`.

`validators/validate_routing.py` enforces this mapping. Wrong target, orchestrator bypass, invalid activation path, or a direct `target_profile` is invalid even if evidence lineage would otherwise pass.

Forbidden:
- inference substituting for missing readback;
- accepting a handoff or candidate boolean as authority/readback proof;
- accepting a syntactically valid or internally matching hash without recomputing it from resolved data;
- accepting semantic `authority_ref` outside the resolved material authority universe;
- accepting receipt identity/subject solely from candidate fields;
- translating structural identifiers;
- direct profile-to-profile redirection that bypasses the Orchestrator;
- changing repository/database/runtime state.

# Runtime Payload Budget

Ordinary execution loads only `runtime_capsule.md` plus resolved binding data required for the specific task. Authoring docs, examples, judges and full schemas are validation assets, not normal prompt payload.

Default capsule limit: 2,000 UTF-8 characters.

Unbound execution budget: 0 adapter characters.

Adapter application must not create a second model invocation.

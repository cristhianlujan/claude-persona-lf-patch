# Profile Runtime Task Binding Adapter V1

Source-only compatibility adapter for exact task-bound Profile Runtime material.

## Purpose

The shared Profile Runtime historically resolves standalone packages below `profiles/<profile_slug>/`. Some governed consumers keep Profiles inside another canonical package, such as a Skill. Duplicating those Profiles under `profiles/` would create a second source-of-truth.

`TaskRuntimeBindingAdapter` accepts an already-resolved `LF_PROFILE_TASK_RUNTIME_BINDING_V1`, verifies it against local repository bytes, and materializes the exact sources/schema/validator/judge needed by a future runtime integration.

## Authority boundary

The adapter does **not** resolve:

- Profile identity;
- Router eligibility;
- currentness;
- worker role selection;
- schema/validator/judge applicability.

Those decisions belong upstream. The adapter only verifies the binding digest, root/path scope and exact SHA-256 of every declared source.

## Embedded sources

`EMBEDDED_SKILL_PROFILE` is accepted without creating `profiles/<slug>/`. All declared sources must remain under the bound `source_root`; path escape, byte drift and duplicate refs fail closed.

## Output

The adapter returns:

- model-visible Profile sources selected by `model_context.source_refs`;
- an exact `SchemaBinding` using `TASK_BOUND_EXACT_REF`;
- deterministic validator descriptor;
- independent judge descriptor;
- source revision and binding digest.

`PYTHON_CALLABLE` validators can be loaded only from the already SHA-bound path. `CLI` validators are preserved as descriptors but are not executed by this adapter.

## Boundary

This solution is not wired into `ProfileRuntimeEngine`. It does not change existing standalone Profile behavior, does not call network/DB, does not execute models, does not enqueue work, and does not activate runtime or production. Runtime integration remains a separate solution/PR.

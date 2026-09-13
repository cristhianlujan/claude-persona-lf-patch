# LF Capability Standard v1

Status: candidate source for transversal governance. Scope: sandbox/control-plane only. No runtime, production, scheduler, Golden, or main-branch authorization is implied.

## Goal

LF capabilities are internal products with one stable identity, immutable released versions, exactly one CURRENT pointer, executable consumption metadata, compatibility/migration rules, dependency declarations, currentness checks, and rollback instructions.

The consumer must never rely on a chat, Strategy number, historical branch name, or human memory to know how to use a capability.

## Required model

A capability is split into four concerns:

1. `lf_capability_registry`: stable identity and ownership.
2. `lf_capability_version_registry`: immutable version + executable manifest + SHA-256.
3. `lf_capability_current`: the single mutable CURRENT pointer.
4. `lf_capability_binding`: execution-scoped binding to an exact version/fingerprint.

Released version rows are immutable. Promotion changes only the CURRENT pointer. Historical versions remain queryable.

## Versioning

Use strict `MAJOR.MINOR.PATCH`.

- PATCH: compatible correction.
- MINOR: compatible capability extension.
- MAJOR: incompatible contract/behavior change; migration gate required.

A consumer records both `bound_version` and `bound_manifest_sha256`. Before material work it compares that fingerprint with CURRENT.

## Mandatory manifest blocks

Every version must declare:

- `schema_version`
- `capability_code`
- `version`
- `contract`
- `delivery`
- `installation`
- `dependencies`
- `compatibility`
- `migration`
- `rollback`
- `usage`
- `currentness`

If local packages are required, `dependencies.packages` must declare their package manager, required version/range, and reinstall/update policy. A consumer must not install or upgrade packages silently in the middle of material execution.

For centrally delivered capabilities, `installation.required=false` and `reinstall_required=false`; consumers bind to CURRENT instead of reinstalling local code.

## Consumption protocol

Before material work:

1. Resolve CURRENT.
2. Read manifest/manual/dependencies.
3. Run capability preflight.
4. If unbound and no material steps/active lease: bind CURRENT.
5. If stale and no material steps/active lease: rebind CURRENT.
6. If work already started: pin the bound version or require migration/restart; never silently switch behavior mid-execution.
7. Immediately before the write, compare the CURRENT manifest SHA again.
8. Execute only if the binding and authority checks are still current.

Expected decisions:

- `BIND_CURRENT_SAFE`
- `READY_CURRENT`
- `REBIND_CURRENT_SAFE`
- `PIN_BOUND_VERSION`
- `MIGRATION_REQUIRED`
- fail-closed `BLOCK_*`

## Destination Resolution LF v2

`DESTINATION_RESOLUTION_LF` is the first capability using this standard.

It separates the single transversal resolver from execution-specific destinations:

- `ACTIVE`: eligible for legacy/default lookup.
- `BINDING_ONLY`: never selected implicitly; usable only when the execution requests its exact `destination_code`.

This keeps one transversal resolver while allowing isolated branches/carriles for S35, canaries, or other executions.

Resolution rules:

- explicit `destination_code`: exact match only; status must be `ACTIVE` or `BINDING_ONLY`; operation/artifact/repo/path must match.
- no explicit code: exactly one matching `ACTIVE` destination is required.
- zero matches: block.
- more than one default match: block; never choose by accident or priority.

## Legacy executions

An execution created before the capability registry is not mutated automatically.

- zero recorded steps and no active lease: safe to bind CURRENT on its next preflight.
- any recorded work: no automatic major-version rebind; migration/restart gate applies.
- closed executions retain historical evidence and are never rewritten.

This is the intended behavior for open legacy Strategy Create executions such as S35: they can discover v2 on their next preflight without another chat editing their execution record.

## Rollout

1. Create immutable candidate version.
2. Validate contract, compatibility, negative cases, dependency instructions, and rollback.
3. Canary using an explicitly bound execution/destination.
4. Promote the single CURRENT pointer atomically.
5. New/zero-step executions bind CURRENT.
6. In-flight material executions remain pinned or go through migration/restart.
7. Keep previous versions as evidence.

## Rollback

Rollback is a CURRENT-pointer action, not an overwrite of a released version. A rollback must use expected-current fingerprint/currentness guards. It does not rewrite historical bindings or execution evidence.

## Security and safety

- fail closed on missing CURRENT, missing version, stale fingerprint, ambiguous default destination, repo/path mismatch, or incompatible migration.
- use expected SHA/currentness before mutation.
- no auto-install, auto-upgrade, auto-rebase, force-push, production promotion, runtime enablement, or scheduler enablement.
- capability functions that mutate bindings/current pointers are service-role/governance operations; read/preflight functions may be exposed read-only according to RLS.

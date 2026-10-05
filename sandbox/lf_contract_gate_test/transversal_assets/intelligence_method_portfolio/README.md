# Intelligence Method Portfolio V1

Purpose: provide the governed, exact-version catalog that dynamic intelligence consumers give to `CAPABILITY_SELECTOR`. This surface is a registry/read model only; it does not implement a second selector and does not authorize execution.

## Eligibility

A method may be current only when its exact version is `RELEASED` and `QUALIFIED`, with source, validator, output contract, qualification and benchmark evidence plus holdout evidence or an explicit holdout N/A reason. Historical, superseded, retired or unqualified versions remain benchmark/history only and cannot be bound as active candidates.

## Champion / challenger

Champion scope is per decision family, never global. A champion can be one method (`SINGLE`) or a qualified mix. Challengers may be active candidates for shadow/holdout comparison but cannot replace a champion without fresh qualification evidence.

Allowed mix modes are `SINGLE`, `UNION_COMPLEMENTARY`, `CONSENSUS_REQUIRED`, `AUTHORITY_PRIORITY`, `HARD_INVARIANT_VETO` and `BOUNDED_ALTERNATIVES`. `priority_order` is ordering only, never an implicit numerical weight. Arbitrary numeric weights are outside V1; any future weighted mix requires a separate empirically calibrated contract and evidence reference.

## Shared evidence and provenance

Methods should consume the same targeted evidence base where possible. The portfolio returns exact method/version, evidence refs, output contract, qualification/benchmark digests and mix metadata so downstream normalized results can preserve per-method provenance and contradictions.

## Qualification protocol

`method_qualification_protocol_v1.json` defines the mandatory path from exact identity/currentness through contract validation, adversarial validation, family benchmark, holdout and promotion. A current/released capability is not automatically a method Champion: family-specific qualification still applies.

## Candidate inventory

`method_candidate_inventory_v2.json` is the complete inventory for the 19 intelligence-selection units declared by `lf_eventos://20346`. It supersedes the incomplete 13-family draft. It records plan methods plus existing live providers without promoting concepts, historical prior art or current capabilities that lack family-specific qualification.

## Fallback

Preferred policy: `SPECIALIST_IF_CLEAR -> JUSTIFIED_MIX -> TARGETED_EVIDENCE -> QUALIFIED_ROBUST_DEFAULT -> BLOCK`. No-signal or contradictory cases must not silently admit an unqualified or stale method.

## Transport

No ZIP and no full-repository payload. Consumers retrieve the typed catalog by decision family and pass that bounded catalog to `CAPABILITY_SELECTOR`.

## Runtime boundary

This V1 only materializes registry/readback primitives. It does not activate runtime, production, model calls, method execution, or any capability current pointer.

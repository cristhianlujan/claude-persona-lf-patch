# Intelligence Method Portfolio V1

Purpose: provide the governed, exact-version catalog that dynamic intelligence consumers give to `CAPABILITY_SELECTOR`. This surface is a registry/read model only; it does not implement a second selector and does not authorize execution.

## Critical boundary

A **selection method** is the reasoning/decision procedure used to choose, compose or escalate domain options from typed evidence. A **decision option** is the strategy, test technique, partition mode, judge type or deployment mode being chosen. Champion/Challenger status applies to selection methods or qualified selection-method mixes, not automatically to the domain options themselves.

## Eligibility

A method may be current only when its exact version is `RELEASED` and `QUALIFIED`, with source, validator, output contract, qualification and benchmark evidence plus holdout evidence or an explicit holdout N/A reason. Historical, superseded, retired or unqualified versions remain benchmark/history only and cannot be bound as active candidates.

## Champion / challenger

Champion scope is per decision family, never global. A champion can be one method (`SINGLE`) or a qualified mix. Challengers may be active candidates for shadow/holdout comparison but cannot replace a champion without fresh qualification evidence.

Allowed mix modes are `SINGLE`, `UNION_COMPLEMENTARY`, `CONSENSUS_REQUIRED`, `AUTHORITY_PRIORITY`, `HARD_INVARIANT_VETO` and `BOUNDED_ALTERNATIVES`. `priority_order` is ordering only, never an implicit numerical weight. Arbitrary numeric weights are outside V1; any future weighted mix requires a separate empirically calibrated contract and evidence reference.

## Proven prior art

`selection_method_prior_art_v1.json` anchors IG00..IG06 from the governed 12x7 IGQ benchmark. The prior art demonstrated complementary evidence-graph, business/future inference, traceability and safe-admission behaviors, plus two useful mixes. It is benchmark prior art only: the historical benchmark had a method-identity mismatch that required corrective re-freeze, so exact current source/version/currentness must be re-proven before portfolio eligibility.

## Candidate inventory

`method_candidate_inventory_v3.json` covers all 19 intelligence-selection units declared by `lf_eventos://20346` and explicitly separates selection-method candidates from domain decision options. It supersedes the earlier draft that conflated options such as TDD, vertical partitioning or property-based testing with the methods used to select them.

## Wave 2 qualification

`wave2_selection_method_qualification_batch_v2.json` covers A6, A7, A9, PG-02, PG-03, PG-04, TST-07, TST-08, TST-09 and TST-10. It reuses proven prior art where applicable, adds only explicit challengers where a reusable method is missing, and requires family benchmark plus sealed holdout before any Champion binding.

## Shared evidence and provenance

Methods should consume the same targeted evidence base where possible. The portfolio returns exact method/version, evidence refs, output contract, qualification/benchmark digests and mix metadata so downstream normalized results can preserve per-method provenance and contradictions.

## Fallback

Preferred policy: `SPECIALIST_IF_CLEAR -> JUSTIFIED_MIX -> TARGETED_EVIDENCE -> QUALIFIED_ROBUST_DEFAULT -> BLOCK`. No-signal or contradictory cases must not silently admit an unqualified or stale method.

## Transport

No ZIP and no full-repository payload. Consumers retrieve the typed catalog by decision family and pass that bounded catalog to `CAPABILITY_SELECTOR`.

## Runtime boundary

This V1 only materializes registry/readback primitives and qualification source. It does not activate runtime, production, model calls, method execution, or any capability current pointer.

# TARGETED_EVIDENCE_ACQUISITION

Transversal LF capability that selects the smallest next evidence acquisition that can still change a pending decision, and stops when additional search can no longer change that decision.

## Boundary

- Owner: `SUPER_ADMIN`.
- Capability: `TARGETED_EVIDENCE_ACQUISITION`.
- IG is a consumer, never the owner.
- Reuses `TYPED_EVIDENCE_REGISTRY`; it does not create another evidence store or resolver engine.
- It does **not** fetch evidence, repair a target, approve a change, execute a proposal, or escalate a human by itself.

## Generic contract

Input is domain-agnostic:

- `consumer_ref`: opaque trace label.
- `unresolved_reasons[]`: exact reasons that can still affect the current decision.
- `current_evidence[]`: optional typed evidence already available; every supplied item is validated through `TYPED_EVIDENCE_REGISTRY`.
- `candidates[]`: candidate acquisitions with `candidate_ref`, `covers_reasons[]`, `source_ref`, `acquisition_cost_rank`, `available`, and `material`.

Output:

- `state`: `CONTINUE` or `STOP`.
- `next_evidence`: one deterministic minimal candidate when continuing.
- `stop_when`: explicit terminal condition.
- `remaining_reasons`: unresolved decision reasons.
- `code`: deterministic explanation.

## Selection rule

A candidate is eligible only when it is available, material, has a source reference, and covers at least one unresolved reason. Eligible candidates are ordered by:

1. lowest `acquisition_cost_rank`;
2. greatest number of unresolved reasons covered;
3. lexical `candidate_ref` tie-break.

This makes the next acquisition minimal and deterministic. Confidence is not permission.

## Stop rule

The provider returns `STOP` when:

- no unresolved reason remains; or
- no eligible candidate can cover any unresolved reason.

`STOP_NO_DECISION_CHANGING_EVIDENCE` means automation options for evidence acquisition are exhausted. The consumer may then use its existing admission/judge/human-boundary policy. The capability itself does not reinterpret `STOP` as approval or as a mandatory human decision.

## Anti-oversearch invariant

Once `STOP` is reached for the same unresolved-reason set and candidate set, the provider must not suggest additional search. Adding irrelevant candidates must not change `STOP`; adding a newly material eligible candidate may reopen the decision to `CONTINUE`.

## IG binding semantics

For Input Governance the intended sequence is:

`MISSING/PARTIAL -> candidate methods/sources -> TARGETED_EVIDENCE_ACQUISITION -> acquire selected evidence -> judge/admission -> AUTOMATIZABLE when proven; otherwise repeat only while evidence can change the decision -> human boundary only after STOP/exhaustion or an explicit material decision requirement.`

This prevents `RECOMENDADA` from being treated as an immediate human escalation while useful automated evidence acquisition remains.

## Non-IG proof

The same provider must work with opaque non-IG reasons and candidates without any provider code branch for screen, family, Curator, Validator, Story, or method names.

## Currentness and authority

The capability is versioned through `lf_capability_registry`, `lf_capability_version_registry`, and `lf_capability_current`. Dependency currentness for `TYPED_EVIDENCE_REGISTRY` is pinned in the manifest and checked on each call. The provider never creates a shadow currentness authority.

## Fail closed

Malformed input, malformed typed evidence, missing dependency currentness, duplicate candidate identities, invalid ranks, or malformed candidate shapes return `STOP` with a fail-closed code and no acquisition recommendation.

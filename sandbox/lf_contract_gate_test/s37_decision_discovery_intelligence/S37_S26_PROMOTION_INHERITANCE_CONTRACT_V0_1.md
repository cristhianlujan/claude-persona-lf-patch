# S37 ↔ S26 Promotion / Inheritance Contract v0.1

Status: CANDIDATE / NON_PRODUCTION / NO_AUTOMATIC_INHERITANCE
Date: 2026-09-13

## Objective

Define the one-way, governed crossing between the closed S26 baseline and S37 Decision & Discovery Intelligence without creating circular dependencies or allowing experimental behavior to contaminate S26.

## Direction A — S26 to S37

S37 may consume only stable, evidence-bound S26 capabilities through explicit version/hash bindings, including Typed Context, provenance, Profile Runtime evidence and deterministic governance contracts.

S37 must not fork, copy or silently redefine S26 authority. If an S26 dependency is absent, stale, incompatible or cannot be resolved to governed evidence, S37 fails closed or declares the dependency unresolved.

## Direction B — S37 back to the LF platform

No S37 artifact in EXPERIMENTAL or CANDIDATE state may flow back into S26 or another Golden runtime automatically.

A discovery produced by S37 becomes eligible for reuse only when all of the following are true:

1. the behavior is independently validated against a frozen baseline/holdout;
2. domain fidelity and unsupported-claim gates pass;
3. the capability is demonstrably generic/reusable rather than S37-specific prompt logic;
4. it is materialized as a governed capability with explicit contract, version, evidence, negative tests and rollback boundary;
5. the reusable-capability lifecycle/currentness rules are satisfied;
6. adoption by any consumer is an explicit versioned decision, never implicit inheritance.

## Promotion states

```text
S37 EXPERIMENTAL
      |
      v
S37 CANDIDATE
      |
      v
VALIDATED DISCOVERY
      |
      +---- S37-specific ------------------> stays in S37
      |
      +---- reusable/generalizable --------> governed reusable capability
                                                |
                                                v
                                            GOLDEN-eligible
                                                |
                                                v
                                    explicit consumer adoption
```

`VALIDATED` does not mean `GOLDEN`. `GOLDEN-eligible` does not authorize runtime or production. Each promotion remains separately governed.

## S26 closure rule

S37 does not block, reopen or extend S26 merely because S37 exists or later discovers a better approach.

S26 is evaluated against its own frozen objectives, contracts and evidence. A future S37 finding may create a new capability candidate or a separately governed S26 successor/update request, but it cannot retroactively convert a properly closed S26 item into an unresolved gap.

Conversely, any S26 defect discovered through S37 that violates an already-promised S26 invariant must be recorded as a new governed defect/regression and handled through the appropriate owner; it must not be hidden as “innovation”.

## No circular dependency

Forbidden:

```text
S26 runtime -> S37 experimental behavior -> S26 authority
```

Allowed:

```text
S26 stable capability -> S37 experiment
S37 validated reusable discovery -> governed capability lifecycle -> explicit future consumer adoption
```

## Traceability requirements

Every crossing must preserve:

- producer strategy/capability identity;
- exact version and source/evidence hashes;
- validation state at time of adoption;
- consumer identity;
- explicit adoption decision;
- rollback/supersession semantics;
- no automatic production or Golden promotion.

## Current disposition

- S26 remains the stable governed profile/runtime baseline and is closed only on its own evidence.
- S37 remains CANDIDATE / NON_PRODUCTION and may consume S26 evidence-bound capabilities.
- S37 currently has no authority to mutate S26, Golden, production, pricing or creditor decisions.
- Future inheritance is opt-in, versioned and evidence-gated.

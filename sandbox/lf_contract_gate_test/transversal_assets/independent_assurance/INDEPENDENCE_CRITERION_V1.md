# INDEPENDENT_ASSURANCE — Independence Criterion V1

Owner: `SUPER_ADMIN`  
Executor of this extension: `T-INDEP / PAULO-035`

## Purpose

A different execution id is necessary but not sufficient for independent review. `CLOSURE_REQUIRED` review must prove separation of execution, evidence path and material oracle dependencies.

## Criterion

An independent review is clean only when all of the following hold:

1. **Execution separation** — reviewer execution id differs from producer execution id.
2. **Evidence separation** — the reviewer consumes the producer result only through an immutable exact-subject binding; mutable producer context is not authoritative input.
3. **Oracle dependency separation** — the transitive material dependency set of the reviewer has zero overlap with the producer's transitive material dependency set, except infrastructure dependencies explicitly adjudicated as non-semantic transport/authority.
4. **Exception discipline** — every shared dependency exception is explicit, named, evidence-bound and adjudicated. An absent list means zero exceptions, not implicit tolerance.
5. **Readback** — the independence result and the exact dependency-set digests are durable and can be re-read before closure.

## Allowed infrastructure exception class

Infrastructure may be shared only when it does not produce the semantic verdict being independently checked. Examples that may be adjudicated, never auto-whitelisted:

- Router / dispatch transport;
- Evidence Ledger transport and exact binding;
- currentness/readback authority used symmetrically only to bind identity.

The fact that a dependency is transversal does not by itself make it an allowed exception.

## Result

```text
PASS
  if execution_distinct
  and evidence_path_bound
  and shared_material_dependencies = 0 after adjudicated exceptions
  and dependency digests/readback are durable

BLOCKED
  if either dependency set cannot be measured or currentness is missing

FAIL
  if a non-adjudicated material dependency is shared
```

## Consumer rule

`PREFLIGHT_ONLY` may report whether this criterion can be evaluated but cannot satisfy it.

`CLOSURE_REQUIRED` must carry the resulting independence receipt. A reviewer receipt without this criterion is not closure-satisfying once the T-INDEP extension is activated.

## Compatibility

The existing Strategy specialization remains unchanged until equivalent replay proves that the generic replacement preserves its current fail-closed behavior. No bulk cutover and no parallel active reviewer engine are authorized by this document.

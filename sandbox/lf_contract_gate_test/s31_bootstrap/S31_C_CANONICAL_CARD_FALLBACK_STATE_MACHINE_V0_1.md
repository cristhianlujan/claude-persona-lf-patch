# S31-C — Canonical Cards / Fallback State Machine v0.1

Status: CANDIDATE DESIGN / READ-ONLY OWNER SOURCES
Work Package: `WP-S31-C-001`
Base main: `ee7aca94c672fcc555db90962f09fe439eedf4f0`

## Problem

LF currently expresses Card/fallback semantics through overlapping vocabularies:

1. S26 governance gate: `EXACT | COMPATIBLE | NONE | AMBIGUOUS`.
2. S26 source-first operating policy: `EXACT -> COMPOSED -> GENERIC_SAFE`.
3. Runtime resolver: resolved/fallback behavior including `NO_CARD_GOVERNED`.
4. Fallback alternatives: `CONTRACT_SCHEMA | GENERIC_CAPABILITY | SAFE_COMPOSITION`.

These are not necessarily logically incompatible, but today they mix **resolution state**, **resolution strategy**, **fallback path**, and **runtime encoding**.

## Canonical separation

S31 proposes four separate axes instead of one overloaded enum.

### 1. Resolution status

- `RESOLVED`
- `NO_DIRECT_CARD`
- `AMBIGUOUS`
- `BLOCKED`

### 2. Resolution mode

When `RESOLVED`:
- `EXACT`
- `COMPATIBLE`
- `COMPOSED`
- `GENERIC_SAFE`

### 3. Governed fallback path

When `NO_DIRECT_CARD`:
1. `CONTRACT_SCHEMA`
2. `GENERIC_CAPABILITY`
3. `SAFE_COMPOSITION`
4. `MANUAL_REQUIRED` only if all safe alternatives fail with evidence and no blocker exists.

`NO_DIRECT_CARD` is therefore governed, not manual by definition.

### 4. Runtime encoding

Existing runtime values such as `ROUTER_SELECTED` and `NO_CARD_GOVERNED` remain implementation/boundary encodings. They map to the canonical model but are not the canonical semantics themselves.

## Canonical transition rules

```text
candidate discovery
      |
      +-- multiple unresolved meanings ----------> AMBIGUOUS -> FAIL_CLOSED
      |
      +-- exact match ---------------------------> RESOLVED / EXACT
      |
      +-- proven compatible ---------------------> RESOLVED / COMPATIBLE
      |
      +-- safe composition possible -------------> RESOLVED / COMPOSED
      |
      +-- generic governed capability sufficient -> RESOLVED / GENERIC_SAFE
      |
      +-- no direct resolution ------------------> NO_DIRECT_CARD
                                                     |
                                                     v
                                             CONTRACT_SCHEMA
                                                     |
                                             GENERIC_CAPABILITY
                                                     |
                                              SAFE_COMPOSITION
                                                     |
                                      all fail with evidence?
                                         |                 |
                                        no                yes
                                         |                 |
                                  use safe fallback   MANUAL_REQUIRED
```

## Source authority invariant

Cards govern **HOW**. Source authority governs **WHAT**.

No resolution mode may override authoritative source semantics, schema, runtime binding or currentness. If a Card conflicts with source authority, the Card is incompatible for that task.

## Boundary mapping

| Existing vocabulary | Canonical interpretation |
|---|---|
| S26 `EXACT` | `RESOLVED / EXACT` |
| S26 `COMPATIBLE` | `RESOLVED / COMPATIBLE` |
| S26 policy `COMPOSED` | `RESOLVED / COMPOSED` |
| S26 policy `GENERIC_SAFE` | `RESOLVED / GENERIC_SAFE` |
| S26 gate `NONE` | `NO_DIRECT_CARD` |
| S26 gate `AMBIGUOUS` | `AMBIGUOUS -> FAIL_CLOSED` |
| runtime `ROUTER_SELECTED` | implementation encoding of `RESOLVED/*` |
| runtime `NO_CARD_GOVERNED` | implementation encoding of `NO_DIRECT_CARD` with governed fallback semantics |
| fallback `CONTRACT_SCHEMA` | first safe fallback path |
| fallback `GENERIC_CAPABILITY` | second safe fallback path |
| fallback `SAFE_COMPOSITION` | third safe fallback path |
| `MANUAL_REQUIRED` | terminal fallback only after safe alternatives fail with evidence |

## Required evidence

A Card resolution receipt must capture:
- task/surface classification;
- candidates considered;
- selected status + mode;
- source authority binding;
- compatibility evidence when non-exact;
- alternatives attempted when no direct Card exists;
- failure reason/evidence per rejected fallback;
- final execution permission or fail-closed result.

## Negative cases

1. `NONE -> MANUAL_REQUIRED` without attempting safe alternatives: reject.
2. `AMBIGUOUS -> EXECUTE`: reject.
3. Card changes source field/semantic because presentation template differs: reject.
4. `COMPATIBLE` without compatibility evidence: reject.
5. runtime `NO_CARD_GOVERNED` interpreted as uncontrolled free-form execution: reject.

## Migration rule

Do not rewrite S26 runtime or governance contracts in this lane. First stabilize this canonical vocabulary and mappings. Any owner implementation change later requires an explicit S26 handoff and compatibility adapter/tests.

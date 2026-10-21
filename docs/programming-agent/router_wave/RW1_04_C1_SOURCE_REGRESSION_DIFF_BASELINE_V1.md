# RW1-04_C1 — Source freeze, regression baseline and minimal implementation diff

**Plan:** `LF_ROUTER_ARCHITECTURE_WAVE_V1`  
**Unit:** `RW1-04` — Refactor núcleo Router  
**Checkpoint:** `RW1-04_C1`  
**Nature:** verified-current-source baseline. No runtime activation, no ACL change, no operation mutation, no production effect.

## 1. Frozen current source

Main snapshot: `6d26bdf36ebf1ae1f718157654941be466bc2b41`.

Current DB function identities:

- `public.lf_router_resolve_v1(text,text,text,text,text)` md5: `d45f5bddb693791b6459bbe3acfd4ed3`
- `public.lf_router_intent_handoff_v1(text,jsonb,text)` md5: `540bc1b60caf2e3f9d81461f99c509ef`
- `programacion.fn_lf_router_input_governance_resolve_v1(text,jsonb,text)` md5: `72e153a7fbfe7b10a8c9ae694a61b334`

Active route registry: 35 routes = 26 write + 9 non-write.

Ledger-current Router source migrations:

| Version | Name | Git blob |
|---|---|---|
| 20261017034602 | lf_router_exact_identity_structured_discovery_v1 | `d97ac62da84b728706ceed34598853bb52ad0c4f` |
| 20261017035500 | lf_router_unstructured_mutation_fail_closed_v1 | `2c67ffe2c98c7022a79dd6f687a67e1be789db1f` |
| 20261017040500 | lf_router_explicit_target_semantic_admission_v1 | `23acf59f2afcee2cf81d10e05c6d31ec4c23ebf2` |

The exact current Router source contains five semantic-gap emission sites using `lf_router_intent_handoff_v1`:
- `BLOCK_MULTIPLE_EXACT_TARGETS_NEED_SCOPE`
- `BLOCK_EXPLICIT_TARGET_INTENT_ATTESTATION_REQUIRED`
- `BLOCK_EXECUTOR_CAPABILITY_UNATTESTED`
- `BLOCK_SCOPE_SEMANTICS_UNATTESTED`
- `BLOCK_UNSTRUCTURED_MUTATION_INTENT_UNATTESTED`

## 2. Approved architecture to reproduce

Authoritative contract:
- `RW1_03_C2_SEMANTIC_ABI_TRANSITION_V1.json`
- blob `bfd571d5e7c7d1d80c5ed39414a822b4096c20d6`

Review capture:
- `RW1_03_C3_REVIEW_CAPTURE_V1.json`
- blob `4e9648a5ff8202aa1094001bc398b41fb3b67637`
- C3 assertion receipt: `f4edb9722cfd1ff7e278897934c63b50343a50515d256ab160bc14b950b96216`

Non-negotiable authority boundary:
- ACT-0001 keeps discovery, derivation, currentness, operation selection and effect-authority binding.
- Semantic specialist only normalizes intent, exclusions, conditions and material ambiguity.
- Specialist cannot discover workers, select route/operation/executor, widen scope, mint target authority or authorize effects.
- Merge Train remains independent bootstrap authority.
- No second Router.
- No ACL widening.

## 3. Regression suite frozen for C2

C2 must keep these existing regressions green without rewriting them merely to fit the new implementation:

| Regression source | Git blob | Protected behavior |
|---|---|---|
| `test_router_exact_identity_source_v1.py` | `258cd2c56127343d31546bc0ab9c12e7646041a4` | canonical identity, artifact binding, no keyword identity |
| `test_router_unstructured_intent_source_v1.py` | `0ef68a2f54011f93da89946993650eb7a82895b2` | unstructured mutations fail closed |
| `test_router_explicit_target_and_catalog_v1.py` | `5697303692390aef85d387d2134748bd209afe7d` | target hint is not scope/effect authority |
| `router_intent_semantic_contract_v1.py` | `9804e804c2ab9d9f651fa53247a97a03a2ca2509` | advisory semantic consumer boundary |
| `test_router_intent_semantic_contract_v1.py` | `91b3a9639a6d1d57fdc8ad2a708bc085c24e3174` | semantic proposal negatives and no execution authority |

C2 may add V2-specific tests; it must not weaken these assertions.

## 4. Current gap vs approved ABI

Current `LF_ROUTER_INTENT_HANDOFF_V1` already preserves:
- literal request;
- request SHA-256;
- reference kind;
- candidate subjects;
- positive and excluded refs placeholders;
- allowed/forbidden scope placeholders;
- explicit blocked execution state.

It does **not** carry the complete approved request ABI:
- no `conditions`;
- no explicit `source_currentness`;
- no V2 schema identity.

There is also no DB-level versioned semantic resume validator that enforces:
- request hash match;
- source currentness;
- candidate subset only;
- no scope widening;
- exclusions preserved;
- no operation/executor/effect authority from specialist.

## 5. Minimal implementation diff frozen for RW1-04_C2

The architecture must not be enlarged to satisfy tests. The minimum code delta is:

### D1 — Add versioned semantic handoff V2

Add one helper, proposed canonical name:
`public.lf_router_intent_handoff_v2(text,jsonb,text,jsonb,jsonb)`

It must emit the approved request envelope and remain read-only:
- schema `LF_ROUTER_SEMANTIC_REQUEST_V1`;
- router = `ACT-0001`;
- literal + SHA-256;
- reference kind;
- Router-supplied candidates;
- positive/excluded refs;
- allowed/forbidden scope;
- conditions;
- source currentness;
- no operation code;
- no executor;
- no effect authority;
- downstream execution blocked.

V1 remains available for compatibility during transition.

### D2 — Add fail-closed semantic resume validator

Add one read-only validator, proposed canonical name:
`public.lf_router_semantic_resume_validate_v1(jsonb,jsonb)`

It must reject at least:
- request hash mismatch;
- stale/missing currentness;
- target outside candidate set;
- scope widening;
- dropped exclusions;
- returned operation code;
- returned executor;
- returned effect authority / downstream execution flag.

Successful validation does not select a route. It returns only a bounded result allowing ACT-0001 to rederive route and authority from current source.

### D3 — Patch only semantic-gap emission sites

Modify only the five existing semantic-gap returns in `lf_router_resolve_v1` to emit the versioned V2 handoff in addition to compatibility data required during transition.

Do not rewrite:
- discovery;
- canonical identity logic;
- operation registry resolution;
- policy/contract gates;
- downstream authority guards;
- Input Governance;
- DB Train route.

### D4 — Keep activation shadow/disabled

RW1-04_C2 may install V2 functions and wire emission, but:
- no semantic runtime is activated;
- no ACL is widened;
- no consumer gains write/effect authority;
- no legacy path is retired;
- no production or E2E claim is permitted.

## 6. Negative controls for C2

Implementation must fail closed for:
1. missing source;
2. stale source;
3. cross-project/cross-subject candidate;
4. forged target;
5. dropped exclusion;
6. scope widening;
7. specialist-returned operation/executor/effect authority;
8. Train bootstrap through V2;
9. second Router behavior;
10. legacy consumer receiving new effect authority.

## 7. Explicit non-scope

C1 does not:
- implement D1-D4;
- alter database functions;
- alter grants;
- activate semantic runtime;
- change operations;
- change Merge Train;
- rewrite existing tests;
- open RW1-04_C2 by side effect;
- claim runtime, E2E or production PASS.

## 8. Exit criterion for C1

C1 is DONE only when:
- main SHA, DB function hashes and ledger source versions above are current at close time;
- RW1-03 is 3/3 DONE;
- all frozen regression blobs still match;
- approved C2 contract + C3 receipt remain exact;
- minimal diff D1-D4 is persisted;
- C2 and C3 remain PENDING;
- no runtime/ACL/production mutation occurred.

**C1 verdict:** source baseline is sufficiently frozen to let C2 implement the approved architecture without rediscovery or architecture drift.

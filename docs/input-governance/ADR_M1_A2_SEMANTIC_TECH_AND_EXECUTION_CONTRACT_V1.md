# ADR M1.A2 — Semantic technology + execution contract

- Plan: `IG_CURATOR_VALIDATOR_REFACTOR_V2`
- Unit: `M1.A2 / PAULO-037`
- Decision: `DEC-INPUT-GOV-SEMANTIC-TECH-001`
- Status: `VIGENTE`
- Human owner: `SUPER_ADMIN`
- Scope: architecture + execution contract only; no M2.6, M2.8 or M3.7 implementation.

## Context

`INPUT_GOVERNANCE_EXECUTION_CONTRACT` revision `1.5` already points to the active Agent/Curator/Validator Edge runtimes, but it also declares `runtime_binding_status=UNBOUND_SEMANTIC_RUNTIME` and `semantic_curator_runtime=EXTERNAL_SEMANTIC_RUNTIME_REQUIRED_FOR_NEW_OR_CHANGED_SCOPE`. Live runtime contradicts that wording: `input-governance-agent-v1`, `input-governance-curator-v1` and `input-governance-validator-v1` are deployed, and the Curator delegates to governed SQL/RPC rather than embedding an LLM provider.

The architecture must therefore separate deterministic resolution from semantic resolution, preserve the existing Agent/Curator/Validator boundary, reuse transversal capabilities, and prevent model output from becoming authority.

## Decision

### 1. Deterministic-first invariant

For every requested resolution, IG MUST first resolve everything derivable from current governed authority using deterministic code, contracts, registries, exact rules, resolvers, hashes, typed evidence and currentness checks.

A model/capability MUST NOT be invoked for a field whose required value is derivable deterministically from authoritative inputs.

### 2. Semantic-gap criterion

Semantic execution is allowed only when all of the following are true:

1. authoritative inputs and applicable versions were resolved;
2. deterministic resolution was attempted and recorded;
3. at least one required output remains non-derivable by deterministic rules;
4. the unresolved item is explicitly classified as a semantic gap;
5. policy permits a semantic capability for that gap;
6. evidence/currentness requirements are satisfied.

If any condition is not met, the path is deterministic or fail-closed; it is not a model call.

### 3. Input contract

The semantic-resolution request MUST bind at least:

- `subject` + version/identity;
- requested obligation/output fields;
- resolved authority references and digests;
- decision context / as-of reference when applicable;
- typed signals/evidence;
- deterministic result set;
- unresolved semantic gaps only;
- consumer policy reference/version;
- required capability class;
- currentness/compatibility state;
- execution id and trace id.

Raw mutable `latest` context without version/as-of binding is not valid input for a material decision.

### 4. Output contract

A semantic execution MAY return:

- proposed/resolved values for the declared gaps;
- per-gap reasoning/evidence references;
- uncertainty state;
- contradictions;
- selected capability/profile/model/provider attestation;
- execution receipt and digests;
- fallback/block reason.

It MUST NOT return or claim canonical authority merely because a model produced the value. Model output is evidence/proposal until validated against the governing contract and admitted by the appropriate authority path.

### 5. Selection policy

Selection is policy-driven and dynamic:

1. typed signals + catalog + consumer policy are passed to `CAPABILITY_SELECTOR`;
2. returned capability codes do not grant execution permission;
3. `CAPABILITY_VERSION_COMPATIBILITY` resolves compatible governed versions;
4. the execution policy resolves an eligible execution profile / adapter / provider / model for the selected capability;
5. no provider or model identifier is hardcoded in IG business logic;
6. runtime attestation MUST prove that the actual profile/adapter/provider/model satisfies the selected policy.

`CLEAR`, `MULTI`, `NO_SIGNAL`, `CONTRADICTORY` and `CAPABILITY_FAILURE` remain selection/fallback states; they are not semantic truth states.

### 6. Uncertainty, contradiction and insufficient evidence

- `UNCERTAIN`: no canonical write/admission from the unresolved semantic result.
- `CONTRADICTORY`: fail closed for the affected obligation until contradiction is reconciled.
- `INSUFFICIENT_EVIDENCE`: request governed evidence refresh only for the missing material input; do not broaden to full rediscovery.
- deterministic contradiction with a model result: deterministic governed authority wins unless the deterministic authority itself is proven stale/invalid.

### 7. Reproducibility invariants

Every material result MUST bind:

- exact contract revision;
- authority/version/as-of refs;
- deterministic inputs and outputs;
- semantic-gap list;
- selector policy/version;
- selected capability/version;
- execution profile/adapter/provider/model attestation when a model path is used;
- raw semantic output digest;
- validator/assurance evidence;
- final admitted value source.

Replaying the same deterministic inputs and contract MUST reproduce the deterministic portion exactly. Non-deterministic execution is isolated to the declared gap and cannot alter already-resolved deterministic fields.

### 8. Versioning

Semantic decisions are versioned by contract revision plus referenced authority/capability/policy versions. Historical decisions MUST be reconstructible using `DECISION_CONTEXT_ASOF`; newer mutable policy or registry state must not reinterpret old evidence.

### 9. Observability and evidence

Reuse:

- `TYPED_EVIDENCE_REGISTRY` for evidence typing/validation;
- `CURRENTNESS_AUTHORITY` for currentness;
- `DECISION_CONTEXT_ASOF` for historical context;
- `CAPABILITY_SELECTOR` for capability selection;
- `CAPABILITY_VERSION_COMPATIBILITY` for compatible version resolution;
- `INDEPENDENT_ASSURANCE` where independent verification is required.

Observability MUST expose deterministic coverage, unresolved semantic gaps, selection reasons/fallback, runtime attestation, raw-output digest, validation result and block/fallback reason.

### 10. Fallback

Fallback order is:

1. deterministic governed resolution;
2. policy-selected semantic capability only for non-derivable gaps;
3. consumer-configured governed fallback capability/profile if eligible;
4. fail closed.

There is no fallback to an unregistered provider/model, fixture, direct generator, or implicit human authority.

### 11. Authority boundary

IG is a consumer/orchestrator of transversal authorities and capabilities. IG does not own or fork their registries, currentness logic, evidence schemas, compatibility rules or historical context authority.

The existing `DEC-INPUT-GOV-RUNTIME-001` boundary remains in force:

- Agent orchestrates;
- Curator produces/recurates but does not accept/reject;
- Validator independently accepts/rejects against authority/evidence;
- Curator output is never authority merely because it was produced by Curator/model;
- promotion/production remain separately governed.

## Contract amendment

`INPUT_GOVERNANCE_EXECUTION_CONTRACT` advances from revision `1.5` to `1.6`.

Revision `1.6` removes the obsolete assertion that a new/changed scope requires an unbound external semantic runtime. The canonical rule becomes:

`DETERMINISTIC_FIRST; POLICY_SELECTED_SEMANTIC_CAPABILITY_ONLY_FOR_NON_DERIVABLE_GAPS; MODEL_OUTPUT_NON_AUTHORITATIVE`.

The three active role runtimes remain bound as Agent / Curator / Validator. This amendment does not deploy or replace runtime code.

## Compatibility / reconciliation

- `DEC-INPUT-GOV-RUNTIME-001`: preserved and extended only by reference; no competing runtime boundary is created.
- Contract `1.5`: preserved as historical evidence; `1.6` supersedes it for future execution decisions.
- Existing valid runs/evidence are not invalidated solely by this amendment. Re-evaluation is required only when currentness, contradiction, stale evidence, drift or material fingerprint change is demonstrated.
- M2.6, M2.8 and M3.7 remain out of scope for this unit.

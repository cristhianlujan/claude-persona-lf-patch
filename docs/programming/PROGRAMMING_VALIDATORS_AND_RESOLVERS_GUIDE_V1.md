# PROGRAMMING VALIDATORS & RESOLVERS GUIDE V1

## 1. Purpose

This guide explains what Programming validators and resolvers do, how they are reused, how they are qualified, and how a plan binds them to atomic checkpoints.

The operating principle is:

```text
REUSE PROCEDURE
      +
EXPLICIT CHECKPOINT INPUT
      +
CURRENT EXECUTION EVIDENCE
      =
CURRENT PASS / FAIL
```

A previous PASS is never reused to close a new checkpoint.

---

## 2. Concepts

### Validator

A validator is a deterministic procedure that answers one bounded question about the current state.

Examples:

- does a file contain required source markers?
- does a database row exist?
- does a JSON contract contain the required fields?
- does a test run have PASS status?
- does a file SHA match the expected value?

A validator must not infer what to check from a checkpoint title.

### Resolver

A resolver is a deterministic repair procedure for one known validation failure family.

A resolver:

- is coupled to a validation code and failure code;
- executes only after the current validation returns FAIL;
- records evidence that it actually ran;
- never grants PASS;
- must be followed by a new validation of the current state.

### Checkpoint binding

A checkpoint does not embed validator logic.

It binds:

```text
checkpoint
  -> validation_code
  -> failure_code
  -> validation_input
```

This allows the same validator to be reused by many checkpoints without duplicating validator definitions.

---

## 3. Reuse model

### What is reused

| Element | Reused? | Meaning |
|---|---:|---|
| `validation_code` | Yes | Stable validator identity |
| `validator_handler` | Yes | Deterministic procedure |
| Validator qualification tests | Yes | Proof that the procedure works |
| `resolver_code` | Yes | Stable repair identity |
| `resolver_handler` | Yes | Deterministic repair procedure |
| Resolver qualification tests | Yes | Proof that repair + post-validation work |
| `validation_input` | No | Specific to the checkpoint |
| Current validation receipt | No | New for each run/unit/checkpoint |
| Previous runtime PASS | No | Never satisfies the current checkpoint |

### Required invariant

```text
REUSE != BYPASS
```

Reusing a validator means running the same proven procedure with new explicit inputs.

It does not mean inheriting a previous result.

---

## 4. Validator registry

Canonical table:

`programacion.programming_validation_registry`

Important fields:

| Field | Purpose |
|---|---|
| `validation_code` | Stable reusable identifier |
| `rule_code` | Rule family represented |
| `rule_mode` | BLOCKING_AUTOMATIC / HUMAN_DECISION / CHECK_ONLY |
| `input_contract` | Accepted input shape |
| `validator_handler` | Deterministic execution handler |
| `pass_condition` | Objective PASS condition |
| `fail_condition` | Objective FAIL condition |
| `positive_test_run_id` | Exact qualification test |
| `negative_test_run_id` | Exact qualification test |
| `status` | PROPOSED / PROVEN / ACTIVE / RETIRED |

### Modes

#### `BLOCKING_AUTOMATIC`

Use only when:

- validator is deterministic and qualified;
- an ACTIVE deterministic resolver exists;
- resolver has qualification proof;
- post-validation has qualification proof.

A missing resolver means the rule cannot be admitted as automatic blocking.

#### `HUMAN_DECISION`

Use when detection is deterministic but the remediation/decision is not safe to automate.

The validator may return FAIL, but the executor routes to human decision rather than inventing a repair.

#### `CHECK_ONLY`

Informational/non-blocking.

It cannot back a required checkpoint.

---

## 5. Resolver registry

Canonical table:

`programacion.programming_resolver_registry`

Important fields:

| Field | Purpose |
|---|---|
| `resolver_code` | Stable reusable repair identifier |
| `validation_code` | Validator it resolves |
| `failure_code` | Exact failure family |
| `resolver_handler` | Deterministic repair procedure |
| `preconditions` | Conditions required before repair |
| `post_validation_code` | Validator that must run again |
| `resolver_test_run_id` | Exact resolver qualification test |
| `post_validation_test_run_id` | Exact post-repair qualification test |
| `status` | PROPOSED / PROVEN / ACTIVE / RETIRED |

The resolver never writes PASS into the checkpoint.

The mandatory flow is:

```text
CURRENT VALIDATION
      |
      +-- PASS -> checkpoint may close
      |
      +-- FAIL
            |
            v
        RESOLVER
            |
            v
     resolution receipt
            |
            v
       REVALIDATE
            |
            +-- PASS -> checkpoint may close
            +-- FAIL -> remains unresolved
```

---

## 6. Qualification proof vs runtime history

Qualification proof proves that the validator/resolver procedure itself works.

It is not a search through previous plan history.

For admission, the executor reads exact `public.lf_test_runs.test_run_id` values by primary key.

Required qualification metadata:

### Validator positive test

```json
{
  "programming_subject_type": "VALIDATION",
  "programming_subject_code": "<validation_code>",
  "programming_test_role": "POSITIVE"
}
```

### Validator negative test

```json
{
  "programming_subject_type": "VALIDATION",
  "programming_subject_code": "<validation_code>",
  "programming_test_role": "NEGATIVE"
}
```

### Resolver test

```json
{
  "programming_subject_type": "RESOLVER",
  "programming_subject_code": "<resolver_code>",
  "programming_test_role": "RESOLVER"
}
```

### Resolver post-validation test

```json
{
  "programming_subject_type": "RESOLVER",
  "programming_subject_code": "<resolver_code>",
  "programming_test_role": "POST_VALIDATION"
}
```

A new validator with zero runtime history is valid once its fresh qualification tests pass.

---

## 7. Checkpoint input

Canonical binding table:

`programacion.programming_checkpoint_bindings`

Each binding carries an explicit `validation_input`.

This is what prevents one validator per checkpoint.

Example using the current GitHub source validator:

```json
{
  "repository": "cristhianlujan/libertad-financiera",
  "ref": "8c82bb46b92134d3ece17d52c0208e0ebe56bb48",
  "path": "src/components/b2b-shell/b2b-shell.tsx",
  "must_contain": [
    "data-shell-code=\"B2B_APP_SHELL\"",
    "data-shell-version=\"v0.9\""
  ],
  "must_not_contain": [
    "ADMIN_APP_SHELL"
  ],
  "exact_count": {
    "id=\"b2b-shell-overlay-root\"": 1
  }
}
```

### Input rules

1. Parameters must be explicit.
2. Do not infer parameters from unit/checkpoint titles.
3. Use stable semantic markers where formatting is not part of the contract.
4. Use exact count/order only when count/order is itself a requirement.
5. Keep the validator generic; put file/ref/literal differences in `validation_input`.

---

## 8. Current reusable catalog

### Active validators

#### `PROGRAMMING_GITHUB_FILE_TEXT_ASSERT_V1`

**Status:** ACTIVE  
**Mode:** HUMAN_DECISION  
**Handler:** `GITHUB_FILE_TEXT_ASSERT_V1`

Purpose:

Deterministically validate text contracts in a GitHub file at an exact repository/ref/path.

Required input:

- `repository`
- `ref`
- `path`

Optional input:

- `must_contain`
- `must_not_contain`
- `ordered_contains`
- `exact_count`

PASS:

All declared assertions are satisfied.

FAIL:

At least one declared assertion fails, with the failed assertion identified.

Qualification:

- positive test: `lf_test_runs:2bd5b1c1-81f6-4e8d-a3a5-83bb97b329bc`
- negative test: `lf_test_runs:f1bd339e-bb7e-4685-88b0-fdc7dd4b29e0`

Known usage:

`B2B_SHELL_ATOMIC_PILOT_V1` reused this validator across 16 checkpoints by changing only `validation_input`.

#### `PROGRAMMING_SUPABASE_CATALOG_ASSERT_V1`

**Status:** ACTIVE  
**Mode:** HUMAN_DECISION  
**Handler:** `SUPABASE_CATALOG_ASSERT_V1`

Purpose:

Deterministically validate current Supabase catalog/readback conditions with explicit assertions.

Supported assertion families:

- `TABLE_EXISTS`
- `RLS_ENABLED`
- `POLICY_EXISTS`
- `FUNCTION_EXISTS`
- `ROW_COUNT_EQUALS`
- `COLUMN_EXISTS`

The schema/object names and expected values belong in `validation_input`. Do not create one validator per table, function, policy, or migration.

Qualification:

- positive test: `lf_test_runs:fb6646bb-eef5-4e5f-8beb-5b5a580c7367`
- negative test: `lf_test_runs:0a6699b3-7d12-4524-8e84-b9d62426f105`

Known usage:

B2B S07 live readback reused this validator to confirm the support-channel table, RLS, policy, runtime function and extensible catalog shape after migration application.

#### `PROGRAMMING_GITHUB_FILE_SHA256_ASSERT_V1`

**Status:** ACTIVE  
**Mode:** HUMAN_DECISION  
**Handler:** `GITHUB_FILE_SHA256_ASSERT_V1`

Purpose:

Validate binary repository assets byte-for-byte by fetching the exact GitHub file at a declared ref, decoding the bytes, computing SHA-256 and comparing the result with `expected_sha256`.

Required input:

- `repository`
- `ref`
- `path`
- `expected_sha256`

Do not substitute Git blob SHA for the declared SHA-256 contract.

Qualification:

- positive test: `lf_test_runs:ffc40106-8825-44e6-882f-e3fca7288e2b`
- negative test: `lf_test_runs:8d773299-7c71-4a87-a2d9-e9ad72cd74b6`

Known usage:

B2B S03.4 reused this validator for the expanded LF logo and collapsed shield. Both current exact-ref byte hashes matched the governed SHA-256 values.

### Active resolvers

None currently registered.

This is intentional.

A resolver must not be created just to complete the catalog. It enters only after a real deterministic repair family is identified and its resolver + post-validation are tested.

---

## 9. How to use an existing validator

Before creating a new validator:

1. Search `programacion.programming_validation_registry`.
2. Compare the required deterministic behavior with the existing `input_contract`.
3. If only parameters differ, reuse the validator and supply a new `validation_input`.
4. Execute it against the current checkpoint state.
5. Record a new current-run validation receipt.

Do not create another validator because:

- the file path changed;
- the repository changed;
- the expected literal changed;
- the SHA changed;
- the checkpoint belongs to another unit.

Those are normally input differences, not procedure differences.

---

## 10. When a new validator is justified

Create a new validator only when the deterministic procedure is genuinely different.

Examples:

```text
GITHUB_FILE_TEXT_ASSERT
vs
GITHUB_FILE_SHA256_ASSERT
vs
SQL_ROW_EXISTS
vs
JSON_SCHEMA_ASSERT
```

These require different execution procedures.

Before ACTIVE:

```text
define input contract
      ->
implement deterministic handler
      ->
positive qualification test
      ->
negative qualification test
      ->
register exact test_run_ids
      ->
admission PASS
      ->
ACTIVE
```

If deterministic validation cannot be defined, the rule does not enter as an automatic validator.

Propose a measurable alternative or model it explicitly as a human decision.

---

## 11. When a new resolver is justified

A resolver is justified only if a FAIL family has a deterministic repair.

Good example:

```text
VALIDATION:
required generated file missing

FAILURE:
GENERATED_FILE_MISSING

RESOLVER:
run canonical deterministic generator with declared inputs

POST:
rerun original validator
```

Bad examples:

- "fix the architecture";
- "improve UX";
- "decide whether this is correct";
- "repair whatever is wrong".

Those are not deterministic resolver contracts.

---

## 12. Plan-author checklist

Before binding a checkpoint:

```text
[ ] Is the rule intrinsic to this unit?
[ ] Is there an existing validator that already performs this procedure?
[ ] Can differences be expressed only as validation_input?
[ ] Is the validator ACTIVE and qualification-proven?
[ ] Does this checkpoint need BLOCKING_AUTOMATIC, HUMAN_DECISION, or CHECK_ONLY?
[ ] If BLOCKING_AUTOMATIC, is the matching resolver ACTIVE and proven?
[ ] Does current execution produce a new receipt?
[ ] Is any previous runtime PASS being reused? If yes -> reject.
```

---

## 13. Anti-patterns

### Validator per checkpoint

Wrong:

```text
VALIDATE_S01_FILE
VALIDATE_S02_FILE
VALIDATE_S03_FILE
```

when all three only test text in a GitHub file.

Correct:

```text
PROGRAMMING_GITHUB_FILE_TEXT_ASSERT_V1
  + validation_input S01
  + validation_input S02
  + validation_input S03
```

### Generic intelligent validator

Wrong:

```text
"inspect checkpoint and decide if it looks correct"
```

There is no deterministic PASS/FAIL contract.

### Historical PASS reuse

Wrong:

```text
validator passed yesterday
therefore current checkpoint = DONE
```

Correct:

```text
validator is qualified
      +
run it again against current input/state
      =
current receipt
```

### Resolver self-approval

Wrong:

```text
resolver executed -> DONE
```

Correct:

```text
resolver executed
      ->
resolution receipt
      ->
validator reruns
      ->
PASS
      ->
DONE
```

---

## 14. Source of truth

Operational source of truth:

- `programacion.programming_validation_registry`
- `programacion.programming_resolver_registry`
- `programacion.programming_checkpoint_bindings`
- `programacion.programming_resolution_receipts`
- `public.lf_test_runs`

This document explains usage. It does not replace registry state.

Relevant EKB:

- `PROGRAMMING-SIMPLE-EXECUTOR-RULE-ADMISSION-001`
- `PROGRAMMING-SIMPLE-BINDING-INPUT-001`
- `PROGRAMMING-SIMPLE-QUALIFICATION-PROOF-001`
- `PROGRAMMING-SIMPLE-RESOLVER-NO-BYPASS-001`
- `PROGRAMMING-SUPABASE-CATALOG-VALIDATOR-001`
- `PROGRAMMING-GITHUB-BINARY-SHA256-VALIDATOR-001`


## 15. Discovery in Supabase

For agents that start from Supabase instead of GitHub, this capability is registered in the canonical capability registry:

`public.lf_capability_registry.capability_code = PROGRAMMING_VALIDATOR_RESOLVER_CATALOG`

Version registry:

`public.lf_capability_version_registry (PROGRAMMING_VALIDATOR_RESOLVER_CATALOG, 1.0.0)`

The registry summary points back to the live Programming tables and this GitHub guide.

Recommended discovery order:

```text
1. Search public.lf_capability_registry for PROGRAMMING_VALIDATOR_RESOLVER_CATALOG
2. Read public.lf_capability_version_registry manifest.usage
3. Query programacion.programming_validation_registry
4. Query programacion.programming_resolver_registry
5. Reuse an existing procedure when only validation_input changes
6. Create a new validator/resolver only for a genuinely different deterministic procedure
```

Current live catalog at registration time:

- ACTIVE validators: 3
- ACTIVE resolvers: 0
- reusable validators:
  - `PROGRAMMING_GITHUB_FILE_TEXT_ASSERT_V1`
  - `PROGRAMMING_SUPABASE_CATALOG_ASSERT_V1`
  - `PROGRAMMING_GITHUB_FILE_SHA256_ASSERT_V1`

The counts in the capability manifest are a discovery snapshot. The live registries remain authoritative.

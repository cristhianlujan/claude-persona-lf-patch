# DECISION_CONTEXT_ASOF v1

Owner: `SUPER_ADMIN`  
Capability: `DECISION_CONTEXT_ASOF`  
Consumer model: generic transversal capability; IG is only a consumer through `IG_CURATOR_VALIDATOR_REFACTOR_V2:N-16`.

## Purpose

Persist the exact decision context that applied when a decision was taken and resolve it later by `as_of`, without reinterpreting history from mutable latest state.

## Canonical contract

Input schema: `decision-context-asof/v1`.

Required branches:
- `decision_ref`
- `consumer_code`
- `subject.ref` + `subject.version`
- `actor_authority.actor_ref`
- `actor_authority.authority_ref` + `authority_version` + `authority_sha256`
- `governing.policy_ref` + `policy_version` + `policy_sha256`
- `governing.terms_ref` + `terms_version` + `terms_sha256`
- `times.decided_at` + `times.effective_at`
- `authority_refs[]`
- `extensions` for non-authoritative consumer metadata

Core authority branches accept references, versions and digests only. Payload/document/snapshot copies are rejected there.

## Reused authorities

The capability does not replace temporal/currentness/version/evidence authorities. A record is admitted only when the request pins the same current revisions declared by the capability manifest for:
- `CURRENTNESS_AUTHORITY`
- `CAPABILITY_VERSION_COMPATIBILITY`
- `TYPED_EVIDENCE_REGISTRY`

`TYPED_EVIDENCE_REGISTRY` validates `decision-context-asof/v1`.

## Entry points

- Record: `public.fn_lf_decision_context_asof_record_v1(jsonb,text)`
- Resolve: `public.fn_lf_decision_context_asof_resolve_v1(text,text,timestamptz)`
- Immutable store: `private.lf_decision_context_asof_v1`

The resolver reads the immutable historical receipt whose `decided_at <= as_of`. It does not query mutable latest policy/terms/role/owner state to reinterpret that receipt.

## Invariants

1. `latest != as-of`.
2. Later role/owner/policy/terms changes do not mutate the recorded context.
3. Historical rows are append-only.
4. No public IG-specific columns exist.
5. No IG-specific branch exists in record/resolve logic.
6. Consumer extensions are non-authoritative metadata only.
7. Unknown/drift blocks new recording; historical resolution remains readable.

## Verification

`test_decision_context_asof_v1.sql` is rollback-only. It:
1. records an IG-consumer decision context against canary authority/policy/terms v1;
2. mutates the canary latest values to v2;
3. resolves the earlier `as_of` and proves the historical v1 refs/digests are unchanged;
4. records and resolves a `STORY_CREATOR` decision with the exact same contract;
5. rolls back all canary records and mutations.

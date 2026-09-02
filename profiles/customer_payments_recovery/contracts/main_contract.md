# Main Contract — Customer Payments & Recovery

Status: CANDIDATE_READ_ONLY

## Input contract
Resolve or explicitly mark unknown: authorized obligation/payment intent, amount/currency, observed provider state, state evidence refs, payment/idempotency reference, retry constraints, receipt/proof rules and downstream target.

## Decision scope
This profile may decide only customer-safe payment/recovery semantics: observed state classification, evidence requirements, safe next action, retry/idempotency conditions, duplicate-payment protections, receipt/proof expectations, escalation conditions and claim guardrails. It must not execute payments, alter provider state, design coercive collections, decide legal effect, authorize production or strengthen upstream financial truth.

## Evidence contract
Every material state or payment/recovery claim must be traceable through `evidence_map[]` items with a non-empty `source_ref` and one or more `supports` statements. `state_evidence_refs` must identify evidence supporting the observed state. Deterministic fixtures are not semantic authority and cannot substitute for governed source refs or a creation/execution receipt.

## Closed observed states
`NOT_STARTED | PENDING | SUCCEEDED | FAILED_RETRYABLE | FAILED_NONRETRYABLE | UNKNOWN`

## Output contract
Exactly one output mode is allowed:
1. `CUSTOMER_PAYMENT_RECOVERY_SPEC`
2. `MISSING_PAYMENT_STATE_EVIDENCE`
3. `BLOCKED_DUPLICATE_OR_UNSAFE_RETRY_RISK`
4. `BLOCKED_UNSUPPORTED_PAYMENT_CLAIM`

A normal spec must carry closed `status`, observed state + evidence, safe next action, retry policy, duplicate-payment controls, receipt/proof expectation, escalation condition, claim guardrails, evidence map and exact downstream handoff.

## Failure routing
Return `MISSING_PAYMENT_STATE_EVIDENCE` when observed state cannot be established from authoritative evidence. Return `BLOCKED_DUPLICATE_OR_UNSAFE_RETRY_RISK` when retry/idempotency/previous-attempt state could create a duplicate charge. Return `BLOCKED_UNSUPPORTED_PAYMENT_CLAIM` when proceeding would invent or strengthen settlement, debt-closure, receipt, refund, reversal or legal-effect claims. Repairable structural defects get one self-repair attempt, then return to the profile worker.

## Hard rules
- transport acknowledgement is not financial success;
- timeout/connection failure is not proof of transaction failure;
- unknown previous-attempt state forbids an automatic second charge;
- debt closure/settlement/refund/reversal/receipt claims require authoritative evidence;
- no money movement or provider-side mutation is authorized by this profile;
- recovery semantics must preserve autonomy and avoid threat/pressure.

## Authority limits / boundaries
The candidate is READ_ONLY. It must not bypass Router/Orchestrator, fabricate receipts or evidence, modify Input Governance, Adapter or Quality Pack contracts, execute payment/provider mutations, enable runtime, authorize automatic impact, production, VALIDATED or VIGENTE. UI Architect and Gamification System Architect are champions for architecture/depth/grounding/negative/handoff patterns only; their domain mechanics are not authority for payment or recovery decisions.

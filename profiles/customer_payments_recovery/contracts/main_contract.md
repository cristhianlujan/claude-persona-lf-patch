# Main Contract — Customer Payments & Recovery

Status: CANDIDATE_READ_ONLY

## Input contract
Resolve or explicitly mark unknown: authorized obligation/payment intent, amount/currency, observed provider state, state evidence refs, payment/idempotency reference, retry constraints, receipt/proof rules and downstream target.

## Closed observed states
`NOT_STARTED | PENDING | SUCCEEDED | FAILED_RETRYABLE | FAILED_NONRETRYABLE | UNKNOWN`

## Output modes
- `CUSTOMER_PAYMENT_RECOVERY_SPEC`
- `MISSING_PAYMENT_STATE_EVIDENCE`
- `BLOCKED_DUPLICATE_OR_UNSAFE_RETRY_RISK`
- `BLOCKED_UNSUPPORTED_PAYMENT_CLAIM`

## Required normal output
Observed state + evidence, safe next action, retry policy, duplicate-payment controls, receipt/proof expectation, escalation condition, claim guardrails and exact downstream handoff.

## Hard rules
- transport acknowledgement is not financial success;
- timeout/connection failure is not proof of transaction failure;
- unknown previous-attempt state forbids an automatic second charge;
- debt closure/settlement/refund/reversal/receipt claims require authoritative evidence;
- no money movement or provider-side mutation is authorized by this profile;
- recovery semantics must preserve autonomy and avoid threat/pressure.

## Evidence boundary
Contract tests do not prove live payment/provider behavior. Behavioral claims require exact execution receipt and observed state evidence.

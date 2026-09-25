# GITHUB_PROVIDER_READBACK_V1 · verification plan

1. Shared helper syntax/import.
2. E.16 synthetic inventory matrix remains PASS.
3. DNS failure retries exactly 3 times then `BLOCKED_INFRA_DNS`.
4. Retryable HTTP can recover within the bounded retry budget.
5. 401/403 never retry and classify `FAIL_AUTH`.
6. Invalid JSON/shape/oversize classify `FAIL_EVIDENCE_MISMATCH`.
7. Nonretryable HTTP classifies `FAIL_GITHUB_API`.
8. Exact-head CI readback required before candidate close.
9. No merge, runtime activation or production mutation in this candidate.

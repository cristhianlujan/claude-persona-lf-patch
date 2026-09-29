# P11-A execution sequence

1. Extend the existing canonical qualification ledger to `CONTROL_SYSTEM`.
2. Merge + apply + read back the authority extension exactly.
3. Produce one independent exact-head `PASE_CONTROL_QUALIFICATION_V1` receipt for the merge-gate candidate.
4. Change `PASE_MERGE_GATE_QUALIFICATION_READBACK_V1` to consume only that canonical receipt readback.
5. Re-run trusted-base validator over the stored qualification packet/result.
6. Exact-head probe: qualified self-change must PASS.
7. Negative probe: same control-system route without an exact receipt must BLOCK.
8. Merge the repaired merge-gate readback.
9. Continue cutover with enforcement still non-required: P0 dual-identity compatibility -> reconciliation dual-identity compatibility -> canonical source-authority retirement capability -> activate `pase.yml` as the only ordinary PR entrypoint -> live-fire/replay/readback -> retire the legacy entrypoint only after destination proof.
10. Only after the complete cutover and legacy-retirement readback, restore `pase-merge-gate` as a required status and run the final enforcement proof.

Guardrails: Changeset Governance remains the only applicability authority; one solution per PR; no ZIP; no foreign-control repair inside the candidate PR; no legacy retirement before destination proof. `protect-main.required_status_checks` stays empty throughout construction, cutover, and live-fire validation; required enforcement is the final step, not a prerequisite for cutover.

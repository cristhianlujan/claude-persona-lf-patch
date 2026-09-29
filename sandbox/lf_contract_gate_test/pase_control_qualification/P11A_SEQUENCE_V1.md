# P11-A execution sequence

1. Extend the existing canonical qualification ledger to `CONTROL_SYSTEM`.
2. Merge + apply + read back the authority extension exactly.
3. Produce one independent exact-head `PASE_CONTROL_QUALIFICATION_V1` receipt for the merge-gate candidate.
4. Change `PASE_MERGE_GATE_QUALIFICATION_READBACK_V1` to consume only that canonical receipt readback.
5. Re-run trusted-base validator over the stored qualification packet/result.
6. Exact-head probe: qualified self-change must PASS.
7. Negative probe: same control-system route without an exact receipt must BLOCK.
8. Merge the repaired merge-gate readback.
9. Restore `pase-merge-gate` as the required PASE merge status only after PASS/BLOCK live-fire and ruleset readback.
10. Continue cutover: P0 consumer compatibility -> activate `pase.yml` -> retire legacy entrypoint only after replay/readback.

Guardrails: Changeset Governance remains the only applicability authority; one solution per PR; no ZIP; no foreign-control repair inside the candidate PR; no legacy retirement before destination proof.

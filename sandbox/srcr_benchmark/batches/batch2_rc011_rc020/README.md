# SRCR Benchmark — Batch 2 blind handoff

Scope: RC-011 through RC-020 only.

Execution context must be isolated from any oracle-bearing conversation or file.

Required order for each case:
1. Run SYSTEMIC_ROOT_CAUSE_REPAIR_LF_V0_6 using the exact case input from `inputs_only.json`.
2. Freeze the complete raw output and bind it to input/model/output identity.
3. Run M11_RECONSTRUCTED_SRCR_V0_1 using the exact same case input.
4. Freeze the complete raw output and bind it to input/model/output identity.
5. Only after both freezes, evaluate against the case oracle.
6. Normalize both outputs to the shared comparison contract.

Do not run M01-M10 external comparators in this batch.
Do not mutate production, activate runtime/controls, merge, or advance to RC-021.

Pinned models:
- V0.6: `a0f58ad1a1219f0c4dc9a70f167a1908418e5491:profiles/systemic_root_cause_repair_lf/SKILL.md`
- M11: `ff31b709aa33dc1b3ce5afcdd2cd320909e6bc76:sandbox/srcr_benchmark/models/m11_reconstructed_srcr_v0_1/SKILL.md`

Expected consolidated columns after scoring:
`Caso | modelo | raíz detectada | invariantes | hallazgos | gaps | FP | score | estado | evidencia`

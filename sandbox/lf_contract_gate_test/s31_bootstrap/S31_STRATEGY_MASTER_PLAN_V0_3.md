# S31 Strategy Master Plan v0.3 — Continuous EKB Learning Loop

Status: CANDIDATE / PRODUCER-HARDENED DELTA / NO RUNTIME OR PROMOTION AUTHORITY

## 1. Purpose

S31 v0.3 preserves the reviewed S31 v0.2 artifacts as immutable history and adds one transversal execution invariant learned from S30: EKB is not a one-time preflight and a final readback. It is an event-driven continuous control loop throughout every material execution.

The required cycle is:

```text
READ -> APPLY -> EXECUTE MATERIAL BATCH -> OBSERVE
  -> on FAIL/BLOCKED/ERROR/material new evidence: EKB LOOKUP
  -> classify RECURRENCE | NEW_ERROR | NOT_LEARNING_WITH_REASON
  -> persist through governed writer when required
  -> writer receipt + readback
  -> only then REPAIR/REPLAN
  -> fresh EKB refresh before the next material batch
  -> repeat
  -> final EKB learning disposition + final readback
  -> close guard
```

This is event-driven continuous learning, not blind polling. Every material batch boundary and every failure/block/error boundary must prove the appropriate EKB state.

## 2. Canonical S30 semantics reused

S31 reuses, without claiming S30 runtime ownership:

- `GOV-010`: fresh applicable EKB before material work and mapped to executable controls;
- `S30-GATE-EKB-AUTOPERSIST-MISSING-001`: FAIL/BLOCKED/ERROR must perform EKB lookup; recurrence/new error persistence and readback precede repair;
- `EKB-NEW-ERROR-SHAPE-PREFLIGHT-MISSING-001`: NEW_ERROR requires governed writer shape preflight;
- `PROFILE-RUNTIME-RUN-REPORT-ANTI-CLOSE-VIOLATION-001`: close requires final EKB readback and zero remaining safe work;
- `DB-001`: schema-first before EKB/database reads or writes.

The recurrence that motivated this plan delta was persisted through `public.lf_write_pipeline_ekb_v1` as event `13502`, classification `RECURRENCE`, frequency `3` for `S30-GATE-EKB-AUTOPERSIST-MISSING-001` before this repair was materialized.

## 3. Mandatory execution lifecycle

```text
Admission / Work Package
    -> schema-first EKB source resolution
    -> fresh EKB + authority/currentness binding
    -> source/schema/contract resolution
    -> material macrobatch
    -> observation checkpoint
       -> PASS without material new evidence: continue
       -> FAIL/BLOCKED/ERROR/material new evidence:
            EKB lookup
            -> existing code/family: RECURRENCE
            -> no existing code/family: NEW_ERROR
            -> non-learning observation: NOT_LEARNING_WITH_REASON
            -> if RECURRENCE/NEW_ERROR: governed writer receipt + post-write readback
            -> if persistence/readback fails: BLOCKED_EKB_PERSISTENCE; repair forbidden
            -> repair/replan only after disposition is complete
    -> fresh EKB refresh before next material macrobatch
    -> deterministic validation
    -> adversarial bypass audit
    -> repeat observation/EKB loop for any new defect
    -> final EKB learning disposition
    -> final EKB readback after the last EKB write
    -> global safe-work rescan
    -> scope-specific freeze
    -> independent semantic review
    -> integration/replay gate
    -> explicit promotion decision only by authority
```

## 4. Hard rules

1. EKB lookup is mandatory on every material `FAIL`, `BLOCKED` or `ERROR` before repair begins.
2. Material new evidence that changes the causal hypothesis also triggers EKB lookup before the next material batch.
3. Existing code/family is a `RECURRENCE`; do not create duplicate EKB entries.
4. `NEW_ERROR` must pass the governed writer-shape preflight before persistence.
5. Required EKB persistence must use the governed writer route; no direct DML bypass.
6. Repair is forbidden until the EKB disposition is terminal and required writer receipt/readback exists.
7. Failed EKB persistence yields `BLOCKED_EKB_PERSISTENCE`; it cannot be re-labelled as a candidate defect or ignored to continue the same causal repair.
8. Before every subsequent material macrobatch, applicable EKB must be refreshed when the prior observation changed evidence, classification, controls or causal hypothesis.
9. Close is forbidden while any observed learning event is `PENDING`, any required persistence lacks readback, or final EKB readback is older than the last EKB write.
10. `NOT_LEARNING_WITH_REASON` is allowed only with explicit evidence-based reason; it is not a silent skip.

## 5. Executable control

The executable companion is `s31_ekb_continuous_cycle_v0_1.json` with validator `validate_s31_ekb_continuous_cycle_v0_1.py` and adversarial self-test `test_s31_ekb_continuous_cycle_v0_1.py`.

The master plan cannot claim executable compliance unless that control passes for the actual run receipt.

## 6. Versioning and review boundary

- v0.2 artifacts and independent-review bundles remain immutable historical evidence.
- This v0.3 delta does not retroactively change their verdicts or receipts.
- Any future Work Package evolution must bind this continuous EKB cycle rather than merely carry preflight/final booleans.
- No merge to main, Golden, production, runtime activation or framework cutover is authorized by this plan.

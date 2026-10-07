# SRCR V0.7R1 terminality repair candidate

Purpose: repair the matched-evidence finding from execution `EXEC-MFC-V5R4-MATCHED-EVIDENCE-20261006-001`.

Measured baseline:
- canonical defects: 5/5;
- required facets: 20/20;
- material fronts: 21/22;
- terminal accuracy: 0/5 (all five incorrectly emitted `SYSTEMIC_REPAIR_SPEC` while material evidence remained open).

Scope:
- preserve V0.7 diagnostic architecture and required RAW output keys;
- add a zero-diagnostic-cost terminality/completeness gate;
- add `OPERABILITY_MAINTENANCE_OWNERSHIP` only when persistent effects/cleanup/maintenance make it applicable;
- do not adopt R4 as a parallel diagnostic overlay;
- no runtime or production activation.

Target regression:
- RC-078, RC-030, RC-008, RC-053, RC-012 => `NEEDS_MORE_EVIDENCE`;
- fully closed control => `SYSTEMIC_REPAIR_SPEC`;
- canonical defect/facet recall must not regress;
- material-front target >=21/22, target 22/22.

# P0 V4.2 completeness contract

Completeness is conservation, not enumeration: every material source observation must map to exactly one atomic candidate element, and every confirmed candidate must retain source support.

The denominator is produced independently from source pixels through OCR PSM-6, Canny geometry and binary-threshold compact geometry. Candidate-list enumeration cannot add to the denominator. Repeated controls reconcile observed and represented cardinality with distinct matched element IDs.

`UNEXPLAINED_VISUAL_RESIDUAL`, `MATERIAL_OMISSION`, `REPEATED_CONTROL_CARDINALITY_MISMATCH`, `SHARED_EVIDENCE_VIOLATION` and `UNJUSTIFIED_PARTITION` are fail-closed. Background, fill and composite-image exceptions require explicit source-bound justification; a page/container bbox is not such a justification.

System-wide autonomous readiness additionally requires a versioned labelled corpus of at least 10 screens, 100/100 mutation detection, and zero escaped defects on five consecutive unseen screens. Until then, human review remains mandatory and P0-5 / production remain unauthorized.

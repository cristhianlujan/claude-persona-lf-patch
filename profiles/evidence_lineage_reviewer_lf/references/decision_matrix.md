# Decision Matrix

| Condition | Decision |
|---|---|
| Authority + direct source + exact revision + reconciliation all valid | PASS_EVIDENCE_LINEAGE |
| Claim proven, but a separate downstream/non-claim gate remains | PASS_WITH_RESTRICTIONS |
| Direct readback or exact revision missing/stale | RETURN_TO_SOURCE_FOR_READBACK |
| Live authorities conflict or translated structural identifier conflicts | BLOCK_PIPELINE |
| Requested action would mutate repo/DB/runtime | BLOCK_PIPELINE |

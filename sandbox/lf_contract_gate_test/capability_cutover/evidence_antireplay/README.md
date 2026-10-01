# EVIDENCE_ANTIREPLAY cutover v1

`SADM-PP-L5-022` isolated capability cutover.

Promotes the already-applied anti-replay and composition cross-binding enforcement as version `1.1.0`. The authority is the existing Evidence Ledger guard after migration `20260930133539` with statement SHA-256 `7b1abd2d539a1b58403514d987ec0cdd156d15ff74d45212f74466e6c5dfee0a` and live guard md5 `2eba89c4c6c87904205564d39994f2e5`.

Prerequisites: `EVIDENCE_LEDGER@1.1.0` and `EVIDENCE_RESOLVER_REGISTRY@1.0.0` current. No evidence rows are modified.

Rollback removes only the exact current pointer and restores pre-cutover owner/asset metadata while preserving version history and ledger data.

No runtime/deploy/production, no bulk cutover, and no ZIP authority.

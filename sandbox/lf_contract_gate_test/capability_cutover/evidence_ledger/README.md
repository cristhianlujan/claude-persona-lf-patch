# EVIDENCE_LEDGER cutover v1

`SADM-PP-L5-022` isolated capability cutover.

This cutover promotes the already-applied cross-binding hardening of the existing append-only Evidence Ledger as capability version `1.1.0`. It creates no ledger, replays no DDL, and mutates no existing evidence rows.

Authority is bound to migration `20260930133539`, statement SHA-256 `7b1abd2d539a1b58403514d987ec0cdd156d15ff74d45212f74466e6c5dfee0a`, live guard md5 `2eba89c4c6c87904205564d39994f2e5`, and live anchor md5 `fde5b4db6af6b3566a93906c27e01c39`.

The three hardening blockers were closed before this cutover under terminal readback #19630. Resolver `1.0.0` and Typed Evidence `3.0.0` must already be current.

Rollback removes only the exact `1.1.0` current pointer and restores pre-cutover owner/asset metadata. Version history and all ledger rows remain untouched.

No runtime/deploy/production, no bulk cutover, and no ZIP authority.

-- F0 first real migration canary: deliberately no schema or data mutations.
-- This file is intended to test the managed Merge Train and its migration ledger.
-- It must NOT be executed except via a separately authorized production-like Train window.
-- Rollback of database objects/data: NO-OP (none changed).
-- The schema_migrations ledger entry is durable after apply: do NOT DELETE it manually.
-- Revert source via a separately approved source-only follow-up if ever necessary.
SELECT 1 AS f0_train_credential_canary_noop_v1;

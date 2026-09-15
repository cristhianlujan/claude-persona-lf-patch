-- Source parity alias for the governed APP_SHELL lifecycle applied in Supabase as version 20260915120247.
-- Canonical implementation remains byte-for-byte represented by the immediately preceding source candidate; this file exists to reconcile migration version parity after the Supabase migration service assigned its ledger timestamp.
-- See PR #841 and execution EXEC-CREACION-ADMIN-APP-SHELL-20260915-001.

-- No SQL replay here: the migration body was already applied once and is evidenced by the governed operation/readback.
-- This source-only parity marker MUST NOT be applied as a second business mutation.

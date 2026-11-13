-- EXACT rollback before COMMIT only, in the SAME database session.
-- This is not a post-commit inverse migration. Such a reversal requires a new
-- governed migration and fresh preimage readback; updated_at touch trigger prevents
-- an unprivileged inverse from reproducing the old full-row SHA.
-- Example in pg17/18 harness:
-- BEGIN;
-- [paste the canonical single DO migration from supabase/migrations/20261113130100_lf_b2b_policy19_otp_brevo_profiles12_v1.sql]
-- SELECT ... readback ...;
ROLLBACK;
-- Read back original source_sha256 f82cf4ed0887d8240e1a20d193a7a3a82f92271334de6eb543e4489ecac21b07

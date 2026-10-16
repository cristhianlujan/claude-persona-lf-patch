-- ACT-0001 construction sandbox transport qualification. NO production objects.
-- Proves PostgreSQL 17 ephemeral CI service is empty and rollback removes a write.
-- It is NOT a functional proof of T02/T12/T14/PE1 or live prewrite enforcement.
\set ON_ERROR_STOP on
SET statement_timeout TO '30s';
DO $probe$
BEGIN
  IF current_database() <> 'postgres' OR current_user <> 'postgres' THEN
    RAISE EXCEPTION 'FAIL_UNEXPECTED_PG_IDENTITY';
  END IF;
  IF to_regclass('public.lf_activos') IS NOT NULL
     OR to_regclass('public.lf_operation_execution') IS NOT NULL
     OR to_regclass('public.lf_router_action_registry') IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL_SANDBOX_NOT_EMPTY';
  END IF;
  IF to_regclass('public.act0001_rollback_isolation_probe_v1') IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL_PREEXISTING_PROBE';
  END IF;
END
$probe$;
BEGIN;
CREATE TABLE public.act0001_rollback_isolation_probe_v1 (
  id integer PRIMARY KEY,
  label text NOT NULL
);
INSERT INTO public.act0001_rollback_isolation_probe_v1 (id,label)
VALUES (1,'write_inside_sandbox_transaction');
DO $probe$
BEGIN
  IF (SELECT count(*) FROM public.act0001_rollback_isolation_probe_v1) <> 1 THEN
    RAISE EXCEPTION 'FAIL_SANDBOX_WRITE_NOT_VISIBLE_IN_TRANSACTION';
  END IF;
END
$probe$;
ROLLBACK;
DO $probe$
BEGIN
  IF to_regclass('public.act0001_rollback_isolation_probe_v1') IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL_SANDBOX_ROLLBACK_RESIDUE';
  END IF;
END
$probe$;
SELECT 'PASS_ACT0001_ISOLATED_PG17_ROLLBACK_NO_RESIDUE' AS assertion;

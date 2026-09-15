-- S30-R23: harden canonical qualification/assurance stores.
-- Scope: RLS + least-privilege grants only. No qualification semantic changes.

ALTER TABLE public.lf_strategy_test_characteristic_catalog ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lf_strategy_test_characteristics ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lf_test_requirement_bindings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lf_qualification_receipts ENABLE ROW LEVEL SECURITY;

REVOKE ALL PRIVILEGES ON TABLE public.lf_strategy_test_characteristic_catalog FROM anon, authenticated;
REVOKE ALL PRIVILEGES ON TABLE public.lf_strategy_test_characteristics FROM anon, authenticated;
REVOKE ALL PRIVILEGES ON TABLE public.lf_test_requirement_bindings FROM anon, authenticated;
REVOKE ALL PRIVILEGES ON TABLE public.lf_qualification_receipts FROM anon, authenticated;

DO $r23$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'lf_strategy_test_characteristic_catalog',
    'lf_strategy_test_characteristics',
    'lf_test_requirement_bindings',
    'lf_qualification_receipts'
  ] LOOP
    IF NOT EXISTS (
      SELECT 1
      FROM pg_class c
      JOIN pg_namespace n ON n.oid=c.relnamespace
      WHERE n.nspname='public' AND c.relname=t AND c.relrowsecurity
    ) THEN
      RAISE EXCEPTION 'S30_R23_RLS_NOT_ENABLED:%',t;
    END IF;

    IF EXISTS (
      SELECT 1
      FROM information_schema.role_table_grants g
      WHERE g.table_schema='public'
        AND g.table_name=t
        AND g.grantee IN ('anon','authenticated')
        AND g.privilege_type IN ('SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER')
    ) THEN
      RAISE EXCEPTION 'S30_R23_CLIENT_TABLE_PRIVILEGE_REMAINS:%',t;
    END IF;
  END LOOP;
END
$r23$;

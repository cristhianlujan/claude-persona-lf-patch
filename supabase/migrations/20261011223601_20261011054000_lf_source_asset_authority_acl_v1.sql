-- LF source authority hardening: protect the existing canonical asset catalog.
-- Transactional migration. Only privileges and the permissive client INSERT
-- policy on public.lf_activos; no data, API/RLS SELECT or service writer changes.
REVOKE INSERT, TRUNCATE, TRIGGER, REFERENCES
  ON TABLE public.lf_activos FROM PUBLIC, anon, authenticated;
DROP POLICY IF EXISTS lf_activos_authenticated_insert ON public.lf_activos;
COMMENT ON TABLE public.lf_activos IS
  'Canonical LF asset metadata. Client reads retain existing SELECT policy; direct INSERT, TRUNCATE, TRIGGER, REFERENCES are restricted to governed server/owner paths. Source read-binding admission requires separate verified governance.';

-- Corrige EKB LF-RLS-REGLAS-VERSIONES-DISABLED-20261120-001: lf_ops.reglas_versiones replica la convención de lf_ops.reglas.
-- Lectores con BYPASSRLS (postgres, service_role, supabase_read_only_user) y la vista lf_ops.v_reglas_historial (dueño postgres) no cambian.
ALTER TABLE lf_ops.reglas_versiones ENABLE ROW LEVEL SECURITY;
CREATE POLICY deny_direct_client_access ON lf_ops.reglas_versiones
  AS PERMISSIVE FOR ALL TO anon, authenticated USING (false) WITH CHECK (false);
REVOKE ALL ON lf_ops.reglas_versiones FROM anon, authenticated;

UPDATE public.lf_error_knowledge
   SET estado = 'RESUELTO',
       validacion = 'RLS activo + deny_direct_client_access; lectores BYPASSRLS y v_reglas_historial siguen leyendo; anon denegado (prueba local).',
       pr = 'lf/rls-reglas-versiones',
       ultima_vez = clock_timestamp(),
       updated_at = clock_timestamp()
 WHERE codigo = 'LF-RLS-REGLAS-VERSIONES-DISABLED-20261120-001'
   AND estado = 'ACTIVO';

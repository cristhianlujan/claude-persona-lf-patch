-- F4: contrato tipado derivable del registro LF. Sólo lectura, aditivo, sin conectar runtime ni IG.
-- Las 64 familias y los 25 enums se derivan de catálogo real, jamás de copias mantenidas manualmente.
BEGIN;
CREATE FUNCTION lf_ops.f4_tipos_catalogo_v1()
RETURNS jsonb
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO 'pg_catalog','lf_ops'
AS $f4$
  SELECT jsonb_build_object(
    'schema_version','LF_NUCLEO_TYPED_CATALOG_V1',
    'familias',(
      SELECT COALESCE(jsonb_agg(jsonb_build_object('codigo',f.codigo,'tipo',f.tipo) ORDER BY f.codigo),'[]'::jsonb)
      FROM lf_ops.nucleo_familias f
    ),
    'enums',(
      SELECT COALESCE(jsonb_agg(jsonb_build_object('hecho',x.hecho,'valores',x.valores) ORDER BY x.hecho),'[]'::jsonb)
      FROM (
        SELECT e.hecho,jsonb_agg(e.valor ORDER BY e.valor) AS valores
        FROM lf_ops.f0_valores_vocabulario_v1 e
        GROUP BY e.hecho
      ) x
    )
  );
$f4$;
REVOKE ALL ON FUNCTION lf_ops.f4_tipos_catalogo_v1() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION lf_ops.f4_tipos_catalogo_v1() TO service_role;
COMMENT ON FUNCTION lf_ops.f4_tipos_catalogo_v1() IS
 'F4 LF: fuente de generación read-only de tipos y constantes. No evalúa reglas ni consulta bindings runtime, sin promoción ni corte legacy.';
DO $verify$
DECLARE j jsonb;
BEGIN
  SELECT lf_ops.f4_tipos_catalogo_v1() INTO j;
  IF j->>'schema_version'<>'LF_NUCLEO_TYPED_CATALOG_V1'
    OR jsonb_array_length(j->'familias')<>64
    OR jsonb_array_length(j->'enums')<>25
    OR (SELECT COUNT(*) FROM lf_ops.f0_valores_vocabulario_v1)<>94
  THEN RAISE EXCEPTION 'F4_CODEGEN_SOURCE_PRESTATE_DRIFT'; END IF;
  IF EXISTS(SELECT 1 FROM lf_ops.nucleo_familias f
    WHERE NOT EXISTS(SELECT 1 FROM jsonb_array_elements(j->'familias') x
      WHERE x->>'codigo'=f.codigo AND x->>'tipo'=f.tipo))
  THEN RAISE EXCEPTION 'F4_CODEGEN_FAMILY_MISMATCH'; END IF;
  IF EXISTS(SELECT 1 FROM lf_ops.f0_valores_vocabulario_v1 e
    WHERE NOT EXISTS(SELECT 1 FROM jsonb_array_elements(j->'enums') x
      WHERE x->>'hecho'=e.hecho AND x->'valores' @> to_jsonb(e.valor)))
  THEN RAISE EXCEPTION 'F4_CODEGEN_ENUM_MISMATCH'; END IF;
  IF has_function_privilege('anon','lf_ops.f4_tipos_catalogo_v1()','EXECUTE')
    OR has_function_privilege('authenticated','lf_ops.f4_tipos_catalogo_v1()','EXECUTE')
    OR NOT has_function_privilege('service_role','lf_ops.f4_tipos_catalogo_v1()','EXECUTE')
  THEN RAISE EXCEPTION 'F4_CODEGEN_ACCESS_DRIFT'; END IF;
  RAISE NOTICE 'F4_CODEGEN_PASS 64 familias, 25 listas, 94 valores, permisos privados, sólo lectura';
END $verify$;
COMMIT;

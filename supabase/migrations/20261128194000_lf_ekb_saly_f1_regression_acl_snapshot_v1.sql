-- SALY F1/F3-A regression: PG17 baseline ACL snapshot drift and correction.
BEGIN;

INSERT INTO transversal.error_knowledge
(codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,frecuencia,lote_origen,estado,evidencia,lifecycle_phase,consumer_role,root_cause_family,detectability,source_context,source_ref)
VALUES
(
 'SALY-F1-PG17-WIRE-ACL-SNAPSHOT-DRIFT-20261128-001',
 'TESTING',
 'Snapshot PG17 omitía ACL de creative_native_render_wire_v1',
 'La regresión R5 detectó que el baseline PG17 y, por herencia, las lanes F1 y F1+F3-A exponían proacl=NULL para creative_native_render_wire_v1, mientras producción tenía {postgres=X/postgres}. Owner postgres, SECURITY DEFINER y pg_get_functiondef md5 sí coincidían. La diferencia era del sustrato CI, no un cambio de F1/F3-A en producción.',
 'El snapshot baseline recreó la función pero no reprodujo el REVOKE de EXECUTE a PUBLIC. En PostgreSQL, CREATE FUNCTION deja ACL implícita representada como NULL; por eso aplicar F1 sobre ese baseline conservaba una autoridad distinta de producción aunque el md5 de pg_get_functiondef fuera idéntico.',
 'PG17_BASELINE_FUNCTION_ACL_SNAPSHOT_DRIFT',
 'Al construir baselines PG17 de funciones SECURITY DEFINER, capturar y reproducir como conjunto indivisible: pg_get_userbyid(proowner), prosecdef, proacl y md5(pg_get_functiondef). No aceptar proacl=NULL como equivalente a {postgres=X/postgres}; ejecutar una prueba R5 baseline/candidato contra el readback actual de producción antes de declarar regresión verde.',
 'PR #4859: run 46182022620 / job 141093529086 detectó R5 FAIL con candidate=NULL|postgres|true|2915c3827aece1095bb9e9913a7c2010. Se añadió REVOKE ALL ... creative_native_render_wire_v1(uuid,bigint,text) FROM PUBLIC al baseline. En HEAD 406b8656a28572e337b1e32e47d44d48e7444ed7, run 46182129218 / job 141093868828 pasó R5 con baseline_acl=candidate_acl=f3a_acl=postgres=X/postgres y R1-R5 PASS.',
 'HIGH',
 1,
 'SALY_CREATIVE_F1_F3A_REAL_REGRESSION_20261128',
 'ACTIVO',
 'Evidencia no nula: producción read-only 28/11/2026: wire owner=postgres, SECURITY DEFINER=true, proacl=postgres=X/postgres, md5=2915c3827aece1095bb9e9913a7c2010. CI previo: run 46182022620 R5 candidate=NULL. CI corregido: run 46182129218 R5 baseline/candidate/f3a=postgres=X/postgres. PR #4859 merge 7608490c2169a383ca819443282c7c04ada324e2.',
 'DESIGN',
 ARRAY['CLAUDE_NATIVE','PROGRAMADOR'],
 'R2_NO_VE',
 'PROCESS_DEPENDENT',
 'SALY Fabrica Digital F1/F3-A regression',
 'https://github.com/cristhianlujan/claude-persona-lf-patch/pull/4859'
)
ON CONFLICT (codigo) DO NOTHING;

DO $qa$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.lf_error_knowledge
    WHERE codigo='SALY-F1-PG17-WIRE-ACL-SNAPSHOT-DRIFT-20261128-001'
      AND evidencia IS NOT NULL
      AND evidencia LIKE '%46182022620%'
      AND evidencia LIKE '%46182129218%'
      AND prevencion LIKE '%proacl=NULL%'
      AND validacion LIKE '%baseline_acl=candidate_acl=f3a_acl=postgres=X/postgres%'
  ) THEN
    RAISE EXCEPTION 'SALY_F1_PG17_WIRE_ACL_EKB_READBACK_MISSING';
  END IF;
END
$qa$;

COMMIT;

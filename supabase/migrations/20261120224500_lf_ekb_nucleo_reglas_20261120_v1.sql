-- EKB del núcleo de reglas, 2026-11-20: 5 aprendizajes del día. Solo registro en EKB, sin cambios de código ni de runtime.
BEGIN;
DO $ekb$
DECLARE
 v_src text := 'supabase/migrations/20261120224500_lf_ekb_nucleo_reglas_20261120_v1.sql';
 v_codes text[] := ARRAY[
   'LF-GH-PR-CREATE-GRAPHQL-403-20261120-001',
   'LF-LOCAL-PG-STOPS-BETWEEN-CYCLES-20261120-001',
   'LF-NUCLEO-TREE-LEVEL-TRIGGER-CHILDREN-20261120-001',
   'LF-NUCLEO-TREE-COPIED-SCREEN-CODE-20261120-001',
   'LF-RLS-REGLAS-VERSIONES-DISABLED-20261120-001']::text[];
BEGIN
 IF EXISTS (SELECT 1 FROM public.lf_error_knowledge WHERE codigo = ANY(v_codes)) THEN
   RAISE EXCEPTION 'LF_EKB_NUCLEO_20261120_CODE_ALREADY_EXISTS';
 END IF;
 INSERT INTO public.lf_error_knowledge(
  id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,frecuencia,
  primera_vez,ultima_vez,lote_origen,pr,estado,evidencia,lifecycle_phase,consumer_role,root_cause_family,
  detectability,source_context,source_ref,created_at,updated_at)
 VALUES
 (gen_random_uuid(),'LF-GH-PR-CREATE-GRAPHQL-403-20261120-001','DevOps/CI',
  'gh pr create falla con HTTP 403: GraphQL no disponible en sesiones de agente',
  'Al abrir el PR #4458 con gh pr create la CLI usó GraphQL y recibió 403 (GraphQL no disponible desde sesiones Claude Code).',
  'gh pr create usa la API GraphQL; la sesión solo admite REST.',
  'TOOL_API_SURFACE_ASSUMPTION',
  'Abrir PR con gh api repos/{owner}/{repo}/pulls (REST) y etiquetar con gh api .../issues/{n}/labels.',
  'PR #4458, #4459 y #4460 abiertos por REST y fusionados por el Train.',
  'LOW',1,clock_timestamp(),clock_timestamp(),'LF_NUCLEO_REGLAS_20261120','#4458','RESUELTO',
  'Salida literal de gh: HTTP 403 GraphQL is not available from Claude Code sessions',
  'CI_GOVERNANCE',ARRAY['CLAUDE_NATIVE']::text[],'R1_NO_SABE','LOUD_EARLY',
  'Núcleo de reglas F0, 2026-11-20',v_src,clock_timestamp(),clock_timestamp()),
 (gen_random_uuid(),'LF-LOCAL-PG-STOPS-BETWEEN-CYCLES-20261120-001','Testing',
  'Postgres local de pruebas se detiene entre ciclos y la prueba parece fallar',
  'En el ciclo de las 17:12 las pruebas locales devolvieron "Connection refused" y los rechazos aparecían como NO RECHAZADA; el servidor se había detenido entre turnos.',
  'Procesos en segundo plano del sandbox se detienen al terminar el turno.',
  'TEST_ENVIRONMENT_NOT_ASSERTED',
  'Levantar el servidor con un script idempotente antes de cada prueba y abortar si no responde (no interpretar conexión fallida como resultado).',
  'Script pgup.sh; pruebas repetidas con 7/7 rechazos reales.',
  'LOW',1,clock_timestamp(),clock_timestamp(),'LF_NUCLEO_REGLAS_20261120','#4459','RESUELTO',
  'psql: connection to server on socket failed: Connection refused',
  'TEST',ARRAY['CLAUDE_NATIVE']::text[],'R2_NO_VE','PROCESS_DEPENDENT',
  'Núcleo de reglas F0, 2026-11-20',v_src,clock_timestamp(),clock_timestamp()),
 (gen_random_uuid(),'LF-NUCLEO-TREE-LEVEL-TRIGGER-CHILDREN-20261120-001','DB_GOVERNANCE',
  'Trigger de jerarquía validaba solo el padre; cambiar el nivel de un nodo invalidaba a sus hijos',
  'En lf_ops.nucleo_nodos, cambiar B2B de AMBITO a MODULO dejó 6 hijos MODULO bajo un MODULO sin error.',
  'La validación de jerarquía miraba hacia arriba (padre) y no hacia abajo (hijos) en UPDATE.',
  'HIERARCHY_INVARIANT_ONE_DIRECTION',
  'Toda invariante de jerarquía se valida en ambos sentidos en UPDATE, con una prueba negativa de cambio de nivel de un nodo con hijos.',
  'Postgres local: antes 6 hijos inválidos; después NUCLEO_NODO_NIVEL_INVALIDO; 7/7 rechazos. Fusionado en PR #4459.',
  'MEDIUM',1,clock_timestamp(),clock_timestamp(),'LF_NUCLEO_REGLAS_20261120','#4459','RESUELTO',
  'Prueba local antes de publicar el PR',
  'CONSTRUCTION',ARRAY['CLAUDE_NATIVE','PROGRAMADOR']::text[],'R4_NO_CUESTIONA','SILENT',
  'Núcleo de reglas F0, 2026-11-20',v_src,clock_timestamp(),clock_timestamp()),
 (gen_random_uuid(),'LF-NUCLEO-TREE-COPIED-SCREEN-CODE-20261120-001','DB_GOVERNANCE',
  'Nodos de pantalla copiaban el código de la pantalla (relación duplicada)',
  'lf_ops.nucleo_nodos usaba como código del nodo el código de lf_ops.pantallas; un renombre dejaría el árbol desalineado.',
  'Se copió un dato derivable en vez de referenciarlo (resguardo B14 no revisado como lista antes del PR #4459).',
  'DERIVABLE_RELATION_COPIED',
  'Nodos de pantalla por id estable (PANTALLA-<id>), constraint que impide la copia y vista con el código vigente; correr la lista de revisión de resguardos antes de cada PR.',
  'PR #4460: 53/53 por id, 53 etiquetas leídas en vivo, renombre reflejado en la vista, copia rechazada.',
  'MEDIUM',1,clock_timestamp(),clock_timestamp(),'LF_NUCLEO_REGLAS_20261120','#4460','RESUELTO',
  'Detectado al revisar los PR contra LF_resguardos_construccion.md',
  'CONSTRUCTION',ARRAY['CLAUDE_NATIVE','PROGRAMADOR']::text[],'R5_EROSION_PROCESO','SILENT',
  'Núcleo de reglas F0, 2026-11-20',v_src,clock_timestamp(),clock_timestamp()),
 (gen_random_uuid(),'LF-RLS-REGLAS-VERSIONES-DISABLED-20261120-001','DATABASE_SECURITY',
  'lf_ops.reglas_versiones tiene RLS desactivado, a diferencia de lf_ops.reglas',
  'Medido el 2026-11-20: reglas y reglas_pantallas tienen RLS y deny_direct_client_access; reglas_versiones no tiene RLS ni política.',
  'La migración del historial (20261119040000) no replicó la convención de acceso de la tabla de reglas.',
  'ACCESS_CONVENTION_NOT_REPLICATED',
  'Toda tabla nueva en lf_ops replica RLS + deny_direct_client_access + REVOKE a anon/authenticated; agregar control en CI.',
  'Pendiente: PR de corrección y prueba negativa de acceso anónimo.',
  'MEDIUM',1,clock_timestamp(),clock_timestamp(),'LF_NUCLEO_REGLAS_20261120',NULL,'ACTIVO',
  'SELECT relrowsecurity en pg_class (solo lectura)',
  'DATABASE_SECURITY_ASSURANCE',ARRAY['CLAUDE_NATIVE','PROGRAMADOR']::text[],'R5_EROSION_PROCESO','SILENT',
  'Núcleo de reglas F0, 2026-11-20',v_src,clock_timestamp(),clock_timestamp());
END $ekb$;
COMMIT;

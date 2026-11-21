-- EKB del núcleo de reglas, 2026-11-21 (instancia SALY): 2 registros. Solo EKB.
BEGIN;
DO $ekb$
DECLARE v_src text := 'supabase/migrations/20261121015000_lf_ekb_nucleo_reglas_20261121c_v1.sql';
BEGIN
 IF EXISTS (SELECT 1 FROM public.lf_error_knowledge WHERE codigo IN ('LF-NUCLEO-ENGINE-PRODUCT-CONSTANTS-20261121-001','LF-TRAIN-POLL-LATEST-RUN-MISSES-OWN-20261121-001')) THEN
   RAISE EXCEPTION 'LF_EKB_NUCLEO_20261121C_CODE_ALREADY_EXISTS';
 END IF;
 INSERT INTO public.lf_error_knowledge(
  id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,frecuencia,
  primera_vez,ultima_vez,lote_origen,pr,estado,evidencia,lifecycle_phase,consumer_role,root_cause_family,
  detectability,source_context,source_ref,created_at,updated_at)
 VALUES (gen_random_uuid(),'LF-NUCLEO-ENGINE-PRODUCT-CONSTANTS-20261121-001','ARCHITECTURE_GOVERNANCE','Motor del núcleo con valores y datos de LF que impedían reutilizarlo en SALY','Al preparar la instancia SALY (un motor, una instancia por producto) se encontró que el control 19 tenía escritos los ámbitos de LF (B2B, CLIENTE, BACKEND) y que las 65 autopruebas dependían de datos de LF (familia RATE_LIMIT, autoridad Q01, parámetros AUTH, pantallas B2B).','El motor y sus pruebas se construyeron con una sola instancia a la vista; los datos de prueba se tomaron del catálogo real en vez de crearse.','ENGINE_COUPLED_TO_INSTANCE_DATA','Todo valor de producto del motor va en la configuración de la instancia; las autopruebas crean sus propios datos dentro de la subtransacción; una prueba conjunta verifica paridad de código y tablas entre instancias.','PR #4483 (motor independiente: 65/65 pruebas, 77/77 mutaciones cubiertas) y PR #4484 (instancia SALY: 65/65 en SALY y LF, conjunto 5/5, 5 divergencias detectadas).','MEDIUM',1,
  clock_timestamp(),clock_timestamp(),'LF_NUCLEO_REGLAS_20261121','#4484','RESUELTO','Preparación de la instancia SALY',
  'DESIGN',ARRAY['CLAUDE_NATIVE','PROGRAMADOR']::text[],'R2_NO_VE','LOUD_EARLY',
  'Núcleo de reglas, instancia SALY, 2026-11-21',v_src,clock_timestamp(),clock_timestamp());
 INSERT INTO public.lf_error_knowledge(
  id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,frecuencia,
  primera_vez,ultima_vez,lote_origen,pr,estado,evidencia,lifecycle_phase,consumer_role,root_cause_family,
  detectability,source_context,source_ref,created_at,updated_at)
 VALUES (gen_random_uuid(),'LF-TRAIN-POLL-LATEST-RUN-MISSES-OWN-20261121-001','DevOps/CI','La espera del Train miraba solo la última corrida y no veía la propia','Para esperar la fusión se consultaba la última corrida del Merge Train; otra rama (SALY) encoló una corrida justo después y la espera siguió hasta su límite aunque el PR propio ya estaba fusionado.','Se identificó la corrida por posición (la más reciente) y no por el PR o la rama propios.','POLL_BY_POSITION_NOT_IDENTITY','Esperar por el estado merged del propio PR, o filtrar las corridas por rama o por título del PR; nunca por la posición en la lista.','PR #4484 fusionado mientras la espera seguía; se detuvo la espera y se verificó por el PR.','LOW',1,
  clock_timestamp(),clock_timestamp(),'LF_NUCLEO_REGLAS_20261121','#4484','RESUELTO','Seguimiento del Train del PR #4484',
  'DESIGN',ARRAY['CLAUDE_NATIVE','PROGRAMADOR']::text[],'R2_NO_VE','PROCESS_DEPENDENT',
  'Núcleo de reglas, instancia SALY, 2026-11-21',v_src,clock_timestamp(),clock_timestamp());
END $ekb$;
COMMIT;

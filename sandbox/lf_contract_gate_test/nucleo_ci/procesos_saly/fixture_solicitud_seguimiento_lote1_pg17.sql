-- Lote 1: SOLO PG17 aislado en CI; no usar sobre Supabase.
-- Fuente: extracción SALY 2026-11-23 13:08, corrección 13:20.
-- No contiene ramas por canal ni estado visible INCIDENCIA.
-- La nota del paso motor guarda REFERENCIA_NODO=MOTOR_ABONOS porque
-- base_candidata.sql NO incluye columna/clave foranea paso -> nodo.
-- Ninguna regla de seleccion provisional se materializa aqui.
\set ON_ERROR_STOP on
BEGIN;
DO $precheck$
BEGIN
 IF current_setting('server_version_num')::integer / 10000 <> 17
    OR current_database() NOT LIKE 'saly_test_%'
    OR inet_server_addr() IS DISTINCT FROM '127.0.0.1'::inet THEN
   RAISE EXCEPTION 'LOTE1_SOLO_PG17_AISLADO';
 END IF;
END $precheck$;

CREATE SCHEMA saly;
DO $roles$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon NOLOGIN; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='service_role') THEN CREATE ROLE service_role NOLOGIN; END IF;
END $roles$;
\ir stub_nucleo_nodos.sql
\ir base_candidata.sql

DO $qa$
DECLARE
 v_proceso bigint;
 v_paso bigint;
 rec record;
 e record;
 v_codigo text;
 v_esperados integer;
 v_obtenidos integer;
 v_error text;
BEGIN
 -- Los tres MODULO solo se insertan en el fixture desechable.
 -- MOTOR_ABONOS ya existe en Supabase real; NO se vuelve a crear allí.
 -- Los otros dos MODULO solo se simulan porque el candidato exige nivel MODULO.
 INSERT INTO saly.nucleo_nodos(codigo,padre,nivel,nota) VALUES
  ('GLOBAL',NULL,'GLOBAL','Raiz sintética PG17'),
  ('ADELANTO','GLOBAL','AMBITO','Ambito sintetico PG17'),
  ('MOTOR_ABONOS','ADELANTO','MODULO','Motor unico y generico, sin nodos por proveedor'),
  ('MOD_SOLICITUD_ADELANTO','ADELANTO','MODULO','Solo fixture PG17: ubicar Solicitud'),
  ('MOD_SEGUIMIENTO_ADELANTO','ADELANTO','MODULO','Solo fixture PG17: ubicar Seguimiento');

 INSERT INTO saly.procesos(codigo,nodo_codigo)
 VALUES ('SOLICITUD_ADELANTO','MOD_SOLICITUD_ADELANTO'),
        ('SEGUIMIENTO_ADELANTO','MOD_SEGUIMIENTO_ADELANTO');
 INSERT INTO saly.procesos_versiones(proceso_id,version,titulo,motivo,origen_ref,creado_por)
 SELECT id,1,CASE codigo WHEN 'SOLICITUD_ADELANTO' THEN 'Solicitud de adelanto'
                              ELSE 'Seguimiento del adelanto' END,
 'Fixture documental del lote 1',
 'SALY-PLANEAMIENTO-20261123-1308-1320','QA_PG17'
 FROM saly.procesos;

 FOR rec IN SELECT * FROM (VALUES
('SOLICITUD_ADELANTO',1,'S01_HOME','Ingresar a Home y solicitar adelanto','PANTALLA_DIBUJADA','SALY_HOME_IPHONE16PRO_REWARDS_SORTEOS_V3_APROBADA.png','Usuario ingresa al Home y pulsa Solicitar adelanto.'),
('SOLICITUD_ADELANTO',2,'S02_MONTO','Elegir monto y revisar recomendaciones','PANTALLA_DIBUJADA','SALY_SOLICITAR_ADELANTO_INTELIGENTE_v1.0.png','Revisar sugerencia o ingresar monto manual; reglas de recomendaciones no implementadas por este fixture.'),
('SOLICITUD_ADELANTO',3,'S03_OTP','Revisar resumen y confirmar con OTP','PANTALLA_DIBUJADA','SALY_OTP_CONFIRMACION_IGV_v1.1.png','Resumen incluye comision e IGV; OTP por correo con SMS alternativo.'),
('SOLICITUD_ADELANTO',4,'S04_SQS_ENCOLAR','Enviar orden de abono a SQS','INTERNO','SIN_PANTALLA','Encolar orden para procesamiento; interfaz SQS VACÍO; sin llamada real a AWS.'),
('SOLICITUD_ADELANTO',5,'S05_CONFIRMACION','Mostrar confirmacion de solicitud','POR_CONSTRUIR','VACÍO','Pantalla de confirmacion POR CONSTRUIR; cinco minutos son margen tecnico de cola, no espera de negocio.'),
('SOLICITUD_ADELANTO',6,'S06_SQS_PROCESAR','Ejecutar procesamiento posterior de cola','INTERNO','SIN_PANTALLA','Worker consume orden SQS; ejecucion de cola no definida tecnicamente.'),
('SOLICITUD_ADELANTO',7,'S07_MOTOR_ABONOS','El Motor de Abonos elige el canal y ejecuta el abono','INTERNO','SIN_PANTALLA','REFERENCIA_NODO=MOTOR_ABONOS. Canal configurable, sin ramas ni etiquetas por proveedor. VACÍO: elegibilidad, pricing/vigencia, regla de seleccion.'),
('SOLICITUD_ADELANTO',8,'S08_CONTINGENCIA','Derivar a manual como ultimo recurso si un canal falla','INTERNO','SIN_PANTALLA','Si falla un canal, se deriva a manual como ultimo recurso. VACÍO: numero y criterios de reintentos.'),
('SOLICITUD_ADELANTO',9,'S09_NOTIFICAR','Enviar estado por push y correo','INTERNO','SIN_PANTALLA','Notificacion posterior al procesamiento; contratos y plantillas VACÍO.'),
('SOLICITUD_ADELANTO',10,'S10_ACTUALIZAR','Actualizar estado consultable en Seguimiento','INTERNO','SIN_PANTALLA','Salida hacia proceso SEGUIMIENTO_ADELANTO; representacion de estado en UI depende de Seguimiento.'),
('SEGUIMIENTO_ADELANTO',1,'G01_CONSULTAR','Consultar el estado de la solicitud','PANTALLA_DIBUJADA','SALY_SEGUIMIENTO_MINIMAL_v1.5.png','Consulta de solicitud confirmada; no existe estado Incidencia visible para el empleado.'),
('SEGUIMIENTO_ADELANTO',2,'G02_EN_PROCESO','Mostrar En proceso durante la ventana tecnica SQS','PANTALLA_DIBUJADA','SALY_SEGUIMIENTO_MINIMAL_v1.5.png','En proceso durante procesamiento de cola; abono inmediato de negocio.'),
('SEGUIMIENTO_ADELANTO',3,'G03_MOTOR','El Motor de Abonos procesa por canal configurable','INTERNO','SIN_PANTALLA','REFERENCIA_NODO=MOTOR_ABONOS. No fijar Niubiz/Manual ni ramas por canal.'),
('SEGUIMIENTO_ADELANTO',4,'G04_CONTINGENCIA','Derivar a manual tras falla de canal','INTERNO','SIN_PANTALLA','La vista del empleado permanece En proceso; VACÍO reintentos antes del recurso manual.'),
('SEGUIMIENTO_ADELANTO',5,'G05_MANUAL_PENDIENTE','Mostrar En proceso con abono manual programado','POR_CONSTRUIR','VACÍO','VACÍO: pantalla En proceso para manual programado, reubicacion de v1.4; no crear estado Incidencia.'),
('SEGUIMIENTO_ADELANTO',6,'G06_HORARIOS','Mostrar horario configurable del abono manual','POR_CONSTRUIR','VACÍO','VACÍO: tabla de horarios, vigencia y pantalla de linea temporal; no fijar hora en interfaz.'),
('SEGUIMIENTO_ADELANTO',7,'G07_RESULTADO','Actualizar consulta y emitir notificaciones de estado','INTERNO','SIN_PANTALLA','Push y correo tras procesamiento y estado consultable; VACÍO catalogo tecnico y pantalla final independiente.')
 ) AS pasos(proceso_codigo,orden,codigo,titulo,tipo,pantalla,detalle)
 ORDER BY proceso_codigo,orden
 LOOP
  SELECT id INTO STRICT v_proceso FROM saly.procesos WHERE codigo=rec.proceso_codigo;
  INSERT INTO saly.procesos_pasos(proceso_id,codigo)
  VALUES (v_proceso,rec.codigo) RETURNING paso_id INTO v_paso;
  INSERT INTO saly.procesos_pasos_versiones(proceso_id,paso_id,version,titulo,descripcion)
  VALUES (v_proceso,v_paso,1,rec.titulo,
       format('TIPO=%s | PANTALLA=%s | %s',rec.tipo,rec.pantalla,rec.detalle));
  INSERT INTO saly.procesos_version_pasos
  (proceso_id,proceso_version,paso_id,paso_version,orden,es_inicio,es_fin)
  VALUES(v_proceso,1,v_paso,1,rec.orden,rec.orden=1,
         (rec.proceso_codigo='SOLICITUD_ADELANTO' AND rec.orden=10)
         OR (rec.proceso_codigo='SEGUIMIENTO_ADELANTO' AND rec.orden=7));
 END LOOP;

 -- Transiciones lineales SOLO de fixture. Solicitúud queda incompleta a proposito
 -- (falta la arista 9->10) para comprobar el rechazo del SELLADO.
 FOR e IN
 SELECT a.proceso_id,a.proceso_version,a.paso_id desde,b.paso_id hacia
 FROM saly.procesos_version_pasos a
 JOIN saly.procesos_version_pasos b ON
  (b.proceso_id,b.proceso_version,b.orden)=(a.proceso_id,a.proceso_version,a.orden+1)
 JOIN saly.procesos p ON p.id=a.proceso_id
 WHERE NOT(p.codigo='SOLICITUD_ADELANTO' AND a.orden=9)
 ORDER BY a.proceso_id,a.orden
 LOOP
  INSERT INTO saly.procesos_version_transiciones
   (proceso_id,proceso_version,desde_paso,hacia_paso,ruta)
  VALUES(e.proceso_id,e.proceso_version,e.desde,e.hacia,'CONTINUAR');
 END LOOP;

 SELECT count(*) INTO v_obtenidos FROM saly.procesos;
 IF v_obtenidos<>2 THEN RAISE EXCEPTION 'LOTE1_CONTEO_PROCESOS %',v_obtenidos; END IF;
 RAISE NOTICE 'LOTE1_PROCESOS_PASS 2/2';

 SELECT count(*) INTO v_obtenidos FROM saly.procesos_versiones
 WHERE version=1 AND estado='BORRADOR';
 IF v_obtenidos<>2 THEN RAISE EXCEPTION 'LOTE1_CONTEO_VERSIONES %',v_obtenidos; END IF;
 RAISE NOTICE 'LOTE1_VERSIONES_PASS 2/2 BORRADOR';

 SELECT count(*) INTO v_obtenidos FROM saly.procesos_pasos;
 IF v_obtenidos<>17 THEN RAISE EXCEPTION 'LOTE1_CONTEO_PASOS %',v_obtenidos; END IF;
 SELECT count(*) INTO v_obtenidos FROM saly.procesos_pasos_versiones;
 IF v_obtenidos<>17 THEN RAISE EXCEPTION 'LOTE1_CONTEO_DEFINICIONES %',v_obtenidos; END IF;
 SELECT count(*) INTO v_obtenidos FROM saly.procesos_version_pasos;
 IF v_obtenidos<>17 THEN RAISE EXCEPTION 'LOTE1_CONTEO_COMPOSICION %',v_obtenidos; END IF;
 IF (SELECT count(*) FROM saly.procesos_pasos p
     JOIN saly.procesos t ON t.id=p.proceso_id WHERE t.codigo='SOLICITUD_ADELANTO')<>10
 OR (SELECT count(*) FROM saly.procesos_pasos p
     JOIN saly.procesos t ON t.id=p.proceso_id WHERE t.codigo='SEGUIMIENTO_ADELANTO')<>7
 THEN RAISE EXCEPTION 'LOTE1_DISTRIBUCION_10_7_FALLIDA'; END IF;
 RAISE NOTICE 'LOTE1_PASOS_PASS 17/17 (Solicitud=10, Seguimiento=7)';

 SELECT count(*) INTO v_obtenidos FROM saly.procesos_pasos_versiones
 WHERE descripcion LIKE '%REFERENCIA_NODO=MOTOR_ABONOS%';
 IF v_obtenidos<>2 OR
 NOT EXISTS(SELECT 1 FROM saly.nucleo_nodos
   WHERE codigo='MOTOR_ABONOS' AND nivel='MODULO' AND padre='ADELANTO')
 THEN RAISE EXCEPTION 'LOTE1_MOTOR_REFERENCIA_NODO_FALLIDA'; END IF;
 IF EXISTS (SELECT 1 FROM saly.nucleo_nodos WHERE codigo IN ('NIUBIZ','LIGO','MANUAL','YAPE')) THEN
    RAISE EXCEPTION 'LOTE1_NODO_POR_CANAL_PROHIBIDO'; END IF;
 RAISE NOTICE 'LOTE1_MOTOR_NODO_PASS 1 MODULO, 2 referencias documentales, 0 nodos por canal';

 SELECT count(*) INTO v_obtenidos FROM saly.procesos_pasos_versiones
 WHERE descripcion LIKE '%TIPO=PANTALLA_DIBUJADA%';
 IF v_obtenidos<>5 THEN RAISE EXCEPTION 'LOTE1_TIPO_PANTALLA %',v_obtenidos; END IF;
 SELECT count(*) INTO v_obtenidos FROM saly.procesos_pasos_versiones
 WHERE descripcion LIKE '%TIPO=INTERNO%';
 IF v_obtenidos<>9 THEN RAISE EXCEPTION 'LOTE1_TIPO_INTERNO %',v_obtenidos; END IF;
 SELECT count(*) INTO v_obtenidos FROM saly.procesos_pasos_versiones
 WHERE descripcion LIKE '%TIPO=POR_CONSTRUIR%' AND descripcion LIKE '%VACÍO%';
 IF v_obtenidos<>3 THEN RAISE EXCEPTION 'LOTE1_TIPO_CONSTRUIR %',v_obtenidos; END IF;
 IF EXISTS (SELECT 1 FROM saly.procesos_pasos
            WHERE codigo ~* '(INCIDENCIA|NIUBIZ|LIGO|MANUAL|YAPE)') THEN
   RAISE EXCEPTION 'LOTE1_CANAL_COMO_PASO_O_ESTADO'; END IF;
 RAISE NOTICE 'LOTE1_TIPOS_PASS pantallas=5 internos=9 por_construir=3; SIN INCIDENCIA';

 SELECT count(*) INTO v_obtenidos FROM saly.procesos_version_transiciones;
 IF v_obtenidos<>14 THEN RAISE EXCEPTION 'LOTE1_TRANSICIONES_14 %',v_obtenidos; END IF;
 RAISE NOTICE 'LOTE1_TRANSICIONES_PASS 14/14 (una arista omitida intencionalmente)';

 -- Caso negativo: sellar la version con paso final no alcanzable debe FALLAR.
 SELECT id INTO STRICT v_proceso FROM saly.procesos WHERE codigo='SOLICITUD_ADELANTO';
 BEGIN
  UPDATE saly.procesos_versiones SET estado='SELLADA'
   WHERE proceso_id=v_proceso AND version=1;
  RAISE EXCEPTION 'LOTE1_ERROR: SELLADO_INCOMPLETO_ACEPTADO';
 EXCEPTION WHEN SQLSTATE '23514' THEN
  GET STACKED DIAGNOSTICS v_error=MESSAGE_TEXT;
  IF v_error IS DISTINCT FROM 'SALY_PROCESO_FLUJO_INCOMPLETO' THEN
    RAISE EXCEPTION 'LOTE1_ERROR_NEGATIVO_NO_ES_EL_ESPERADO: %',v_error;
  END IF;
  RAISE NOTICE 'LOTE1_SELLADO_INCOMPLETO_RECHAZADO_PASS SQLSTATE=23514 %',v_error;
 END;
 IF EXISTS(SELECT 1 FROM saly.procesos_versiones WHERE estado='SELLADA') THEN
   RAISE EXCEPTION 'LOTE1_ERROR_VERSION_SELLADA';
 END IF;
 RAISE NOTICE 'LOTE1_CANDIDATO_SIN_PUBLICAR_PASS 2 BORRADOR';
END $qa$;
ROLLBACK;
DO $final$
BEGIN
 IF to_regclass('saly.procesos') IS NOT NULL
    OR to_regclass('saly.nucleo_nodos') IS NOT NULL THEN
  RAISE EXCEPTION 'LOTE1_ROLLBACK_RESIDUO';
 END IF;
 RAISE NOTICE 'LOTE1_ROLLBACK_PASS 0 tablas persistentes';
END $final$;

-- SALY / ADELANTO: identidad del modulo MOTOR DE ABONOS.
-- Decisión funcional 2026-11-23: un MODULO, no un paso de Solicitud/Seguimiento.
-- Alcance: UN nodo de nivel MODULO, sin reglas de selección, proveedores, tarifas ni escrituras operativas.
-- Ruta de ejecución: exclusivamente PR -> Merge Train (ready-to-merge).
BEGIN;
DO $saly_motor_abonos$
BEGIN
 IF NOT EXISTS (
   SELECT 1 FROM saly.nucleo_nodos
   WHERE codigo='ADELANTO' AND nivel='AMBITO' AND padre='GLOBAL'
 ) THEN
   RAISE EXCEPTION 'SALY_MOTOR_ABONOS_AMBITO_ADELANTO_NO_VALIDADO';
 END IF;

 IF EXISTS (
   SELECT 1 FROM saly.nucleo_nodos
   WHERE codigo='MOTOR_ABONOS'
     AND (nivel IS DISTINCT FROM 'MODULO'
       OR padre IS DISTINCT FROM 'ADELANTO'
       OR pantalla_id IS NOT NULL)
 ) THEN
   RAISE EXCEPTION 'SALY_MOTOR_ABONOS_NODO_CONFLICTO_EXISTENTE';
 END IF;

 INSERT INTO saly.nucleo_nodos (codigo,padre,nivel,pantalla_id,nota)
 VALUES (
   'MOTOR_ABONOS','ADELANTO','MODULO',NULL,
   'Módulo Motor de Abonos (SALY). Procesos: Configuración de Canales, Gestión de Empresas, Configurar Empresa y Selección de Canal al Abonar. Fuente: https://kuntur1.my.canva.site/configuracion-abonos-tsy y definición funcional 2026-11-23. No implica motor implementado.'
 )
 ON CONFLICT (codigo) DO NOTHING;

 IF NOT EXISTS (
   SELECT 1 FROM saly.nucleo_nodos
   WHERE codigo='MOTOR_ABONOS' AND nivel='MODULO'
     AND padre='ADELANTO' AND pantalla_id IS NULL
 ) THEN
   RAISE EXCEPTION 'SALY_MOTOR_ABONOS_NODO_READBACK_FALLIDO';
 END IF;

 RAISE NOTICE 'SALY_MOTOR_ABONOS_MODULO_PASS';
END $saly_motor_abonos$;
COMMIT;

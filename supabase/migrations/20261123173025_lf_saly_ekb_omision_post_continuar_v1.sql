-- SALY Planeamiento: registro de omision de fuente historica en inventario funcional.
-- Solo EKB. La migracion no modifica pantallas, reglas, procesos ni runtime.
INSERT INTO transversal.error_knowledge (
 codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
 severidad,frecuencia,lote_origen,estado,evidencia,lifecycle_phase,
 consumer_role,root_cause_family,detectability,source_context,source_ref
) VALUES (
 'SALY-PROCESOS-POST-CONTINUAR-OTP-OMITIDO-20261123-001',
 'SALY_PROCESOS_HALLAZGO',
 'Inventario B2C omitio flujo OTP y confirmacion posterior a Continuar',
 'La primera tabla del Nucleo de Procesos SALY reporto como no definida la secuencia despues de Continuar en Solicitar adelanto. Al revisar los chats del 13/11/2026 se recupero: OTP por correo, SMS alternativo, resumen con comision e impuestos, Verificar y confirmar y luego Seguimiento. No se dispone de detalle independiente de persistencia/registro o desembolso.',
 'El inventario inicial se construyo con recuperacion incompleta de las fuentes historicas de pantallas y decisiones.',
 'Sintetizar historial parcial como ausencia de definicion produce un falso VACIO.',
 'Contrastar las afirmaciones de ausencia con busqueda focalizada en historial por pantalla, fecha y acciones antes del cierre documental.',
 'La extraccion del proceso distingue Continuar, OTP correo/SMS, resumen con impuesto, Verificar y confirmar y Seguimiento, y marca VACIO el registro/desembolso independiente.',
 'LOW',1,'SALY_PLANEAMIENTO_EXTRACCION_B2C_20261123','ACTIVO',
 'Chat SALY Planeamiento 13/11/2026 (decision sobre OTP por correo/SMS y pantalla integrada); tabla de procesos del intercambio Claude/GPT 23/11.',
 'DESIGN',ARRAY['PROGRAMADOR','PRODUCTO'],
 'R2_NO_VE','PROCESS_DEPENDENT',
 'SALY Planeamiento, extraccion de seis procesos B2C',
 'SALY_CHAT_PLANEAMIENTO_20261113_OTP'
)
ON CONFLICT (codigo) DO UPDATE SET
 frecuencia=transversal.error_knowledge.frecuencia+1,
 ultima_vez=now(),
 updated_at=now();
DO $check$
BEGIN
 IF NOT EXISTS (
  SELECT 1 FROM transversal.error_knowledge
  WHERE codigo='SALY-PROCESOS-POST-CONTINUAR-OTP-OMITIDO-20261123-001'
  AND estado='ACTIVO' AND frecuencia>=1
 ) THEN RAISE EXCEPTION 'SALY_EKB_OTP_HALLAZGO_NO_REGISTRADO'; END IF;
 RAISE NOTICE 'SALY_EKB_OTP_HALLAZGO_PASS';
END $check$;

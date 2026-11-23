-- SALY Procesos: dos hallazgos de diseño (Claude/GPT, 2026-11-23).
-- EKB exclusivamente. No crea nodos, no asigna canales ni modifica runtime.
-- Aplicacion unicamente por PR -> Merge Train.

INSERT INTO transversal.error_knowledge (
 codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
 severidad,frecuencia,lote_origen,estado,evidencia,lifecycle_phase,
 consumer_role,root_cause_family,detectability,source_context,source_ref
)
VALUES
(
 'SALY-PROCESOS-PANTALLA-CANAL-PENDIENTE-20261123-001',
 'SALY_PROCESOS_HALLAZGO',
 'Canal funcional sin confirmar para pantallas de fondeo y conciliación',
 'Las pantallas dibujadas Configuración de fondeo y Conciliación inteligente no tienen asignación B2B/ADM confirmada en el inventario funcional del Núcleo de Procesos SALY V1.1. No atribuir canal por inferencia.',
 'Decisión de asignación funcional de canal todavía no constatada en las fuentes revisadas.',
 'Pantalla diseñada sin relación con canal validado; riesgo de catalogación incorrecta.',
 'Conservar canal como PENDIENTE y vincularlo solo cuando exista decisión funcional verificable; no modificar pantallas.',
 'Verificar decisión funcional y contrato de pantalla antes de persistir asociación a canal.',
 'LOW',1,'SALY_PROCESOS_HANDOFF_20261123','ACTIVO',
 'Consulta de origen: Claude -> GPT, 2026-11-23 09:52 Lima, H1.',
 'DESIGN',ARRAY['PROGRAMADOR','PRODUCTO'],
 'UNCLASSIFIED_WITH_REASON','PROCESS_DEPENDENT',
 'Saly Planeamiento: auditoría de procesos y pantallas',
 'SALY_HANDOFF_20261123_0952_H1'
),
(
 'SALY-PROCESOS-MODULO-NODOS-AUSENTES-20261123-001',
 'SALY_PROCESOS_HALLAZGO',
 'Guard de Procesos exige MODULO sin nodos MODULO en el árbol SALY',
 'Al corte informado en la auditoría de Claude, saly.nucleo_nodos solo contiene GLOBAL y ADELANTO; no hay nodos MODULO. El guard del Núcleo de Procesos exige un nodo de nivel MODULO para ubicar un proceso. Es una dependencia de datos de catálogo, no autorización para crear nodos.',
 'El catálogo SALY aún no dispone de módulos funcionales registrados; guard de pertenencia ya requiere el nivel MODULO.',
 'Primer proceso no puede asociarse a módulo existente en SALY bajo los datos actuales.',
 'Registrar dependencia y exigir decisión de módulos antes de habilitar procesos; no inventar jerarquía.',
 'Comprobar niveles/nodos actuales de saly.nucleo_nodos y guard vigente de procesos con lectura, antes de resolver el hallazgo.',
 'MEDIUM',1,'SALY_PROCESOS_HANDOFF_20261123','ACTIVO',
 'Consulta de origen: Claude -> GPT, 2026-11-23 09:52 Lima, H2.',
 'DESIGN',ARRAY['PROGRAMADOR','PRODUCTO'],
 'UNCLASSIFIED_WITH_REASON','PROCESS_DEPENDENT',
 'Saly Planeamiento: auditoría del Núcleo de Procesos',
 'SALY_HANDOFF_20261123_0952_H2'
)
ON CONFLICT (codigo) DO UPDATE
 SET frecuencia=transversal.error_knowledge.frecuencia+1,
     ultima_vez=now(),
     updated_at=now();

DO $qa$
DECLARE n integer;
BEGIN
 SELECT count(*) INTO n
 FROM transversal.error_knowledge
 WHERE codigo IN (
  'SALY-PROCESOS-PANTALLA-CANAL-PENDIENTE-20261123-001',
  'SALY-PROCESOS-MODULO-NODOS-AUSENTES-20261123-001'
 );
 IF n<>2 THEN RAISE EXCEPTION 'SALY_EKB_HALLAZGOS_CONTEO_ESPERADO_2_OBTENIDO_%',n; END IF;
 IF EXISTS (
   SELECT 1 FROM transversal.error_knowledge
   WHERE codigo IN (
    'SALY-PROCESOS-PANTALLA-CANAL-PENDIENTE-20261123-001',
    'SALY-PROCESOS-MODULO-NODOS-AUSENTES-20261123-001'
   ) AND (frecuencia<1 OR estado IS DISTINCT FROM 'ACTIVO')
 ) THEN RAISE EXCEPTION 'SALY_EKB_HALLAZGOS_ESTADO_INVALIDO'; END IF;
 RAISE NOTICE 'SALY_EKB_HALLAZGOS_2_2_PASS';
END $qa$;

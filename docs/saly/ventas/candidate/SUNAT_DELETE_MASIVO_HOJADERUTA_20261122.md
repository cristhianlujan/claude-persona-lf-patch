# SALY — DELETE físico de SUNAT fuera de mercado objetivo

Estado: CANDIDATO. No ejecutado. Dependencia: PR #4621 (vista de elegibilidad) no fusionado.
Autorización de producto: Cristhian, solicitud explícita de DELETE masivo en SALY, 2026-11-22.

## Snapshot real (solo lectura)
- RUN original: `EXEC-SALY-SUNAT-PILOT-20261122-001`.
- Ingestas: 136 lotes x 1000 = 136000 registros.
- Elegibles: 5275 (NroTrab >= 50, ACTIVO + HABIDO en ambos padrones).
- Fuera del alcance comercial: 130725.
- Aún no hecho el DELETE: RUC 20100043905 y 20100028931 continúan.
- Dependencias FK: `saly.ventas_unidades_operativas` -> `ventas_hallazgos` ON DELETE RESTRICT. Al inspeccionar: 0 unidades.
- Operación RUN: `IN_PROGRESS`; descubrimiento: `EN_EJECUCION`; 343 lotes NOT_RUN.
- Restricción: `saly_l28_run_close_disabled` impide `estado='CERRADO'`; no inventar cierre. Estado `HOLD` es válido pero debe ser aplicado por operación gobernada.
- Writer originario comprueba `filas_reportadas`, payload hash y toda fila en replay: la purga exige **congelar/cancelar** el RUN y migrar el futuro hacia un manifiesto nuevo filtrado antes del primer DELETE.

## Lotes y puertas obligatorias (en orden)
1. Cerrar la admisión del viejo writer con cambio gobernado de `SUNAT_POLICY_V1.enabled=false`; llevar `saly.ventas_discovery_runs.estado` a `HOLD`; cancelar/sustituir `public.lf_operation_execution` por la ruta legítima y verificar `lease` vencido. No simular ni saltar la operación. El SQL de purga NO realiza estas transiciones.
2. Fusionar PR #4621 por Merge Train con PG17 positivo/negativo y readback real de vistas, para que exista la clasificación de mercado.
3. Fusionar PR de purga por Merge Train con una sola migración; ésta crea cola mínima (UUID+motivo, sin duplicar JSON) y funciones guardadas **sin ejecutarlas**.
4. Ejecutar `saly.ventas_sunat_purge_prepare_v1('EXEC-SALY-SUNAT-PILOT-20261122-001')` por el ejecutor gobernado con permisos autorizados. Esta etapa hace **un único escaneo JSON** y genera los UUID a retirar. Verificar cantidad contra baseline contemporánea.
5. Ejecutar `saly.ventas_sunat_purge_step_v1('EXEC-SALY-SUNAT-PILOT-20261122-001',1000)` por ciclos gobernados, una transacción de 1000 como máximo, comprobando `deleted` y `remaining` antes de continuar. Interrumpir con alertas de I/O, desvío de conteo o FK.
6. Readback final: cola `remaining=0`, conteo de empresas del RUN = baseline ELEGIBLE, RUC excluidos ausentes, fila de otro origen intacta, cantidad de batches y archivos/hashes de ingesta original conservados.
7. Validar que la siguiente ingesta usa un manifiesto NUEVO con umbral 50 y ambos estados; jamás reanudar los antiguos 479 lotes sobre datos podados. Actualizar los contratos de reconciliación para que la cola de purga explique el desfase entre `filas_reportadas` históricas y filas supervivientes.

## Riesgo alto de I/O
`DELETE` genera WAL, actividad sobre índices y tuplas muertas: **no libera de inmediato el espacio físico**. No usar `TRUNCATE`, `CASCADE`, `VACUUM FULL` ni `DELETE` sin límite. Evitar consultas de COUNT sobre JSON en cada lote. Consultar Disk IO Balance/IOPS en Supabase antes y durante la ventana de purga.

## Evidencia y cierre
No existe un canal de DML directo: el conector Supabase es READ_ONLY. Este documento y PR son candidatos, no prueba de ejecución. Los tests PG17 y la autorización del Router preceden al etiquetado `ready-to-merge`.

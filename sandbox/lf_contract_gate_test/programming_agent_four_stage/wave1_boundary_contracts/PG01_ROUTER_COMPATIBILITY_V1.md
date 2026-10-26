# PG01_ROUTER_COMPATIBILITY_V1

Fecha: 26-oct-2026. Evidencia local; sin admisión operativa.
Base integrada por merge normal: main `ce3a96ba7bf25cc8ef4b1142509a5a6c6399a267`. Historia anterior de #3135 preservada, sin conflictos. El documento y JSON del 24-oct son históricos; no recertifican esta base.

## Resultado y límites

PRODUCTO, PROGRAMACION y OPERACIONES son los tres canales de la política DEPLOYED_LF_V2 en fuente. GESTION_ACTIVOS_IA es transversal. Despliegue y mantenimiento técnico corresponden a PROGRAMACION y conservan su autorización independiente. No se modificó el Router ni se verificó su despliegue vivo.

La ejecución de la función canónica de 20261024133000_lf_router_product_context_resolution_v1.sql, seguida de los parches DO exactos 20261024170000, 20261024193000, 20261025000500 y 20261026145500 (#3165) de main, devuelve `paso=PROGRAMACION_PRECHECK_DEFINICION`. `PROGRAMACION_ADMISION_REQUERIDA` aparece solamente en `si_definicion_vigente`: no certifica una definición vigente ni ejecuta ese precheck. La fixture declara una intención sobre definición vigente, no aporta evidencia de currentness admitida. No se fabricó una salida distinta para satisfacer el escenario pedido.

`contrato_entrada_despues_precheck=PROGRAMMING_ENTRY_CONTRACT_V1` coincide con el schema_version del contrato exacto. El receptor valida el digest de ese archivo: `d2e347efe07a9971790f1a605f0b6ab93fa48a1608744330d1e49e59930d7fb8`. Los tres controles nuevos comprueban el selector dinámico, la lectura canónica previa de Producto y la igualdad exacta de la rama PROGRAMACION antes/después de esos parches. El Router no emite digest: hay identidad nominal y cotejo local, no binding criptográfico Router→receptor.

`upstream_requerido_despues_precheck=ANALYSIS_IMPLEMENTATION_PACKAGE_V1` es un requisito nominal. Sin ExpectedHandoff el receptor devuelve EXPECTED_HANDOFF_INVALID_OR_MISSING. Pero un snapshot estructural válido con handoff/currentness sintéticos puede obtener ACCEPT sin autenticar un envelope A9 ni la procedencia de un scope READY admitido. Esta brecha queda caracterizada, no corregida en esta tarea. Sin READY hay NO_READY_SCOPE; scope desconocido produce REQUESTED_SCOPE_NOT_READY_OR_UNKNOWN. Todos los permisos de ejecución permanecen falsos.

## Correspondencia de retornos

Esta tabla es una propuesta de proyección del futuro consumidor. Los retornos de decision_policy no son un dispatch ejecutado por lf_router_route_v1 en esta rama.

| Retorno de política Router | Códigos actuales del receptor | Evidencia y brecha |
|---|---|---|
| RETURN_TO_ANALYSIS_NO_CODE | EXPECTED_HANDOFF_INVALID_OR_MISSING; NO_READY_SCOPE; REQUESTED_SCOPE_NOT_READY_OR_UNKNOWN; CURRENTNESS_NOT_ADMISSIBLE | Casos router_v2_no_expected_handoff_blocks, router_v2_zero_ready_receiver_BLOCK, router_v2_unknown_scope_BLOCK, router_v2_stale_receiver_BLOCK. La ausencia de envelope/admisión A9 no tiene un código independiente. |
| BLOCK_NO_CODE | MATERIAL_PROJECTION_LOSS_OR_MISMATCH; EXACT_RECEIPT_MISMATCH; HANDOFF_SCHEMA_DIGEST_MISMATCH; PRODUCER_RECEIVER_SCHEMA_DIGEST_MISMATCH | Proyección: router_v2_lossy_receiver_BLOCK. Integridad: N6_modified_context_vs_original_receipt, schema_digest_mismatch, producer_schema_drift. No hay equivalencia para autorización runtime ausente: es otra compuerta. |
| RETURN_TO_PRODUCTO_NO_CODE | Sin código equivalente | Definición canónica y currentness funcional corresponden al precheck de Producto; PG-01 no las inventa. |

## Reproducción y resultados locales

- 76 unittest PG-01, sin errores: preplanning_checks, preplanning_receiver, technical_currentness, exact_artifact_reader.
- 85 unittest Router, sin errores: descubrimiento de test_*.py en router_stage1.
- 148 assertions SQL coincidentes: 111 de fundamento/emisor/preplanning, 28 Router V2, 9 de replay exacto de tres contextos históricos.
- PostgreSQL 17.6 desechable: imagen postgres:17.6, sin red ni puertos, tmpfs y cleanup. DDL solo en esa instancia.
- Comando SQL: `python3 run_programming_pg01_receiver_base_v1.py --allow-local-docker --sudo-docker --router-v2-evidence --historical-input /ruta/privada/historicos.json`.
- Las lecturas de los tres contextos reales se hicieron por Supabase RO; su replay fue local. El export crudo privado no se incorpora al repo.
- La evidencia saneada completa y hashes fuente están en pg01_router_compatibility_local_20261026.json. Sin modelos reales, escrituras hosted o activación.

## Pendientes

P1/I0 siguen abiertos: positivo acordado C1/PR2, proveedor/currentness admitidos, C4/C7 operativos, envelope/admisión A9 y D7/C6 persistido con readback. Véanse PG01_P1_CLOSURE_MAP_V1.md y PG01_D7_RECEIPT_PERSISTENCE_PROPOSAL_V1.md. CI debe leerse por nombre sobre el HEAD publicado; estos conteos son locales. Ninguna conclusión constituye autorización operativa.

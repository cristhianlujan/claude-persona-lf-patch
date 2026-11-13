# L28 — Decisión del dueño en conversación (PENDIENTE FIRMA)

**Estado literal:** `DECIDIDA_EN_CONVERSACION_PENDIENTE_FIRMA`. No es `APROBADO`, `VIGENTE`, ni cierre de B13/B14. Fuente: instrucción directa del dueño en conversación. No adjuntó comprobante del panel o acuse de proveedor de backups a esta tarea.

## Contexto y alcance
- Supabase `mhwmirqcgxxukpctffuv` es **base de trabajo temporal**; será migrada a base de producción real en el futuro (proyecto destino no identificado).
- **Panel Supabase reportado por el dueño:** `7 copias físicas diarias`, última `2026-11-12 09:37 UTC`. Es un **dato testimonial** del panel, no verificado de forma independiente ni una prueba de restaurabilidad. En B13 mantener campo `EVIDENCIA_REFERIDA_POR_DUEÑO_PENDIENTE_FIRMA`, no `CERRADO`.
- Para todo cambio temporal debe existir **preimagen con SHA-256 del objeto/filas afectados**, repositorio/función/contrato, actor y alcance, readback y camino de rollback antes del cambio. Si el rollback no es seguro, detener.
- No contratar PITR ni crear otro proyecto Supabase de prueba para la base temporal. Pruebas PG18 y PG17.6 aisladas en Docker/CI no son proyectos Supabase.
- **B13_BACKUP** y **B14_RESTORE** se evalúan en Infraestructura **base final**. B13 final incluye backups físicos, PITR, política de retención/cifrado/custodia, RPO/RTO; B14 final incluye restauración real aislada con readback/checksum. Los dos siguen **ABIERTOS / 0/2**, con sus recibos vacíos.

## Corte de las 14 barreras (sin cierres)
| Grupo | IDs | Estado |
|---|---|---|
| MOTOR TEMPORAL | B02 B03 B06 B07 B08 B09 B12 | 0/7 |
| CONTENIDO | B01 B04 B05 B10 B11 | 0/5 |
| INFRA FINAL | B13 B14 | 0/2 |

**GO técnico temporal:** solo G01/G02/G03/G04/G08/G11/G12 + G15-MOTOR temporal firmable por autoridad real. No exige G09/G10 de Infra final ni G05/G06/G07/G13/G14 de Contenido. El criterio original L21 no se altera, y G15-MOTOR no se declara habilitado en runtime.

**Camino final:** B13 → B14 → migración a la base final → revalidación técnica de Motor/esquema/contratos según destino. Esto preserva el propósito de B13/B14 pero cambia el punto en que se exigen.

## PR #3803 — rollback complementario
- PR DRAFT: `https://github.com/cristhianlujan/claude-persona-lf-patch/pull/3803`.
- Forward original `supabase/migrations/20261113030000_lf_ig_rule_lifecycle_writer_v2.sql` mantenido sin alteración (blob original `3b447b35f5aaad9d548e20255256513d9f27c19f`).
- Rollback manual (no autoaplicado): `sandbox/lf_contract_gate_test/input_governance_lifecycle/rollback_ig_rule_lifecycle_writer_v2.sql`.
- Test Docker: `sandbox/lf_contract_gate_test/edge_function_operation/test_ig_rule_lifecycle_rollback_pg18_pg176.py`.
- El rollback se bloquea si hay filas nuevas en tablas V2, restaura catálogo/ACL y utiliza `DROP ... RESTRICT`; no toca RUN. **No ejecutar en Supabase actual** ni prometer que substituye restore o backup.
- **Resultados de CI:** verificar workflow y logs en el SHA final del PR; hasta entonces `PENDIENTE_EVIDENCIA_DE_EJECUCION`.

## Evidencia y firmas faltantes
| Campo | Registro |
|---|---|
| Firma dueño y sub | __________________ |
| Captura/recibo proveedor 7 backups | __________________ |
| IDs/checksums/retención de copias | __________________ |
| Hash de preimagen por cambio futuro | __________________ |
| Aprobación formal de scope 7/5/2 | __________________ |
| Proyecto productivo destino / fecha migración | **NO_DEFINIDO** |
| Política PITR y ensayo restore final | **PENDIENTES EN BASE FINAL** |
| Estado B13 y B14 | **ABIERTOS** |

## Riesgos
- Backup reportado en panel no acredita restore, retención ni tiempo de recuperación. La base temporal sigue expuesta a pérdida de datos entre snapshots; no se infiere RPO.
- Sin PITR temporal, la reversión por script y preimagen SHA debe estar validada en cada cambio; un rollback de esquema puede no recuperar transacciones o efectos externos.
- Migración futura debe revalidar contratos, identidad, permisos, QA y datos reales; un PASS PG18/PG17.6 de subconjunto no acredita deploy ni compatibilidad del destino completo.

**Nunca afirmar:** aprobación firmada, 7/7 cerrados, 2/2 Infra cerrados, prueba de restore, PITR contratado, proyecto de ensayo nuevo, modificación de base viva, RUN alterado o firma de juez externo.

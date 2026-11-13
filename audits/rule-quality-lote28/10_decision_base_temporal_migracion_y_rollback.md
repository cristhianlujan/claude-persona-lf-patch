# L28 — Decisión del dueño en conversación (PENDIENTE FIRMA)

## ENMIENDA PRIORITARIA L28 — decisión del dueño, PENDIENTE DE FIRMA

**Solo base temporal.** B08 ya no exige verificar identidad humana vía Supabase Auth/JWT/MFA: toda decisión humana se **atribuye documentalmente** a `Cristhian Luján` con `identity_verified=false`, `identity_mode=UNVERIFIED_CHAT_DECLARATION`, frase, fecha, proponente, hashes y readback. No es identidad física comprobada ni firma. IAM humano real queda como requisito al migrar a la base de producción final. **B06**: el owner canónico de activos es `LF_GOVERNANCE` (distinto del decisor humano), guard en PR #3804 y backfill de **155** en PR #3806; ambos sujetos a PR #3803 vía Train. Los tres PR están sin readback de aplicación.

**Migraciones:** decisión solicitada «por Merge Train directamente, sin Router»; **no se debe llamar al Router manualmente antes de enviar una migración**. Se detectó conflicto con la implementación del Train y los PR, que aún exigen `ACTUALIZACION_DB_LF` y `router_authority_receipt`. No crear esos recibos ficticios ni retirar guardas: **reconciliación oficial pendiente**. La entrada ACT-0001 para *perfiles* y el Step70/Step80 EKB no cambian.

**PR #3803:** Train run `43373800126` falló por `LF_OPERATION_PROVENANCE_CREATED_EXECUTION_MISSING:EXEC-MIGRATION-LF-IG-LIFECYCLE-V2`; sin apply/merge exitoso. En último HEAD observado `655822a9bdbd1af3796b2ffd7346cc273fa31028` hay bootstrap candidato, pero R17 run `43376438216` FAIL (un SELECT de test mal tipado y replay sin Train RUN exacto); PASE y clasificación PASS. #3804 DRAFT/mergeable=false y #3806 DRAFT/test aislado PASS, no aplicados. **0/7 Motor, 0/5 Contenido y 0/2 Infra final, todos abiertos.** Pruebas exactas y fuentes: `12_criterios_cierre_motor_7.md`; `13_readback_pr3803_3804_3806_train.md`.

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
- **Resultados CI verificados (solo prueba de código):** HEAD `607880071ffef18071d92f1979a93e270502e8b8`, `PASE` **SUCCESS** run `43363122819`, clasificación de migración **SUCCESS** run `43363122964`, R17 **SUCCESS** run `43363123119`; logs PG17.6 v170006 `PASS_PR3803_REVERSE_postgres_17.6`, PG18.7 v180007 `PASS_PR3803_REVERSE_postgres_18`, suite 211 tests `OK`. Evidencia en `11_resultado_pr3803_rollback_ci.md`. No probado contra instancia real Supabase ni base completa.

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

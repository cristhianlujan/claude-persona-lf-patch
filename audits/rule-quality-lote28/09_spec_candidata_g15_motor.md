# L28 — Spec candidata G15-MOTOR-TEMPORAL v2 (NO APLICAR)

## ENMIENDA PRIORITARIA L28 — decisión del dueño, PENDIENTE DE FIRMA

**Solo base temporal.** B08 ya no exige verificar identidad humana vía Supabase Auth/JWT/MFA: toda decisión humana se **atribuye documentalmente** a `Cristhian Luján` con `identity_verified=false`, `identity_mode=UNVERIFIED_CHAT_DECLARATION`, frase, fecha, proponente, hashes y readback. No es identidad física comprobada ni firma. IAM humano real queda como requisito al migrar a la base de producción final. **B06**: el owner canónico de activos es `LF_GOVERNANCE` (distinto del decisor humano), guard en PR #3804 y backfill de **155** en PR #3806; ambos sujetos a PR #3803 vía Train. Los tres PR están sin readback de aplicación.

**Migraciones:** decisión solicitada «por Merge Train directamente, sin Router»; **no se debe llamar al Router manualmente antes de enviar una migración**. Se detectó conflicto con la implementación del Train y los PR, que aún exigen `ACTUALIZACION_DB_LF` y `router_authority_receipt`. No crear esos recibos ficticios ni retirar guardas: **reconciliación oficial pendiente**. La entrada ACT-0001 para *perfiles* y el Step70/Step80 EKB no cambian.

**PR #3803:** Train run `43373800126` falló por `LF_OPERATION_PROVENANCE_CREATED_EXECUTION_MISSING:EXEC-MIGRATION-LF-IG-LIFECYCLE-V2`; sin apply/merge exitoso. En último HEAD observado `655822a9bdbd1af3796b2ffd7346cc273fa31028` hay bootstrap candidato, pero R17 run `43376438216` FAIL (un SELECT de test mal tipado y replay sin Train RUN exacto); PASE y clasificación PASS. #3804 DRAFT/mergeable=false y #3806 DRAFT/test aislado PASS, no aplicados. **0/7 Motor, 0/5 Contenido y 0/2 Infra final, todos abiertos.** Pruebas exactas y fuentes: `12_criterios_cierre_motor_7.md`; `13_readback_pr3803_3804_3806_train.md`.

**Alcance pendiente de firma:** la base actual es temporal; G15-MOTOR mide **7 bloqueos** (B02, B03, B06, B07, B08, B09, B12) y excluye Contenido (B01/B04/B05/B10/B11) e Infraestructura final (B13/B14). Las dependencias técnicas cruzadas no se eliminan.

| Campo | Criterio |
|---|---|
| scope | INPUT_GOVERNANCE_MOTOR_TEMPORARY_DB_ONLY |
| required_blockers | [B02_RUN_SCOPE,B03_RUN_EFFECTS,B06_OWNER,B07_SCHEMA,B08_IDENTITY,B09_E2E,B12_LEGACY] |
| required_gates | [G01,G02,G03,G04,G08,G11,G12] |
| infrastructure_deferred_to_final_db | [B13_BACKUP,B14_RESTORE] / [G09,G10] |
| content_documentary_nonblocking | [B01_MFA,B04_FAMILY,B05_RULES,B10_BUSINESS,B11_LEGAL] / [G05,G06,G07,G13,G14] |
| cross_group_technical_gates | B01→B09 fail-closed si Login; B04→B07 interfaz; B05→B12 baseline |
| preimage_before_each_temporary_change | fuente, PK/objeto, bytes/DDL/JSON RAW, SHA256, actor/sub, hora, scope, diff, recepción y readback |
| rollback | script inverso probado en PG18 y evaluación PG17.6; **no se ejecuta sobre base viva** por este lote |
| release_authority | owner/sujeto real autenticado, evidencia de controles, operación gobernada y reversión |
| decision | GO_MOTOR_LIMITADO / NO_GO_MOTOR / INCONCLUSO; lo no probado equivale a NO_GO |
| prohibition | no promover reglas ni MFA/negocio; no modificar RUN; no saltar bloqueo production_promotion en IG |
| final_database_gate | verificar backups/PITR, retención/RPO/RTO, restauración aislada real y autorización de migración final |

## Evals propuestos (NO ejecutados por L28)
| ID | Caso | Esperado |
|---|---|---|
| T01 | 7 Motor válidos, 0 Contenido, 0 Infra final; contrato temporal definido, firma de Motor y riesgo acotado | GO_MOTOR_LIMITADO, solo motor temporal |
| T02 | 6/7 Motor, aunque Contenido 5/5 | NO_GO_MOTOR |
| T03 | B06/B08 sub inválido, SUPER_ADMIN supuesto, roles no confirmados | NO_GO_MOTOR |
| T04 | B09 Login habilita AUTHENTICATED prematuro mientras B01 pendiente | NO_GO_MOTOR |
| T05 | B07 ignora interfaz B04 o no tiene preimagen/hash/rollback probado | NO_GO_MOTOR |
| T06 | B12 rompe baseline B05/4 funciones legacy/MD5 | NO_GO_MOTOR |
| T07 | Motor completo, B10/B11 no aprobados; intento publicar pagos/cartas/claims | DENY content, Motor sin privilegio para ello |
| T08 | Motor completo, B13/B14 pendientes para base final | No vetan GO temporal; sí vetan migración/GO base final |
| T09 | Llamada a operación IG con production_promotion | DENY conforme contrato vigente |
| T10 | Cambio de RUN histórico o función congelada | NO_GO_MOTOR |
| T11 | Firma vacía o promesa de preimagen sin hash/readback | NO_GO_MOTOR |
| T12 | Runtime externo aún exige G15 global 14/32 | NO_GO hasta reconciliación oficial del contrato |
| T13 | Cambio temporal sin reversión segura o con rollback no verificado | NO_GO para esa operación de cambio |
| T14 | Infra final sin PITR/restore real cuando se solicita migración | NO_GO_BASE_FINAL |

**PR #3803:** rollback manual fuera de `supabase/migrations/`, test Docker PostgreSQL 17.6 y 18.7; **PASS verificado** por logs de GitHub Actions `43363123119` (ambas pruebas `ok`; 211 tests R17 `OK`). Forward intacto. Evidencia y límites exactos en `11_resultado_pr3803_rollback_ci.md`. Un PASS en CI **NO** promueve el PR, no acredita restore ni sustituye un backend completo.

**Fuentes inmutables:** G15 L21 y contratos oficiales. Para usar 7/7 realmente, validar autoridad y cursar una modificación gobernada separada de contrato/gate desplegado si hay conflicto. Propuesta ≠ aprobación.

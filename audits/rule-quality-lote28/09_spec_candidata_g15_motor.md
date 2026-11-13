# L28 — Spec candidata G15-MOTOR-TEMPORAL v2 (NO APLICAR)

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

**PR #3803:** `sandbox/lf_contract_gate_test/input_governance_lifecycle/rollback_ig_rule_lifecycle_writer_v2.sql` es script inverso manual, **fuera de migrations** para respetar 1 SQL migración/PR. Archivo de prueba `test_ig_rule_lifecycle_rollback_pg18_pg176.py` para PostgreSQL 18 y 17.6 aislados por Docker CI. **No afirmar PASS hasta verificar CI/logs**. Migración forward sin tocar.

**Fuentes inmutables:** G15 L21 y contratos oficiales. Para usar 7/7 realmente, validar autoridad y cursar una modificación gobernada separada de contrato/gate desplegado si hay conflicto. Propuesta ≠ aprobación.

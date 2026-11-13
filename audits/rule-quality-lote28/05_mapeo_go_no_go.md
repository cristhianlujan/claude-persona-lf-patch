# Mapeo L28 de los 15 gates G01–G15 por entorno

## ENMIENDA PRIORITARIA L28 — decisión del dueño, PENDIENTE DE FIRMA

**Solo base temporal.** B08 ya no exige verificar identidad humana vía Supabase Auth/JWT/MFA: toda decisión humana se **atribuye documentalmente** a `Cristhian Luján` con `identity_verified=false`, `identity_mode=UNVERIFIED_CHAT_DECLARATION`, frase, fecha, proponente, hashes y readback. No es identidad física comprobada ni firma. IAM humano real queda como requisito al migrar a la base de producción final. **B06**: el owner canónico de activos es `LF_GOVERNANCE` (distinto del decisor humano), guard en PR #3804 y backfill de **155** en PR #3806; ambos sujetos a PR #3803 vía Train. Los tres PR están sin readback de aplicación.

**Migraciones:** decisión solicitada «por Merge Train directamente, sin Router»; **no se debe llamar al Router manualmente antes de enviar una migración**. Se detectó conflicto con la implementación del Train y los PR, que aún exigen `ACTUALIZACION_DB_LF` y `router_authority_receipt`. No crear esos recibos ficticios ni retirar guardas: **reconciliación oficial pendiente**. La entrada ACT-0001 para *perfiles* y el Step70/Step80 EKB no cambian.

**PR #3803:** Train run `43373800126` falló por `LF_OPERATION_PROVENANCE_CREATED_EXECUTION_MISSING:EXEC-MIGRATION-LF-IG-LIFECYCLE-V2`; sin apply/merge exitoso. En último HEAD observado `655822a9bdbd1af3796b2ffd7346cc273fa31028` hay bootstrap candidato, pero R17 run `43376438216` FAIL (un SELECT de test mal tipado y replay sin Train RUN exacto); PASE y clasificación PASS. #3804 DRAFT/mergeable=false y #3806 DRAFT/test aislado PASS, no aplicados. **0/7 Motor, 0/5 Contenido y 0/2 Infra final, todos abiertos.** Pruebas exactas y fuentes: `12_criterios_cierre_motor_7.md`; `13_readback_pr3803_3804_3806_train.md`.

**Los gates de L21 mantienen sus IDs y exigencias originales.** Cambia únicamente qué gates se miden para el pase del motor **temporal**; no se declara actualizada una política/función SQL de producción.

| Gate | Bloqueo | Grupo en L28 | ¿Bloquea G15-MOTOR temporal? | Estado |
|---|---|---|---|---|
| G01 | B02_RUN_SCOPE | MOTOR | **Sí** | NO_VERIFICADO |
| G02 | B03_RUN_EFFECTS | MOTOR | **Sí** | NO_VERIFICADO |
| G03 | B06_OWNER | MOTOR | **Sí**, owner LF_GOVERNANCE 238/238, guard+155 recibos (#3804/#3806) | NO_VERIFICADO |
| G04 | B08_IDENTITY | MOTOR | **Sí**, registro documental no autenticado identity_verified=false, no JWT/MFA | NO_VERIFICADO |
| G05 | B01_MFA | CONTENIDO | No; B09 debe pasar control fail-closed si Login | NO_VERIFICADO |
| G06 | B04_FAMILY | CONTENIDO | No; B07 requiere interfaz técnica sin firma integral | NO_VERIFICADO |
| G07 | B05_RULES | CONTENIDO | No; B12 requiere baseline/compatibilidad | NO_VERIFICADO |
| G08 | B12_LEGACY | MOTOR | **Sí** | NO_VERIFICADO |
| G09 | B13_BACKUP | INFRA_FINAL | **No temporal; Sí base final** | NO_VERIFICADO |
| G10 | B14_RESTORE | INFRA_FINAL | **No temporal; Sí base final** | NO_VERIFICADO |
| G11 | B07_SCHEMA | MOTOR | **Sí**: preimagen SHA, reversión segura, RLS/rollback | NO_VERIFICADO |
| G12 | B09_E2E | MOTOR | **Sí** | NO_VERIFICADO |
| G13 | B10_BUSINESS | CONTENIDO | No; solo su funcionalidad posterior | NO_VERIFICADO |
| G14 | B11_LEGAL | CONTENIDO | No; solo publicación/legales posteriores | NO_VERIFICADO |
| G15 | RELEASE_GOVERNANCE | **G15-MOTOR TEMPORAL propuesto** | **Sí** si 7/7 Motor+7 gates y autorización propia; **G15 L21 original** conserva alcance global hasta cambio oficial | NO_VERIFICADO |

**GO/NO-GO:** hoy 0/7 Motor, 0/5 Contenido, 0/2 Infra final; global 0/14. La cifra histórica G01–G15 sigue 0/15 acreditados. B13/B14 no se cierran al moverlos. Un GO técnico de IG no implica GO para Contenido ni para la migración de base final.

**Nuevo criterio declarativo pendiente de firma:** G15-MOTOR = G01+G02+G03+G04+G08+G11+G12 + 7 recibos y firma de autoridad de motor; G09/G10 se toman en infraestructura final, en base real productiva. **No contratar PITR ni crear proyecto de prueba en la base temporal.** La firma sobre backups actuales no se infiere de la conversación. Si la fuente oficial todavía exige G15 global, requiere ruta gobernada separada, no bypass.

**Aristas técnicas:** B04→B07 interfaz de familia, B05→B12 baseline, B01→B09 fail-closed cuando Login, B13→B14→migración final con rerevisión de B07 en destino. No degradar seguridad ni reversibilidad.

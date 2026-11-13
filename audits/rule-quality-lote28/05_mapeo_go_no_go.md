# Mapeo L28 de los 15 gates G01–G15 por entorno

**Los gates de L21 mantienen sus IDs y exigencias originales.** Cambia únicamente qué gates se miden para el pase del motor **temporal**; no se declara actualizada una política/función SQL de producción.

| Gate | Bloqueo | Grupo en L28 | ¿Bloquea G15-MOTOR temporal? | Estado |
|---|---|---|---|---|
| G01 | B02_RUN_SCOPE | MOTOR | **Sí** | NO_VERIFICADO |
| G02 | B03_RUN_EFFECTS | MOTOR | **Sí** | NO_VERIFICADO |
| G03 | B06_OWNER | MOTOR | **Sí** | NO_VERIFICADO |
| G04 | B08_IDENTITY | MOTOR | **Sí** | NO_VERIFICADO |
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

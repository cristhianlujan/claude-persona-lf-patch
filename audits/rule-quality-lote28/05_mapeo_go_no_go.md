# GO/NO-GO técnico IG (Motor) + seguimiento de Contenido — G01–G15

**Todas las casillas sin marcar:** cada gate sigue `NO_VERIFICADO`. Los 15 criterios originales L21 se conservan por ID y no se reescriben en su fuente. **Para el alcance nuevo L28, G15-MOTOR** evalúa solo los nueve gates Motor; los cinco gates Contenido siguen como seguimiento en IG, sus firmas no vetan GO del Motor. **Esta reinterpretación de alcance no modifica automáticamente un contrato oficial desplegado**.

**Motor (9 gates):** `G01,G02,G03,G04,G08,G09,G10,G11,G12` → G15-MOTOR. **Contenido (5 gates):** `G05,G06,G07,G13,G14` → seguimiento documental paralelo.


| Gate | Grupo | Bloqueo principal | Evidencia para cierre (no presentada aquí) | Dependencias transversales | Estado |
|---|---|---|---|---|---|
| G01 | MOTOR | B02_RUN_SCOPE | Lista 232/32 literal, RECON_SCOPE_RECEIPT, freeze SHA/as_of, dueño+Ops | Punto inicial B03 | ☐ NO_VERIFICADO |
| G02 | MOTOR | B03_RUN_EFFECTS | Preimage/efectos/leases/worker por RUN, EFFECT_RECON/LIVENESS, idempotencia, firma | B02 | ☐ NO_VERIFICADO |
| G03 | MOTOR | B06_OWNER | Owner LF/SALY sub/actor/perfil/proyecto, binding + readback, negativos SUPER_ADMIN/cross-project | contrato B06-D + B08 + B06-A | ☐ NO_VERIFICADO |
| G04 | MOTOR | B08_IDENTITY | JWT/OIDC real, issuer/aud/JWKS, actor/role, RLS/GRANT, pruebas de suplantación | B06-D | ☐ NO_VERIFICADO |
| G05 | CONTENIDO | B01_MFA | AUTH-022→018 fail-closed, policy 19 VIGENTE, SAML/IdP, Brevo OTP, ADR-003 M1, negativos | B08; proveedor SMS no confirmado | ☐ NO_VERIFICADO |
| G06 | CONTENIDO | B04_FAMILY | 15 familias + 23 dictámenes individuales, SALY segregado y frecuencias LF/SALY firmadas | B06 | ☐ NO_VERIFICADO |
| G07 | CONTENIDO | B05_RULES | Decisiones sobre 57, 3 refs y 20 pares; negativos semánticos, sin igualación ciega | B04 + B01 ref MFA | ☐ NO_VERIFICADO |
| G08 | MOTOR | B12_LEGACY | Contratos y regresión 4 funciones, signatures/diff/md5, positivos y negativos | B08 + baseline técnico B05; cierre B05 no requerido | ☐ NO_VERIFICADO |
| G09 | MOTOR | B13_BACKUP | Backup físico+PITR, retención/cifrado, RPO/RTO, provider IDs/checksums | Previo a DDL | ☐ NO_VERIFICADO |
| G10 | MOTOR | B14_RESTORE | Restauración real aislada, checksums/tiempos/readback, firma DBA/Continuidad | B13 | ☐ NO_VERIFICADO |
| G11 | MOTOR | B07_SCHEMA | Draft LF4/SALY5 UP/DOWN, backfill, RLS/GRANT, rollback seguro y QA | interfaz B04 + B08+B12+B14; cierre B04 no requerido | ☐ NO_VERIFICADO |
| G12 | MOTOR | B09_E2E | ACT-0001→Perfil→RUN→IG→Curator/Validator→Step70/OIDC→terminal; 11 pasos, RAW/readback y juez acreditado | B03+B06+B08+B07; B01 fail-closed si Login sin firma B01 | ☐ NO_VERIFICADO |
| G13 | CONTENIDO | B10_BUSINESS | Niubiz/PCI, ledger, pricing, cuota/settlement/IDV/aliados, permisos, QA e informes | B08+B05; B09 antes de operar | ☐ NO_VERIFICADO |
| G14 | CONTENIDO | B11_LEGAL | Anexo I, consentimientos, mora/reclamaciones, claims visuales versionados/firma Legal | B05 | ☐ NO_VERIFICADO |
| G15 | **MOTOR (G15-MOTOR, alcance L28)** | **RELEASE_GOVERNANCE — pase técnico IG** | Dossier con 9 recibos Motor, firmas de autoridad Motor, riesgos, SHAs, actor autorizado, alcance/rollback, NO-GO/GO firmado y operación FUTURA acotada; 5 recibos y firmas Contenido siguen pendientes documentales | **Solo G01,G02,G03,G04,G08,G09,G10,G11,G12**; referencia original L21 G15 exige 14 y 32, no modificada aquí | ☐ NO_VERIFICADO |

## Regla GO/NO-GO para Input Governance (L28)
- **NO-GO técnico ahora:** Motor 0/9 cierres y 0/9 gates acreditados; G15-MOTOR pendiente. Contenido 0/5, 0/5 gates, **no impacta la fórmula de GO técnico**. Total histórico 0/14, 0/15 y 0/32 firmas L21; preservados, no son la nueva fórmula.
- **GO técnico futuro:** los 9 Motor cerrados + G01,G02,G03,G04,G08,G09,G10,G11,G12 acreditados + G15-MOTOR con firma de autoridad Motor, alcance técnico, pruebas negativas, sin funcionalidades de Contenido indebidamente activas, rollback y operación posterior identificada. **No exige G05,G06,G07,G13,G14 ni firmas de decisiones de Contenido**.
- **Dependencias cruzadas preservadas:** B05→B12 como baseline/contrato probado; B04→B07 como compatibilidad de interfaz/familias; B01→B09 como prueba fail-closed si Login. Si una dependencia técnica está insegura o no probada, el **bloque Motor NO cierra**; no basta ignorarla.
- **Alcance distinto de producto:** GO técnico IG no da GO a MFA/negocio/legal/UX ni a políticas CANDIDATO. Contenido se promueve después por IG con sus propios registros, pruebas y firmas.
- **Fuente y despliegue:** G15 original L21 sigue indicando 14 recibos/32 firmas. El criterio L28 es separación documental propuesta por instrucción del dueño; antes de usarlo en un gate operativo real, verificar la autoridad y, si aplica, tramitar cambio gobernado del contrato/fuente oficial sin alterar lo verificado.
- **Ninguna plantilla vacía** modifica estado. Un check manual, fixture PG18 o una preferencia conversada nunca acreditan un gate.


# Matriz exhaustiva G01–G15 → B01–B14

**Todas las casillas sin marcar:** cada gate sigue `NO_VERIFICADO`. Mapeo conserva la numeración y condiciones de L21 `04_go_no_go_firmable.md`; G15 es gobernanza de release, no bloqueo número 15.

| Gate | Bloqueo principal | Evidencia para cierre (no presentada aquí) | Dependencias transversales | Estado |
|---|---|---|---|---|
| G01 | B02_RUN_SCOPE | Lista 232/32 literal, RECON_SCOPE_RECEIPT, freeze SHA/as_of, dueño+Ops | Punto inicial B03 | ☐ NO_VERIFICADO |
| G02 | B03_RUN_EFFECTS | Preimage/efectos/leases/worker por RUN, EFFECT_RECON/LIVENESS, idempotencia, firma | B02 | ☐ NO_VERIFICADO |
| G03 | B06_OWNER | Owner LF/SALY sub/actor/perfil/proyecto, binding + readback, negativos SUPER_ADMIN/cross-project | contrato B06-D + B08 + B06-A | ☐ NO_VERIFICADO |
| G04 | B08_IDENTITY | JWT/OIDC real, issuer/aud/JWKS, actor/role, RLS/GRANT, pruebas de suplantación | B06-D | ☐ NO_VERIFICADO |
| G05 | B01_MFA | AUTH-022→018 fail-closed, policy 19 VIGENTE, SAML/IdP, Brevo OTP, ADR-003 M1, negativos | B08; proveedor SMS no confirmado | ☐ NO_VERIFICADO |
| G06 | B04_FAMILY | 15 familias + 23 dictámenes individuales, SALY segregado y frecuencias LF/SALY firmadas | B06 | ☐ NO_VERIFICADO |
| G07 | B05_RULES | Decisiones sobre 57, 3 refs y 20 pares; negativos semánticos, sin igualación ciega | B04 + B01 ref MFA | ☐ NO_VERIFICADO |
| G08 | B12_LEGACY | Contratos y regresión 4 funciones, signatures/diff/md5, positivos y negativos | B08 + B05 | ☐ NO_VERIFICADO |
| G09 | B13_BACKUP | Backup físico+PITR, retención/cifrado, RPO/RTO, provider IDs/checksums | Previo a DDL | ☐ NO_VERIFICADO |
| G10 | B14_RESTORE | Restauración real aislada, checksums/tiempos/readback, firma DBA/Continuidad | B13 | ☐ NO_VERIFICADO |
| G11 | B07_SCHEMA | Draft LF4/SALY5 UP/DOWN, backfill, RLS/GRANT, rollback seguro y QA | B04+B08+B12+B14 | ☐ NO_VERIFICADO |
| G12 | B09_E2E | ACT-0001→Perfil→RUN→IG→Curator/Validator→Step70/OIDC→terminal; 11 pasos, RAW/readback y juez acreditado | B03+B06+B08+B01+B07 | ☐ NO_VERIFICADO |
| G13 | B10_BUSINESS | Niubiz/PCI, ledger, pricing, cuota/settlement/IDV/aliados, permisos, QA e informes | B08+B05; B09 antes de operar | ☐ NO_VERIFICADO |
| G14 | B11_LEGAL | Anexo I, consentimientos, mora/reclamaciones, claims visuales versionados/firma Legal | B05 | ☐ NO_VERIFICADO |
| G15 | **RELEASE_GOVERNANCE (B01–B14)** | Dossier con 14 recibos, 32 decisiones firmadas, riesgos, SHAs, actor autorizado, NO-GO/GO firmado y operación FUTURA acotada | **Todos G01–G14** | ☐ NO_VERIFICADO |

## Regla GO/NO-GO
- **NO-GO ahora:** 0/14 bloqueos cerrados, 0/15 gates acreditados, 0/32 decisiones L21 firmadas; B13/B14, E2E real e identidad real no acreditados.
- **GO futuro:** requiere todos los gates aplicables y recibos autenticados; solo autoridad real puede emitirlo. GO de diseño ≠ ejecución; una nueva operación gobernada con alcance, autorización, rollback y ventana debe tramitarse por separado.
- **Ninguna plantilla vacía** modifica el estado. Un check manual, fixture PG18 o una preferencia de conversación nunca cuentan como acreditación.


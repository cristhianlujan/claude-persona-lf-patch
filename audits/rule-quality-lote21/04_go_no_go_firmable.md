# Lote 21 — Criterio GO / NO-GO firmable (sin firma emitida)

**Estado por defecto: NO-GO / UNVERIFIED.** Marcar una casilla no ejecuta una operación, no prueba una identidad y no valida evidencias. La firma final solo puede producirse después de que todas las condiciones correspondientes al alcance estén verificadas y se redacte un acta con identidad confiable. **El propio L21 no autoriza producción ni migraciones.**

## Checklist objetivo de aceptación futura

| Check | Gate | Condición verificable | Evidencia exigida | Quién acredita | Estado |
|---|---|---|---|---|---|
| ☐ G01 | `B02_RUN_SCOPE` | Cohorte RUN firmada con lista literal: 232 o 32 IDs justificados; frozen SHA+as_of. | L19 R01; L21 S21_01; lista IDs + RECON_SCOPE_RECEIPT | DUEÑO + Operaciones | **NO_VERIFICADO** |
| ☐ G02 | `B03_RUN_EFFECTS` | Los RUN seleccionados tienen reconciliación individual preimage/guardas/efectos/worker, sin reintentos ni cierres ciegos. | EFFECT_RECON_RECEIPT, LIVENESS_RECEIPT, idempotency readback, worker externo y SHA por RUN | DUEÑO + Operaciones/DBA | **NO_VERIFICADO** |
| ☐ G03 | `B06_OWNER` | Owner de LF y de SALY identificado y autenticado, con actor/perfil por proyecto y familias; SUPER_ADMIN no aprobador. | OWNER_REGISTRY_RECEIPT + pruebas negativas cruzadas LF/SALY + SELECT S21_05 | DUEÑO LF/SALY + IAM | **NO_VERIFICADO** |
| ☐ G04 | `B08_IDENTITY` | Supabase Auth real: JWT/OIDC validado, sub→perfil, role efectivo, RLS/GRANT, pooler, no claims de test. | ID_BOUNDARY_ATTESTATION firmado, tokens reales redacted, prueba impersonación/cross-project | DUEÑO + Seguridad | **NO_VERIFICADO** |
| ☐ G05 | `B01_MFA` | AUTH-022→018 permanece fail-closed; promoción solo con SAML/IdP admins, Brevo OTP, ADR-003 M1, policy 19 VIGENTE y no AUTHENTICATED temprano. | Política 19/20 readback, admin SAML, Brevo API+webhook, AUTH-018 pruebas antes/después de MFA, negativo bypass | DUEÑO + Seguridad | **NO_VERIFICADO** |
| ☐ G06 | `B04_FAMILY` | 15 familias LF y 23 membresías dudosas validadas; familias SALY segregadas; frecuencias LF/SALY firmadas. | Acta owner de 15 familias + 23 veredictos y tabla de intervalos días; fuentes L13/L16 | DUEÑO LF/SALY + Gobernanza | **NO_VERIFICADO** |
| ☐ G07 | `B05_RULES` | 57 pendientes con disposición; 3 referencias y 20 pares con dictamen que no degrada controles. | CSV 57 firmado, refs y pares literal, pruebas semánticas y decisiones owner correspondientes | DUEÑO + Legal/Producto/Seguridad | **NO_VERIFICADO** |
| ☐ G08 | `B12_LEGACY` | Compatibilidad con 4 funciones legadas public.* probada contra migración propuesta, sin cambiar gates congelados. | SELECT S21_04, contrato y regresión apply_batch, decide_batch, report, guard, diff y hashes | DUEÑO + Arquitectura | **NO_VERIFICADO** |
| ☐ G09 | `B13_BACKUP` | Backup físico + PITR existentes y verificables, cobertura/rango, retención, cifrado, RPO/RTO. | Provider backup IDs, hashes, ventana PITR y registro firmado DBA/Continuidad | DUEÑO + DBA | **NO_VERIFICADO** |
| ☐ G10 | `B14_RESTORE` | Restauración REAL desde backup/PITR en aislamiento con readback y RPO/RTO medidos. | RESTORE_TEST_RECEIPT, job ID, checksums antes/después, evidencias de tiempo medido | DUEÑO + DBA | **NO_VERIFICADO** |
| ☐ G11 | `B07_SCHEMA` | Esquema lifecycle LF 4 + SALY 5 columnas aprobado; backfill/compatibilidad, reversión post-datos, contrato de SALY.estado. | DDL UP/DOWN L20 SHA, design signoff, replay en dato representativo, rollback no destructivo | DUEÑO LF/SALY + DBA | **NO_VERIFICADO** |
| ☐ G12 | `B09_E2E` | Prueba oficial ACT-0001→Perfil→RUN→IG (si aplica)→Curator/Validator→Step70/OIDC→registro→cierre; juez acreditado según contrato. | IDs de RUN/recibos por 11 pasos, Gate2, transporte, Step70 nativo, raw verdict, readback, CI negativo/positivo | DUEÑO + IG/Plataforma | **NO_VERIFICADO** |
| ☐ G13 | `B10_BUSINESS` | Pagos/ledger/pricing/IDV/settlement autorizados por área con proveedor y fuente reales. | Contrato ledger y proveedor, PCI, quote, SLA aliados, pruebas idempotentes e informes financieros | DUEÑO + Producto/Finanzas/Operaciones | **NO_VERIFICADO** |
| ☐ G14 | `B11_LEGAL` | Legales, consentimientos, moras, reclamaciones y claims/UX aprobados por autoridad competente. | Anexo I, copy y consentimientos versionados, validación Legal, evidencia visual confirmada | DUEÑO + Legal/UX | **NO_VERIFICADO** |
| ☐ G15 | `RELEASE_GOVERNANCE` | Dossier y todos los recibos actuales; signoff NO delega ejecución; futuro cambio debe tener operación gobernada separada y rollback. | Registro único 32 decisiones con firma autenticada, SHA por evidencia, segregación, aprobación final GO explícita | DUEÑO del proyecto | **NO_VERIFICADO** |

## Política de decisión

- **GO solamente si:** todos los gates aplicables fueron acreditados mediante recibos auténticos verificables; la cohorte, el plan de cambio, los hashes de fuente y los riesgos residuales están firmados; no se eludió ningún gate; y se emite autorización positiva explícita para una operación posterior identificada (RUN/operación/alcance) con rollback, propietario y ventana.
- **NO-GO obligatorio si:** no hay identidades verificadas; existen los RUN por reconciliar sin efecto conocido; falta backup/restauración; MFA puede degradarse; la migración o compatibilidad no tiene readback; se usan fixtures como evidencia productiva; el juez se presenta como independiente sin recibo; hay firma sin actor autorizado; o Step70/OIDC nativo está NO_PROBADO.
- **La firma del dueño aquí solo resuelve decisiones de diseño/política**, salvo que el texto de una autorización posterior especifique la operación gobernada y el alcance. Una elección A/B/C no es una llamada a escritor.
- **Condición de auditor:** el modelo actual es GPT-6; **juez del mismo modelo, NO independiente**. La independencia solo podrá acreditarse después con identidad y recibos verificables de otra ejecución/actor autorizado.

## Readback base para firmar

| Evidencia OBJETIVA | Valor acreditado y origen |
|---|---|
| Reglas LF | 578 (412 VIGENTE / 166 CANDIDATO), L21 S21_01 `4a4eb9eecd7182a6f432f2df1b927733531dc26a58617eb422926f2870c6c933` |
| SALY | 14 reglas vigentes, L21 S21_01 mismo SHA |
| RUN | 232 IN_PROGRESS, 184 >30 días y 8 leases vencidos, L21 S21_01 mismo SHA |
| Owners actuales | 8 perfiles, 45 permisos, 0 asignaciones inspeccionadas, 1 proyecto SALY, L21 S21_01 |
| Política MFA | 19 CANDIDATO, AUTH-018 CANDIDATO y AUTH-022 VIGENTE, L21 S21_03 `3cff7e13769ed846a69c274f88e4f89cabea989a13c2c6488a6e7acc0ca371ee` |
| Columnas faltantes | 4 LF y 5 SALY, L21 S21_02 `0a8624c58887c553249137fe556594d311ced96ced7ed4cf12d7af0fa34c7090` |
| 4 funciones legadas | Existen en `public`, L21 S21_04 `344c5611f98c1933f8e6337e53e24b74e3cdda4af7e045ba96335878e7e97016` |
| Modelo 12 etapas PG18 | 15 REAL_EN_SANDBOX / 36, 41,7%; producción E2E acreditada 0/36, reporte L18 blob `64f763defa2e929e87539a5507126860ffd61577` y L20 blob `4b28a22978061bb049c541a0713636597e830d3b` |

## Plantilla de firma — SIN RELLENAR

**Proyecto:** ______________________

**Versión / digest del paquete:** ______________________

**RUN / operación futura permitida (si aplica):** ______________________

**Alcance exacto y exclusiones:** ______________________

**Gates completos (IDs + evidencias):** ______________________

**Riesgos residuales aceptados explícitamente:** ______________________

**Resultado de la evaluación:** ☐ GO limitado a operación futura especificada  ☐ NO-GO  ☐ RECHAZADO / PENDIENTE

**Dueño autorizado (nombre / rol / sub verificado):** ______________________

**Firma / recibo autenticado:** ______________________

**Fecha UTC:** ______________________

**Dictamen del auditor independiente (si exigido por contrato):** ______________________

**Readback posterior:** ______________________

**Al cierre de L21:** todas las casillas están sin marcar, no existe firma del dueño emitida en esta conversación, no hay RUN/PR productiva aprobada. **NO-GO / UNVERIFIED.**

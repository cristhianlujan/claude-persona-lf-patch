# L37 — Ajustes de criterio y riesgos para aceptación expresa del dueño
**Documento de una página · BORRADOR DE RIESGOS, SIN FIRMA · base temporal LF**

| ID de excepción | Cambio de criterio que se solicita reconocer | Riesgo residual que el dueño debe asumir | Límite que NO elimina la firma |
|---|---|---|---|
| **R01 / recibos** | El dueño firma la **conformidad** de los recibos de Operaciones, DBA y auditor. | Falta de segregación y autovalidación; un error del emisor podría no ser detectado. | La firma del dueño no acredita ejecución, custodia ni revisión **independiente** del auditor. G01/G02 pendientes sin evidencia de origen y readback. |
| **R02 / B09 nativo** | GPT nativo en chat nuevo, sin API keys; juez como instrucciones del **mismo LLM**. | Autoevaluación, sesgo y fallo correlacionado; no hay independencia real del juez ni comprobante de proveedor. | **No** etiquetar `PASS_INDEPENDENT_SEMANTIC` ni Step70 verificado. Requiere contrato reespecificado y probado; B09/G12 sigue abierto. |
| **R03 / B07 padre/hija** | Sustituir exigencia LF4+SALY5 por **padre=regla vigente; hija=histórico versionado**, con decisor, fecha y SHA. | Incompatibilidad con consumidores y migración/rollback; pérdida o fabricación de historia anterior. | Exigir contrato, integridad/atomicidad, backfill limitado, RLS/índices, pruebas PG17/18 y rollback. B07/G11 abierto. |
| **R04 / G15** | Para pase **temporal Motor** aceptar como cobertura sólo siete gates G01/G02/G03/G04/G08/G11/G12. | Confundir GO parcial con producción segura; quedan fuera MFA/negocio/legal/backup/restore. | B01/B04/B05/B10/B11 y B13/B14 permanecen abiertos; producción **NO-GO**. No afirmar G15 habilitado sin contrato y 7/7 recibos. |
| **R05 / AUTH-019 + política 19** | Perfiles 1 y 2: usuario+contraseña y, cuando aplica MFA, OTP correo/Brevo, sin FIDO2. | OTP por correo es vulnerable a phishing y no equivale a factor resistente a phishing ni prueba AAL2 nativo. | Seguridad/QA/IdP deben revisar política 19; si MFA exigible no hay acceso solo con contraseña. Regla/política no promocionadas. |

**Declaración para la firma del bloque:** Al aprobar el ID único y SHA-256 del manifiesto, el dueño ratifica que conoce **R01–R05 como riesgos documentales**. No afirma que el riesgo esté mitigado, que existan firmas autenticadas ni que los criterios técnicos sean PASS.

**Condición invariable:** `identity_mode=UNVERIFIED_CHAT_DECLARATION`; `identity_verified=false`; decisión documental ≠ recibo operacional, auditoría independiente, VIGENTE o GO. No ejecutar escritores ni cambiar RUN con esta firma.

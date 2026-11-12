# LF — Lote 10 · Demostración PG18 de límites de autenticidad E2E

**Estado:** DRAFT / NO-GO. Alcance sandbox, PostgreSQL 18 con ROLLBACK en cada variante. Sin producción, merge, Router, segundo IG/juez/modelo, SQL nuevo de gate, apply live ni RUN históricos.

## Declaración del dueño ≠ atestación del sistema

El dueño declaró que **ChatGPT** procesó las cinco revisiones ciegas y que **IG, perfil y revisor son el mismo modelo**. Se registra `reviewer_model=ChatGPT`, `reviewer_model_source=OWNER_DECLARED_NOT_SYSTEM_ATTESTED`, `reviewer_model_system_attestation=false`, `review_independence=CONSISTENCY_NOT_INDEPENDENCE` en metadatos L6 y L9. No se edita el archivo bruto de 154 líneas (SHA256 `d319670079ece0e0285e37a3194a1e1c9e784e9b7b6f5e7d35ed4882200bf4bc`) ni se cambia la etiqueta neutra `REVIEW_5PASS_VERDICTS_NOT_NATIVE_IG_RECEIPT_MODEL_UNATTESTED`.

## Ruta real pedida y límite del gate

- **a — ALLOW real** `K00E813F0`, cita exacta del export de la pasada 1: `En producción, otp_code solo puede persistirse como hash`. Fuente L4C `REG_SEG_004`, **propuesta** original, sin editar. PG18 puede congelar, validar y registrar la línea mediante las funciones L7/L8 **solo con fixture de IG/Step70 claramente sintético**. El resultado permitido por el gate es `PROFILE_OWNER_REVIEW_ONLY`, NO `VERIFIED_CAPTURE_BINDING`.
- El dueño autorizó **propietario simulado** para la prueba, pero no proporcionó un recibo nativo de IG #3682 ni Step70 firmado del mismo RUN. No se inventa una procedencia `OFFICIAL_STEP70_VERIFIED_NATIVE_IG`. El ensayo con propietario `test_only_synthetic=true` NO confiere autoridad, y `apply` queda bloqueado. La regla debe conservar `CANDIDATO`. **No es legítimo forzar la ruta feliz hasta VIGENTE para llamarla E2E.**
- **b — BLOCK real** `K00A10207`: cita real del export y `HUMAN_DECISION_REQUIRED`, nunca promueve.
- **c — ALLOW corto real** `K00C8E827`: 39 caracteres, `L7_QUOTE_EMPTY_OR_TRIVIAL`, escala a humano.
- **d — misma cita real de a**, captura estructural bajo stub, alteración de la descripción de regla dentro de la misma transacción, `L7_EXACT_CITATION_NOT_CURRENT` al solicitar apply, estado `CANDIDATO`, ROLLBACK.

## Tablero de 12 etapas (se emite como JSON RAW en CI)

El tablero del **mismo caso K00E813F0** usa exclusivamente las etiquetas `SANDBOX_VERIFIED` o `NOT_PROVEN`. No se acreditan rutas auténticas mediante stubs.

| Etapa | Estado | Motivo |
| --- | --- | --- |
| Router | NOT_PROVEN | Sin entrada oficial ACT-0001 ni OIDC |
| Perfil | NOT_PROVEN | Propietario sintético, sin ejecución auténtica |
| RUN | NOT_PROVEN | RUN en base PG18 descartable; no RUN oficial |
| IG | NOT_PROVEN | No hay recibo nativo #3682 |
| Curator | NOT_PROVEN | No se emitió recibo Curator verificable |
| Validator | SANDBOX_VERIFIED | Coincidencia literal, identidad de caso y snapshot L7/L8; no juicio semántico |
| Retorno perfil | NOT_PROVEN | No hay transporte ni `READY` real |
| Ejecucion | NOT_PROVEN | No consta el perfil completo 11/11 con recibos |
| Promocion | NOT_PROVEN | Sin aprobación real del propietario, apply bloqueado |
| VIGENTE | NOT_PROVEN | Persistió `CANDIDATO` |
| Readback | SANDBOX_VERIFIED | Readback **negativo**: comprobó CANDIDATO y rollback; no readback VIGENTE |
| Cierre | NOT_PROVEN | Sin RUN COMPLETED, 11/11, juez y recibo terminal READY |

**El tablero NO es global PASS.** Es una prueba de que los controles existentes permanecen fail-closed cuando faltan las atestaciones externas. Si se desea un E2E feliz auténtico, se requiere una ejecución nueva por la ruta gobernada, evidencia verificable de IG #3682, Step70 del RUN, perfil propietario autorizado y la cadena final de readback/retorno/cierre; no se obtienen fabricando filas en PG18.

## Controles y no-regresiones

No hay migración de L10. Se preservan MD5 `apply=86b0494984edf95cf0f9c0a0df67000b`, `capture_record=89cbfac4162dbc9f8ecca59f2c3ab4c3`, `citation_verify=773a62783baa5edbe967200cac66b8c3`, `L8 guard=522d12f0843be1da3c785cef3c0bf3fc`; la suite PG18 compara antes/después.

El historial anterior prueba 42 +12 +15 +9 +8 +13 +6 controles estructurales, además de 154 citas L9 con ROLLBACK. La medición determinista L4 de 33 casos **no** demuestra eficacia del juez: 22 falsos negativos y cero falsos positivos; su ejecución no es un PASS de fiabilidad.

**UNVERIFIED:** Router oficial; perfil y RUN reales; enlace Curator/Validator/IG auténtico; recibo #3682 y Step70 verificable; perfil aprobador real; resultado VIGENTE; transporte de retorno; readback positivo y cierre terminal. **PASE permanece bloqueante**.

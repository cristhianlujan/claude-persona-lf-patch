# L29 AJUSTADO — Contrato de revisión E2E con fuente real del Login B2B

**Sustituye como entrega objetivo al ensayo previo de 3 reglas de muestra (conservado por trazabilidad).** Nueva CI [#43340333844](https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/43340333844) = SUCCESS PG18. **Autor: GPT-6, mismo modelo; Curator SQL no independiente.**

## Entrada y trazabilidad

- 51 códigos solicitados: AUTH-001..048, AUTH-STATE-001, SECURITY-BASELINE-001, NAV-LEGAL-001. **49 existentes** y 2 ausentes (AUTH-009 y AUTH-010), no creados.
- SOURCE SELECT: `lf_ops.reglas`, 9 VIGENTE + 40 CANDIDATO, SHA-256 `4959cfd6d9319ea26b60f9a21a1751c674e06c4417fb4d589f3665424d539bd3`; PG18 hizo readback de ese mismo SHA. El origen no se editó.
- Los últimos tres códigos se guardan realmente como `B2B-RULE-AUTH-STATE-001`, `B2B-RULE-SECURITY-BASELINE-001`, `B2B-RULE-NAV-LEGAL-001`.
- Politicas centrales SELECT: `lf_ops.politicas_seguridad` IDs 3,19,20,25 y política de sesión ID 1; cuatro propuestas de modificación sobre copias PG18, no DML real.
- Decisiones del dueño: MFA OTP correo Brevo principal, SMS contingencia (proveedor sin confirmar), 30 días sin uso o tres meses sin cambio clave como parámetros centrales, otros disparadores pendientes. Q11 soporte+documento+doble persona+48h+aviso contacto anterior. Estado `DECIDIDA_EN_CONVERSACION_PENDIENTE_FIRMA` sin firma formal.

## Flujo reproducible en PG18

```text
EKB leído → SELECT origen y cuatro políticas (solo lectura)
 → 49 filas reales copiadas en schema l29_actual con SHA igual
 → fuente sellada con trigger de solo lectura + 4 políticas copy
 → propuesta individual por código con descripción+config completas y diff literal
 → Curator determinista: 49 evaluaciones en 1.ª vuelta
 → 4 DEVOLVER (AUTH-018/019/020/033)
 → aplicar 4 cambios SOLO a drafts de reglas
 → aplicar 4 cambios SOLO a drafts de políticas
 → re-Curator SOLO 4 modificadas (2.ª vuelta)
 → 23 aceptación preliminar + 26 escaladas + 2 sin fuente
 → validaciones de huella, duplicidad, parámetros y firmas
 → falta firma formal: BLOCK promoción
 → 0 VIGENTE nuevos, 0 RUN tocados, 0 producción
```

**No se usa la regla sintética `REG_SEG_004`** en el runner actual. El archivo anterior `test_pg18_lote29_e2e_ig_gap.py` existe como historia del lote, pero la CI ya solo ejecuta `test_pg18_lote29_actual_login_b2b_49.py`. El ensayo no inyecta reglas nuevas para llenar AUTH-009/010.

## Límites exactos

- El Mini-Curator SQL es un evaluador determinista sobre diffs/duplicado exacto/pending declarado, no revisión semántica independiente. `ACEPTAR_PRELIMINAR_SANDBOX` no significa listo para promoción oficial.
- La ruta **EKB obligatoria** ACT-0001 → PERFIL → RUN → pasos perfil → IG → VALIDACIÓN → juez → registro → cierre **no se ejecutó**. El perfil/Router/RUN/Step70 reales no fueron reemplazados por otro acceso. No se ingresa `service_role` en Router.
- Valores numéricos de MFA 30 días/3 meses **solo** en propuesta de config de política 3; 48 h recuperación **solo** en política 20; no hardcodeados en las reglas. Otros disparadores MFA, uso SMS en SAML admins y alcance de soporte Google quedan pendientes.
- Es necesario **B07 lifecycle**, **B08 Auth/owner**, **B12 gates legacy**, **B02/B03 RUN**, más B09 E2E nativo, B01..B14. 0/14 cerrados.
- Fuente VIGENTE no alterada ni en sandbox: la fuente copia se protege por trigger. Los cambios de cuatro propuestas se aplicaron a drafts independientes; nunca a fuente real, ni a las 9 VIGENTES.
- **MD5 de gates**: integridad de código por Git compare desde base L26 + md5 históricos comprobados en la CI anterior de laboratorio. Esta corrida de 49 reglas no ejecutó apply/citación/Step70, por lo que no re-mide MD5. No afirmar lo contrario.

## Archivos

- `05_login_b2b_reglas_origen_49.json`: 49 preimágenes, SHA-256 de SELECT, 2 faltantes.
- `06_politicas_centrales_mfa_origen.json`: 4 políticas y sesión; separación dueño/fuente.
- `07_login_b2b_matriz_diffs_51.json`: 51 códigos con antes/después literal, 4 parches + 4 políticas.
- `08_login_b2b_vueltas_curator_51.json`: métrica de iteraciones por regla, reconstrucción exacta de lógica SQL cotejada con los agregados de CI.
- `09_matriz_humana_51.md`: la matriz completa y diffs críticos en humano.
- `test_pg18_lote29_actual_login_b2b_49.py` y workflow L29: único runner CI real actual.
- `02_resultados_e2e_pg18.md`, `03_tablero_12_etapas_medidas.md`, `01_matriz_brechas_b09_y_bloqueos.md`: readback, tablero y límites.

**Resultado:** 53 evaluaciones PG18, 4 DEVOLVER, 23 preliminares, 26 escaladas, 2 ausentes; 0 firmas, 0 promociones, 0/14 bloqueos cerrados. Producción **NO-GO / UNVERIFIED**.

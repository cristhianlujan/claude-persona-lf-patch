# L29 ajustado — Resultado verificable con 49 reglas REALES del Login B2B

## Dictamen

**SANDBOX_VERIFIED sólo para revisión de reglas reales copiadas de origen.** No equivale a ejecución del IG productivo, Router, perfil, RUN, jueces independientes, promoción ni cierre del circuito oficial.

**CI final:** [GitHub Actions #43340333844](https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/43340333844) · job `131606765364` · commit probado `7ba1d3b38bd63b0e69ac96a1fd90bf2ebc6befb1` · `SUCCESS` · PostgreSQL 18 desechable. RAW `l29_login_b2b_actual_runtime.json`, SHA-256 `a898a38cb6f8cedaf1271e7390df7517ef8bd3cfce63c60997ae097edd05b08f` (artefacto `13998749112`; ZIP SHA-256 `c82bdb62c7b270ade62a9082413bc68f84fb243d67502259351dbdb845502cac`; retención 14 días).

**Lectura sólo origen:** `lf_ops.reglas` 49 filas, 9 VIGENTE + 40 CANDIDATO, copia en PostgreSQL con SHA-256 idéntico al generado por servidor vivo: `4959cfd6d9319ea26b60f9a21a1751c674e06c4417fb4d589f3665424d539bd3`. Se buscaron 51: **AUTH-009 y AUTH-010 no existen**, las otras tres reglas tienen prefijo `B2B-RULE-` completo. Ninguna se inventó.

## Métrica real de vueltas (no estimada)

| Métrica | SQL PG18 observado |
|---|---:|
| Reglas reales copiadas y revisadas | **49/49** |
| Códigos sin fila, fuera de revisión | **2** |
| Primeras evaluaciones | **49** |
| Segundas evaluaciones por corrección propuesta | **4** |
| **Total iteraciones** | **53** |
| **DEVOLVER_CON_MOTIVO primera vuelta** | **4** |
| ACEPTAR_PRELIMINAR_SANDBOX final | **23** |
| ESCALAR_A_HUMANO final | **26** |
| NO_EVALUABLE_SIN_FUENTE | **2** |
| Firmas del dueño | **0** |
| Reglas promovidas | **0** |

`AUTH-018`, `AUTH-019`, `AUTH-020`, `AUTH-033`: cada una requirió una devolución `DEVOLVER` en vuelta 1 y un diff aplicado **únicamente a su copia candidata PG18**; la vuelta 2 `ESCALAR_A_HUMANO` porque quedan decisiones adicionales o dependencias sin verificar. El Curator no devuelve indefinidamente lo que ya no puede corregir sin evidencia externa. **Ninguna de esas cuatro quedó lista para promoción oficial.**

Las **23** aceptaciones son preliminares bajo comparador SQL determinista, sin firma, sin despliegue, sin revisión semántica independiente ni QA productivo. La métrica `cierra_sin_intervencion_humana` corresponde sólo a revisión documental automática de sandbox, **no cierre del RUN ni adopción de regla**.

## Políticas centrales: 4 propuestas, sin modificar VIGENTE

| Política existente | Evidencia en fuente | Propuesta documental de sandbox | Límite |
|---|---|---|---|
| Seguridad 3 `SEC-B2B-MFA` | **VIGENTE**; perfiles 1..6, sin parámetros 30/3 | Parámetros **30 días sin uso** y **3 meses calendario sin cambiar clave**. Otros casos `PENDING_OWNER` | No insertar valores en AUTH-003 ni modificar política VIGENTE |
| Seguridad 19 `SEC-B2B-MFA-FACTOR-ELIGIBILITY` | **CANDIDATO**; 1–2 Google SAML; 3–6 correo OTP Brevo | Conservar métodos; SMS exclusivamente contingencia, proveedor `NOT_CONFIRMED` | Definir alcance de SMS para perfiles SAML; ejecutar SAML/Brevo QA |
| Seguridad 20 `SEC-B2B-MFA-RECOVERY` | **CANDIDATO**; recuperación email no definida | Soporte, documento, dos personas, plazo central de **48h**, aviso contacto anterior, sin bypass | Dependencia de soporte/IAM; alcance administradores Google pendiente |
| Seguridad 25 `SEC-B2B-TRUSTED-DEVICE` | **CANDIDATO**; `UNRECOGNIZED_DEVICE_ONLY` | La confianza no anula disparadores MFA centrales | Otros disparadores de dispositivo/revocación pendientes del dueño |

**CI adicional real:** `PASS_L29_REAL_FOUR_POLICY_DRAFTS_ONLY`: `draft_revised=4`, `draft_matches_proposal=4`, `source_rows_unchanged=4`. Ocurrió en PG18 aislado, no en Supabase.

## Adversariales SQL ejecutados

- `SOURCE_SHA_MATCH`: SHA-256 de 49 reglas cargadas coincide con original del SELECT vivo.
- `SOURCE_ORIGINAL_UNTOUCHED`: 49/49 preimágenes sin alteración.
- `NO_LITERAL_DUPLICATES`: cero pares de configuración+descripción idénticos, sin afirmar cero duplicidad semántica.
- `CENTRAL_POLICY_ONLY_THRESHOLDS`: 30d y 3m en config de política 3, 48h en config de política 20, cero parámetros nuevos numéricos MFA embebidos en regla.
- `IMMUTABLE_REAL_ORIGIN`: actualización del origen PG18 bloqueada.
- `NO_UNSIGNED_PROMOTION`: `BLOCK_L29_NO_FORMAL_OWNER_SIGNATURE`.
- `MISSING_SOURCE_FAIL_CLOSED`: `BLOCK_L29_REAL_RULE_SOURCE_MISSING`.
- `NO_DUPLICATE_APPLY`: rechaza segunda aplicación del mismo diff.
- `BOARD_49_BY_12`: **588** celdas auditadas, sin sobreacreditar etapas nativas.

## Base histórica L29 de muestra — NO es la entrega ajustada

La CI anterior [#43336082581](https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/43336082581) probó **22/22** con `REG_SEG_004` y otros fixtures y observó MD5 de gates. **Está sustituida como prueba principal** por la CI real de 49 reglas. El script previo se conserva por trazabilidad en Git, pero la CI modificada **ya no lo ejecuta** para este ajuste.

**MD5 gates históricamente verificados y SQL originales intactos:** apply `86b0494984edf95cf0f9c0a0df67000b`, capture `89cbfac4162dbc9f8ecca59f2c3ab4c3`, citation_verify `773a62783baa5edbe967200cac66b8c3`, l8 guard `522d12f0843be1da3c785cef3c0bf3fc`. **No se recalcularon los cuatro MD5 durante la nueva revisión de las 49 reglas** porque ésta no invocó el apply congelado. La integridad de sus archivos se audita por diff de Git desde L26.

## Gobierno

Los inputs del dueño sobre MFA y Q11 son **DECIDIDA_EN_CONVERSACION_PENDIENTE_FIRMA**; 0 firmas y 0 promociones. Otros casos MFA, operador SMS, dependencia SAML/Brevo/IdP y alcance del soporte siguen sin autorización. En todos los cambios, el Curator es mini-revisor determinista escrito por **GPT-6, mismo modelo y sin independencia**; no se ejecutó JWT nativo de Supabase. La referencia HMAC L17 pertenece a los lotes históricos de laboratorio.

**B09_E2E Nativo: NO_PROBADO. Bloqueos B01..B14 cerrados: 0/14. Producción NO-GO / UNVERIFIED.**

# L37 — Nueve frases literales preparadas para el dueño (NINGUNA FIRMADA)

**Estado documental:** 9/9 paquetes y SHA de contenido GitHub verificados por PostgreSQL `SELECT`; **identity_verified=false**; `firmas_realizadas=0`. La aceptación del formato “Yo, Cristhian Luján, apruebo la decisión X” NO es una firma. No se llamó ningún escritor V2 ni se creó un RUN.

## Diferencia entre hashes
- **SHA-256 del documento**: hash de bytes exactos del paquete `signatures/*.json`, incluido en la frase para que el dueño indique lo que ratifica. El hash queda en `01_frases_exclusivas_firma_documental_login.json`.
- **SHA-256 del patch**: hash del JSONB `governed_rule_patch` exacto derivado de perfil; es el único permitido en `p_decision.propuesta_sha256` de `lf_ig_rule_owner_decide_v2`. No sustituirlo por SHA del documento.
- La aprobación del documento no repara el sistema ni activa política/regla; si el usuario copia una frase se registra primero como declaración documental, no como firma verificada.

## Clasificación de entradas
- Decisiones conversacionales: Q01, Q11, Q12, aceptación del riesgo de phishing (4).
- Decisión funcional conversada, pero SHA del patch no firmado: política 19 y AUTH-019 (2).
- Propuestas de regla sin decisión del SHA del dueño: AUTH-018, AUTH-020, AUTH-033 (3).
- Propuestas sin alcance listo para solicitar frase de firma: política 3 (VIGENTE, requiere sucesora), política 20, política 25 y AUTH-002/003/040; no incluirlas como decisiones aprobadas.

## Frases exactas para copiar (ninguna ha sido pronunciada todavía)

### 1. LF-LOGIN-Q01-MFA-20261113

**Tipo:** DECIDIDA_EN_CONVERSACION_PENDIENTE_FIRMA · **Mecanismo actual:** documento GitHub · **Escritor V2:** NO ADMITIDO (decisión/política)

**SHA-256 DOCUMENTO:** `767bbcc73eb9c7eacceb060c21f6386119d021ed680a863757c48bcd8c93a545`  
**SHA-256 patch (cuando existe):** `NO APLICA`  
**Fuente:** [Paquete exacto](https://github.com/cristhianlujan/claude-persona-lf-patch/blob/lf/issue-3779-lote37-login-decision-signature-packets-v1/docs/rule-quality-lote37/signatures/lf-login-q01-mfa-20261113.json)

> Yo, Cristhian Luján, apruebo la decisión LF-LOGIN-Q01-MFA-20261113, documento SHA-256 767bbcc73eb9c7eacceb060c21f6386119d021ed680a863757c48bcd8c93a545, exclusivamente como aprobación documental. Esta declaración no autoriza ejecutar escritores, migraciones ni promover a producción.

**Bloqueos:** FIRMA_Y_VERIFICACION_IDENTIDAD; POLICY3_VIGENTE_REQUIERE_SUCESORA; OTROS_DISPARADORES_MFA_PENDIENTES; QA_MFA


### 2. LF-LOGIN-Q11-RECOVERY-20261113

**Tipo:** DECIDIDA_EN_CONVERSACION_PENDIENTE_FIRMA · **Mecanismo actual:** documento GitHub · **Escritor V2:** NO ADMITIDO (decisión/política)

**SHA-256 DOCUMENTO:** `f7a9eb88e001aa973e92f10df163cd7809a9d04c80419034d224b1752e3ca4d7`  
**SHA-256 patch (cuando existe):** `NO APLICA`  
**Fuente:** [Paquete exacto](https://github.com/cristhianlujan/claude-persona-lf-patch/blob/lf/issue-3779-lote37-login-decision-signature-packets-v1/docs/rule-quality-lote37/signatures/lf-login-q11-recovery-20261113.json)

> Yo, Cristhian Luján, apruebo la decisión LF-LOGIN-Q11-RECOVERY-20261113, documento SHA-256 f7a9eb88e001aa973e92f10df163cd7809a9d04c80419034d224b1752e3ca4d7, exclusivamente como aprobación documental. Esta declaración no autoriza ejecutar escritores, migraciones ni promover a producción.

**Bloqueos:** IDV_SIN_PROVEEDOR; DOBLE_CONTROL_NO_IMPLEMENTADO; QA_RECUPERACION; POLICY20_PENDIENTE


### 3. LF-LOGIN-Q12-RISK-20261113

**Tipo:** DECIDIDA_EN_CONVERSACION_PENDIENTE_FIRMA · **Mecanismo actual:** documento GitHub · **Escritor V2:** NO ADMITIDO (decisión/política)

**SHA-256 DOCUMENTO:** `3dfd72354d70e8e62653f4ac82160b2173d233a96be2b58bbee8d46ada3ef21a`  
**SHA-256 patch (cuando existe):** `NO APLICA`  
**Fuente:** [Paquete exacto](https://github.com/cristhianlujan/claude-persona-lf-patch/blob/lf/issue-3779-lote37-login-decision-signature-packets-v1/docs/rule-quality-lote37/signatures/lf-login-q12-risk-20261113.json)

> Yo, Cristhian Luján, apruebo la decisión LF-LOGIN-Q12-RISK-20261113, documento SHA-256 3dfd72354d70e8e62653f4ac82160b2173d233a96be2b58bbee8d46ada3ef21a, exclusivamente como aprobación documental. Esta declaración no autoriza ejecutar escritores, migraciones ni promover a producción.

**Bloqueos:** EVENTO_CONTROL_UNIDAD_PENDIENTES; QA_TELEMETRIA; PERMISO_PANTALLA_NO_ACREDITADO


### 4. LF-LOGIN-POL19-P1P2-OTP-20261113

**Tipo:** DECISION_FUNCIONAL_CONVERSADA_PATCH_POLITICA_PENDIENTE_FIRMA · **Mecanismo actual:** documento GitHub · **Escritor V2:** NO ADMITIDO (decisión/política)

**SHA-256 DOCUMENTO:** `120b4bfd1d47e3d15d092c64489df909f000910830887cb8fbfd11a61e872992`  
**SHA-256 patch (cuando existe):** `4e2156de362f377ace9a0aef758a136501c9530ca02f7ee20691f38494b021f7`  
**Fuente:** [Paquete exacto](https://github.com/cristhianlujan/claude-persona-lf-patch/blob/lf/issue-3779-lote37-login-decision-signature-packets-v1/docs/rule-quality-lote37/signatures/lf-login-pol19-p1p2-otp-20261113.json)

> Yo, Cristhian Luján, apruebo la decisión LF-LOGIN-POL19-P1P2-OTP-20261113, documento SHA-256 120b4bfd1d47e3d15d092c64489df909f000910830887cb8fbfd11a61e872992, exclusivamente como aprobación documental. Acepto el riesgo residual: el OTP por correo puede ser retransmitido mediante phishing. Esta declaración no autoriza ejecutar escritores, migraciones ni promover a producción.

**Bloqueos:** NO_NATIVE_POLICY19_OWNER_DECIDE_V2; PARAMETER_PROVENANCE_REFRESH_REQUIRED; MIGRATION_MERGE_TRAIN_GOVERNED; PG17_PG18_ROLLBACK_NOT_TESTED; JUDGE_Y_QA


### 5. LF-LOGIN-AUTH019-P1P2-OTP-20261113

**Tipo:** DECISION_FUNCIONAL_CONVERSADA_PATCH_EXACTO_PENDIENTE_FIRMA · **Mecanismo actual:** documento GitHub · **Escritor V2:** SOLO POSTERIOR, luego de RUN/juez/alcance exactos

**SHA-256 DOCUMENTO:** `4b5ee91381ebbf456b5f1b1a5ac7d38c6a75f5e8b63a949e8674482151a808a4`  
**SHA-256 patch (cuando existe):** `f70ded45a786f6fc6664081ecec5a3963514d0e3cf9ad06089914fcd425dd288`  
**Fuente:** [Paquete exacto](https://github.com/cristhianlujan/claude-persona-lf-patch/blob/lf/issue-3779-lote37-login-decision-signature-packets-v1/docs/rule-quality-lote37/signatures/lf-login-auth019-p1p2-otp-20261113.json)

> Yo, Cristhian Luján, apruebo la decisión LF-LOGIN-AUTH019-P1P2-OTP-20261113, documento SHA-256 4b5ee91381ebbf456b5f1b1a5ac7d38c6a75f5e8b63a949e8674482151a808a4, exclusivamente como aprobación documental. Acepto el riesgo residual: el OTP por correo puede ser retransmitido mediante phishing. Esta declaración no autoriza ejecutar escritores, migraciones ni promover a producción.

**Bloqueos:** AUTH019_VALOR_CONFIG_CONTRADICE_TEXTO; POLICY19_CONTRADICE_OTP; REAL_RUN_JUDGE_INDEPENDIENTE; IDENTITY_VERIFIED_FALSE


### 6. LF-LOGIN-AUTH018-20261113

**Tipo:** PROPUESTA_DOCUMENTAL_PENDIENTE_DECISION_DEL_DUENO · **Mecanismo actual:** documento GitHub · **Escritor V2:** SOLO POSTERIOR, luego de RUN/juez/alcance exactos

**SHA-256 DOCUMENTO:** `02b17ce2dcf1d59d849e09063f065d5e648df30e796470546d9a1ae8a7bab524`  
**SHA-256 patch (cuando existe):** `c45b974b519ee985a3ae8fd4a0be8d4d0417eb6a113ea3732112efc86a793ef1`  
**Fuente:** [Paquete exacto](https://github.com/cristhianlujan/claude-persona-lf-patch/blob/lf/issue-3779-lote37-login-decision-signature-packets-v1/docs/rule-quality-lote37/signatures/lf-login-auth018-20261113.json)

> Yo, Cristhian Luján, apruebo la decisión LF-LOGIN-AUTH018-20261113, documento SHA-256 02b17ce2dcf1d59d849e09063f065d5e648df30e796470546d9a1ae8a7bab524, exclusivamente como aprobación documental. Esta declaración no autoriza ejecutar escritores, migraciones ni promover a producción.

**Bloqueos:** POLICY3_VIGENTE; OTROS_TRIGGERS; REAL_RUN_JUEZ; IDENTIDAD


### 7. LF-LOGIN-AUTH020-20261113

**Tipo:** PROPUESTA_DOCUMENTAL_PENDIENTE_DECISION_DEL_DUENO · **Mecanismo actual:** documento GitHub · **Escritor V2:** SOLO POSTERIOR, luego de RUN/juez/alcance exactos

**SHA-256 DOCUMENTO:** `9191a21709de5d44d413d6616c8947d7026fa9281f0394f1499c8a80c2fd8c0c`  
**SHA-256 patch (cuando existe):** `696c2504d0bbe220d8d616fed545d73b89e9c69efa06f51ab60f78a888f3cd3c`  
**Fuente:** [Paquete exacto](https://github.com/cristhianlujan/claude-persona-lf-patch/blob/lf/issue-3779-lote37-login-decision-signature-packets-v1/docs/rule-quality-lote37/signatures/lf-login-auth020-20261113.json)

> Yo, Cristhian Luján, apruebo la decisión LF-LOGIN-AUTH020-20261113, documento SHA-256 9191a21709de5d44d413d6616c8947d7026fa9281f0394f1499c8a80c2fd8c0c, exclusivamente como aprobación documental. Esta declaración no autoriza ejecutar escritores, migraciones ni promover a producción.

**Bloqueos:** IDV; POLICY20; SOPORTE_DOBLE_CONTROL; RUN_JUEZ


### 8. LF-LOGIN-AUTH033-20261113

**Tipo:** PROPUESTA_DOCUMENTAL_PENDIENTE_DECISION_DEL_DUENO · **Mecanismo actual:** documento GitHub · **Escritor V2:** SOLO POSTERIOR, luego de RUN/juez/alcance exactos

**SHA-256 DOCUMENTO:** `2a878fa7ab702f6eb0ce483bf7f206bd98971e4a2d747f36b6f087d0ddb02ff7`  
**SHA-256 patch (cuando existe):** `6a398f8cdbd59a4a56099f9deb8ec01a3ea95e62ea1864735546db60c5cfb769`  
**Fuente:** [Paquete exacto](https://github.com/cristhianlujan/claude-persona-lf-patch/blob/lf/issue-3779-lote37-login-decision-signature-packets-v1/docs/rule-quality-lote37/signatures/lf-login-auth033-20261113.json)

> Yo, Cristhian Luján, apruebo la decisión LF-LOGIN-AUTH033-20261113, documento SHA-256 2a878fa7ab702f6eb0ce483bf7f206bd98971e4a2d747f36b6f087d0ddb02ff7, exclusivamente como aprobación documental. Esta declaración no autoriza ejecutar escritores, migraciones ni promover a producción.

**Bloqueos:** POLICY25_DEVICE; RUN_PANTALLA_B2B_AUTH004; JUEZ_INDEPENDIENTE; OIDC


### 9. LF-LOGIN-OTP-PHISHING-RISK-20261113

**Tipo:** DECIDIDA_EN_CONVERSACION_PENDIENTE_FIRMA · **Mecanismo actual:** documento GitHub · **Escritor V2:** NO ADMITIDO (decisión/política)

**SHA-256 DOCUMENTO:** `1726998d8233e88431708d3b0f11564f89b7a1aa8d6b6ffddaa66a876af0c43e`  
**SHA-256 patch (cuando existe):** `NO APLICA`  
**Fuente:** [Paquete exacto](https://github.com/cristhianlujan/claude-persona-lf-patch/blob/lf/issue-3779-lote37-login-decision-signature-packets-v1/docs/rule-quality-lote37/signatures/lf-login-otp-phishing-risk-20261113.json)

> Yo, Cristhian Luján, apruebo la decisión LF-LOGIN-OTP-PHISHING-RISK-20261113, documento SHA-256 1726998d8233e88431708d3b0f11564f89b7a1aa8d6b6ffddaa66a876af0c43e, exclusivamente como aprobación documental. Acepto el riesgo residual: el OTP por correo puede ser retransmitido mediante phishing. Esta declaración no autoriza ejecutar escritores, migraciones ni promover a producción.

**Bloqueos:** FIRMA_DEL_DUENO; DICTAMEN_SEGURIDAD; CONTROLES_DETECTIVOS_Y_QA



## Registro posterior de frase, sin inventar identidad
1. Dueño publica UNA o varias frases exactas anteriores; recepción en conversación no comprueba identidad civil ni criptográfica. Se puede registrar documentación append-only con frase, fecha real de observación, hash de documento y contexto; `identity_verified=false`, sin marcar `firmada=true` sin recibo oficial.
2. **Para reglas AUTH-018/019/020/033 solamente cuando exista autorización nueva de ejecución:** usar mismo perfil Product Director, RUN `EJECUCION_PERFIL_LF` con fuente actual, selector de pantalla correcto (AUTH-033 → B2B-AUTH-004), outputs RAW, Step70 juez independiente, `output_validate` y propuesta SHA exacta. El writer es `public.lf_ig_rule_owner_decide_v2(p_parent,p_rule,p_source_sha256,p_decision)`, con `p_decision` de seis campos string: `codigo_regla`, `propuesta_sha256`, `veredicto`, `decisor`, `fecha`, `frase_literal`. Una llamada con APROBAR puede ejecutar el skill y PROMOVER; no es registro “firma sola”. `p_source_sha256` debe venir de `lf_asset_snapshot_sha_v1`, nunca de hash fila.
3. **Para política central 19 y decisiones Q01/Q11/Q12/riesgo:** la ruta actual es registro documental; **NO existe writer owner_decide_v2 admitido para `lf_ops.politicas_seguridad`**. Ratificación en chat no produce recibo oficial, y el antiguo `UNVERIFIED_CHAT_DECLARATION` devuelve `identity_verified=false`.
4. `p_decision.fecha` oficial debe ser ISO8601 con zona real del momento del RUN y dentro de la ventana validada por el writer (desde RUN.started_at −5 min hasta ahora +5 min). No inventar fecha/firmante verificado ni retrofechar una decisión a un RUN futuro.
5. No conflar esta preparación con permiso de disparar la migración de policy19: la aplicación aún está **NO-GO** hasta Router atestación, PG17/PG18 con rollback real, resolución de inconsistencias de configuración, juez y decisión posterior de disparo.

## Ruta de aplicación política 19
`02_plan_aplicacion_politica19_train_pg17_pg18_rollback.md`: PR + `ready-to-merge` → Migration Merge Train/DB_WRITE_TRANSPORT, writer SQL `UPDATE lf_ops.politicas_seguridad SET description=...`, no escritor de reglas. Migration candidato, fixture y tester están preparados, PG17.6/PG18.7 **NOT_TESTED** por falta de Docker/host. `lf_router_resolve_v1` devolvió `BLOCK_SCOPE_SEMANTICS_UNATTESTED` para la petición de preparación; no hay admisión de efectos.

**Cierre:** preparación documental 100%; firmas verificadas 0/9; SQL de laboratorio en PG17.6/PG18.7 0/2 NOT_TESTED; Supabase live DML/DDL 0; promociones 0.

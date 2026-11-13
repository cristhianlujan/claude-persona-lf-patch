# L33 — Login B2B | AUTH-033 en pantalla 004; tres patches; decisión AUTH-019

**Fecha:** 13 noviembre 2026, corte de inspección en Supabase actual. **Modalidad:** solo SELECT/read-only Supabase; archivos nuevos en rama L33. **Prohibido/NO ejecutado:** DML, DDL, promoción, decisión del dueño, creación/modificación de RUN, GitHub Issue disparador.

## 1. AUTH-033: handoff oficial preparado (SIN crear RUN)
Entrada literal: ver `01_auth033_gate2_screen004_handoff_preparado.json`.
- Se leyó EKB `INPUT GOVERNANCE LF — INSTRUCCIONES OPERATIVAS V1.4` (CANDIDATO VERIFICADO PARCIALMENTE) antes de actuar; ruta `ACT-0001 → PERFIL → RUN → IG → juez → registro → cierre`.
- Ejecutado por SELECT: `lf_router_pipeline_context_begin_v2` → `stage1_submit_v2` (`VALID`, canal PRODUCTO/negocio LF) → `profile_semantic_prepare_v2` → `profile_semantic_submit_v2`.
- Resultado REAL: `GATE2_DERIVED_PENDING_GOVERNED_ADMISSION`; perfil `PERFIL-PRODUCT-DIRECTOR-LF`, `semantic_validation=VALID`, transición `HANDOFF_CONTEXT_TO_SELECTED_PROFILE`. SHA-256 exacto del objeto Gate2 del servidor: `6d86c90b336669c38feb6652e321506eee3064fc83154d0a890dab0c3ac7205f`.
- Selector nativo dentro del ámbito de perfil: `lf_profile_screen_selector_semantic_prepare_v1` → `finalize_v1`, `status=VALID`, selección única fundada en coincidencia exacta **B2B-AUTH-004**, pantalla **54**, `Verificar identidad`, módulo `B2B_AUTENTICACION`, `B2B_APP_SHELL`. `lf_ops.reglas_pantallas` confirma enlace real 1/1 AUTH-033 → pantalla 54.
- El archivo guarda `official_github_begin_issue_body_NOT_SENT` con `schema_version=LF_PROFILE_NATIVE_BEGIN_REQUEST_V1`, `router_context` INTACTO, `executor_mode=GPT_NATIVE`; también `screen_selection_draft` validado y plantilla de RESUME sin ID inventado.
- Para crear RUN real habría que presentar ese BEGIN exacto por **GitHub Issue + etiqueta lf-profile-resume-governed** → GitHub Actions/OIDC → Edge `lf-profiles-governance-caller-v1`. Eso **escribe** en `public.lf_operation_execution`, aunque el perfil sea read-only. **No se envió** porque el dueño prohibió escribir en Supabase. `execution_id`: **NO EXISTE PARA ESTE LOTE**. No convertir Gate2 en paso 0 de RUN ni afirmar 11/11.
- La selección `B2B-AUTH-004` queda validada para futura continuación del perfil. No se seleccionó/alteró la pantalla anterior `B2B-AUTH-001`, cuyos RUN históricos no se tocaron.

## 2. Propuestas documentales AUTH-002, 003 y 040

Fuente: filas actuales de `lf_ops.reglas`; texto original preservado **íntegramente como prefijo** y añadido solo texto de aclaración. Patch exactamente `{rule_code,change_kind:"DOCUMENTARY_ONLY",changes:{descripcion:...}}`. SHA-256: `encode(sha256(convert_to(patch::jsonb::text,'UTF8')),'hex')` calculado en Postgres vivo. **No utilizar huella de fila como si fuera SHA de patch o snapshot canónico del writer.**

| Regla | Estado fuente | Qué aclara la propuesta | SHA-256 patch V2 | Gate real |
|---|---|---|---|---|
| `B2B-RULE-AUTH-002` | **VIGENTE** | Política de aislamiento multiempresa no equivale a modelo físico `multi_company_physical_model_status=PENDING_FUNCTIONAL_DEFINITION`; server-only y pruebas negativas de tenant hasta verificar binding | `8d5bcb9986f664906552fab43493455acda5b4c12a86b9ede19dd69b8a0e9ffe` | **BLOQUEADO para aplicación V2:** RULE_UPDATE_APPLY exige fuente CANDIDATO. Requiere evidencia Arquitectura/DB + QA, no fingir cierre |
| `B2B-RULE-AUTH-003` | **VIGENTE** | La política MFA central (3) es autoridad; la decisión Q01 no cambia automáticamente la política vigente. Dispositivo conocido no omite MFA exigible | `b54de40a5b472a0e48a70534d136b6566dad59a9f02551e8466a566479e95490` | **BLOQUEADO para aplicación V2:** RULE_UPDATE_APPLY exige fuente CANDIDATO y política 3 requiere sucesión gobernada |
| `B2B-RULE-AUTH-040` | **CANDIDATO** | Cookie opaca no autentica, no elimina MFA exigido, respeta caducidad/revocación y AUTH-039; no presume que política 25 ya cambió | `92e734ea8a3e948f087d5adc9ba9382e10befc585f87cc394e921e798cbda330` | Patch de forma V2 válido; **NO ejecutable todavía** sin RUN admitido, decisión, juez y reconciliación política 25 |

La fuente completa, los sufijos exactos y la configuración sin modificaciones están en `02_propuestas_documentales_002_003_040_v2.json`. Para **preparar** propuestas ya existe decisión temática Q01 del dueño; para **aprobar o cerrar oficialmente** V2 se exige dictamen del owner sobre SHA exacto y RUN/juez. No afirmar que estos tres quedan cerrados automáticamente por el motor.

### Evidencia de pruebas SQL reales
`03_readback_pruebas_select_en_vivo.json` contiene recibo de:
- **3/3** source SHA full-row sin drift, **3/3** patch SHA exactos, **3/3** descripción base retenida, **3/3** configuración original intacta, **3/3** `DOCUMENTARY_ONLY` y un solo campo de cambio conforme a forma del writer.
- **1/1** enlace `AUTH-033 → B2B-AUTH-004` (pantalla 54).
- En base, `AUTH-002` y `AUTH-003` VIGENTE; `AUTH-040` CANDIDATO. No se ejecutó aplicación, QA E2E, semantic judge externo ni un RUN.

## 3. AUTH-019: decisión legible sobre Admin Empresa (profile_id=2)

**Estado en fuente vivo:** `AUTH-019=CANDIDATO`. La política central 19 también `CANDIDATO` mantiene `admin_minimum_strength=PHISHING_RESISTANT`, `admin_phishing_resistant_requirement=GOOGLE_WORKSPACE_PASSKEY_OR_SECURITY_KEY_POLICY`. La decisión Q01 registrada en conversación (L30) ordenó **OTP correo/Brevo como segundo factor del Admin Empresa**, y dejó Admin LF perfil 1 por confirmar. **Existe un conflicto, no un simple texto pendiente**.

| Alternativa | Beneficio | Riesgo/efecto |
|---|---|---|
| A. Sólo OTP por correo con Brevo para Admin Empresa | Menor fricción y coincide literalmente con la decisión conversada | Un atacante puede reenviar códigos en una página falsa. **NO cumple** requisito PHISHING_RESISTANT vigente; no promover sin nueva decisión explícita y dictamen de Seguridad que acepte el riesgo/cambio |
| B. Passkey FIDO2/WebAuthn o llave de seguridad para Admin Empresa | Factor criptográfico vinculado al dominio, resistente a phishing; mantiene el control central | Requiere IdP/infra, enrolamiento, recuperación y QA. Necesita reconciliar la decisión Q01 de usar OTP/Brevo |
| C. **Recomendada: FIDO2/WebAuthn o llave de seguridad para Admin Empresa, con Brevo como canal complementario no sustitutivo** | Mantiene protección fuerte y permite conservar comunicaciones por Brevo | No se puede usar OTP Brevo o SMS como fallback que evite el requisito FIDO2. El dueño debe confirmar modificación de Q01, Seguridad acreditar diseño y IAM probar implementación |

**Explicación:** ser usuario de Google Workspace/SAML no es suficiente por sí solo: debe demostrarse que el método de autenticación del IdP es resistente a phishing. NIST SP800-63B (edición de 2025), §3.2.5, declara que los OTP introducidos manualmente no satisfacen resistencia a phishing y que WebAuthn/FIDO2 sí puede satisfacerla cuando se implementa correctamente: https://pages.nist.gov/800-63-4/sp800-63b.html.

**Sugerencia concreta al dueño:** conservar OTP/Brevo para perfiles 3–6 según gobierno actual; para Admin Empresa (2), exigir passkey FIDO2 con verificación apropiada o llave de seguridad y dejar Brevo como complemento/aviso, jamás como bypass. Admin LF (1) permanece pendiente sin método inferido. Esta alternativa **cambia** el alcance de la selección conversada Q01, por tanto requiere una NUEVA decisión explícita; no la aplicar ni darla por decidida aquí.

## Estado y siguiente acción
- Resultado: contexto ROUTER **VALID**, selección pantalla **VALID**, archivo BEGIN **PREPARADO_NO_ENVIADO**; **RUN nuevo=0**.
- Parches V2 **3/3 verificados documentalmente** con SQL contra base viva; **aplicaciones=0**, **cerrados oficialmente=0**.
- AUTH-019 **recomendación preparada**, decisión de factor del Admin Empresa **PENDIENTE DE RECONCILIACIÓN**.
- Próximo paso en lote separado: autorización de persistir un RUN de perfil para AUTH-033, y para las reglas VIGENTE definir operación/ciclo que soporte actualización sin eludir gates. Esta entrega no solicita cambiar base, políticas ni RUN.

# LF — Lote 34 | AUTH-019 / decisión del dueño FIDO2 (perfil 2)

**Fecha de corte:** 13-nov-2026. **Estado del registro:** `DECIDIDA_EN_CONVERSACION_PENDIENTE_FIRMA`. **Supabase:** 0 escrituras, 0 promoción, 0 RUN, 0 llamada a `lf_ig_rule_owner_decide_v2`. EKB leída antes de proceder. **Rama:** `lf/issue-3779-lote34-auth019-fido2-owner-decision-v1`.

## Tablero de lote

| Lote y prueba | Estado | Evidencia |
|---|---|---|
| Declaración del dueño sobre opción C | REGISTRADA, NO FIRMADA | `00_decision_dueno_auth019_q01_perfil2_fido2_pendiente_firma.json` |
| AUTH-019 patch documental para `lf_ig_rule_owner_decide_v2` | PREPARADO, NO APROBADO | `01_auth019_patch_v2_sha_card_six_fields.json` |
| Controles de DB PostgreSQL (SELECT) | 25/25 PASS | `03_prueba_sql_live_25_controles.json` con SQL efectivamente ejecutado |
| Matriz de impactos y bloqueos | COMPLETADA DOCUMENTALMENTE | `02_matriz_impactos_politica19_auth003_018_033_bloqueos.json` |
| Modificaciones a políticas, reglas y RUN de Supabase | 0 | Ninguna operación DML/DDL ejecutada |
| Firma, juez independiente, promoción | 0 | NO EJECUTADO / NO ACREDITADO |

## 1. Decisión exacta — cambio restringido de Q01

El dueño expresa en esta conversación: “se adopta la opción C, FIDO2/WebAuthn resistente a phishing para Admin Empresa (perfil 2), con OTP por correo/Brevo solo como canal complementario, nunca como alternativa que omita FIDO2. Esto reemplaza la parte de Q01 para ese perfil. Admin LF (perfil 1) sigue pendiente.”

**Consecuencia:** reemplaza SOLO la anterior selección de OTP/Brevo como factor principal de Admin Empresa (perfil 2). No altera la definición de MFA condicional de Q01 (30 días sin uso / tres meses sin cambio de contraseña), ni el carácter de contingencia SMS sin proveedor confirmado, ni el OTP/Brevo de perfiles 3–6. La decisión no elige IdP, proveedor WebAuthn, alcance de recuperación ni método de Admin LF (perfil 1). No confundir aprobación conceptual conversacional con aprobación criptográficamente vinculada al SHA del patch V2.

Firma `null`, `firmada=false`, `firmante_validado=null`, `promovida=false`.

## 2. AUTH-019 — nueva descripción propuesta, sin modificar configuración

**SHA-256 de la fila fuente actual:** `7802a694fd4d29dab489974760babc984950ef6c06d90981c81e88530bf4882e`  
**SHA-256 del patch V2 exacto:** `d2b77023da5920dc6a5fad9fad7a213b4e3a89b9b9d3bdf653c3c1d3fcca3093`

Patch: `{"rule_code":"B2B-RULE-AUTH-019","change_kind":"DOCUMENTARY_ONLY","changes":{"descripcion":"<texto completo de 01_auth019_patch...json>"}}`. El archivo JSON conserva el texto íntegro listo para transportar, sin abreviaturas ni placeholders en la descripción. La pantalla de autoridad es `B2B-AUTH-001`.

**Tarjeta:** Actualmente la regla agrupa administradores 1/2 bajo Google SAML con factor resistente a phishing y asigna OTP/Brevo a 3–6. La nueva descripción exige FIDO2/WebAuthn en perfil 2 cuando el MFA aplique; OTP/Brevo solo complemento que nunca permite acceso sin FIDO2; mantiene perfiles 3–6 en OTP; perfil 1 no decidido. Es la opción del dueño y protege contra phishing. **Sugerencia:** aprobar el criterio de seguridad como decisión conversacional registrada, pero **NO invocar V2** hasta reconciliar política 19 y `valor_config`, completar enrolamiento/IdP, ejecutar juez y obtener decisión formal sobre el SHA exacto. Un `APROBAR` ejecutado en V2 podría actualizar y promover una descripción que contradiga configuración aún vigente en la base. Si se rechaza el patch exacto, no se modifican reglas, ni se infiere aprobación de la configuración anterior.

Registro de SEIS campos, plantilla no invocada (las tres expresiones con corchetes son pendientes, no constituyen una decisión formal):

```json
{
  "codigo_regla": "B2B-RULE-AUTH-019",
  "propuesta_sha256": "d2b77023da5920dc6a5fad9fad7a213b4e3a89b9b9d3bdf653c3c1d3fcca3093",
  "veredicto": "<APROBAR_O_RECHAZAR_PATCH_EXACTO>",
  "decisor": "Cristhian Luján",
  "fecha": "<YYYY-MM-DDTHH:MM:SS-05:00_AL_FIRMAR>",
  "frase_literal": "<DECLARACION_LITERAL_DE_APROBACION_O_RECHAZO_DE_ESTE_SHA>"
}
```

Para invocar V2, además se requiere `p_parent` RUN de perfil admitido con salida RAW y juez independiente; `p_rule` exacta; `p_source_sha256` del snapshot canónico `lf_asset_snapshot_sha_v1('REGLA','B2B-RULE-AUTH-019')` (NO sustituir por el hash de fila) y `p_decision` real con los seis campos validados. No se conoce ni inventa el `p_parent` correspondiente. Los cambios en configuración y política no son realizables por el patch `DOCUMENTARY_ONLY`.

## 3. Impacto específico, no ejecutado

| Objeto | Cambio que deberá gobernarse | No cambia automáticamente |
|---|---|---|
| **Política central 19** — CANDIDATO | Diferenciar perfil 2 = FIDO2 obligatorio cuando MFA aplique y Brevo complementario; perfil 1 = pendiente. Desacoplar requisito de factor resistente de un IdP Google específico, manteniendo `admin_minimum_strength=PHISHING_RESISTANT` | Política no fue editada; `admin_primary_method=GOOGLE_WORKSPACE_SAML_SSO`, `admin_phishing_resistant_requirement=GOOGLE_WORKSPACE_PASSKEY_OR_SECURITY_KEY_POLICY` aún requieren reconciliación real |
| **AUTH-003** — VIGENTE | Mantener MFA decidido por política central y su referencia, sin umbrales ni nuevo factor codificado en pantalla. **No requiere cambio directo por esta decisión** | Q01 de 30 días/tres meses es tema separado de política 3; no cambiar regla VIGENTE por writer CANDIDATO |
| **AUTH-018** — CANDIDATO | MFA_REQUIRED bloquea sesión hasta verificar factor; para perfil 2 ahora la evidencia de factor debe ser FIDO2, no OTP/Brevo solo | No cambia cobertura, condición de exigir MFA ni se crea flujo de factor |
| **AUTH-033** — CANDIDATO | Al enrutarse a B2B-AUTH-004 debe diferenciar desafío FIDO2 para perfil 2 del OTP para 3–6; dispositivo reconocido no elude FIDO2 exigido | `second_control_trigger=UNRECOGNIZED_DEVICE_ONLY`, política 25, AUTH-039 y reglas de confianza todavía deben reconciliarse en operación separada |

No confundir elección de **factor** con selección del **IdP**. FIDO2/WebAuthn puede integrarse con el IdP elegido, pero la nueva declaración no confirma Google Workspace, Cognito, Supabase Auth ni otro proveedor.

## 4. Bloqueos reales por responsable

| Responsable primario | Bloqueo y evidencia exigida | Estado |
|---|---|---|
| **Dueño** | Formalizar decisión sobre patch SHA exacto; Admin LF (1) aún sin método confirmado | PENDIENTE FIRMA |
| **Seguridad/IAM** | Definir RP ID/origen, desafío server-side, enrolamiento seguro, verificación de assertions, revocación y recuperación sin bypass | NO VERIFICADO |
| **Identidad/OIDC** | Cerrar ADR-003 M1 y binding real de IdP, backend y sesiones; demostrar FIDO2 operativo | NO VERIFICADO |
| **Producto/UI** | Registrar passkeys y flujo de verificación en pantallas B2B-AUTH-004/005, errores y contingencias | NO DEFINIDO/PROBADO |
| **Brevo/Operaciones** | Transporte OTP para 3–6 y complemento perfil 2, sin fallback que permita omitir FIDO2 | NO VERIFICADO |
| **Motor IG/Gobernanza** | Política 19 candidata, configuración de AUTH-019 heredada, aprobación exacta SHA, RUN real + Step70 juez independiente + promoción gobernada | NO-GO |
| **QA/Seguridad** | OTP solo perfil 2 debe fallar; passkey válida/credencial revocada/origen incorrecto/dispositivo reconocido/sesión prematura fail-closed | NO EJECUTADO |

**No hay cierres productivos acreditados.** La incompatibilidad conceptual anterior OTP/Brevo vs resistencia a phishing está resuelta **como decisión conversacional**, no como implementación.

## 5. Pruebas y cierre del lote

Prueba SQL REAL de solo lectura en Supabase: **25/25 deterministas PASS**. Incluye preimagen SHA de AUTH-019 sin drift, SHA del patch exacto, forma documental V2, único campo `descripcion`, integridad de estado CANDIDATO y vínculo pantalla, preservación de perfiles y bloqueos OTP, política 19 intacta, `admin_minimum_strength=PHISHING_RESISTANT`, configuraciones Google pendientes y SHA fuente sin cambios de AUTH-003/018/033. No equivale a juez semántico independiente ni QA de FIDO2.

**Alcance autorizado completado documentalmente: 100%.** Nuevos registros de decisión oficial firmada: **0**; RUN: **0**; aprobación/promoción: **0**; DML/DDL Supabase: **0**.

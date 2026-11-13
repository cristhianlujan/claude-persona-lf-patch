# L35 — Login B2B / AUTH-019: opción A del dueño, sin FIDO2

**Estado:** DECIDIDA_EN_CONVERSACION_PENDIENTE_FIRMA. **Cambia:** se deja sin efecto la selección C del L34 para perfil 2 y se vuelve a Q01 original. **Regla/política Supabase:** SIN CAMBIOS. EKB V1.4 revisada antes de ejecutar.

## Tablero
| Entregable | Estado | Evidencia |
|---|---|---|
| Decisión corregida y sustitución de L34 | REGISTRADA, SIN FIRMA | 00_decision_dueno_auth019_opcion_a_corrige_l34.json |
| AUTH-019 con flujo usuario + contraseña → OTP correo/Brevo | PATCH DOCUMENTAL PREPARADO, NO APROBADO | 01_auth019_opcion_a_patch_v2_tarjeta_seis_campos.json |
| Ajuste textual exacto de política 19 y riesgo residual | PROPUESTO, POLÍTICA NO MODIFICADA | 02_politica_central_19_reemplazo_texto_y_riesgo.json |
| Prueba determinista contra base real SELECT | 36/36 PASS, SIN APLICAR | 03_prueba_sql_select_36_controles.json |
| Supabase, decisiones V2, RUN, promociones | 0 escrituras / 0 firmas / 0 promociones | No se invocaron escritores ni mutaciones |

## Decisión: alcance exacto
Para **Admin Empresa (perfil 2)** se define login **usuario + contraseña** validado por servidor; cuando MFA sea requerido conforme política central, un **OTP enviado al correo por Brevo** es el segundo factor y debe verificarse antes de crear sesión. **Sin FIDO2, passkeys ni llaves de seguridad.** Admin LF (perfil 1) sigue pendiente. Perfiles 3–6 y contingencia SMS sin proveedor no cambian. El documento L34 anterior se conserva para auditoría pero su opción C quedó SUPERADA por la nueva declaración del dueño.

**Riesgo residual aceptado por el dueño en conversación, pendiente de firma: el OTP por correo puede ser retransmitido mediante phishing.**

## Patch AUTH-019
- Fuente actual: `CANDIDATO`, pant. `B2B-AUTH-001`.
- Preimagen full-row SHA-256: `7802a694fd4d29dab489974760babc984950ef6c06d90981c81e88530bf4882e`.
- **Patch V2 SHA-256:** `58826a2760f593eb9e85f8eedc44aef90b2a91e8f413a326a219f3eeb4a34018`. Se calculó con `sha256(convert_to(patch::jsonb::text,'UTF8'))` en PostgreSQL actual.
- Forma: `DOCUMENTARY_ONLY`, cambio único `changes.descripcion` con descripción íntegra y exacta en JSON. `valor_config` no se modifica.
- La tarjeta de decisión con seis claves existe como **plantilla no firmada**; placeholders de veredicto, fecha y frase literal. **No llamar `lf_ig_rule_owner_decide_v2`** ahora: un `APROBAR` puede ejecutar escritor y promover pese a discrepancia entre descripción, política 19 y configuración.
- `p_source_sha256` requiere snapshot canónico del escritor, no usar SHA de fila.

## Política central 19: sustitución textual exacta propuesta
**Texto original incompatible #1:**
> Los administradores requieren SSO Google Workspace SAML con control resistente a phishing.

**Sustituir por:**
> Para Admin Empresa (profile_id 2), el Login comienza con usuario y contraseña validados por el servidor. Cuando la política de aplicabilidad MFA exige segundo factor, LF genera y envía un código de un solo uso (OTP) al correo registrado mediante Brevo y debe verificar ese OTP del lado servidor antes de completar AUTHENTICATED, crear sesión operativa o conceder permisos. Para Admin Empresa el OTP por correo/Brevo es el segundo factor elegido por el dueño: no se exigen FIDO2/WebAuthn, passkeys ni llaves de seguridad. Para Admin LF (profile_id 1) el método del segundo factor continúa pendiente de decisión del dueño y no se afirma como confirmado Google Workspace SAML ni otro proveedor.

**Texto original incompatible #2:**
> Los demas perfiles usan un segundo control LF de OTP por correo entregado con Brevo; debe verificarse del lado servidor antes del acceso operativo.

**Sustituir por:**
> Para perfiles 3, 4, 5 y 6 se conserva el segundo factor OTP por correo/Brevo, verificado del lado servidor.

**Aclaración adicional necesaria:**
> Un OTP por correo no es resistente a phishing ni equivale por sí solo a Supabase native AAL2. SMS es solo contingencia sin proveedor confirmado ni fallback automático. Si MFA resulta exigible, una contraseña sola, un OTP inválido o no verificado y un dispositivo reconocido no conceden acceso operativo.

El **texto íntegro y sin abreviaturas para sustituir la descripción completa de la política 19** se encuentra en `02_politica_central_19_reemplazo_texto_y_riesgo.json` bajo `proposed_replacement_description_LITERAL`.

**No basta con cambiar el texto:** los campos actuales `admin_minimum_strength=PHISHING_RESISTANT`, `admin_phishing_resistant_requirement=GOOGLE_WORKSPACE_PASSKEY_OR_SECURITY_KEY_POLICY`, `phishing_resistant_option_required=true`, `admin_primary_method=GOOGLE_WORKSPACE_SAML_SSO`, `admin_identity_provider=GOOGLE_WORKSPACE`, `admin_sso_protocol=SAML_2_0`, entre otros, contradicen la decisión A y exigen reconciliación gobernada, segregada por perfil. No modificar los requisitos del perfil 1 por inferencia. El archivo 02 enumera los nueve puntos exactos.

## Prueba ejecutada / límites
**36/36 PASS** sobre consulta real SQL de solo lectura, incluidas preimagen, SHA del patch, un solo campo `descripcion`, código y pantalla, orden usuario-contraseña-OTP, ausencia de FIDO2, pendientes perfil 1, cobertura perfiles 3–6, fuente política 19 sin deriva, riesgos y registro seis campos. Esta prueba no es ejecución del writer, juez independiente, QA Brevo, corrección de política 19 ni aceptación firmada.

**Cierre documental: 100%; ejecución y promoción: 0%.**

# L30 — Manifiesto SHA-256 y lectura del alcance documental

**Rama:** `lf/issue-3779-lote30-owner-conversation-decisions-v1` en `cristhianlujan/claude-persona-lf-patch`.
**Base exacta:** `bb0779bad18e45a122d70ac17b1ae393080bc7b6` (L29). **Sólo archivos nuevos** en `docs/rule-quality-lote30/`.
**EKB leído:** INPUT GOVERNANCE LF V1.4, CANDIDATO VERIFICADO PARCIALMENTE. **Revisador:** GPT-6, mismo modelo; sin independencia ni firma acreditada.
**Fuentes históricas:** L27 `audits/rule-quality-lote21/01_registro_unico_decisiones.md` blob `4a791c544350354324adf0b19d795448491b21eb`; L29 `07_login_b2b_matriz_diffs_51.json` blob `948cac85748125ad9be1c72a65307df3d62146ab`, y snapshot de políticas `06_politicas_centrales_mfa_origen.json`. Ninguna de estas fuentes fue editada.

## Conteos

| Registro | Cantidad | Validación |
|---|---:|---|
| Nuevas entradas L30 | **10** | 9 decisiones Q01/Q02/Q06..Q12 + 1 modelo aprobación |
| Decididas en conversación, pendientes de firma | **10** | Estado exacto `DECIDIDA_EN_CONVERSACION_PENDIENTE_FIRMA` |
| Firmas, recibos o identidades firmantes verificadas | **0** | Campos `null` / vacíos en JSON y CSV |
| Reglas aprobadas/promovidas | **0** | No registrador ni promoción |
| Preguntas L16 Q01–Q12 con conversación decidida tras overlay L27+L30 | **12/12** | No confundir con 0 firmas y subdecisiones pendientes |
| Otras decisiones L19/L21 que continúan pendientes | **20** | Sin alterar dossier L21/L27 |
| Bloqueos productivos cerrados | **0/14** | NO-GO / UNVERIFIED |

## Hash SHA-256 de contenido UTF-8 y blob SHA-1 Git

| Archivo | SHA-256 | Git blob SHA-1 |
|---|---|---|
| `00_contexto_alcance.md` | `fd39cb4089fbede9af68cdd96a2c9f8c6f85c358a235a6767c1b5a9968a8a94c` | `44ec9792cd43abdeb176005af3ac517b8e2413bb` |
| `01_registro_decisiones_dueno_l30.json` | `c42ff945049548660a256454af2a265efdd4be260c8e7bc9d95bd262a195b28f` | `a4bee84814de48c5e4d9b53091af390ac855e166` |
| `02_respuestas_conversacion_l30.csv` | `74e25e19b64e4100d3cec792ffb960832530606cf32cbd85df4af979ed1991aa` | `7ba7bbb4918ea191fd5218ed7358fb6603a9e44e` |
| `03_auth019_y_politica19_correccion_propuesta.json` | `b90dc887510706d889b782a6ce805cb9bfea7097338c02f7202df8f51d316921` | `ce2d05ac095a8353004a1dd2be58777b758b3d09` |
| `04_modelo_aprobacion_y_brechas.md` | `a36098858cf38f93f8be93044771bd63349d1141d848c79874a4ef94decb15fc` | `cd5070de78ffa5aedc50fc4c936a454b13bdfbdf` |
| `05_comparacion_l27_l30_y_pendientes.md` | `80f69d155a2d94a8131a8423a40aad01504fb21135a622408bcfdcc1a873da27` | `20bf1f4354affcd7a4ac78fa242c1a8b1f8af245` |

**Método:** SHA-256 calculado sobre el texto íntegro leído desde GitHub en esta rama; algoritmo contrastado con el vector público SHA256('abc'). El blob Git SHA-1 es evidencia distinta, no sustituye SHA-256.

## AUTH-019 y control de no debilitamiento

- Propuesta L29: Admin LF 1 y Admin Empresa 2 con Google SAML. Propuesta L30: Admin Empresa **2 OTP correo Brevo**, Admin LF **1 método no confirmado**.
- El diff propone modificar en documentos la regla CANDIDATO AUTH-019 y la política central CANDIDATO 19, **sin cambiar el original ni conceder nuevas facultades**.
- `password_only_fallback=DENY`, `supabase_native_aal2_claim_for_email_otp=DENY`, y `admin_minimum_strength=PHISHING_RESISTANT` heredado se preservan. Queda **REQUIERE_REVISION_SEMANTICA_SEGURIDAD** para resolver si el factor de Admin Empresa cumple los controles vigentes.
- Proveedor SMS no confirmado; nunca se escribe un proveedor ficticio. Métodos/protocolos del Admin LF no confirmados; **no autorización de SAML, OTP o fallback** para perfil 1 por este documento.

## Restricciones y readback

- **Supabase:** cero operaciones, incluso SELECT. **PG18:** no ejecutado. **Producción:** cero DDL/DML y cero cambios. **RUN:** ninguno reintentado, abierto, cerrado o modificado.
- No se editó EKB, políticas, reglas, CSV de L27, código PG18 del L29, gates, workflow o branch principal. **MD5 históricos L29** `86b0494984edf95cf0f9c0a0df67000b`, `89cbfac4162dbc9f8ecca59f2c3ab4c3`, `773a62783baa5edbe967200cac66b8c3`, `522d12f0843be1da3c785cef3c0bf3fc`: **no se recalcularon en este lote**, sólo se preservaron los archivos.
- El readback final debe confirmar siete archivos nuevos **únicamente** `docs/rule-quality-lote30/*`, merge-base exacto, 0 archivos modificados, hashes y cuenta de firmas.

**Resultado final:** REGISTRO DOCUMENTAL CAPTURADO, FIRMA FORMAL 0, PROMOCIÓN 0, BLOQUEOS CERRADOS 0/14. **NO-GO / UNVERIFIED.**

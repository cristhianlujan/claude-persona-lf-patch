# LF — Lote 41: barrido de impacto residual Login B2B
**Mandato:** revisión y propuesta exclusivamente para fuentes NO cubiertas por PR #3844, #3846 ni #3847. **EKB V1.4 leída**; estas son propuestas documentales sin ejecución gobernada ni promoción. `identity_verified=false`; no usar APIs/modelos externos. Fuentes Supabase mediante SELECT y GitHub. Base: main `f9d20b3add2418ddae3f3372ccc0b0a49e3a9f6f`.

## Tablero de universo, separación de alcances y choque
| Familia/alcance | Revisión real | Choque nuevo / otra fuente |
|---|---:|---|
| Reglas `lf_ops.reglas` (AUTH, SEC, RATE, THEME, reglas B2B-AUTH enlazadas, coincidencias de vocabulario) | **226** | AUTH-044 es el único UPDATE nuevo de regla |
| `lf_ops.politicas_seguridad` | **25/25** | SEC22, SEC24 son UPDATE nuevos |
| `lf_ops.politicas_rate_limit` | **9/9** | 0 UPDATE: 1/7/8 requieren homologación de alcance, sin modificar códigos |
| TOTAL individualizado (incluye textos y hashes) | **260** | **3 CHOCA / 228 NO / 29 ya cubiertos** |
| PR #3844 / #3846 / #3847 | **10 / 9 / 10** | Excluidos para evitar doble escritura |
| HEX en reglas B2B-THEME y de diseño vinculadas al Login | **0 encontrados** | 4 UX ajenas tienen HEX; incidencia transversal separada, NO edición B2B |

Inventario individualizado (regla/política | `choca` | `proposed_text` solo en tres sí | SHA | pantallas | responsable PR): `audits/login-b2b-lote41/01_inventario_260_reglas_politicas_estado_choque.json`. Preimágenes completas divididas en 4 fixtures reglas (65/65/65/31) más 25 políticas SEC y 9 RATE, con SHA de fila completa.

## Tabla de los 3 choques nuevos
| Fuente | ¿choca? | Motivo y reemplazo exacto |
|---|---|---|
| **AUTH-044 CANDIDATO** | SÍ | Antes se expresa como entrega exclusivamente Brevo. Mantener Brevo principal y sus garantías; incorporar SMS **Intico solo habilitado por soporte con permiso**, después de actualizar correo y no recibir OTP; auditoría, validación server-side, **no automático**. AUTH-045 se limita a webhooks Brevo; Intico requiere contrato independiente. |
| **SEC-B2B-AUTH-ABUSE-PROTECTION / ID22 CANDIDATO** | SÍ | `PASSWORD_RECOVERY_OTP_SEND` y `AUTH_NEW_DEVICE_OTP_SEND` no representan recuperación de soporte Q11 ni OTP MFA en dispositivo reconocido por contraseña antigua. Separar controles de Login/IP, fallos escalonados de password, OTP MFA y caso de soporte; preservar IDs anteriores como legado, **sin crear códigos nuevos**. |
| **SEC-B2B-PASSWORD-CREDENTIAL / ID24 CANDIDATO** | SÍ | La config aún obliga `GOOGLE_WORKSPACE` y deshabilita password admin. Pasar perfiles 1–6 a usuario+contraseña validada por servidor, MFA condicional y recuperación con soporte, sin asegurar IDP real; mantener complejidad canónica y revocar tokens por cambio de password/recuperación aprobada. |

Todos los demás 228 incluidos en el alcance resultaron **NO CHOCA directo**; los 29 ya asignados a PR existentes no se repropusieron. El nuevo `proposed_text` íntegro y los cambios JSONB exactos están en `sandbox/lf_contract_gate_test/edge_function_operation/fixtures/lf_l41_remaining_conflicts_patch.json`.

## Hallazgos de alto impacto SIN actualización
- **AUTH-045 CANDIDATO:** autenticación webhook Brevo Bearer, independiente de SMS Intico. No convertir contrato Brevo en auth Intico.
- **SEC3 VIGENTE:** determina cobertura 1–6; la política25 de PR #3846 gobierna evento 30 días por dispositivo y contraseña 3 meses. No duplicar parámetros en SEC3.
- **RATE-B2B-LOGIN ID1 VIGENTE:** `scope_key=IP_USER`; no concluir que es IP-only sin confirmar H01. El escalonado de intentos es política `AUTH_LOGIN_FAILED_PASSWORD` en #3844, con contador independiente.
- **RATE7 CANDIDATO** para PASSWORD_RECOVERY_OTP y **RATE8 CANDIDATO** para NEW_DEVICE_OTP; ninguno acredita límites de soporte Q11 ni MFA por contraseña 3 meses. Se requiere mapping canónico, no inventar regla/policy ni reutilizar silenciosamente.
- **REG_ALR_003 VIGENTE** de onboarding Cliente registra `activar_fallback_sms`: no aplicar automáticamente a Login B2B; el PR #3847 lo identifica como transversal. WhatsApp/OTP Cliente no se sustituye por Intico B2B.
- **THEME-001/002/003 B2B** y diseño vinculado a Login no contienen HEX de color directos; THEME-002 ya asignado a #3844. Hay cuatro UX de otras superficies con HEX, fuera de este permiso de edición.
- **B2B-AUTH-002/003/004/005/006** están en #3847, con decisiones H01–H05: recovery Cliente, reloj 48h, aviso fallido, compatibilidad de AUTH-041/044/045; L41 no duplica pantallas ni cambia vinculación.

## Decisiones humanas separadas de gates técnicos
`audits/login-b2b-lote41/03_decisiones_humanas_separadas.json`: H01 decidir `IP_USER` vs IP exclusivamente para RATE1 y sus efectos NAT; H02 actos ya en PR3847 (no duplicar); H03 opción C, Brevo/Intico y token de diseño **ya decididos en conversación, aún sin firma**. Ingenieros deben resolver integración Intico, rate limit general MFA, rate por expediente soporte, proveedor/fecha de contraseña y procedencia sec; no son aprobaciones del dueño por sí solas.

## Prueba laboratorio y garantías
- `test_lf_l41_b2b_impact_pg17_pg18.py` crea PostgreSQL **17.6 y 18.7** desechables; reconstruye **226 +25 +9 =260 preimágenes** con `jsonb_populate_record` y verifica SHA.
- Ejecución de prueba: `BEGIN` → tres `UPDATE` → SHA interno de 260 filas → `ROLLBACK` → SHA completo; 257 filas deben quedar intactas incluso dentro de la transacción.
- Para SEC22/24 se recrea el guard real `programacion.fn_guard_input_parameter_provenance_v1` y un negativo sin provenance debe ser rechazado.
- Procedencia propuesta `LF_PROVISIONAL_DEFAULT/LF_PROVISIONAL` por `identity_verified=false`; no es firma, ni registro canónico aprobado.
- **No probar producción**: 0 escrituras Supabase vivo, 0 escritor V2, 0 promociones; sin API externa para producción. CI exact HEAD y PASE deben comprobarse antes de etiquetar PASS del laboratorio.

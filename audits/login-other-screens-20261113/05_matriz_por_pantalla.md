# Auditoría otras pantallas autenticación — solo SELECT / PR DRAFT
EKB consultada: INPUT GOVERNANCE LF V1.4 (CANDIDATO VERIFICADO PARCIALMENTE). Ruta oficial de cualquier ejecución futura: Router → perfil → IG si aplica → escritor oficial → validación → readback. Este PR solo prepara una propuesta, sin promoción, sin writer vivo.
Fuente: SELECT `lf_ops.pantallas` + `lf_ops.reglas_pantallas` + `lf_ops.reglas`. Base main `f9d20b3add2418ddae3f3372ccc0b0a49e3a9f6f`. Total **344 vínculos / 8 pantallas**; además 3 reglas nuevas propuestas (5 vínculos).
## Tabla por pantalla: regla | choca/falta | nuevo texto
| Pantalla (reglas V/C) | Regla y choque/falta | Propuesta concreta |
|---|---|---|
| B2B-AUTH-002 (25/7) | AUTH-028, AUTH-042: OTP recovery vs soporte | Abrir caso con DNI escaneado, aprobadores política 20, aviso anterior, auditoría, 48 h, clave temporal única; rate limit por solicitud soporte |
| B2B-AUTH-003 (26/6) | AUTH-029: contexto posterior a OTP; nuevo soporte | PASSWORD_UPDATE_ONLY solo tras expediente aprobado y clave temporal única; no sesión |
| B2B-AUTH-004 (29/10) | MFA continúa en PR #3844/#3846 y reglas protegidas | SIN CAMBIO; usuario + contraseña + OTP correo Brevo cuando aplique; SMS Intico solo contingencia de soporte; proveedor real/QA pendiente |
| B2B-AUTH-005 (21/3) | Pantalla REEMPLAZADO, activa=false | NO TOCAR: 24 enlaces, 21 reglas con estado VIGENTE. SELECT prueba inactividad de pantalla, no ausencia de reglas enlazadas ni de consumidores que las lean |
| B2B-AUTH-006 (25/9) | AUTH-029/037/038: OTP recovery y reenvío contra soporte | Verificar expediente de soporte, espera 48 h server-side, notificación y clave temporal única; no reenviar código recovery |
| ONB_001 (70/4) | No hay cambio exclusivo seguro; REG_UNI_002 compartida con otras 23 pantallas | Mantener OTP celular WhatsApp y tránsito ONB_002; revisar respuesta anti-enumeración por PR transversal |
| ONB_002 (99/5) | UI_STATES_001 muestra SMS automático; REG_ALR_003 activa fallback global | Ocultar SMS sin activación de soporte, Intico solo contingencia auditable; regla candidata nueva; REG_ALR_003 transversal no se toca |
| REC_001 (5/0) | IDV_STEPUP, IDV_OUTCOME, PHONE_CONTROL, REBIND_ATOMIC VIGENTE desconocen Q11 soporte | DNI escaneado, dos operadores distintos, avisos celular/correo anteriores, 48 h, prueba manual verificable, rebind solo después |
## Reconciliación de reglas compartidas
AUTH-041/044/045 siguen enlazadas a recuperación y MFA. No se cambia su texto ni se elimina relación en este lote, porque también sirven a B2B-AUTH-004; requiere prueba de consumidores antes de desvincular. REG_ALR_003 y REG_UNI_002 se comparten con otras 23 pantallas; REG_FLOW_PHONE_BRANCH_001 también alcanza ONB_003. Este PR no amplía alcance de esos contratos. Reglas protegidas de #3844/#3846: todas INTACTAS.
## Decisiones humanas pendientes
- H01: **Selfie en recuperación Cliente** — No activar selfie ni darla por prueba aprobada hasta decisión explícita sobre liveness, seguridad, consentimiento y QA.
- H02: **Proveedor IDV para recuperación Cliente** — Dejar PENDING_CANONICAL_IDV_PROVIDER; definir proveedor y pruebas antes de aceptar VERIFIED automático.
- H03: **Inicio de la espera de 48 horas B2B y Cliente** — Iniciar después de completar aprobación(es) y avisos al contacto previo, con timestamp server-side auditable.
- H04: **Avisos al contacto anterior fallidos** — Bloquear liberación hasta definir tratamiento alterno gobernado, sin bypass silencioso.
- H05: **Enlaces compartidos de OTP Brevo en pantallas de recuperación** — Reconciliar por PR independiente los vínculos AUTH-041/044/045 sin afectar B2B-AUTH-004 ni reglas cubiertas por #3844/#3846.
## Evidencia / límites
- Inventario completo regla–estado–choque–texto nuevo: `01_inventario_regla_estado_choca_texto.csv` (344 filas originales + 5 vínculos INSERT propuestos).
- Snapshot `sandbox/lf_contract_gate_test/edge_function_operation/fixtures/lf_other_auth_screens_20261113_source_patch.json`: cada regla UPDATE conserva fila `to_jsonb(r)` y SHA256 real desde SELECT. Total **10 UPDATE**, **3 INSERT**, **5 nuevos enlaces**. Todo marcado documental/candidato; nunca activar aquí.
- SQL `04_propuesta_update_insert_rollback.sql` lleva BEGIN/ROLLBACK, previas SHA y cero cambios persistidos.
- Test Docker PG17.6 y PG18.7 `sandbox/lf_contract_gate_test/edge_function_operation/test_lf_other_auth_screens_20261113_pgdual.py`: para cada UPDATE e INSERT comprueba SHA-256 antes, durante y tras ROLLBACK, sin conectarse al Supabase real.
- Riesgos: semántica antigua en asociaciones compartidas; REEMPLAZADO no prueba ausencia de lectores de vínculos; provider IDV y selfie sin decidir; dark mode, QA, aprobaciones y emisión real no verificados. **NO-GO** para promoción.

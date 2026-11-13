# B2B-AUTH-001 / B2B-RULE-AUTH-* — informe de sandbox y gates de promoción
Fecha de corte: 2026-11-12 (America/Lima).
Repositorio: `cristhianlujan/claude-persona-lf-patch`; base SHA `882c7213f83887952a99ad0793174d535eb91233`.
Rama aislada: `lf/auth-login-b2b-ig-sandbox-20261112`.
Estado global: **BLOCKED_FOR_PROMOTION**. Este documento NO acredita ejecución gobernada, QA ni autorización de producción.

## Alcance / evidencia de entrada
- EKB: `INPUT GOVERNANCE LF — INSTRUCCIONES OPERATIVAS V1.4`, arquitectura `USUARIO -> ACT-0001 -> PERFIL -> RUN -> INPUT GOVERNANCE (si aplica) -> VALIDACIÓN -> JUEZ -> REGISTRO -> CIERRE`.
- Supabase: `mhwmirqcgxxukpctffuv`, conexión `read_only`, única rama listada `main` (no hay sandbox DB autorizado aquí).
- `lf_ops.reglas`: 47 códigos `B2B-RULE-AUTH-*`, 31 directamente asociados a `pantalla_id=51`, 9 `VIGENTE`, 38 `CANDIDATO`, 1 de estos con `pendiente_decision=true` (`AUTH-047`).
- Referencia: `01_inventario.json` con ID, estado, vínculo a pantallas, claves config y MD5 de lectura. Este MD5 **no** sustituye el hash canónico `lf_asset_snapshot_sha_v1`; SELECT de esa función devolvió `permission denied`.
- Readback canónico IG de pantalla 51: `programacion.input_readiness_runs.id=951`, `status=COMPLETED`, `contract_revision=5.13.1`; `fn_input_governance_continuation_currentness_v1(951)` devolvió `COMPLETED_CURRENT`, `source_current=true`, `classifier_checked=false`, `semantic_depth_checked=false`. La metadata del RUN declara `validator_semantic_mode=SOURCE_INTEGRITY_ONLY`, `semantic_promotion_authorized=false`, `production_authorized=false`. **CURRENT no es autorización de promoción**.
- Políticas centrales: seguridad 3 `SEC-B2B-MFA=VIGENTE`; seguridad 19 `SEC-B2B-MFA-FACTOR-ELIGIBILITY=CANDIDATO`; 20 `SEC-B2B-MFA-RECOVERY=CANDIDATO`; 25 `SEC-B2B-TRUSTED-DEVICE=CANDIDATO`.

## Ejecución efectiva y evidencia
- Propuestas de mejora en `02_patches_candidatos.json`: `AUTH-016` (separación timeout vs binding/QA), `AUTH-020` (recuperación segura y no-bypass), `AUTH-033` (dispositivo reconocido condicionado a política y verificación server-side).
- **Ninguna propuesta se aplicó a Supabase**. No se cambiaron `estado`, `valor_config`, ID, relaciones ni políticas. No se incluyeron migraciones ejecutables ni se activaron workflows.
- Pruebas: `03_checks_staticos.json`; 18 verificaciones deterministas sobre lectura de fuentes + texto candidato = 18 PASS, 0 FAIL. Son checks estáticos locales a la evaluación, **no** E2E y **no** juez semántico independiente.
- Readback GitHub: tres archivos creados, recuperados y parseados desde la rama. Readback de Supabase para los IDs 435, 439 y 452 conservó el MD5 de lectura original y el mismo estado.

## Bloqueos de promoción, sin alterar su autoridad
| Gate | Dependencia | Evidencia exigida para desbloquear |
|---|---|---|
| G01 SANDBOX | No existe conexión a una DB sandbox aislada en herramientas disponibles | `project_ref` de entorno aislado y copia/seed controlada de relaciones/políticas; constancia de no producción |
| G02 INGRESO | No se ejecutó un nuevo `ACT-0001` / Gate2 / `EJECUCION_PERFIL_LF` | Nuevo `execution_id`, handoff íntegro `CONTEXT_TRANSPORT`, perfil seleccionado y recibos 0..80 (11/11) |
| G03 IG+JUEZ | IG `951` está CURRENT, pero NO tiene comparador semántico certificado ni autoridad de promoción | Context pack del nuevo RUN, Curator+Validator independientes si aplica, juez V3, firma/procedencia, receipts y hashes |
| G04 IDENTIDAD | `AUTH-015/026/048`: endpoint/grant/binding siguen `UNDEFINED/PENDING_ADR_003_M1_SPIKE` | Decisión ADR-003 M1, binding de identidad en staging, pruebas OIDC/JWT/JWKS, sin suponer disponibilidad |
| G05 FACTORES MFA | Política 19 `CANDIDATO`; SAML Google Workspace y correo Brevo en implementación | Autorización gobernada de política y evidencia MFA por cada perfil, rechazo fail-closed y no AAL2 nativo de correo |
| G06 RECUPERACIÓN | Política 20 `CANDIDATO`, procedimiento del buzón perdido `PENDING_FUNCTIONAL_DEFINITION` | Decisión del dueño, identidad independiente, auditoría, QA; prohibir bypass |
| G07 DISPOSITIVO | Política 25 `CANDIDATO`, `AUTH-033` permite outcome reconocido condicionado; potencial desalineación `USER_SUSPENDED` de política vs `DISABLED` canónico de `AUTH-039` | Reconciliación de estados, evaluación de consumidores, permisos y pruebas de expiración/revocación; no inventar equivalencia |
| G08 OTP / webhook | `AUTH-044/045`: `secret_storage_status=BLOCKED_NO_DESTINATION` | Destino de secretos y rotación autorizados, firma/autenticación webhooks probada, eventos idempotentes |
| G09 PARÁMETROS | `AUTH-047` tiene `dependency_status=MISSING` para política de intentos de contraseña | Política canónica o decisión explícita de excluir AUTH-047 de promoción; no asumir definida |
| G10 QA | `AUTH-016/022` tienen implementación/QA pendiente | E2E staging: anti-enumeración, MFA, trusted-device, sesión, rate limit, OTP, recobro, logs sin secretos |
| G11 INTEGRIDAD | No se pudo obtener SHA canónico por permisos | Hash oficial, preimage guard, ledger y comparación Git=ledger=DB bajo escritor autorizado |
| G12 PROMOCIÓN | No hay aprobación de owner, juez ni recibo terminal nuevo | Promoción por regla a través de operación oficial con aprobaciones, evidencias y recibo terminal READY |

## Readback del flujo de 11 pasos de perfil
La operación contractual `EJECUCION_PERFIL_LF` registra órdenes `0,10,20,30,40,45,47,50,60,70,80`. En **este lote**: `execution_id = null`; todos `NOT_EXECUTED_ON_SANDBOX`. No se inventaron `evidence_ref`, tickets, hashes SHA256, llamadas del juez ni respuestas RAW.
El RUN de IG `951` es **histórico**, no la ejecución de este trabajo. No sustituirlo por un nuevo RUN ni transformarlo en PASS.
`public.lf_profile_execution_terminal_authority_receipt_v1` no fue llamado: no existe execution_id nuevo.

## Ruta operativa siguiente
1. Proveer o habilitar sandbox Supabase realmente aislado y con ruta oficial de escritor, sin conectar a producción.
2. Releer contratos vigentes de Router/Perfil/IG, abrir RUN nuevo desde `ACT-0001` y transportar Gate2 íntegro (sin secretos en prompts).
3. Aplicar solo propuestas aceptadas como candidatos **por Train/operación gobernada**; estudiar consumidores de AUTH-033 y políticas 19/20/25 antes de alterar comportamiento.
4. Ejecutar suite de negativos y E2E, juez independiente, readback Git/ledger/DB, 11/11 pasos y recibo terminal.
5. Solicitar dictamen de elegibilidad y autorización de promoción. **Sin G01-G12 acreditados, no promover.**

## Límite de afirmaciones
- La revisión semántica del asistente no acredita independencia del juez; la prueba estática no demuestra ejecución real.
- La rama es únicamente documentación de cambios candidatos; el despliegue funcional y la promoción permanecen bloqueados.
- No se alteró el Router, el perfil, las fuentes oficiales ni producción.

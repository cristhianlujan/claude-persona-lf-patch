# PE10A SR03/SR04 — Implementación parcial controlada (2026-11-03)

Estado: CANDIDATE / NO_ENFORCEMENT / NO_E2E. No es autorización de producción ni cierre de checkpoints.

## Arquitectura que debe respetarse

ACT-0001 → EJECUCION_PERFIL_LF (Reparador SRCR) → llamada de capacidad del perfil (CONTEXT_PACK) → ACTUALIZACION_PERFIL_LF (17 etapas) → recibo verificable → continuar run SRCR.

**Patrón reutilizado de Input Governance:** `input_validate(40)` evalúa aplicabilidad y retorna `INPUT_GOVERNANCE_RUNTIME_REQUIRED` o `READY`, asociado a `consumer=CONTEXT_PACK` y `resume_via=EJECUCION_PERFIL_LF/input_validate`. El Updater debe usar **el mismo mecanismo de capacidad perteneciente al perfil**, pero **después de resultado real del Reparador validado por `semantic_judge(70)` y `report_output(80)`**, no durante `input_validate`. No se duplica el Router ni se vuelve a decidir la intención.

**El contrato JSON de este PR es el payload especializado de la capacidad, NO un contrato de nueva ruta de navegación.** Mantiene campos de trazabilidad necesarios para ligar parent/child y el recibo; los campos no son autoridad, el servidor los relee.

El Router clasifica/deriva; SRCR diagnostica y solicita, pero no llama otro perfil ni escribe por su cuenta. GitHub Actions/OIDC, Edge y RPC son transporte técnico, no autoridad para decidir.

## Lote entregado: SR03 (contrato candidato)

- Contrato tipado en contracts/LF_SRCR_UPDATER_HANDOFF_V1_CANDIDATE.json.
- Preflight determinista en skills/profile_creator/validators/srcr_updater_handoff_v1.py y pruebas negativas.
- Exige parent run, perfil SRCR, mismo request, target/path/scope exactos, SHA40 de main y blob objetivo, SHA256 de Router, policy y diagnóstico, `context_transport=CONTEXT_PACK`, `consumer=PROFILE_EXECUTION`, `resume_via=EJECUCION_PERFIL_LF`.
- Devuelve READY_FOR_SERVER_VERIFICATION, nunca PASS, dispatch_authorized ni escritura.
- No reutiliza repair_execution_authority de SRCR: su único intent actual de escritura es REPAIR_MISSING_PRODUCT_STRUCTURE, que no da permiso general para Updater.
- La entrada/continuación del Reparador sigue por el mecanismo existente `LF_PROFILE_NATIVE_BEGIN_REQUEST_V1` / `LF_PROFILE_NATIVE_RESUME_REQUEST_V1` (Issue `lf-profile-resume-governed` → GitHub OIDC → Edge → RPC). Este PR no altera ni duplica ese transporte.

## SR04: integración pendiente y bloqueada por autoridad

Para integrar: (1) orquestador relee del servidor parent EJECUCION_PERFIL_LF autorizado y comprueba `semantic_judge(70)` + `report_output(80)` limpios; (2) lee la salida real de SRCR y autoriza la solicitud de Updater con alcance exacto; (3) congela parent/child/scope/SHAs en init de Updater; (4) usa la ruta de continuación del perfil existente y el dispatcher Updater existente (issue+label/OIDC) como adaptador de capacidad, sin nueva ruta Router ni service_role en Router; (5) retorna recibo terminal auténtico y HEAD SHA exacto al run SRCR identificado, sin crear otro run de perfil y registra recepción; (6) juez independiente verifica readback Github/Supabase/runtime. Una estructura JSON sola no demuestra ninguno de estos pasos.

## Evidencia LIVE de partida

- En 92 manifests de ACTUALIZACION_PERFIL_LF: 0 con parent_profile_execution_id, 0 con repair_execution_authority.
- El run SRCR EXEC-PROFILE-GATE2-B6070E56727C1FB64437B850 está READ_ONLY y repair_execution_authority=null.
- PE10A_SR03, PE10A_SR04, PE10A_ST12 y PE10A_OP08 están PENDING, sin recibo final.

## Falsificadores para siguiente lote

Rechazar sin parent, SALY, target equivocado, path traversal, scope extra, digest inválido, autoridad fabricada, política obsoleta, retorno con otro child, PASS autodeclarado, recibo ausente, replay, cambio de permisos o nueva ruta directa.

No merge hasta revisión independiente, enforcement server-side y E2E. No se modifica ACT-0001, Edge, RPC, perfiles, permisos ni producción con este PR.

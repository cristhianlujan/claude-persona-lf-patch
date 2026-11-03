# PE10A SR03/SR04 — Implementación parcial controlada (2026-11-03)

Estado: CANDIDATE / NO_ENFORCEMENT / NO_E2E. No es autorización de producción ni cierre de checkpoints.

## Arquitectura que debe respetarse

ACT-0001 → EJECUCION_PERFIL_LF (Reparador SRCR) → Orquestador gobernado → ACTUALIZACION_PERFIL_LF (17 etapas) → recibo verificable → Reparador.

El Router clasifica/deriva; SRCR diagnostica y solicita, pero no llama otro perfil ni escribe por su cuenta. GitHub Actions/OIDC, Edge y RPC son transporte técnico, no autoridad para decidir.

## Lote entregado: SR03 (contrato candidato)

- Contrato tipado en contracts/LF_SRCR_UPDATER_HANDOFF_V1_CANDIDATE.json.
- Preflight determinista en skills/profile_creator/validators/srcr_updater_handoff_v1.py y pruebas negativas.
- Exige parent run, perfil SRCR, misma solicitud, target/path/scope exactos, SHA40 de main y blob objetivo, SHA256 de Router, policy y diagnóstico.
- Devuelve READY_FOR_SERVER_VERIFICATION, nunca PASS, dispatch_authorized ni escritura.
- No reutiliza repair_execution_authority de SRCR: su único intent actual de escritura es REPAIR_MISSING_PRODUCT_STRUCTURE, que no da permiso general para Updater.

## SR04: integración pendiente y bloqueada por autoridad

Para integrar: (1) orquestador relee del servidor parent EJECUCION_PERFIL_LF autorizado; (2) lee la salida real de SRCR y autoriza la solicitud de Updater con alcance exacto; (3) congela parent/child/scope/SHAs en init de Updater; (4) transporta por issue+label y OIDC sin nueva ruta Router ni servicio-role en Router; (5) retorna recibo terminal auténtico y HEAD SHA exacto a SRCR y registra recepción; (6) juez independiente verifica readback Github/Supabase/runtime. Una estructura JSON sola no demuestra ninguno de estos pasos.

## Evidencia LIVE de partida

- En 92 manifests de ACTUALIZACION_PERFIL_LF: 0 con parent_profile_execution_id, 0 con repair_execution_authority.
- El run SRCR EXEC-PROFILE-GATE2-B6070E56727C1FB64437B850 está READ_ONLY y repair_execution_authority=null.
- PE10A_SR03, PE10A_SR04, PE10A_ST12 y PE10A_OP08 están PENDING, sin recibo final.

## Falsificadores para siguiente lote

Rechazar sin parent, SALY, target equivocado, path traversal, scope extra, digest inválido, autoridad fabricada, política obsoleta, retorno con otro child, PASS autodeclarado, recibo ausente, replay, cambio de permisos o nueva ruta directa.

No merge hasta revisión independiente, enforcement server-side y E2E. No se modifica ACT-0001, Edge, RPC, perfiles, permisos ni producción con este PR.

# Recuperación — aviso histórico, canal alterno y reglas de acceso (PR #3847)
Decisiones del dueño en conversación; **identity_verified=false**, no evidencia de integración real, no producción. Historia: 06_owner_documentary_decision_2203.json. Actualización de REC_001: 09_owner_documentary_decision_2338.json.

## CLIENTE (REC_001, decisión 23:38 — reemplaza interpretación previa)
- Recuperación/cambio del celular: aviso al **correo ANTERIOR previamente verificado** del titular. Recuperación/cambio de correo: aviso al **celular ANTERIOR previamente verificado**. El **OTRO** canal verificado, no ambos de forma indiscriminada.
- El contacto adicional/secundario es **opcional** en onboarding, no requisito de ONB_004. ONB_004 pide email primario durante alta, no un contacto de contingencia.
- Exigir creador del caso distinto de aprobador(es), `approvers_required` en policy_config Cliente (1 o 2), DNI escaneado, y entrega `DELIVERED` del aviso al canal histórico. Tras gates, entrada **INMEDIATA** en `LIMITED_ACTIVE` sin esperar duración de ventana.
- Si no hay canal histórico verificable, rebote, no entregado o falta de evidencia: **SIN limitado**, incidente de soporte alternativo auditado y **sin bypass**. No aceptar automáticamente un contacto recién declarado, familiar, aprobador o personal de soporte.
- Durante ventana parametrizada, backend autoriza consulta y pago de deuda existente; bloquea operaciones listadas en la política Cliente. Si el dueño real OBJETA y se verifica el evento: revocar sesión y tokens inmediatamente.
- **Solo decisión humana pendiente** para contingencia: prueba alternativa independiente/autorización para un caso sin canal histórico DELIVERED. La lista de contactos secundarios aceptables como equivalentes no está aprobada. IDV pendiente, selfie NO activa.

## B2B (mantener alcance documental anterior)
- Recuperación B2B-AUTH-002/006 por soporte: aprobaciones (política20, todavía sin approvers_required verificable), aviso anterior y espera B2B según alcance anterior. **NO aplicar el acceso Cliente LIMITED_ACTIVE a B2B**, porque el dueño habló solo de recuperación Cliente.
- Reglas MFA Brevo y compartidos conservados sin modificación fuera de PR #3844/#3846.

## Advertencia de implementación
La política candidata `SEC-CLIENT-RECOVERY-LIMITED-ACCESS` solo existe en el fixture del PR. No se ha ejecutado DML/DDL en Supabase; el runtime no reconoce ni puede aplicar esta decisión hasta escritor oficial, sesión server-side y QA.

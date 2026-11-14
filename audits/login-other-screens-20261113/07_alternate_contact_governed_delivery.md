# PR #3847 — decisión del dueño 22:03 Lima (documental; identity_verified=false)
## Puerta determinista cerrada documentalmente
1. Inicio 48 h = MAX(última aprobación requerida completada, última entrega CONFIRMADA al contacto histórico requerido); no usar request_at, SEND, ACCEPTED o QUEUED.
2. Cliente Q11: creador y aprobador distintos; avisos obligatorios al celular anterior Y correo anterior, ambos con evidencia DELIVERED. B2B: 1 o 2 aprobadores desde política 20 (valor inicial documental 1); aviso al contacto previo DELIVERED.
3. Rebote, rechazo, retraso sin prueba o revocación: NO_STARTED o PAUSED; reloj server-side acumula únicamente tiempo elegible. BLOCK emisión de clave temporal, rebind, sesión y promoción mientras falte entrega. Recuperar solo con prueba confirmada y readback de condiciones.
4. Soporte puede abrir incidencia alternativa con case_id, actor, motivo, original delivery attempt, timestamp, correlation_id, consentimiento cuando corresponda, escalamiento y autorización; un segundo aviso a un mismo contacto anterior preexistente que termine DELIVERED sí acredita entrega. Un destinatario diferente no la acredita automáticamente.
## Contactos alternos propuestos — NO aceptados aún
- Contacto **del mismo titular**, correo secundario previamente registrado y VERIFICADO antes de abrir el caso (no solo un email capturado).
- Contacto **del mismo titular**, celular secundario previamente registrado y VERIFICADO antes de abrir el caso.
- Para B2B, cualquier contacto corporativo de seguridad previamente designado y verificado necesitaría decisión explícita adicional; NO autorizar administradores, aprobadores ni soporte como sustitutos por defecto.
**PROHIBIDOS**: teléfono/correo recién suministrados durante recovery, familiar/tercero, capturas de DNI por mensajería, dato que no pueda vincularse mediante historial auditable. La selección de la lista con autoridad para sustituir al contacto anterior es H04A/H04B; mientras no se apruebe, FAIL-CLOSED. No se encontró en lf_ops.empresa_usuarios un campo de 'verified secondary contact' en consulta de columnas; NO declarar proveedor de notificaciones/entregas integrado.
## Decisions / technical evidence
H01 cerrado: NO selfie, sin ruta ni regla operativa. H02 IDV pendiente. H03 definido: aprobaciones + DELIVERED. H04 semántica de bloqueo/pause definida; excepción de destinatario alterno pendiente (H04A/H04B).
**Riesgo de sincronización**: política 20 viva CANDIDATO y `policy_config.approvers_required` no consta en SELECT actual; PR #3844 / #3846 la gestionan, NO EDITAR aquí. No habilitar recuperación en producción sin readback de esa política y receipts de entrega.

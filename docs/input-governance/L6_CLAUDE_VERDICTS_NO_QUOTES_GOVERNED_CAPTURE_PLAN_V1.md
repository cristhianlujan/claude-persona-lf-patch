# LF L6 — captura gobernada de citas, RUNs y condiciones de aprobación
**Estado:** DRAFT / NO-GO · solo sandbox PG18 con ROLLBACK · no producción / merge / Router / APPLY live.

## Medición aportada por auditor
- **Fixture:** `lote6_claude_blind_5pass_verdicts_not_native_ig_receipt_v1.json`
- Etiqueta **obligatoria:** `REVIEW_5PASS_VERDICTS_NOT_NATIVE_IG_RECEIPT_MODEL_UNATTESTED`.
- Fuente: 3 bloques literales aportados por auditor, 154 resultados individuales de 5 pasadas declaradas idénticas. **CI no reproduce de nuevo las 5 pasadas ni sus citas**. N=5 es una declaración del auditor, no cinco transcriptos en el fixture.
- 130 BLOCK, 24 ALLOW; 154 IDs coinciden con el paquete ciego; cotejo clave/reportes coincide sin filtrarlos al reviewer.
- En los 154 casos: `citation_status=UNVERIFIED_NOT_CAPTURED`, `exact_excerpt=null`. **NO corresponde transformar ALLOW en cita válida**.
- El fixture **no se inserta en #3682** y no es un recibo de IG. Se usa únicamente para clasificación no autorizante en base PG18 descartable. No se crea modelo ni juez adicional.
- **ALLOW sin cita:** `PROFILE_OWNER_CITATION_CAPTURE_REQUIRED` (revisión humana del perfil, sin autorización de aplicar). **BLOCK:** `HUMAN_DECISION_REQUIRED` (sin promoción). Si hash/cita faltan, `lf_rule_promotion_blind_verdict_pin_v1` + `apply_v1` existentes hacen fail-closed.

## Captura de citas — **propuesta, no ejecutada**
1. Exportar las 5 conversaciones «Revisión de reglas semánticas» sin editar mensajes, conservando identificador del chat, fecha y orden del turno. No recrear/resumir citas.
2. Calcular SHA256 del archivo bruto completo de cada conversación y de cada línea `id|ALLOW/BLOCK|cita literal`. Vincular por ID opaco del fixture, hash del paquete ciego, SHA256 del caso y fuente exacta (campo `base_rule` o `proposal`).
3. Verificar correspondencia **literal** (mismas letras, signos, espacios) con el texto de la regla/propuesta congelada. Si cita inexistente, duplicada, ambigua, de otro caso o de fuente no canónica → `UNVERIFIED_NOT_CAPTURED` / `HUMAN_DECISION_REQUIRED`.
4. Registrar los resultados a través de la **ruta existente IG → Validator #3682**, con RUN/Step70 propios y recibo oficial de la misma ejecución. El SHA del recibo, packet, candidato, snapshot y citas se anclan mediante el gate L5. **Prohibido registrar manualmente la prueba como recibo #3682**.
5. Releer el registro emitido y verificar hashes y cita exacta antes de autorizar el perfil propietario. Si faltan recibo real o fuente legítima, mantener DRAFT/NO-GO.
6. Los cinco chats del mismo modelo y el perfil del mismo modelo solo acreditan **consistencia**, nunca independencia.

## Lote de RUNs solo lectura
- Supabase REAL: **21** `ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF` `IN_PROGRESS` (19–23 septiembre 2026), **21 sin lease y checkpoint=0**, frente a 20 reportados por auditor.
- Grupos de clasificación de readback: 1 sin pasos, 6 con `semantic_judge=BLOCKED_STEP_NOT_CLEAN`, 5 con 12/12 pasos PASS, 5 parciales con evidencia GitHub readback y 4 parciales tempranos. Ninguno acredita cierre ni viabilidad de reanudar sin source currentness/contract/current lease/terminal authority.
- Los 3 RUN `EJECUCION_PERFIL_LF` antes tratados como descartables se reclasifican a **RECOVERY_REQUIRES_CONTEXT_VALIDATION_NOT_DISCARDABLE**. Ninguno ejecutó el paso 40: `10EE2A65` terminó en 10 (`PANTALLA, UNRESOLVED`), `FF4E8403` en 30 (`INPUT_GOVERNANCE, UNRESOLVED`), `35D0AD0C` en 30 (`REGLA, UNRESOLVED`, fecha 11 noviembre 2026).
- Fuente del contrato desplegado: `public.lf_profile_execution_input_validate_v1(text,text,text,jsonb)` contiene la rama directa IG que exige `p_handoff.scope.target_type = 'PANTALLA'` y devuelve `BLOCK_PROFILE_INPUT_GOVERNANCE_SCREEN_SCOPE_REQUIRED` de otro modo. **Ninguno de esos tres llegó al 40**; por tanto no hay evidencia de que el bloqueo concreto explique su interrupción.
- Acciones propuestas: revisar correlación, alcance, dependencia, validación, contratos y EKB de los mismos RUNs **solo con lecturas**; después solicitar decisión oficial sobre reanudar/superseder por operación gobernada. **No cerrar, modificar ni reutilizar estas ejecuciones en este lote**.

## Limitaciones
- Las funciones L5 de producción candidatas **no cambian** en L6: MD5 antes/después idénticos.
- El routing que permite al propietario **capturar la cita** existe exclusivamente como prueba de fixture en PG18; no es un nuevo RPC autorizado en runtime ni un permiso de aprobación.
- Sin citas ni recibo #3682, **no existe evidencia que habilite promoción automática**. La aprobación real por perfil y retorno efectivo del mismo RUN siguen `UNVERIFIED`.

**Corrección de procedencia L9:** la palabra histórica «Claude» en el nombre del archivo L6 no acredita modelo ni autor; etiqueta operativa neutral `REVIEW_5PASS_VERDICTS_NOT_NATIVE_IG_RECEIPT_MODEL_UNATTESTED`. No se cambia ningún veredicto ni se atribuye revisión a un proveedor. La etiqueta es una corrección de metadatos, no independencia.

# LF #3774 / Ratificación de reglas — control de autoridad

**Alcance:** Product Director sigue ejecutando IG y las operaciones existentes. No se añade skill, perfil ni ruta Router. Código candidato sin despliegue. La intervención humana NO se solicita por defecto por el mero estado CANDIDATO.

## Reutilización

- IG existente: `private.fn_lf_ig_candidate_promotion_authority_v1` clasifica específicamente TRANSITIONS y nunca se usa como permiso de acción sobre reglas.
- Autoridad de consumo: `programacion.fn_source_rule_authority` clasifica status de fuentes. No prueba paridad semántica por sí sola.
- Para regla `lf_ops.reglas`, nueva función de lectura `public.lf_rule_promotion_authority_assess_v1(screen_code)` comprueba decisión existente, estado owner, paridad exacta de `rule_code/title/description/reason/rule_config`, sucesión y flags de activación. **Si un campo material no está representado en la autoridad, NO PASS**.
- Ruta humana actual `lf_rule_promotion_decide_v1` se conserva. El trigger `lf_rule_promotion_guard_v1` y aplicación oficial `lf_rule_promotion_apply_v1` siguen vigentes.
- La ruta automática nueva `lf_rule_promotion_auto_ratify_v1(promotion_id,protected_receipt_id)` solo puede actuar con un recibo externamente emitido que ligue acción, fuente, snapshot, juez/seguridad, operación y currentness. Reutiliza `programacion.provenance_receipts`, su insert guard con token, y `lf_rule_promotion_v1`; no permite inventar identidad `HUMAN:`.

## Restricciones técnicas

- **No existe canal productivo** que emita actualmente `RULE_PROMOTION_ACTION_AUTHORIZATION`. Este cambio **NO crea ni activa issuer/canal**; por lo tanto en Supabase actual queda fail-closed aunque se desplegase. No declarar auto-ratificación productiva hasta configurar issuer externo autorizado, generar recibos auténticos y acreditar callback de Product Director.
- La fuente que solo dice `origen=... ` no sirve. `raw_payload.action_authorized=true` NO sirve. La aprobación funcional del owner no equivale a autorización de la acción.
- Prohibidos: `VIGENTE` con `pendiente_decision=true`, producción expresamente desautorizada, fuente reemplazada/ambigua, parámetros diferentes, recibo sin canal permitido, recibo con digest inconsistente, solicitud/ejecución no ligadas y replay.
- Exigir pruebas PostgreSQL 17 positivo, negativo de no-receipt/token, autoridad no aprobada, cambios de regla/snapshot, source drift, rollback, estado final; conservar PR en DRAFT hasta revisión independiente, source parity exacta y despliegue gobernado.

## Inventario real B2B-AUTH-001 (readback 2026-11-10)

- 33 reglas candidatas; 6 con enlaces T_REMED (técnicos, no necesariamente decisiones); 1 con decisión directa `DEC-B2B-AUTH-ROUTING-001` / #134 en `CANDIDATO_CONTROLADO`, sin autoridad de activación.
- Las demás requieren `SOURCE_LOOKUP_REQUIRED`/reconciliación de decisiones, no convocatoria masiva a humanos.
- Con datos actuales **0 reglas automáticamente promocionables acreditadas**.
- Las PR #3775 (LINK) y #3776 (CREATE) siguen en DRAFT con pruebas aisladas PASS. La promoción no depende de mezclarlas en una sola PR, pero producción necesita sus propios gates.

**Cierre técnico** = SQL y tests positivos/negativos PASS sobre HEAD congelado.  
**Cierre operativo** = issuer externo, readback Supabase, 33 reglas evaluadas, Product Director+IG E2E, trazabilidad de cada decisión y autorización de despliegue.

## Marca filtrable y paso posterior al juez (implementación candidata)

Migration `20261110181000_lf_rule_authority_marks_and_product_handoff_v1.sql`.

**Ruta oficial sin nueva etapa numerada ni segundo perfil:**

```text
ACT-0001 → Product Director → IG / fuentes / reglas (40/50)
  → output_validate (60) → semantic_judge (70)
  → subacción 70.5: lf_rule_authority_mark_refresh_v1(RUN, pantalla, evidencia)
     - guarda 1 marca por regla CANDIDATO
     - SOURCE_LOOKUP_REQUIRED = recuperar fuente, NO aprobación humana inmediata
     - SOURCE_NOT_OWNER_APPROVED = resolver decisión actual sin promoción
     - MATERIAL_PARITY_UNPROVEN = corregir semántica y revalidar
     - ACTION_AUTHORIZATION_RECEIPT_REQUIRED = autoridad semántica demostrada, falta permiso de ACCIÓN
  → subacción 70.5b: lf_rule_promotion_request_eligible_v1(RUN, pantalla, regla)
     - solo cuando el emisor protegido está configurado
     - reutiliza lf_rule_promotion_request_v1; NO inventa HUMAN:
     - registra PROMOTION_REQUESTED; espera recibo independiente
  → subacción 70.6: lf_rule_promotion_complete_tracked_v1(RUN, pantalla, regla, receipt_id)
     - reutiliza lf_rule_promotion_auto_ratify_v1 + apply oficial
     - APPLIED_VERIFIED + readback → PROMOTED_VERIFIED
  → report_output (80) con marcas y bloqueos por regla
```

**No cambiar los 11 pasos canónicos de EJECUCION_PERFIL_LF.** Las subacciones son llamadas bajo el RUN vigente, nunca un segundo Router ni una llamada del Router al perfil.

**Consulta para seguimiento en Supabase (solo lectura):**

```sql
SELECT pantalla_codigo, regla_codigo, estado_regla, marca,
       estado_flujo, motivo_codigo, source_decision_id,
       promotion_id, execution_id, evidence_ref, last_checked_at
FROM public.v_lf_rule_authority_filter_v1
WHERE pantalla_codigo = 'B2B-AUTH-001'
  AND marca IN (
    'SOURCE_LOOKUP_REQUIRED',
    'SOURCE_NOT_OWNER_APPROVED',
    'MATERIAL_PARITY_UNPROVEN',
    'REVALIDAR_SNAPSHOT',
    'ACTION_AUTHORIZATION_RECEIPT_REQUIRED',
    'PROMOTION_REQUESTED',
    'PROMOVIDA_VERIFICADA')
ORDER BY marca, regla_codigo;
```

La vista enumera reglas incluso antes de la primera corrida mediante `SIN_EVALUACION_REGISTRADA`. Las marcas efectivamente evaluadas se guardan en `public.lf_rule_authority_tracking_v1` con SHA y evidencia. Una modificación de la regla devuelve `REVALIDAR_SNAPSHOT` en la vista; un registro anterior NO autoriza escritura. `PROMOVIDA_VERIFICADA` exige estado VIGENTE y registro APPLIED en la operación de promoción.

**Reglas B2B actuales:** 32 SOURCE_LOOKUP_REQUIRED y 1 SOURCE_NOT_OWNER_APPROVED con la evidencia observada, **no 32 decisiones humanas**. La ejecución automática de búsqueda de las 32 fuentes sigue sin recibo, y la marca por sí sola no las remedia ni promociona. Estas fuentes deben resolverse por Product Director/IG, actualizando únicamente los metadatos gobernados de procedencia y reejecutando el juez.

**Limitaciones de activación:** Supabase actual no tiene el issuer `LF_RULE_PROMOTION_ACTION_AUTHORITY_V1`, las migraciones no están desplegadas, y Product Director no tiene E2E write-enabled demostrado. El paquete conserva NO-GO. No se crea issuer ni se pone service_role en Router.

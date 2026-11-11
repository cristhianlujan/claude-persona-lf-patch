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

## Lote 3 — Transporte OIDC hacia Product Director y contrato del recibo

**Corrección imprescindible al SQL base:** el esquema real `programacion.provenance_receipts` solo admitía ocho clases de recibo. Su `CHECK` (md5 `c7a32a57bc482030e35a10c2b3c09830`) no incluía `RULE_PROMOTION_ACTION_AUTHORIZATION`. La migración `20261110170000` ya añade ese tipo mediante DDL atómico, con guard del contrato exacto. **No se cambiaron el trigger de procedencia ni los tipos anteriores.**

**Conexión al runtime existente, sin Router ni perfil extra:**

- El mismo Edge caller `lf-profiles-governance-caller-v1` acepta ahora `profile_native_rule_authority_v1`.
- Ruta OIDC: solo identidad `GITHUB_ACTIONS_OIDC_GOVERNED_NATIVE_PROFILE_CONTINUATION_V1` y workflow exacto `.github/workflows/lf-edge-deploy-credential-readback.yml@refs/heads/main`, no `caller` suministrado por JSON.
- El RUN debe ser el Product Director exacto en `profiles/product_director_lf/SKILL.md`, read-only y con Router receipt.
- `MARK` → RPC `lf_rule_authority_mark_refresh_v1`; exige `evidence_ref` **idéntico** al recibo del juez 70 registrado.
- `REQUEST` → RPC `lf_rule_promotion_request_eligible_v1`; exige regla elegible, fuente y hash actuales, más emisor independiente provisionado.
- `COMPLETE` → RPC `lf_rule_promotion_complete_tracked_v1`; exige `receipt_id` real; la función ratificadora valida emisor, digest, currentness, regla y fuente antes de aplicar y cerrar.
- La función de transporte no emite recibos, no recibe service_role en la solicitud y no escribe `lf_ops.reglas` directamente.
- Respuesta `BLOCKED` del SQL → HTTP 409, nunca `COMPLETED` sintético.

Ejemplo de llamada **solo para documentación**, usando el canal OIDC ya autenticado:

```json
{
  "action": "profile_native_rule_authority_v1",
  "execution_id": "<RUN_EXISTENTE>",
  "source_revision": "<SHA_MAIN_VERIFICADO>",
  "screen_code": "B2B-AUTH-001",
  "rule_authority_action": "MARK",
  "evidence_ref": "<REFERENCIA_EXACTA_DEL_JUEZ_70>"
}
```

Para `REQUEST`, reemplazar `rule_authority_action=REQUEST` y suministrar `rule_code`; para `COMPLETE`, suministrar también `receipt_id`. En todos los casos el perfil espera salida y readback antes de reportar el paso 80; no se agregan etapas oficiales numeradas.

**Pruebas sobre fuente candidata:** 62 PASS PostgreSQL 17 aislado, 48 PASS Deno OIDC, PASE/F0 PASS. Ambas suites usan mocks/datos sintéticos; no constituyen emisión oficial ni implementación productiva.

**Pendientes con código exacto o contrato no acreditados:**
1. `LF_RULE_PROMOTION_ACTION_AUTHORITY_V1`: cero registros reales; falta emisor independiente y su política/credenciales protegidas, no basta con tener el nuevo tipo de recibo admitido.
2. `PROMOCION_REGLA_LF` no figura en `public.lf_operation_registry` aunque ya existen funciones de solicitud/decisión/aplicación y autoridad de perfil; revisar el contrato y registrar la operación por el proceso oficial antes de activarla.
3. Faltan 32 procedencias B2B por reconciliar. No inferir aprobación o equivalencia desde `origen`.
4. El perfil continúa `READ_ONLY` y el SQL nuevo aún no está desplegado. Se requiere el camino gobernado de despliegue, la prueba E2E sobre autoridad auténtica y readback.

**Estado operativo: DRAFT / NO-GO** para promoción efectiva. El número de PASS de CI aislado nunca se convierte en progreso productivo.

## Lote 4 — Arquitectura simplificada: un solo LLM, propuesta única de IG

**Ruta aprobada:** ACT-0001 → Product Director → Input Governance (diagnóstico, fuentes, solución propuesta en paso 40) → Product Director (acepta/ajusta/rechaza en paso 50) → validador 60 + juez oficial 70 → operación gobernada → readback → salida paso 80.

- La función **lf_ig_rule_proposal_prepare_v1** es read-only y requiere RUN original, recibo del Router, pantalla seleccionada y input_validate PASS. Entrega LF_IG_RULE_RESOLUTION_PROPOSAL_V1 por cada regla con issue, acción, justificación, fuentes conocidas, snapshot y SHA exacto.
- La Edge **profile_native_continue_v1** adjunta IG en el NATIVE_MODEL_INPUT_READY de Product Director. La misma ejecución y mismo LLM evalúan la propuesta sin enviar la solución de vuelta a IG para una segunda ronda semántica.
- Producto responde en **traceability.ig_rule_proposal_decisions[]** con cobertura exacta: rule_code, ig_proposal_sha256, disposition (ACCEPT_PROPOSAL, ADJUST_PROPOSAL o REJECT_PROPOSAL) y rationale. Sin coincidencia exacta, Edge bloquea ANTES de registrar RAW.
- Después del juez oficial 70, **lf_rule_authority_mark_refresh_v1** compara en SQL las decisiones Product Director contra las propuestas originales de IG y verifica SHA actuales, fuente, evidencia del juez y estado. No inserta marcas con validación incompleta.
- ADJUST_PROPOSAL y REJECT_PROPOSAL dejan marca **PRODUCT_IG_ADJUSTMENT_REQUIRED** o **PRODUCT_IG_REJECTED**, siempre en remediación sin promoción. Solamente ACCEPT_PROPOSAL puede continuar a solicitar autorización gobernada y únicamente si la fuente de negocio ya fue aprobada.
- La operación gobernada sigue exigiendo recibo protegido independiente de autorización de acción. El LLM nunca emite ese recibo ni se da permiso de escritura.

**Límite real:** 32 reglas B2B siguen sin vínculos acreditados de fuente original. Su primera propuesta segura es RECOVER_ORIGINAL_AUTHORITY, no una solución de negocio inventada. La recuperación documental detallada sigue pendiente de implementación/validación. No declararlas reconciliadas.

**Sin rutas ni jueces adicionales:** se conservan los once pasos oficiales; juez 70 permanece obligatorio, no se crea nuevo perfil ni se modifica ACT-0001. Los controles deterministas post-70 no constituyen otra evaluación semántica con otro LLM.

**Evidencia y estado:** PG17 y Deno se ejecutan en CI sobre HEAD específico; siempre volver a verificar el HEAD tras documentación. Supabase real no tiene issuer protegido activo y las funciones siguen no desplegadas; PR DRAFT / NO-GO.

## Lote 5 — Búsqueda determinista y recuperador de fuentes de 33 reglas

**Fuente oficial consultada antes de editar:** INPUT GOVERNANCE LF — INSTRUCCIONES OPERATIVAS V1.4 (Router solo selecciona; Product Director gobierna RUN e invoca IG; step 40/50/60/70/80); EKB activo INPUT-GOV-DECISION-RULE-PROVENANCE-PARITY-001.

**Nuevo recuperador read-only** `public.lf_ig_rule_source_recovery_v1(execution_id,screen_code)`: para cada regla candidata recopila determinísticamente origen, creador histórico, referencias directas a decisiones, menciones de la regla en otras decisiones (sin recontar la decisión directa), enlaces técnicos de T_REMED, relaciones a políticas de seguridad/sesión/rate-limit/timeout/OTP, estado de cada política y estado de la decisión fuente. Devuelve SHA de evidencia, `discovery_status`, y `owner_approval_proven=false` / `action_authorized=false`. No modifica reglas ni abre cola humana.

**Integración del flujo simplificado:** `lf_ig_rule_proposal_prepare_v1` agrega `source_recovery` y vincula `ig_proposal_sha256` a la evaluación semántica de autoridad *y* a la evidencia recuperada. Product Director la recibe una vez en la Edge OIDC antes del paso 50, decide por regla y el juez 70 sigue siendo obligatorio. Si cambia una política o fuente, el hash viejo pierde vigencia y bloquea cualquier marca o promoción.

**Acciones por tipo de pista sin afirmar aprobación:**
- Mención de decisión: `RECONCILE_RELATED_DECISION_REFERENCE`.
- Política explícita: `RECONCILE_POLICY_LINEAGE_AND_OWNER_DECISION`.
- Relación técnica: `RECONCILE_TECHNICAL_LINEAGE_TO_ORIGINAL_APPROVAL`.
- Sin pista directa en catálogos SQL: `SEARCH_ORIGINAL_OWNER_SOURCE`.

**Readback en Supabase oficial, únicamente SELECT, `B2B-AUTH-001`:** 33 reglas `CANDIDATO`: una con decisión directa (todavía `CANDIDATO_CONTROLADO`), y **32 sin aprobación fuente acreditada directamente**. Clasificación de las 32: 1 mención de otra decisión, 4 pistas de política explícita, 2 pistas de relación técnica, **25 sin fuente localizada dentro del alcance determinista SQL**. Se identificaron 6 reglas con vínculos T_REMED; algunas coinciden con pistas de política. Las fuentes originales pueden estar en otros documentos/proveedores; no afirmar ausencia absoluta. Evidencia por regla: `b2b_auth_001_source_leads_readback_20261110.json`, fuente read-only, sin valores inventados.

**Búsqueda documental complementaria:** Se consultó Google Drive por `B2B-AUTH-001`, `B2B LOGIN`, `B2B_AUTENTICACION` y títulos de handoff. El documento `IG-EVO — Registro único y acumulativo de hallazgos (R1–R6)` (Google Docs ID `1_12oOBUfn0Apmng7D9dqC4Nk3ladNJagRVgh2o-adKg`) contiene referencias técnicas de B2B-RULE-AUTH-021 y B2B-RULE-SECURITY-BASELINE-001, pero no se ha acreditado mediante esta lectura la decisión original exacta/material de las 25 pendientes. Se usa solo como referencia para investigación, no como autorización.

**Verificación PG17 aislado:** 84 PASS en HEAD anterior, incluidos descubrimiento, menciones, relación técnica, política con decisión CANDIDATO, cambio de política invalidante, sin aprobación implícita y promoción/rollback sintéticos; más Edge OIDC Deno 51 PASS. Obtener el readback de CI de HEAD final antes de afirmar pase en nuevo commit.

**NO-GO:** 0/32 reglas reconciliadas en autoridad de negocio, 0 promociones reales. IG ya puede identificar 7 pistas concretas, pero **aún debe realizar recuperación documental para las 25 sin fuente SQL**, después vincular decisión original + comparación de campos materiales y ejecutar operación gobernada. PR DRAFT, funciones sin desplegar, emisor protegido ausente y operación `PROMOCION_REGLA_LF` no registrada.

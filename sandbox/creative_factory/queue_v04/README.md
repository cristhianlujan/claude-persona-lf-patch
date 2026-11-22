# SALY · RENDER_READY admission V1 — candidato, no desplegado

**Lote:** continuidad de PR #4616 (cola global y Native dual). **Estado:** código candidato aislado, con prueba local, sin efectos ni permisos. No sustituye `skills/creative_factory/SKILL.md` v0.12 `PLAN_ONLY/REVIEW_ONLY`.

## Autoridad y fuentes

- `LF_resguardos_construccion.md`: B1 esquema leído antes de programar, B6 procedencia vs calidad, B11/B25/B28 pruebas negativas y mutantes por código, B12 puerta única, B13 variables en fuente canónica, B19 decisión del propietario, B30 registro distinto de publicación, B32 nada de valores del negocio en un motor compartido.
- `AGENTS.md`, `CLAUDE.md` y `.claude/operational-execution.md`: cambios por PR, verificación y readback; ningún merge fuera del Train ni DDL por Supabase RO.
- `supabase/migrations/20261029140000_lf_profile_native_executor_claude_parity_v1.sql`: modos `GPT_NATIVE/OPENAI_CHATGPT_NATIVE` y `CLAUDE_NATIVE/ANTHROPIC_CLAUDE_NATIVE`, en el **chat nativo actual**. Ese contrato es de perfiles LF y no concede permisos creativos.
- `skills/creative_factory/SKILL.md`, `saly.creative_native_canonical_wire_v1`, `sandbox/creative_factory/native_transport_capture_v1.py`: wire existente `SALY_CANONICAL_NATIVE_WIRE_V1` de solo revisión, snapshot y hash canónicos, archivo antes de enviar, `native_transmitted=false`. Reutilizar para PLAN, **nunca** promoverlo de facto a render.
- `saly.creative_execution_policy_v1(timestamptz)`: fuente de cuatro parámetros `CREATIVE_FACTORY`, cada uno con versión efectiva desde `saly.config_global`.

## Readback de Supabase del lote (22/11/2026, solo lectura)

`information_schema.columns` y `pg_constraint` releídos: `saly.creative_orders`, `saly.creative_order_items`, `saly.creative_runs`, `saly.config_global`. Dos pedidos `SALY_HOME_BATCH_001` y `SALY_HOME_TEMPLATE_AB_001`, **5 ítems PENDIENTE**, **0 RUN**, **0 filas CREATIVE_FACTORY**, `to_regclass('saly.creative_queue_claims_v1')=NULL`, `to_regclass('saly.creative_queue_delivery_receipts_v1')=NULL`. En ambos pedidos, `scope_json` deniega generación: `rendering_authority=false` o `render_authorized=false/review_only=true`. No se los mutó.

**ACL verificada:** la invocación en solo lectura de `SELECT saly.creative_execution_policy_v1(now())` devolvió `42501 permission denied for function creative_execution_policy_v1`. No se reintentó por credenciales ajenas ni se eludió la protección. El lector oficial futuro debe ejecutarla desde un contexto autorizado; las 0 filas de config se verificaron mediante `SELECT` directo a `saly.config_global`.

## Lo que hace `render_ready_gate_v1.py`

Contrasta **lecturas autorizadas del runtime**; la función no sabe conectarse a Supabase por sí misma y sus callbacks **no pueden venir del pedido**. Es una puerta de validación, no el emisor de permisos:
1. Exige `GPT_NATIVE` o `CLAUDE_NATIVE` con pareja exacta de proveedor, chat actual, sin API ni nueva sesión.
2. Exige `creative_execution_policy_v1` completo, `CREATIVE_FACTORY`, enteros válidos y fechas de vigencia; no aplica valores por defecto ni adopta los de fixtures.
3. Exige pedido nuevo en carril `SERIAL_V1` con `rendering_authority=true`, `render_authorized=true`, `review_only=false`; **no modifica los existentes**.
4. Exige RUN `EJECUTANDO`, ítem elegible, claim `ACTIVE` con el mismo trabajador, intento dentro del máximo y deadline/lease aún vigentes. Valida `execution_policy` del RUN contra snapshot vigente.
5. Exige un **contrato nuevo** `SALY_NATIVE_RENDER_WIRE_V1`, estado `RENDER_WIRE_FROZEN_AUTHORIZED`, atado al pedido, ítem, RUN, claim, modo, proveedor, hash del snapshot y del contrato. Comprueba SHA-256 del cuerpo y prompt; rechaza el wire `REVIEW_ONLY`, JSON duplicado y token de claim en el prompt.
6. Devuelve `RENDER_READY_CANDIDATE_VALIDATED_NOT_DISPATCHED`; explícitamente `image_generation_executed=false`, `provider_attested=false`, `host_delivery_verified=false`, `db_done_allowed=false`. No expone token.

**Importante:** `SALY_NATIVE_RENDER_WIRE_V1` es una **interfaz propuesta**; actualmente no tiene productor SQL activado. Un callback falso puede satisfacer los tests, pero nunca cuenta como evidencia de autorización de un runtime real.

## Pruebas locales realmente ejecutadas

```sh
cd sandbox/creative_factory/queue_v04
python -m unittest -v test_render_ready_gate_v1.py test_mutations_v1.py
```

**33/33 PASS** en Python 3.13.5 sobre archivos locales verificados idénticos a GitHub por hash de blob:
- `render_ready_gate_v1.py`: `b74ea4622e57eb84f462f14674936363c42f5d89`
- `test_render_ready_gate_v1.py`: `68d0b0a80042ebc48f8a919f4657b76018781b7a`
- `test_mutations_v1.py`: `ca52aa2fe5fb1a47e36c663442b7aa493193e1c4`

31 casos contractuales (2 positivos simulados) + 2 mutantes B25/B28 que anulan los controles `render_authorized` y `review_only`; se matan por el **AssertionError esperado** de ausencia del rechazo, no por sintaxis. Ningún test hizo una generación real ni una escritura de Supabase. **No hay ensayo PG17 con esquema íntegro** en este lote.

## Bloqueos y siguiente lote

1. **Aprobación operativa:** `CREATIVE_FACTORY` aún no tiene 4 valores reales; resolver y registrar por Router + migración PR/Train, con autoridad registrada. No inventar números ni reutilizar valores sintéticos.
2. **Puerta efectiva:** implementar productor SQL canónico `SALY_NATIVE_RENDER_WIRE_V1` desde fuente oficial/snapshot con checks, ACL, identidad de runtime, política versionada, idempotencia y ensayos PG17/ROLLBACK sobre esquema real. No usar `creative_native_canonical_wire_v1` de revisión como fuente de permisos.
3. **Entrega:** completar el transporte **de la sesión Native propietaria** al registro de resultado y destino, sin afirmar que GitHub Actions invoca el modelo ni que existe una API de ChatGPT/Claude para certificar host. Si no hay recibo confiable, no promocionar entrega/DONE. La RPC de texto del SQL v02 permanece **NO-GRANT / NO-DEPLOY**.
4. QA independiente, dos invocaciones concurrentes reales, mutantes SQL, PASE, PR gobernado y Merge Train de a uno. No etiquetar #4616 mientras persistan estos bloqueos.

**Estado real:** transición entre revisión y render **diseñada y validada como contrato**; operación productiva **NO habilitada**.

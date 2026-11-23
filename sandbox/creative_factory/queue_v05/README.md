# SALY · GPT_NATIVE / CLAUDE_NATIVE · SQL render wire (candidato)

**Lote:** continuación de [PR #4616](https://github.com/cristhianlujan/claude-persona-lf-patch/pull/4616). Sin despliegue, GRANT, RUN productivo ni generación de imagen.

## Fuente y diseño

Fuentes releídas: `LF_resguardos_construccion.md` (A1–A14, B1–B32), `AGENTS.md`, `CLAUDE.md`, `saly.creative_item_work_packet_l2c`, `saly.creative_item_visual_contract_l3b`, `saly.creative_assert_run_snapshot_v1`, `saly.creative_run_guard_l1`, `saly.creative_execution_policy_v1`, `visual.source_assets`, `saly.creative_item_sources` y SQL de la cola `queue_v02`.

**Hallazgo B1:** `creative_item_work_packet_l2c` retorna `RUN_ALREADY_ACTIVE` cuando el RUN está abierto. Por ello el productor **no lo reejecuta** durante el procesamiento: lee `creative_runs.input_snapshot.visual_contract.production_manifest.prompt_utf8`, generado y comparado **en el INSERT del RUN** contra `creative_assert_run_snapshot_v1` para ítems con `semantic_qa`. El trigger del RUN hace `input_snapshot` inmutable.

`creative_item_visual_contract_l3b` conserva un manifiesto de diseño `PLAN_ONLY`. No se eleva su `mode` ni el wire de revisión. Solo un pedido con `queue_mode=SERIAL_V1`, `rendering_authority=true`, `render_authorized=true`, `review_only=false`, un RUN `EJECUTANDO`, claim `ACTIVE` y política `CREATIVE_FACTORY` efectiva puede preparar un wire nuevo `SALY_NATIVE_RENDER_WIRE_V1`. El SQL NO escribe un permiso, no transmite y no autentica al modelo: `executor_identity_attested=false`.

## Secuencia prevista

```text
Pedido/interpretación aprobados y fuente versionada
   → L2C + visual contract congelados ANTES del RUN
   → Queue claim/admisión gobernada de RUN (snapshot inmutable)
   → RUN EJECUTANDO + lease activo
   → creative_native_render_wire_v1(claim_token, run_id, mode)
        • confirma política, autoridad, claim/worker y vencimientos
        • relee MANIFEST del input_snapshot, no recompila
        • valida SHA256 del contrato, prompt y fuente
        • devuelve wire_base64, wire_sha256 y lista de attachments con SHA/ref
   → host de la conversación GPT_NATIVE o CLAUDE_NATIVE:
        • recuperar bytes originales (Drive u origen autorizado)
        • SHA256 real de cada attachment y archive_pre_dispatch
        • ejecutar generación en sesión nativa actual
        • QA + artefacto + entrega con evidencia confiable
   → cierre SOLO por una puerta SQL autenticada pendiente
```

### Fuente exacta de adjuntos

El snapshot incluye `source_refs` provenientes de `saly.creative_item_context_l2a`; SQL coteja cada vínculo contra `saly.creative_item_sources + visual.source_assets`, el `source_sha256`, el proveedor, la ruta `file_ref`, el `asset_code`, el tipo y `metadata.source_filename`. Acepta el estado de fuente que la compilación de la instancia ya admite (`CANDIDATE` o `APPROVED`) sin inventar promociones. Devuelve descriptores, **NO los bytes**. Sin archivo descargado y hash verificado por el host, **no hay despacho**.

El modo de ejecución se recibe como selección de la sesión dueña y se vincula al proveedor canónico (`GPT_NATIVE/OPENAI_CHATGPT_NATIVE` o `CLAUDE_NATIVE/ANTHROPIC_CLAUDE_NATIVE`). **No certifica** quién llamó o generó, y por eso la función permanece privada y sin GRANT.

## PG17 real (fixture aislado, NO esquema completo de producción)

[Workflow temporal #45060478716](https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/45060478716), HEAD bajo prueba `ce7f6afaa41ddebebdd93d573a15e5f795c967eb`:

- PostgreSQL **17.6** real con servicio Docker y `saly_queue_test` nuevo, sin credenciales de producción.
- Positivo `GPT_NATIVE`, `CLAUDE_NATIVE`, bytes `wire_base64`, SHA256 de payload, prompt y snapshot y fuente referenciada.
- **6 negativos de error exacto**: modo `REMOTE_API`, claim token incorrecto, `review_only=true`, cambio de `file_ref`, nombre de archivo con `../`, política faltante.
- Se verifica `0` recibos de entrega, `RUN` permanece `EJECUTANDO`; `ROLLBACK` de todos los datos de prueba.
- El log contiene `PASS_SALY_NATIVE_RENDER_WIRE_PG17_DISPOSABLE_ROLLBACK`, `PASS 6 exact-code negatives`.
- **Límites:** el fixture V02 reproduce selectivamente disparadores y tablas a partir de readback, pero **NO** es clon completo de Supabase. Ambos modos y referencias son datos sintéticos; no se ha probado una imagen real ni concurrentes nuevos. El archivo CI workflow se retiró de la rama porque PASE lo rechazó por no estar en la allowlist; NO se cambió la allowlist.

## Bloqueos obligatorios antes de merge y despliegue

1. `saly.config_global` actualmente tiene **0 parámetros `CREATIVE_FACTORY`**, comprobado por Supabase RO. Los 4 valores de fixture son solo sintéticos y no se trasladan.
2. La función SQL usa tablas de cola `queue_v02` aún **no desplegadas** y no recibe permisos a ningún rol operativo.
3. Debe existir un **runtime propio de la sesión Native** que obtenga fuentes reales, adjunte archivos y revalide los hashes antes de llamar a ImageGen u otra herramienta Native real; GitHub Actions no invoca modelos nativos.
4. Debe existir una identidad autenticada, separada del worker, para registrar la evidencia de entrega y habilitar `DONE`; `queue_v02.creative_queue_record_delivery_v1` todavía admite texto no autenticado y no es seguro conceder permisos de runtime.
5. Completar pruebas fieles PG17/rollback contra esquema íntegro, QA con bytes reales, mutaciones SQL B25/B28, PASE y decisión de activación antes de Merge Train.
6. Mantener los **2 pedidos, 5 ítems y 0 RUN** actuales sin alterar. `queue_v05` es solo una propuesta autocontenida en sandbox.

**Estado:** SQL compilado y probado en PG17 sintético; integración de render/entrega real pendiente.

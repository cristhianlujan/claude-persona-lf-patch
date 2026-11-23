# SALY · V07 · Fuente auténtica para GPT_NATIVE / CLAUDE_NATIVE

**Estado:** código candidato + prueba real de **fuente gráfica**, NO generación ni entrega, NO GRANT, NO DEPLOY. Mantener `skills/creative_factory/SKILL.md` v0.12 PLAN_ONLY/REVIEW_ONLY hasta un cambio gobernado separado.

## Qué se resolvió

Antes de enviar un handoff a la sesión Native, `native_source_preflight_v1.py` consume el **wire congelado V05** (`SALY_NATIVE_RENDER_WIRE_V1`) y un lector de bytes proporcionado por runtime confiable. El lector debe obtener el archivo usando la referencia almacenada en `visual.source_assets.file_ref`, **no** una URL dictada por el texto del pedido. Comprueba:
- Identidad exacta de pedido/ítem/RUN/claim + hashes de snapshot/contrato/prompt/wire contra readback del runtime.
- `GPT_NATIVE/OPENAI_CHATGPT_NATIVE` o `CLAUDE_NATIVE/ANTHROPIC_CLAUDE_NATIVE`; bloqueo de mezcla de proveedor y modo.
- No entregado/no transmitido; no acepta `db_done_allowed` ni `host_delivery_verified` falseados.
- SHA-256 de cada archivo **calculado desde bytes descargados**, no desde metadatos; tipo PNG e IHDR, tamaño y nombre seguro; sin duplicados ni rutas.
- Emite solo `ALL_REGISTERED_SOURCE_BYTES_VERIFIED_NOT_SENT` y descriptor de archivos. No expone imagen en el JSON de resultado, no genera, no registra QA ni libera `DONE`.

**Reutilización:** el paso siguiente es usar `sandbox/creative_factory/native_transport_capture_v1.py:archive_pre_dispatch`, **existente y verificado**, para archivar bytes, prompt y activos protegidos antes de enviar a la sesión nativa. V07 no reimplementa el archivo ni inventa callback de host. El runtime debe proveer fuente autenticada; la interfaz `read_registered_file` sola no prueba la procedencia.

## Fuentes reales — evidencia directa 22/11/2026

Se consultaron vía Google Drive conectado y `saly.creative_item_sources` + `visual.source_assets` en Supabase RO las referencias de los ítems **5, 6 y 7**. Se descargaron los PNG originales y se compararon su tamaño y SHA256 en dos ejecuciones independientes (JavaScript sobre respuesta de Drive; Python hashlib sobre bytes montados). Las tres coincidieron. Pillow verificó dimensiones 1086×1448, 1024×1536 y 1086×1448 respectivamente. Detalle exacto en `real_drive_byte_evidence_20261122.json`.

**No confundir calidad/autoridad con integridad:** los **tres** registros tienen `approval_status=CANDIDATE` en Supabase. Incluso el archivo cuyo nombre acaba en `V3_APROBADA.png` sigue CANDIDATE en fuente oficial. No se promocionó ningún estado.

## Pruebas de código

`python -m unittest -v test_native_source_preflight_v1.py`

**24/24 PASS**, Python 3.11 en GitHub Actions, SHA evaluado `ffba6d596c11c0f666c78fba1988f14f2ae23c81`, [run 45070113988](https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/45070113988). Son tests de contrato **con imagen sintética de 1×1**, por lo que no sustituyen la verificación real de las tres imágenes de Drive, que está en registro aparte. Negativos para ausencia de lector, modo/proveedor, RUN/claim, SHA del wire, Base64, prompt, PNG, MIME, dimensiones, duplicados y nombre peligroso.

El workflow temporal no es admitido por PASE como workflow ordinario nuevo. Se **retira** una vez obtenido PASS; nunca se amplían allowlists ni se modifica el CI estándar. El SHA final debe recibir su propio PASE.

## Bloqueos de continuación

1. No existe aún un **host de entrega** con lectura autenticada del mensaje mostrado al usuario para GPT Native y Claude Native. La referencia de archivo de entrada no es confirmación del resultado.
2. No hay `CREATIVE_FACTORY` operativo; cola V02, wire SQL V05 y tabla V06 permanecen sin despliegue. No crear RUN basado en un paquete PLAN_ONLY.
3. `native_transport_capture_v1.py` es archivador de **pre-despacho**, no un instrumento de certificación del proveedor. Para entrega, el host debe producir bytes/superficie/identidad de mensaje **releíbles desde un canal confiable distinto del trabajador**, o dejar `STAGED` sin DONE.
4. No usar API externa de modelo por defecto ni asumir callbacks equivalentes para ChatGPT y Claude; el ejecutor es el **chat Native dueño**.
5. Faltan pruebas de extremo a extremo de generación/QA/entrega con material real y autoridad para publicar una configuración/producto. Conservamos 2 pedidos y 0 RUN en Supabase.

**Resultado:** etapa de **descubrimiento de fuentes / validación de adjuntos reales** comprobada. Etapa de **imagen entregada / cierre SQL** bloqueada hasta contar con evidencias reales.

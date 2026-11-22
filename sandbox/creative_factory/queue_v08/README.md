# SALY · V08 Native Archive Bridge — no envío

**Ámbito:** PR #4616, `sandbox/creative_factory/queue_v08/`. Desarrollo candidato sin migración, GRANT, escritura Supabase, generación ni entrega. `skills/creative_factory/SKILL.md` oficial permanece en `PLAN_ONLY/REVIEW_ONLY`.

## Fuentes inspeccionadas

- `/mnt/data/LF_resguardos_construccion.md`: A1, A4, A8, A11, A14; B1, B2, B6, B11, B12, B19, B25, B28, B30. Contratos precisos, no fingir callback, correspondencia de hashes y prueba negativa específica.
- `native_transport_capture_v1.py:archive_pre_dispatch`: función **preexistente**, conserva `payload.json` con bytes exactos, `prompt.txt`, originales `references/`, `protected/` y `archive.json` con `HANDOFF_PREPARED_NOT_SENT`. Nunca marca entrega ni invoca proveedor.
- `queue_v07/native_source_preflight_v1.py`: compara wire congelado, pedido/ítem/RUN/claim, modo/provider, SHA de mensaje, bytes PNG y nombre seguro. Lectura real del archivo viene de un adaptador autorizado (no del pedido).
- `queue_v05/001_saly_native_render_wire_candidate.sql`: contrato `SALY_NATIVE_RENDER_WIRE_V1` produce una lista de adjuntos, hash y prompt congelado. **Aún no está desplegado**.
- `queue_v06`: `DONE` exige verificación de host independiente. El archivo de predespacho no puede satisfacer ese requisito.

## Ejecución V08 propuesta

```text
V05 render wire congelado + binding del mismo RUN
     ↓
V07 verifica bytes del repositorio de fuentes registrado
     ↓
V08 cachea cada archivo leído una sola vez
     ↓
Valida activos LOCK requeridos contra inventario protegido del adaptador
     ↓
Copia bytes originales a staging exclusivo (fichero privado)
     ↓
archive_pre_dispatch EXISTENTE
     ↓
Relee payload.json, prompt.txt, references/, archive.json y hashes
     ↓
HANDOFF_ARCHIVED_NOT_SENT
```

**Límite del adaptador:** `wire` y `binding` deben provenir de un readback autenticado y **vigente** del RUN; `read_registered_file` no puede ser definido por el texto del pedido; `required_protected_components` y `protected_assets` deben venir de la misma fuente de diseño oficial. La clase `Mapping` y el hash no prueban esas autoridades por sí solos. Una lista vacía de protegidos solo se acepta cuando **la fuente oficial** confirma que no hay componentes protegidos para esa unidad. Por seguridad, `output_dir.parent` debe ser un directorio privado 0700 y se bloquea el replay sobre un archivo ya existente.

**Compatibilidad limitada:** V07 permite PNG; V05 acepta también JPEG/SVG, que V08 rechazará **fail-closed** hasta que el validador tenga comprobaciones seguras por MIME, sin convertir silenciosamente los archivos.

**Salida efectiva:** `HANDOFF_ARCHIVED_NOT_SENT`, `native_transmitted=false`, `provider_attested=false`, `host_delivery_verified=false`, `db_done_allowed=false`. El resultado no tiene recepción de GPT Native ni Claude Native, y no abre el siguiente paso por sí solo.

## Pruebas CI observadas

[GitHub Actions 45071762106](https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/45071762106), sobre commit `f42a4ea5df4b9596814ed9f8788a1c9a3f1a3f9d`.

**26/26 PASS**: 24 funcionales con `archive_pre_dispatch` real y PNG sintético, y 2 mutantes B25/B28 muertos **por aserción específica**: eliminación del control de activos protegidos requeridos y eliminación de privacidad del directorio.

Primera ejecución del workflow temporal [45071708122](https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/45071708122) falló **1 de 26**: ausencia del lector devolvía `SALY_NATIVE_SOURCE_READ_FAILED` en lugar de `SALY_NATIVE_SOURCE_READER_MISSING`; se corrigió validando el lector antes del callback. No esconder el fallo anterior.

Los tests positivos usan únicamente un PNG **sintético 1×1**, no producen imágenes. Los **tres PNG reales** de SALY ya se comprobaron directamente contra Drive y `visual.source_assets` en el lote V07; no se repitió allí una prueba de RUN real porque sigue sin existir el ejecutor autorizado. No subir PNG/activos privados a GitHub.

El workflow temporal se retira de la rama antes del PASE final, **sin extender allowlist**.

## Puertas aún abiertas (NO GO)

1. El registro `CREATIVE_FACTORY` tiene 0 parámetros reales; no usar fixture. No existe un RUN creativo de ejecución.
2. Falta desplegar cola V02 / wire V05 / evidencia de entrega V06 por Train; esta carpeta solo almacena código candidato.
3. Falta host/sesión Native real con autoridad de despacho y un recibo de **mensaje entregado**, si el host lo soporta. No fingir API, OAuth ni capacidad de verificación independiente.
4. El cierre en SQL queda bloqueado hasta verificador independiente, QA real y bytes de resultado, no mediante `archive.json`.
5. No activar `GPT_NATIVE` ni `CLAUDE_NATIVE` automáticamente con GitHub Actions: el dueño ejecuta en **su conversación nativa actual**.

**Siguiente lote:** resolver límites reales de despacho en la sesión propietaria y autenticación de entrega, o exponer el bloqueo exacto si el host no ofrece una lectura confiable del resultado.

# SALY · V10 Native dispatch reservation candidate

**Ámbito:** PR #4616, carpeta `sandbox/creative_factory/queue_v10/`. Sin migración real, GRANT, RUN productivo, imagen, mensaje entregado ni merge.

## Problema concreto

Entre el archivo V08 y el último preflight V09 puede vencer el lease, variar la fuente o competir dos procesos. **Un readback Python no equivale a bloqueo transaccional SQL.** V10 registra una intención idempotente bajo el **mismo advisory lock serial** que V02/V05, antes de cualquier posible efecto del host Native. No realiza el efecto y nunca devuelve `dispatch_authorized=true`.

## Contrato candidato

`creative_queue_native_reserve_dispatch_v1(claim_token, run_id, executor_mode, expected_wire_sha256, archive_reported_sha256, request_key)`

- Valida entrada, modo Native, hash y idempotencia. El `claim_token` es fencing, **no identidad del host**.
- Reinvoca **el productor SQL real V05** en la transacción con lock compartido, preservando políticas `CREATIVE_FACTORY`, autoridad del pedido, snapshot, fuentes, worker, claim, lease y deadline. Compara el SHA del wire vigente contra el esperado desde V09.
- Relee RUN+claim tras construir el wire, usa una única hora SQL tras adquirir el lock y registra una reserva inmutable `RESERVED_NOT_DISPATCHED`. Es única por RUN y claim; una repetición idéntica responde `ALREADY_RESERVED_NOT_DISPATCHED`. La repetición con otro idempotency key/modo/hash se rechaza.
- El reporte de hash del archivo se almacena **sin adjudicar procedencia confiable**. No significa que un host haya recuperado los bytes.
- `REVOKE ALL` explícito a `PUBLIC` y roles de aplicación existentes; no se confiere permiso. El estado carece de transiciones `DISPATCHED`, `DELIVERED` o `VERIFIED`; sigue siendo imposible usarlo para `DONE`.
- V06 permanece como puerta independiente que requiere evidencia del host y QA.

## Riesgo sin resolver

**No existe atomicidad de una llamada a ChatGPT/Claude respecto de una transacción Postgres.** La reserva garantiza unicidad del registro SQL, **no** entrega exactamente-una-vez de imágenes ni impide todo posible vencimiento después del commit. Para activarlo se necesita dueño autenticado del host, capacidad real de transmisión/recibo, verificación de `message_id` y artefacto, protocolo de recuperación e identidad de attestor. Sin ello: `NO RENDER / NO DONE`.

## Pruebas y relectura

- `test_pg17.sh` exige PostgreSQL 17 exclusivamente `127.0.0.1`, BD `saly_queue_test`, ninguna credencial de Supabase.
- Carga fixtures V02, **función real** V05 y V06; semilla simulada y positiva sintética. Valida ROLLBACK de 12 negativos por error exacto, inmutabilidad, ACL y `DONE` prohibido.
- B7 ejecuta **dos procesos psql reales** en competencia por el mismo RUN; exactamente una reserva y una respuesta idempotente, cero entrega.
- B25/B28: dos mutaciones comportamentales fallan por la aserción esperada, no por sintaxis.
- Al terminar, restablece la BD de pruebas y verifica que la tabla candidata ya no exista.

**CI PG17.6 verificado:** [run #45075908122](https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/45075908122) sobre SHA exacto `2f1fc2202eb3f317cfb10327e3c0fc5f9690db8b`: positivo/idempotencia sintéticos, 12 rechazos por error exacto, 2 procesos psql concurrentes con una reserva, 2/2 mutaciones muertas por aserción y restauración del fixture. Detalle en `pg17_results.txt`. Primeros dos intentos de CI fallaron y están trazados. Sigue pendiente PASE del HEAD final, retiro de workflow temporal y clon fiel de esquema antes de despliegue.

## Evidencia host

No se ha obtenido confirmación autenticada de entrega por ChatGPT/Claude Native. Los datos de `archive.json`, `provider_receipt` autodeclarado, respuesta Python, y hash de fuente **no certifican que el usuario haya visto la imagen**. La puerta V06 sigue cerrada.

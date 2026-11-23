# SALY Creative V16 · entrada pendiente/QA/cierre interno gobernado

**Decisión vinculante:** un pedido por pantalla. HOME primero; SOLICITAR_ADELANTO solo después de `saly.creative_orders.status='TERMINADO'`. El usuario autorizó continuar por la ruta PR → PASE → Merge Train; **no** se autoriza fingir generación, QA independiente ni entrega real.

## Alcance ejecutado
- Una sola migración privada, sin GRANT ni activación de los dos pedidos, elaborada sobre candidatos V12 (bloque de entrada y QA/cierre).
- `creative_chat_begin_pending_v1` admite un solo código para pedidos APP_SCREEN_SINGLE, verifica el predecesor real con `creative_order_sequence_dependency_met_v1`, después pasa `PENDIENTE → LISTO → PRODUCIENDO` y admite RUN con lease y lock del mecanismo V14.
- `creative_chat_save_qa_v1` registra veredicto/comentario junto al hash de imagen y exige QA distinto del trabajador, vínculo con RUN y checks existentes del ítem.
- `creative_chat_finalize_after_verified_delivery_v1` exige evidencia VERIFIED auténtica según V06; para APP_SCREEN_SINGLE ahora comprueba que **la fila SQL del pedido** terminó en `TERMINADO` antes de devolver éxito. No equipara sin prueba el estado interno APROBADO del ítem con aprobación estética humana.
- **No** habilita la ejecución de estos pedidos: `render_authorized=false`, `review_only=true`; no cliente de chat ni worker recibe privilegios ni tokens. Cualquier paso que no tenga host autenticado debe bloquear.

## Evidencia técnica
- PostgreSQL 17 en GitHub Actions [run 45186157083](https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/45186157083), HEAD `b29fd99feb84e8d97f36c42a56b51a023863b035`, **SUCCESS**.
- Fixture compone V14 cola serial, V15 wire, V16 entry+QA y las tres funciones actuales obtenidas directamente de `pg_get_functiondef` en Supabase: creative_chat_terminal_order_guard_v1, creative_chat_terminal_item_guard_v1 y creative_order_sequence_start_guard_v1.
- Casos negativos exactos: dos códigos en un pedido, Adelanto iniciado antes de Home, REVIEW_ONLY, falta de evidencia de entrega. Positivo de integración: dos pedidos unitarios distintos, Home TERMINADO, después Adelanto admitido y TERMINADO. Registro de dos RUN y dos claims cerrados. **La evidencia de host del positivo es SINTÉTICA (owner de PostgreSQL desechable), no una imagen real ni un mensaje de este chat.**
- CI temporal retirada antes de los gates finales. No hay escritura directa en producción.

## Próximo lote real bloqueado
- Host/bridge Native autenticado (misma conversación) capaz de invocar image_gen, leer los bytes y el mensaje entregado, y persistir recibo verificable mediante una identidad independiente del worker.
- Reserva idempotente V10 y archivado/hash V07–V11: son candidatos y todavía no están desplegados. Sin reconciliación de replay externo, no reintentar entregas dudosas.
- QA técnico y semántico independiente: la aceptación de una estructura SQL **no prueba** el contenido visual ni sustituye un juez real.
- Solo después de tener ese host, credenciales autorizadas, pruebas negativas y readback se podrán abrir las banderas de render de HOME y habilitar el arranque automático. El segundo pedido se liberará cuando el primero sea TERMINADO.

## Resguardos
A1–A14, B1/B2/B3/B6/B7/B11/B13/B19/B25/B27/B30. Nunca afirmar DONE al registrar una intención.

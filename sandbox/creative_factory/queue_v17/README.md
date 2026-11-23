# SALY Creative V17 · reserva Native idempotente (NO ENVÍO)

## Alcance autorizado
Continúa la ruta gobernada del usuario: exactamente 1 pantalla/pedido; Home y luego Solicitar adelanto al obtener estado SQL TERMINADO. No altera pedidos ni autoriza render sin host.

## Implementación
- Una sola migración privada a partir del candidato V10 en main (blob 5567374b2ed4a35b4d139b2e0079d0f9b4892cef), después de V14 cola, V15 wire y V16 entrada/QA.
- Crea `creative_queue_native_dispatch_reservations_v1`: una única reserva por RUN y claim, `RESERVED_NOT_DISPATCHED`, inmutable; reserva repetida idéntica retorna `ALREADY_RESERVED_NOT_DISPATCHED`, variaciones se rechazan.
- `creative_queue_native_reserve_dispatch_v1` revalida hashes, snapshot, fuentes, lease y policy con el productor V15 bajo el lock serial, sin transferir control al Native host.
- Seguridad: RLS FORCE, no políticas ni grants a PUBLIC, anon, authenticated, service_role ni runtime. No concede `dispatch_authorized`; estado real permanece `native_transmitted=false`, `db_done_allowed=false`.
- Los dos pedidos reales permanecen en PLANIFICADO, ítems PENDIENTE, banderas review_only=true y render_authorized=false. No produce RUNs ni imágenes.

## Pruebas reales
- PG17 aislado Actions [45187649390](https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/45187649390), commit `2ffb375e49ff3c84cfd9fa0eb535df939db29046`: SUCCESS.
- V02 cola+V05 productor+V06 entrega+V16 entrada: SQL V17 ejecutado sin credenciales de producción.
- V10 positivas con comprobación de JSON `RESERVED_NOT_DISPATCHED`; 12 negativas por código exacto, ACL y falso DONE.
- Dos procesos PostgreSQL compitiendo por un RUN: 1 nueva reserva y 1 lectura idempotente, 0 entregas.
- Las pruebas usan artefactos y recibos **sintéticos**. No implican generación ni mensaje del host.
- Temporal CI retirado antes de PASE/Train.

## Bloqueo restante
No existe en estas herramientas un puente confiable que pueda ejecutar image_gen desde una cola persistida, releer los bytes realmente entregados y obtener message_id autenticado del mismo chat. Esa integración debe proveerse por el runtime anfitrión; un SQL, un archivo o un worker que dice 'enviado' no pueden sustituirla. Sin ese puerto, no levantar banderas ni GRANT. Falta también la revisión semántica independiente para un artefacto real.

Resguardos A1–A14, B1/B2/B3/B4/B6/B7/B11/B19/B25/B27/B30.

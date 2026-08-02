# PR #93 · LOTE-C · Guardas CA-N44 a CA-N48

## Alcance

Este lote corrige exclusivamente la capa de evidencia y el anclaje del nonce del gate.
No autoriza despliegue, instalación de claves, conexión a Supabase, merge ni baseline.

## CA-N44 · números de prueba

Los identificadores de workflow de la batería están dentro del rango seguro de
JavaScript/PostgreSQL. Se agrega una prueba negativa explícita para
`9007199254740992`, que debe fallar con SQLSTATE `22023` antes del HMAC y sin efectos
en nonces, reconciliaciones, gates o eventos.

## CA-N45 · nonce del gate

`trg_05_bind_gate_writer_nonce_v7` se ejecuta `BEFORE INSERT` y `ENABLE ALWAYS` sobre
`private.lf_gate_test_runs_v3`. Obtiene el hash del nonce del evento creado en la misma
transacción, comprueba el hash del preimage y persiste `writer_nonce_sha256` dentro de
`persisted_effects` de la fila privada. También recalcula `persisted_effects_sha256`.

`fn_gate_nonce_v7_valid` usa la fila privada como ancla primaria y exige que el evento
asociado coincida tanto en nonce como en preimage. Una mutación aislada del evento
produce rechazo, no reparación de evidencia.

## CA-N46 · readbacks confiables

`postgres` recibe `EXECUTE` explícito sobre los helpers de canonicalización, framing y
preimage necesarios para las pruebas y readbacks. `anon`, `authenticated` y
`service_role` permanecen revocados.

## CA-N47 · cobertura restaurada

La batería incluye:

- parser framed positivo y vectores malformados;
- entero inseguro rechazado antes del HMAC;
- control positivo y replay exacto;
- nonce expirado y futuro;
- firma inválida;
- claims ausentes y claims `anon`;
- writer público de reconciliación y binding exacto;
- retry idempotente sin duplicar reconciliaciones ni eventos;
- payload mutado después de firmar y cero efectos;
- writer público de gate, nonce privado y cross-check del evento;
- retry idempotente sin duplicar gate ni evento;
- aceptación simultánea de clave `RETIRING` y `ACTIVE`;
- prueba 13 de acceso API denegado;
- invariante de separación;
- `ROLLBACK` final.

## CA-N48 · invariante permanente

`fn_writer_key_separation_v7_valid()` cubre explícitamente:

- `fn_writer_preimage_scope_v7(text)`;
- `fn_bind_gate_writer_nonce_v7()`.

Ambas deben permanecer no ejecutables por `service_role`.

## Evidencia pendiente

Todo permanece únicamente versionado. Siguen pendientes la auditoría estática del
nuevo head y la ejecución en un entorno Supabase aislado.

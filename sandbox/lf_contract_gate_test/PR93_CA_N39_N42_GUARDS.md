# PR #93 · Guardas CA-N39 a CA-N42

## Alcance

Este lote realinea el contrato criptográfico V7 después de introducir el preimage con
framing y hash del payload completo. No autoriza despliegue, instalación de claves,
merge ni regeneración de baseline.

## Contrato efectivo

```text
payload_hash = SHA-256(canonical_json(payload))
preimage = frame(scope) || frame(execution_id) || frame(payload_hash)
signature = HMAC-SHA256(preimage || ":" || nonce)
```

El consumidor de pruebas debe decodificar exactamente las tres tramas. El contrato
anterior `scope:campo:campo...` se rechaza.

## CA-N39

`private.fn_writer_preimage_scope_v7(text)`:

- decodifica las tres tramas por longitud en bytes UTF-8;
- exige consumo completo del preimage;
- exige `execution_id` no vacío;
- exige hash final hexadecimal de 64 caracteres;
- acepta únicamente `reconciliation-v7` y `gate-v7`;
- devuelve `NULL` para entradas antiguas, truncadas o mal formadas.

`private.fn_consume_writer_proof_v7` utiliza este parser antes de verificar el HMAC y
persistir el nonce.

## CA-N40

Los validadores ya no reconstruyen el preimage antiguo.

### Reconciliación

Se enlazan simultáneamente:

- `n.preimage_sha256 = g.details.signed_preimage_sha256`;
- `n.nonce_sha256 = g.details.writer_nonce_sha256`;
- scope, modo de autenticación, rol y `key_id`;
- cercanía temporal entre consumo y persistencia.

### Gate

Se enlazan simultáneamente:

- `n.preimage_sha256 = t.persisted_effects.signed_preimage_sha256`;
- `n.nonce_sha256 = evidence_event.payload.writer_nonce_sha256`;
- el mismo `signed_preimage_sha256` en fila y evento;
- scope, modo, rol, `key_id` y cercanía temporal.

No se agregan columnas ni se debilitan triggers o políticas.

## CA-N41

`PR93_WRITER_V7_ADVERSARIAL_TESTS.sql` deriva todos los preimages válidos mediante
los helpers activos. Los literales del contrato anterior aparecen únicamente en una
prueba negativa.

La batería incluye:

- scope framed positivo;
- contrato antiguo y framing malformado rechazados;
- consumo positivo y replay;
- expiración, futuro y claims inválidos;
- writer público de reconciliación;
- binding de nonce de reconciliación;
- idempotencia con nonce nuevo;
- mutación posterior a la firma;
- writer público de gate;
- binding de nonce de gate;
- prueba 13 con `service_role`;
- aceptación de claves `RETIRING` y `ACTIVE`;
- rollback final.

## CA-N42

El contrato Edge se movió a:

`supabase/migrations/edge_functions/lf-github-reconcile-v3-v7/canonical_payload_v7.ts`

Tanto `index.ts` como `PR93_EDGE_CANONICAL_PAYLOAD_TEST.ts` importan esa misma
implementación. El módulo no lee secretos, no registra servidor y no tiene efectos
laterales.

También rechaza objetos que no sean records planos, cerrando la divergencia teórica
por `toJSON`, `Date`, `Map` o instancias de clases.

## Evidencia pendiente

Todo el lote es únicamente versionado. Siguen pendientes:

1. aplicar migraciones hasta `180520` en entorno Supabase aislado;
2. ejecutar ambas baterías SQL con rollback;
3. ejecutar el test Deno del módulo compartido;
4. comparar preimages Edge/PostgreSQL sobre payloads reales;
5. ejecutar readback de scope y nonce;
6. auditoría estática independiente del nuevo head.

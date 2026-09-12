# PR #93 · LOTE 1 · instalación y rotación HMAC V7

## Alcance

Procedimiento futuro para un entorno aislado y, solo después de las autorizaciones requeridas, para despliegue desde `main`. No contiene material de clave ni sustituye pruebas runtime.

La implementación activa es:

`supabase/migrations/20260801180400_writer_key_rotation_v7.sql`

No usar las piezas alternativas `20260801_0001` a `20260801_0004`; fueron retiradas por colisión con la cadena V7.

## Contrato que no cambia

Edge y PostgreSQL continúan firmando y verificando exactamente:

```text
<preimage>:<nonce>
```

`key_id` no viaja por Edge ni por los RPC. PostgreSQL determina qué generación validó la firma y la registra en la fila del nonce.

## Condiciones previas

1. Commit fijado por SHA.
2. Migraciones aplicadas en orden hasta `20260801180400` en un entorno aislado.
3. Identidad administradora y revisora distintas.
4. La clave no pasa por chat, ticket, PR, correo, log ni argumento visible de terminal.
5. `service_role`, `anon`, `authenticated` y `lf_governance_owner_v3` no pueden leer ni modificar el keystore.
6. Control positivo de la cadena activa disponible.

## Fase 1 · Preparación

1. Generar una clave aleatoria fuera del repositorio.
2. Definir un identificador público `lf-writer-AAAA-MM-rNN`.
3. Instalarla como `PREPARED` mediante `private.fn_install_writer_hmac_key_v7` usando una sesión PostgreSQL administrativa.
4. Generar un desafío `rotation-check-v7:<UUIDv4>`.
5. Comparar la respuesta de `private.fn_writer_hmac_challenge_v7` con un HMAC calculado localmente dentro del canal administrativo seguro.
6. No registrar la respuesta HMAC; persistir únicamente hashes y metadatos no secretos.

## Fase 2 · Promoción en PostgreSQL

1. Ejecutar `private.fn_promote_writer_hmac_key_v7`.
2. La clave anterior pasa a `RETIRING` y conserva aceptación durante diez minutos.
3. La nueva clave pasa a `ACTIVE` en la misma transacción.
4. PostgreSQL acepta firmas de `ACTIVE` y de `RETIRING` mientras la ventana siga abierta.

## Fase 3 · Cambio de Edge

1. Sustituir el secreto Edge `LF_RECONCILIATION_WRITER_HMAC_V7` por la nueva clave.
2. Ejecutar inmediatamente un control positivo completo a través del writer público.
3. Si falla, revertir Edge a la clave anterior antes de vencer la ventana de retiro.
4. Ejecutar las pruebas adversariales 7–13.
5. No interpretar pruebas negativas si el control positivo no consume exactamente el nonce esperado.

## Fase 4 · Retiro

1. Esperar al menos la ventana de diez minutos y confirmar que no hay nonces sin expirar ligados a la clave `RETIRING`.
2. Ejecutar `private.fn_retire_writer_hmac_key_v7`.
3. Ejecutar `PR93_V7_READBACK.sql`.
4. Confirmar una sola clave `ACTIVE`, ninguna `PREPARED`, ninguna `RETIRING` vencida y cero acceso API al keystore.

## Abortos obligatorios

- El desafío no coincide.
- El control positivo falla.
- Más de una clave aparece en `ACTIVE`, `PREPARED` o `RETIRING`.
- Un rol API puede leer el keystore o ejecutar funciones privadas.
- Edge y PostgreSQL dejan de coincidir después del cambio de secreto.
- Aparece una referencia a Vault en la ruta de la clave V7.
- Se intenta registrar material de clave o respuestas HMAC reutilizables.

## Evidencia no secreta

```yaml
rotation_id: <uuid>
old_key_id: <public-id>
new_key_id: <public-id>
commit_sha: <sha40>
challenge_sha256: <sha256>
database_response_sha256: <sha256>
local_expected_response_sha256: <sha256>
responses_match: true|false
positive_control_nonce_count: <integer>
tests_7_13_executed: true|false
operator_identity: <identity>
reviewer_identity: <different-identity>
```

## Frontera de confianza

El diseño excluye a `service_role` de la clave. No protege frente a un administrador PostgreSQL capaz de modificar funciones o tablas privadas. Para excluir también a ese administrador se requiere firma asimétrica o KMS/HSM.

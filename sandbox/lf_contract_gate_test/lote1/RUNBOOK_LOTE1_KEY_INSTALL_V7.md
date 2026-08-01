# PR #93 · LOTE 1 · instalación y rotación HMAC V7

## Alcance

Este runbook documenta un procedimiento futuro para un entorno aislado y, únicamente después de las autorizaciones requeridas, para el despliegue desde `main`. No autoriza ejecuciones sobre el proyecto activo, no contiene material de clave y no sustituye una prueba runtime.

## Condiciones previas

1. El commit que se prueba está fijado por SHA.
2. Las cuatro piezas SQL del directorio `lote1/` fueron revisadas contra ese SHA.
3. El entorno de prueba está aislado del proyecto activo.
4. La identidad administradora y la identidad revisora son distintas.
5. La clave no se transporta por chat, ticket, PR, correo, log ni historial de terminal.
6. Edge y PostgreSQL usan el mismo `key_id` público, pero almacenan la clave en superficies separadas.

## Identificadores

Formato de `key_id`:

```text
lf-writer-AAAA-MM-rNN
```

Formato de desafío:

```text
rotation-check-v7:<UUIDv4>
```

El desafío es disjunto de `reconciliation-v7:` y `gate-v7:`. Su respuesta no puede reutilizarse como prueba operativa.

## Fase 1 · Preparación

1. Generar una clave aleatoria fuera de ChatGPT y fuera del repositorio.
2. Registrar solamente `rotation_id`, `key_id`, commit SHA y las identidades de operador/revisor.
3. Instalar la clave como `PREPARED` en el keystore PostgreSQL mediante un canal administrativo que no deje el valor en argumentos, historial o logs.
4. Configurar la misma clave como secreto Edge de próxima rotación, sin cambiar todavía el firmante activo.
5. Confirmar mediante readback que `service_role`, `anon`, `authenticated` y `lf_governance_owner_v3` no pueden leer ni modificar el keystore.

## Fase 2 · Coincidencia sin revelar la clave

1. Generar un UUIDv4 nuevo y formar el desafío `rotation-check-v7:<UUIDv4>`.
2. Obtener la respuesta HMAC del verificador PostgreSQL para el `key_id` preparado.
3. Obtener la respuesta HMAC de Edge para el mismo `key_id` y desafío mediante una ruta administrativa separada de la reconciliación operativa.
4. Comparar localmente ambas respuestas y persistir solo sus SHA-256, nunca la clave ni la respuesta reutilizable.
5. Ante cualquier diferencia, detener la rotación. La clave activa anterior permanece sin cambios.

## Fase 3 · Promoción y doble aceptación temporal

1. Promover el `key_id` preparado.
2. PostgreSQL marca la clave anterior como `RETIRING` y la nueva como `ACTIVE` en una sola transacción.
3. Durante la ventana de transición, el verificador acepta `ACTIVE` y `RETIRING`; cada prueba queda ligada al `key_id` firmado.
4. Cambiar Edge para firmar exclusivamente con el `key_id` nuevo.
5. Ejecutar un control positivo completo y luego las pruebas adversariales 7–13.
6. No interpretar pruebas negativas si el control positivo no produce exactamente un nonce consumido.

## Fase 4 · Retiro

1. Esperar el TTL máximo del nonce más la ventana máxima de reintento.
2. Confirmar que no existen nonces sin expirar para la clave `RETIRING`.
3. Retirar la clave anterior.
4. Ejecutar el readback completo.
5. Registrar únicamente metadatos no secretos.

## Evidencia mínima

```yaml
rotation_id: <uuid>
old_key_id: <public-id>
new_key_id: <public-id>
commit_sha: <sha40>
challenge_sha256: <sha256>
edge_response_sha256: <sha256>
database_response_sha256: <sha256>
responses_match: true|false
positive_control_nonce_count: <integer>
tests_7_13_executed: true|false
operator_identity: <identity>
reviewer_identity: <different-identity>
```

## Abortos obligatorios

- El control positivo falla.
- Edge y PostgreSQL responden distinto al desafío.
- Más de una clave está `ACTIVE` o `PREPARED`.
- Un rol API puede leer, modificar o ejecutar directamente el keystore o las funciones administrativas.
- El código Edge y PostgreSQL no construyen exactamente el mismo mensaje canónico.
- Aparece una referencia a Vault en la ruta de la clave V7.
- Se detecta un intento de registrar material secreto.

## Frontera de confianza

Este diseño excluye a `service_role` de la clave. No protege frente a un administrador PostgreSQL capaz de modificar funciones o tablas privadas. Si ese administrador debe considerarse atacante, la solución requiere firma asimétrica o KMS/HSM: Edge conserva la clave privada y PostgreSQL verifica con una clave pública.

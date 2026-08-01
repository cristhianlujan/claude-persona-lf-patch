# PR #93 · LOTE 1 · guards y evidencia

## Procedencia

Implementación documental derivada de `HANDOFF_GPT_LF_PR93_LOTE1_CONSOLIDADO.md`. Los hechos del entorno activo se preservan como readback de solo lectura; no se reinterpretan como prueba de funcionamiento de V7.

## Alcance

- CA-N22: identidad partida entre función y tabla de nonces.
- CA-N23: digest sin clave y token controlado por el llamante.
- CA-N29: Vault legible por `service_role` en el proyecto observado.

El paquete se limita a SQL versionado y documentación. No registra ejecución runtime.

## Guards estructurales

1. `lf_writer_verifier_v7` es `NOLOGIN`, `NOINHERIT` y `NOBYPASSRLS`.
2. Keystore, tabla de nonces, verifier y funciones de rotación comparten el mismo owner dedicado.
3. Keystore y nonces tienen RLS y FORCE RLS.
4. Los roles API y `lf_governance_owner_v3` no reciben privilegios de tabla sobre el keystore ni nonces.
5. `service_role` no puede ejecutar directamente el verifier ni funciones administrativas.
6. La función de verificación no contiene `exception when others`.
7. El HMAC usa `extensions.hmac(..., 'sha256')` y una clave seleccionada por `key_id`.
8. El mensaje canónico es:

```text
<preimage> + LF + <writer_token> + LF + <key_id>
```

`LF` representa un byte de salto de línea (`0x0a`). Edge debe reproducirlo byte a byte.

9. Los scopes operativos válidos son únicamente `reconciliation-v7:` y `gate-v7:`.
10. El desafío de rotación usa `rotation-check-v7:` y no entra en la función operativa.
11. La PK `nonce_sha256` impone consumo único.
12. Los triggers `ENABLE ALWAYS` impiden borrar claves y alterar o borrar nonces.
13. La clave y su identificador son inmutables; solo se permiten transiciones de lifecycle hacia adelante.
14. Existe como máximo una clave `ACTIVE` y una `PREPARED`.
15. Una clave `RETIRING` no puede pasar a `RETIRED` mientras existan nonces sin expirar.

## Pruebas 7–13

Estas definiciones preservan el criterio del informe adversarial y agregan un control positivo obligatorio.

| Prueba | Entrada | Resultado requerido | Evidencia concluyente |
|---:|---|---|---|
| Control positivo | claims `service_role`, HMAC correcto, nonce fresco, `key_id` activo | `true` | exactamente un nonce nuevo |
| 7 | repetir exactamente token, firma, preimage y `key_id` del control positivo | `false` | el contador de nonces no aumenta |
| 8 | token expirado | `false` | no se inserta nonce |
| 9 | token con expiración superior al TTL permitido | `false` | no se inserta nonce |
| 10 | firma hexadecimal incorrecta | `false` | no se inserta nonce |
| 11 | `request.jwt.claims` ausente o vacío | `false` | no se inserta nonce |
| 12 | claims con rol `anon` | `false` | no se inserta nonce |
| 13 | claims `service_role` y firma fabricada sin acceso a la clave | `false` | sin lectura de keystore, sin ejecución del verifier interno y sin nonce nuevo |

Una prueba negativa no es concluyente si el control positivo falla antes de insertar el nonce.

## Prueba 13: comprobaciones mínimas

La ejecución aislada debe demostrar conjuntamente:

```text
service_role cannot SELECT key store
AND service_role cannot INSERT or UPDATE key store
AND service_role cannot EXECUTE the private verifier
AND service_role cannot EXECUTE install, challenge, promote or retire
AND a fabricated signature is rejected
AND nonce count is unchanged
```

## Detección de divergencia Edge ↔ PostgreSQL

Control actual del paquete: desafío manual por `key_id` durante cada instalación o rotación.

Backlog recomendado:

- contador de fallos por `key_id` sin registrar firmas;
- alerta cuando el control positivo falla tras un cambio de secreto o despliegue;
- desafío programado con identidad administrativa separada;
- registro de SHA-256 de respuestas, commit y versión Edge;
- cierre automático del writer ante divergencia.

El desafío demuestra coincidencia solo en el instante observado. No demuestra que ambas superficies permanezcan sincronizadas después.

## Evidencia de origen

```yaml
source_commit: fdf738e6dad136703d1b86828b1b5abdd320b9a9
source_pr: 93
source_branch: lf/architecture-v7-hardening
source_handoff: HANDOFF_GPT_LF_PR93_LOTE1_CONSOLIDADO.md
runtime_execution_recorded: false
live_database_writes: 0
merge_performed: false
baseline_regenerated: false
```

## Plantilla de evento futuro

La plantilla siguiente es documental. No constituye una instrucción de escritura.

```json
{
  "event_type": "LF_WRITER_HMAC_V7_ROTATION_EVIDENCE",
  "execution_id": "<execution-id>",
  "commit_sha": "<sha40>",
  "old_key_id": "<public-id>",
  "new_key_id": "<public-id>",
  "challenge_sha256": "<sha256>",
  "edge_response_sha256": "<sha256>",
  "database_response_sha256": "<sha256>",
  "responses_match": false,
  "positive_control_nonce_count": 0,
  "tests_7_13_executed": false
}
```

## Límites

- SQL no ejecutado.
- Coincidencia del preimage Edge/PostgreSQL pendiente de auditoría byte a byte.
- El administrador PostgreSQL permanece dentro de la frontera de confianza.
- La exposición gestionada de Vault requiere una acción administrativa externa y no se corrige aquí.
- No se deriva ninguna conclusión operativa de métricas o estados persistidos.

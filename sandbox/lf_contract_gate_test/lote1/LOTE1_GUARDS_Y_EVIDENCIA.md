# PR #93 · LOTE 1 · guards y evidencia

## Alcance

- CA-N22: identidad partida entre función y tabla de nonces.
- CA-N23: digest sin clave y token controlado por el llamante.
- CA-N29: Vault legible por `service_role` en el proyecto observado.

La corrección está versionada, no ejecutada.

## Cadena activa

La rotación se integra en `supabase/migrations/20260801180400_writer_key_rotation_v7.sql`. No existen relaciones alternativas con los mismos nombres.

## Guards estructurales

1. `private.lf_writer_hmac_keys_v7` permanece propiedad de `postgres`, con RLS/FORCE RLS y sin privilegios API.
2. `private.lf_reconciliation_writer_nonces_v7` permanece propiedad de `lf_writer_verifier_v7`, que posee la función consumidora y puede insertar estructuralmente.
3. `service_role` no ejecuta `fn_consume_writer_proof_v7`, `fn_writer_hmac_v7_match_key`, `fn_writer_hmac_v7_valid` ni las funciones administrativas.
4. El HMAC conserva el mensaje `preimage:nonce`, igual que Edge V7.
5. `key_id` identifica la generación que validó la firma, pero no forma parte del mensaje firmado ni cambia las firmas RPC.
6. Existe como máximo una clave `ACTIVE`, una `PREPARED` y una `RETIRING`.
7. Una clave `RETIRING` solo valida durante `retiring_until`.
8. La PK `nonce_sha256` impone consumo único.
9. `key_id` es nullable en nonces para conservar compatibilidad con filas anteriores.
10. El trigger `ENABLE ALWAYS` impide borrar claves, modificar material o retroceder el lifecycle.
11. El verifier no contiene `exception when others`; una clave activa ausente genera error de infraestructura.
12. Vault no participa en la verificación.

## Pruebas 7–13

| Prueba | Superficie | Resultado requerido |
|---:|---|---|
| Control positivo | `fn_consume_writer_proof_v7` con HMAC correcto | acepta y consume un nonce |
| 7 | replay exacto | rechaza y no crea otra fila |
| 8 | nonce expirado | rechaza |
| 9 | nonce futuro fuera de seis minutos | rechaza |
| 10 | HMAC incorrecto | rechaza |
| 11 | claims ausentes | rechaza |
| 12 | claims `anon` | rechaza |
| 13 | writer público bajo `SET LOCAL ROLE service_role` con firma fabricada | rechaza sin nonce ni reconciliación nueva |

La prueba 13 también exige que `service_role` no pueda leer el keystore ni ejecutar el verifier privado. El mensaje de error debe demostrar que alcanzó el control HMAC del writer público, no una denegación superficial de EXECUTE.

## Rotación

- La nueva clave se instala como `PREPARED`.
- El desafío administrativo compara PostgreSQL con un cálculo local seguro.
- La promoción mueve la clave anterior a `RETIRING` por diez minutos y la nueva a `ACTIVE`.
- Edge cambia únicamente su secreto; el preimage no cambia.
- Un control positivo posterior detecta divergencia.
- La clave anterior se retira solo después de vencer la ventana y de no existir nonces sin expirar.

## Evidencia de origen

```yaml
source_pr: 93
source_branch: lf/architecture-v7-hardening
static_audit_source: AUDITORIA_ESTATICA_PR93_2c97bb5.md
runtime_execution_recorded: false
live_database_writes: 0
merge_performed: false
baseline_regenerated: false
```

## Límites

- No existe evidencia runtime.
- El administrador PostgreSQL permanece dentro de la frontera de confianza.
- La exposición gestionada de Vault requiere una acción administrativa externa.
- Ninguna métrica o estado persistido se acepta como prueba por sí mismo.

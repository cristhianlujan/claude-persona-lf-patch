# RUNBOOK — PR #93 · Lote A V7

Fecha: 2026-08-01
Repositorio: `cristhianlujan/claude-persona-lf-patch`
Rama: `lf/architecture-v7-hardening`
Producción: `mhwmirqcgxxukpctffuv`

## Regla de cambio

Las migraciones y la Edge V7 de este lote no se aplican directamente en producción.
El flujo obligatorio es:

1. Rama Supabase aislada.
2. Aplicación ordenada de migraciones.
3. Pruebas positivas y adversariales.
4. Readback integral V7.
5. Auditoría independiente.
6. Ruleset y aprobación independiente.
7. Merge del PR.
8. Despliegue desde `main`.
9. Readback post-merge.

## Archivos principales

1. `supabase/migrations/20260801175950_prepare_v7_object_owners.sql`
2. `supabase/migrations/20260801180000_writer_hmac_nonce_v7.sql`
3. `supabase/migrations/20260801180100_quarantine_compensating_evidence_v7.sql`
4. `supabase/migrations/20260801180150_trusted_v7_readback_grants.sql`
5. `supabase/migrations/20260801180200_governance_role_and_rls_v7.sql`
6. `supabase/migrations/20260801180300_static_audit_corrections_v7.sql`
7. `supabase/migrations/20260801180305_prepare_idempotency_owner_context.sql`
8. `supabase/migrations/20260801180310_v7_idempotency_guards.sql`
9. `supabase/migrations/20260801180315_v7_row_integrity_guards.sql`
10. `supabase/migrations/20260801180320_cleanup_idempotency_owner_context.sql`
11. `supabase/migrations/edge_functions/lf-github-reconcile-v3-v7/index.ts`
12. `sandbox/lf_contract_gate_test/PR93_WRITER_V7_ADVERSARIAL_TESTS.sql`
13. `sandbox/lf_contract_gate_test/PR93_V7_READBACK.sql`

## Configuración de la clave HMAC

La misma clave aleatoria de alta entropía se instala después del merge en dos superficies:

- Edge Function: secreto `LF_RECONCILIATION_WRITER_HMAC_V7`.
- PostgreSQL: una única fila activa en `private.lf_writer_hmac_keys_v7`, instalada fuera del repositorio por el administrador PostgreSQL.

No se utiliza `vault.decrypted_secrets` porque el proyecto actual concede lectura de Vault a `service_role`. La tabla de clave V7 es propiedad de `postgres`, tiene RLS/FORCE RLS y no concede privilegios a `anon`, `authenticated`, `service_role`, `lf_governance_owner_v3` ni `lf_writer_verifier_v7`.

La clave nunca se registra en GitHub, migraciones, eventos, logs, readbacks ni comentarios del PR.

## Pruebas obligatorias en preview

Ejecutar `PR93_WRITER_V7_ADVERSARIAL_TESTS.sql` y exigir:

1. La clave de prueba permanece inaccesible para roles API.
2. HMAC correcto + nonce fresco + claims `service_role`: aceptado.
3. Replay del mismo nonce: rechazado.
4. Nonce expirado: rechazado.
5. Nonce futuro: rechazado.
6. Firma incorrecta: rechazada.
7. Ausencia de claims: rechazada.
8. Claims `anon`: rechazados.
9. Efectos persistidos dentro de la transacción: exactamente un nonce.
10. `ROLLBACK`: cero residuos de prueba.

No se interpreta ningún rechazo como control válido si el caso positivo falla.

## Readback estructural

Ejecutar `PR93_V7_READBACK.sql` y verificar:

- Cero membresías de `postgres` en `lf_governance_owner_v3` y `lf_writer_verifier_v7`.
- Los roles de aplicación son `NOLOGIN`, `NOINHERIT` y `NOBYPASSRLS`.
- `lf_governance_owner_v3` no conserva `CREATE` en `public` ni `private`.
- `lf_writer_hmac_keys_v7`: owner `postgres`, RLS/FORCE RLS y cero acceso API.
- `lf_reconciliation_writer_nonces_v7`: owner `lf_writer_verifier_v7`, RLS/FORCE RLS y cero acceso API.
- Writers V5 y V6: no ejecutables por roles API.
- Writers V7: ejecutables únicamente por `service_role`.
- `fn_consume_writer_proof_v7` y `fn_writer_hmac_v7_valid`: no ejecutables por roles API.
- Triggers de integridad V7 en estado `ALWAYS`.
- Todas las reconciliaciones compensatorias o PASS pre-V7 están en cuarentena.
- V8 contiene `GITHUB_OIDC_HMAC_NONCE_V7` y no contiene `token_control_ready`.
- La vista permanece `NOT_READY` sin Edge V7, clave, ruleset, baseline limpio y controles administrativos.

## Idempotencia

Para cada artefacto y workflow fusionado solo puede existir una reconciliación V7. Un reintento autenticado consume un nonce nuevo, compara el hash estable del preimage y devuelve la fila existente. Un payload distinto para el mismo workflow produce conflicto y no crea otro evento.

Los gate tests aplican el mismo criterio sobre `test_code + artifact_id + source_workflow_run_id + source_commit_sha`. Una colisión con evidencia histórica o con un preimage distinto se rechaza.

## Acciones administrativas antes del merge

### GitHub

- Ruleset de `main` activo.
- Pull request obligatorio.
- Una aprobación de identidad distinta del autor.
- `lf-contract-check` obligatorio y estricto.
- Sin bypass actors.
- Bloquear force-push y eliminación.

### Supabase control plane

El grantor `supabase_admin` debe retirar toda membresía residual de `postgres` sobre `lf_governance_owner_v3`:

```sql
revoke admin option for lf_governance_owner_v3
  from postgres
  granted by supabase_admin;
revoke lf_governance_owner_v3
  from postgres
  granted by supabase_admin;
```

El mismo administrador debe retirar `PUBLIC` y roles API de las funciones del esquema `net`. El readback debe demostrar cero funciones ejecutables por `anon`, `authenticated` y `service_role`, salvo una excepción formalmente aprobada y reflejada en el cierre.

## Despliegue post-merge

1. Generar una nueva clave HMAC de alta entropía.
2. Instalarla en `private.lf_writer_hmac_keys_v7` mediante una sesión administrativa segura.
3. Configurar el mismo valor como secreto Edge `LF_RECONCILIATION_WRITER_HMAC_V7`.
4. Aplicar las migraciones desde `main`.
5. Desplegar `lf-github-reconcile-v3` V7 desde `main`.
6. Obtener hash y versión mediante readback del control plane.
7. Registrar evidencia de despliegue con versión `>=7`, modo `GITHUB_OIDC_HMAC_NONCE_V7` y hash observado.
8. Ejecutar reconciliación OIDC post-merge.
9. Exigir 64/64 reconciliaciones V7 y 64/64 gate tests V7.
10. Promover artefactos únicamente después del readback anterior.
11. Regenerar baseline desde el commit fusionado.
12. Ejecutar auditoría adversarial final.

## Prohibiciones

- No desplegar desde la rama del PR.
- No almacenar la clave HMAC en Vault mientras `service_role` pueda leerla.
- No reutilizar claves de prueba.
- No aceptar `VERIFIED_COMPENSATING_CONTROLS`.
- No actualizar ni eliminar filas históricas append-only.
- No generar baseline antes del merge.
- No fusionar basándose solo en checks sintácticos.

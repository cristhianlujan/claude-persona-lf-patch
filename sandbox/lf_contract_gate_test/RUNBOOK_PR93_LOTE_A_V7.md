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
4. Auditoría independiente.
5. Ruleset y aprobación independiente.
6. Merge del PR.
7. Despliegue desde `main`.
8. Readback post-merge.

## Archivos del lote

1. `supabase/migrations/20260801175950_prepare_v7_object_owners.sql`
2. `supabase/migrations/20260801180000_writer_hmac_nonce_v7.sql`
3. `supabase/migrations/20260801180100_quarantine_compensating_evidence_v7.sql`
4. `supabase/migrations/20260801180150_trusted_v7_readback_grants.sql`
5. `supabase/migrations/20260801180200_governance_role_and_rls_v7.sql`
6. `supabase/migrations/edge_functions/lf-github-reconcile-v3-v7/index.ts`
7. `sandbox/lf_contract_gate_test/PR93_WRITER_V7_ADVERSARIAL_TESTS.sql`

## Configuración de secreto

La misma clave aleatoria de alta entropía debe configurarse en dos superficies administradas:

- Vault: nombre `lf_reconciliation_writer_hmac_v7`.
- Edge Function: variable `LF_RECONCILIATION_WRITER_HMAC_V7`.

La clave nunca se registra en GitHub, migraciones, eventos, logs ni comentarios del PR.
`service_role` no sustituye esta clave.

## Pruebas obligatorias en preview

Ejecutar `PR93_WRITER_V7_ADVERSARIAL_TESTS.sql` y exigir:

1. HMAC correcto + nonce fresco + claims `service_role`: aceptado.
2. Replay del mismo nonce: rechazado.
3. Nonce expirado: rechazado.
4. Nonce futuro: rechazado.
5. Firma incorrecta: rechazada.
6. Ausencia de claims: rechazada.
7. Claims `anon`: rechazados.
8. Efectos persistidos dentro de la transacción: exactamente un nonce.
9. `ROLLBACK`: cero residuos de prueba.

No se interpreta ningún rechazo como control válido si el caso positivo falla.

## Readback estructural de preview

Verificar:

- `lf_reconciliation_writer_nonces_v7`: owner `lf_writer_verifier_v7`.
- `relrowsecurity=true` y `relforcerowsecurity=true`.
- `anon`, `authenticated` y `service_role`: sin acceso directo a la tabla.
- Writers V5 y V6: no ejecutables por roles API.
- Writers V7: ejecutables únicamente por `service_role`.
- `fn_consume_writer_proof_v7`: no ejecutable por roles API.
- V4 auditadas: RLS y FORCE RLS activados.
- Las reconciliaciones `VERIFIED_COMPENSATING_CONTROLS` aparecen en cuarentena.
- `v_lf_architecture_closure_current` permanece `NOT_READY` sin Edge V7, ruleset y separación administrativa.

## Acciones administrativas antes del merge

### GitHub

- Ruleset de `main` activo.
- Pull request obligatorio.
- Una aprobación de identidad distinta del autor.
- `lf-contract-check` obligatorio y estricto.
- Sin bypass actors.
- Bloquear force-push y eliminación.

### Supabase control plane

El grantor `supabase_admin` debe retirar la membresía residual:

```sql
revoke admin option for lf_governance_owner_v3
  from postgres
  granted by supabase_admin;
revoke lf_governance_owner_v3
  from postgres
  granted by supabase_admin;
```

El mismo administrador debe retirar `PUBLIC`/roles API de las 12 funciones de `net`.
El readback debe demostrar `anon=0`, `authenticated=0` y `service_role=0` funciones ejecutables en `net` salvo una excepción expresamente aprobada.

## Despliegue post-merge

1. Crear/rotar la clave HMAC administrada.
2. Aplicar las migraciones desde `main`.
3. Desplegar `lf-github-reconcile-v3` V7.
4. Obtener hash y versión mediante readback del control plane.
5. Registrar evidencia de despliegue con:
   - versión `>=7`;
   - modo `GITHUB_OIDC_HMAC_NONCE_V7`;
   - hash observado, nunca predeclarado.
6. Ejecutar reconciliación OIDC post-merge.
7. Exigir 64/64 reconciliaciones V7 y 64/64 gate tests V7.
8. Promover artefactos únicamente después del readback anterior.
9. Regenerar baseline desde el commit fusionado.
10. Ejecutar auditoría adversarial final.

## Prohibiciones

- No desplegar desde la rama del PR.
- No reutilizar secretos de prueba.
- No aceptar `VERIFIED_COMPENSATING_CONTROLS`.
- No actualizar ni eliminar filas históricas append-only.
- No generar baseline antes del merge.
- No fusionar basándose solo en checks sintácticos.

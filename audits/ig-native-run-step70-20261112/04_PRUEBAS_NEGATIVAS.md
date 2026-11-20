# Pruebas negativas de solo lectura — 2026-11-12

**Proyecto real consultado:** `mhwmirqcgxxukpctffuv`. **Rol:** `supabase_read_only_user`.
**Alcance:** inspección de catálogos/funciones/GRANT; sin invocar la RPC que registra, sin alterar ni reanudar ningún RUN.

## Resultados realmente observados

| Caso | Resultado | Evidencia / límite |
|---|---|---|
| Usuario `authenticated` no puede llamar directamente Step70 | PASS | `has_function_privilege(...,'EXECUTE')=false` |
| Segundo bridge de inicio debe permanecer retirado | PASS | Fuente retorna `DUPLICATE_NATIVE_BRIDGE_ENTRY_RETIRED` |
| Step70 contiene controles de independencia/declaración y reclamos no soportados | PASS_SOURCE_ONLY | Lectura del cuerpo de la función; **no demuestra llamada externa al modelo** |
| Step70 RPC sin HMAC | PASS_RPC_ONLY | Sin cadena HMAC en cuerpo de RPC; **no prueba por sí solo todos los transportes externos** |
| Auth humano real en esta sesión | NOT_TESTED_REAL_AUTH | `auth.uid()=NULL`; no suplantar identidad |
| Owner vinculante en política humana | BLOCK_OWNER_REGISTRY_EMPTY | `private.lf_human_decision_authority_policies_v1`: 0 ACTIVE |
| OIDC con JWT inválido, revoked owner, hash desfasado, juez independiente y backup/restauración | NOT_TESTED | Precisa entorno autorizado, credenciales reales y fixtures nuevos; **no ejecutar sobre RUN históricos** |

Consulta SELECT ejecutada (simplificada, sin mutación):

```sql
WITH f AS (
 SELECT
  pg_get_functiondef('public.lf_profile_native_bridge_record_semantic_v1(text,jsonb,text,text)'::regprocedure) semantic_src,
  pg_get_functiondef('public.lf_profile_native_bridge_begin_v1(jsonb,jsonb,text,text)'::regprocedure) retired_begin_src
)
SELECT
 NOT has_function_privilege('authenticated',
   'public.lf_profile_native_bridge_record_semantic_v1(text,jsonb,text,text)','EXECUTE') AS denied_direct_user,
 position('DUPLICATE_NATIVE_BRIDGE_ENTRY_RETIRED' in retired_begin_src)>0 AS retired_entry,
 position('producer_independence_proven' in semantic_src)>0
  AND position('model_call_count' in semantic_src)>0
  AND position('unsupported_claims' in semantic_src)>0 AS field_checks_in_source,
 position('hmac' in lower(semantic_src))=0 AS semantic_rpc_no_hmac,
 auth.uid() IS NOT NULL AS real_authenticated_actor_present,
 (SELECT count(*) FROM private.lf_human_decision_authority_policies_v1 WHERE status='ACTIVE') AS active_human_authority_policies
FROM f;
```

**Prohibido convertir** `PASS_SOURCE_ONLY` o `PASS_RPC_ONLY` en `E2E_PASS`. Estos resultados no acreditan el motor cerrado, ni `VIGENTE`, ni un backup restaurable.

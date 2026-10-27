# DECISION_CONTEXT_ASOF · permisos del escritor (candidato, 27-oct-2026)

Estado: candidato en draft. Ruta: `ACTUALIZACION_DB_LF` → PR → PASE → Merge Train.
Mientras el PR siga en draft, nada de esto está aplicado en `mhwmirqcgxxukpctffuv`.

## Lectura en vivo (solo lectura, 27-oct-2026)

| Dato | Valor observado |
|---|---|
| Firma | `public.fn_lf_decision_context_asof_record_v1(jsonb,text)` |
| Propietario | `postgres` |
| Modo | `SECURITY DEFINER`, `search_path = pg_catalog, public, private, extensions` |
| ACL | `{=X/postgres, postgres=X, anon=X, authenticated=X, service_role=X}` |
| Privilegio efectivo `EXECUTE` | `anon`, `authenticated` y `service_role`: sí |
| Origen de la ACL | Ninguna migración la fija. Viene de `PUBLIC` por defecto y de los privilegios por defecto de Supabase en `public` |
| Cuerpo (`md5(prosrc)`) | `b2b107a86eb8fea55a11ab8f620d9694` |
| Tabla | `private.lf_decision_context_asof_v1`, RLS activa, sin grants; `anon`/`authenticated` sin `USAGE` en `private` |
| Filas | 3 (06–09/10) |

Los tres `created_by_execution_id` registrados no existen en `public.lf_operation_execution`:
`CHATGPT-PROGRAMMING-AGENT-SNAPSHOT-PERSISTENCE-20261006`, `EXEC-ANALYSIS-B2B-SHELL-20261007-001` y
`PROGRAMMING_AGENT_A9_USER_AUTHORIZED_REFRESH_20261009`. Hoy el actor es una etiqueta declarada por quien llama.

### Consumidores

- Ninguna función de la BD llama al escritor. Solo leen la tabla `fn_lf_programming_context_handoff_receipt_record_v1` (D7) y, en #3193, el escritor runtime y `..._receive_v1`.
- En el repo: la migración A15Q (`20261014221200`, aplicada por el Train como `postgres`), pruebas y contratos. Ninguna Edge Function.
- El escritor runtime de #3193 acepta un snapshot solo si `created_by_execution_id = p_source_execution_id`. Por eso un actor libre es una vía para atribuir un snapshot a una ejecución real ajena.

## Hallazgos

| # | Severidad | Hallazgo |
|---|---|---|
| H1 | Alta | Cualquiera con la clave publicable (`anon`) o un usuario autenticado puede registrar un contexto inmutable y atribuirlo a cualquier ejecución. Con #3193 eso alcanza la prueba de origen del snapshot de PG-01 |
| H2 | Media | Un tercero puede ocupar primero un `decision_ref` (es único); el escritor legítimo recibiría después `DECISION_REF_REPLAY_CONFLICT` para siempre |
| H3 | Media | `fn_lf_decision_context_asof_resolve_v1(text,text,timestamptz)` también es `SECURITY DEFINER` y ejecutable por `anon`: expone el payload de cualquier contexto. No se toca en este PR (decisión D-A3) |
| H4 | Informativo | `service_role` sigue pudiendo declarar cualquier actor. Retirar el acceso anónimo no convierte el registro en prueba independiente de procedencia |

## Cambio de este PR

`supabase/migrations/20261027180000_lf_decision_context_asof_record_acl_v1.sql`:

- `REVOKE ALL ... FROM PUBLIC, anon, authenticated` y `GRANT EXECUTE ... TO service_role`.
- No cambia el cuerpo, el modo, el `search_path`, la tabla, el resolvedor ni ninguna fila.
- Termina con aserciones de privilegio **efectivo** (`has_function_privilege`, que incluye membresías). Si algún rol hereda `EXECUTE`, la migración falla y el Train no la aplica.

## Prueba local

`test_decision_context_asof_record_acl_v1.sql`, en PostgreSQL 17.6 desechable, solo socket Unix, todo dentro de una transacción con `ROLLBACK`. Resultado: **15/15**.

- C00: el cuerpo de la fixture es idéntico al hospedado (mismo md5).
- C01–C03: antes de la migración, `anon` y `authenticated` registran con un actor inventado (reproduce H1).
- C04–C06: después, ambos reciben `insufficient_privilege` y no se escribe nada.
- C07–C08: `service_role` registra y el replay es idempotente.
- C09–C11: `PUBLIC` fuera de la ACL; cuerpo, modo y `search_path` intactos; filas previas intactas.
- C12: H4 queda afirmado a propósito (`service_role` declara un actor cualquiera).
- C13–C14: un grant heredado por membresía es efectivo y hace fallar la migración.

Mutación comprobada: con `REVOKE ... FROM PUBLIC` solamente, la migración falla con `LF_ASOF_RECORD_ACL_ANON_STILL_EFFECTIVE`.

Fixtures: tablas de capacidades y validador de payload son stubs mínimos. Esto no es evidencia hospedada.

## Decisiones pendientes

| # | Decisión | Dueño |
|---|---|---|
| D-A1 | Quién registra el snapshot A9 en producción y con qué identidad (la ejecución productora, el llamador Native u otro) | Cristhian |
| D-A2 | Atar el actor a una ejecución real: versión nueva del escritor que exija que `p_actor_execution_id` exista en `lf_operation_execution` y esté en un estado y operación permitidos. Cambia el contrato de una capacidad transversal (IG también es consumidor), por eso no va en este PR | Cristhian |
| D-A3 | Retirar `EXECUTE` de `anon`/`authenticated` también en el resolvedor (H3). Requiere confirmar que ningún cliente público lo usa | Cristhian |
| D-A4 | Qué hacer con las 3 filas existentes cuyo actor no es una ejecución. Son inmutables: solo cabe marcarlas o no usarlas como origen de PG-01 | Paulo + Cristhian |

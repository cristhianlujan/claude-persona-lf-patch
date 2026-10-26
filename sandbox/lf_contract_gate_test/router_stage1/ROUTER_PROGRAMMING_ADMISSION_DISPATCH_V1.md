# Router → Programación: propuesta de admisión y despacho V1

**Owner del Router:** Cristhian. **Proponente:** Paulo. **Fecha:** 26-oct-2026. **Estado:** DRAFT, sin autorización de integración.

## Objetivo y condición de inercia

El Router actual siempre devuelve `PROGRAMACION_PRECHECK_DEFINICION` para `PROGRAMACION`. La propuesta agrega un camino **opt-in** cuando `p_caller.programming_handoff` existe. Si no existe, conserva literalmente el mismo `jsonb` de salida, mismas claves y valores. Con la compuerta D7 vigente (`admissible=false` siempre), un handoff válido solo alcanza `PROGRAMACION_ADMISION_BLOQUEADA`. La operación `DESARROLLO_CODIGO_AGENTE_LF` hoy es `CANDIDATO_READ_ONLY`, no `ACTIVE`.

No se cambia ninguna rama distinta de `PROGRAMACION`. El parche exige el MD5 del Router verificado y reemplaza únicamente el segmento entre los anclajes `IF v_channel='PROGRAMACION' THEN` e `IF v_channel='OPERACIONES' THEN`. Una discrepancia bloquea toda la transacción.

## Contrato de handoff

El objeto opt-in va en `p_caller.programming_handoff` e incluye `context_id`, `context_sha256`, `target_ref`, `requested_scope_ids`, `producer_execution_ref` y `entry_contract_digest_sha256`. El digest debe ser `d2e347efe07a9971790f1a605f0b6ab93fa48a1608744330d1e49e59930d7fb8`. Este objeto **no reemplaza** la definición canónica ni el receptor PG-01. Las futuras reglas de validación de entrada deberán revisar la relación del handoff con el precheck funcional.

## Tabla de decisiones

| Caso | `paso` | Resultado |
|---|---|---|
| Sin handoff | `PROGRAMACION_PRECHECK_DEFINICION` | Salida legada completa idéntica |
| Handoff inválido o digest distinto | `PROGRAMACION_HANDOFF_INVALIDO` | `PG01_ROUTER_BINDING_INVALID` |
| Recibo exacto ausente | `PROGRAMACION_ADMISION_BLOQUEADA` | `RETURN_TO_ANALYSIS_NO_CODE` |
| Recibo hallado, no admisible | `PROGRAMACION_ADMISION_BLOQUEADA` | `BLOCK_NO_CODE` |
| Admisible, operación no ACTIVE | `PROGRAMACION_OPERACION_NO_ACTIVA` | Estado de registro |
| Admisible, operación ACTIVE | `DISPATCHED` | Identidad exacta y scopes para siguiente compuerta |

**En todos los caminos**, `downstream_execution_allowed=false`, incluso `DISPATCHED`. Despacho no equivale a permiso de ejecución.

## Puente de permisos

`public.lf_router_programming_admission_gate_v1(jsonb)` es `SECURITY DEFINER`, `STABLE`, `search_path` fijo, dueño `postgres`. Verifica la forma antes de consultar el lector privado, con las mismas reglas que el lector D7 (incluido `context_id` en minúsculas: el lector real lanza excepción ante cualquier otra forma). Es la única validación del binding: el Router no duplica reglas y traduce `PG01_ROUTER_BINDING_INVALID` a `PROGRAMACION_HANDOFF_INVALIDO`. Cualquier error inesperado del lector se devuelve como `admissible=false`, `reason='PG01_ROUTER_ADMISSION_UNDETERMINED'` (fail closed), nunca como caída del Router. Solo retorna `schema_version`, `found`, `admissible`, `reason`: nunca `receipt`, `envelope` ni datos de fila. `EXECUTE` únicamente para `service_role`, `supabase_read_only_user` y dueño implícito. No se conceden privilegios nuevos al lector D7.

El Router permanece `SECURITY INVOKER`. El puente **no concede** capacidad de escritura ni autoridad para activar la operación.

## Laboratorio

Desde raíz del repo, contra PostgreSQL 17 vacío y desechable:

```sh
psql -v ON_ERROR_STOP=1 "$TEST_DATABASE_URL" -f sandbox/lf_contract_gate_test/router_stage1/test_router_programming_admission_dispatch_v1.sql
```

La fixture del Router no puede igualar el MD5 de la función real de 12.126 caracteres. El script carga el mismo archivo SQL de migración en memoria mediante `\copy`, reemplaza **solo la constante de MD5** por el de la fixture, quita los delimitadores transaccionales externos y ejecuta el resto sin alteraciones; el archivo de producción no cambia. El test abre su propio `BEGIN` y termina `ROLLBACK`. El stub del lector D7 admite artificialmente `target_ref='ADMIT-TEST-ONLY'` para recorrer ramas futuras que **no** son alcanzables en producción en esta fase.

## Condiciones pendientes

1. Contrato V2 de admisión y juez independiente A9 con evidencias gobernadas.
2. Operación escritora de recibos PG-01 en runtime, si se autoriza.
3. Activación explícita de `DESARROLLO_CODIGO_AGENTE_LF` en I1.
4. Revisión de Cristhian del formato y la ubicación de `programming_handoff`, códigos `paso` y modelo del puente.
5. Verificación del MD5 y bloque real en la base viva en el momento del Train. Si difiere, detener; **no** sustituir el hash por uno actualizado sin revisión.

## Alcance de validación

El script contiene 11 bloques. Ejecutado por Claude el 26-oct-2026 en PostgreSQL 16 local desechable: `ROUTER_PROGRAMMING_DISPATCH_TESTS_PASSED:11` (CI corre 17). Contra la base viva, en solo lectura, se comprobó: MD5 `42828a549c0e4ce15e45c902816fa9ea`, cada ancla aparece una vez y el bloque PROGRAMACION vivo (885 caracteres, md5 `787b637c5043c1e35b6bd922b02c32e0`, incluida la línea en blanco previa a OPERACIONES) es idéntico al bloque `$old$` de la migración.

Correcciones de Claude sobre la entrega de GPT: (1) la regex de UUID del Router tenía 4 grupos y rechazaba todo `context_id` válido (la prueba 04 fallaba); (2) un UUID en mayúsculas pasaba el puente y hacía que el lector D7 lanzara excepción; (3) faltaba la línea en blanco del bloque vivo, lo que habría bloqueado el Train con `BLOCK_DRIFT`; (4) el cargador del test perdía líneas en blanco (CSV lee línea vacía como NULL). Se añadieron las pruebas 10 (UUID en mayúsculas, handoff null) y 11 (error del lector, fail closed), y el stub D7 ahora lanza excepción y devuelve `record` como el lector real.

Pendiente de revisión: la revisión de CI y de Cristhian debe confirmar también los permisos efectivos de `postgres`, `service_role` y `supabase_read_only_user` y la compatibilidad del `CREATE OR REPLACE FUNCTION` con el Router vigente.

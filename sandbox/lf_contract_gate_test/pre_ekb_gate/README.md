# PRE_EKB_GATE

Capacidad transversal LF que garantiza que un fallo durable quede persistido en EKB antes de permitir reparación, reanudación o retry limpio.

## Estado

- Capability: `PRE_EKB_GATE`
- Nombre canónico: `TRANSVERSAL_PRE_EKB_GATE`
- Versión: `v0.2.2`
- Estado documental: `VIGENTE`
- Estado operativo: `ACTIVO`
- Runtime: `SUPABASE_ENFORCED`
- Inventory status: `ACTIVE_SHARED_ENFORCEMENT`
- Consumidores enforced: `ACTUALIZACION_DB_LF`, `GITHUB_CONTRACT_GATE_LF`
- Autoridad operacional: Supabase
- No crea un segundo EKB, error store, Router ni workflow engine.

## Propósito

Resolver una sola responsabilidad transversal:

> si una operación produce un fallo durable, el diagnóstico debe quedar en el EKB canónico con evidencia suficiente antes de que el flujo pueda continuar con reparación o reintento limpio.

La capability reutiliza las superficies ya existentes de LF:

- `LF_GATE_ERROR_V1` / `public.lf_operation_gate_check_results`
- `public.lf_operation_execution_steps`
- `EJECUCION_SKILL_LF`
- skill `ACT-0057 / SKILL_ESCRITURA_BASE_CONOCIMIENTO_LF`
- writer authority `ESCRITURA_BASE_CONOCIMIENTO_LF`
- `public.lf_write_pipeline_ekb_v1`
- `EVENT_CONTRACT_GOVERNANCE`
- execution/readback durable de LF

## Flujo

```text
FAIL / BLOCKED / RETURNED / caught exception
        |
        v
durable diagnostic
        |
        v
PRE_EKB_GATE
        |
        v
EJECUCION_SKILL_LF
        |
        v
ACT-0057
        |
        v
ESCRITURA_BASE_CONOCIMIENTO_LF
        |
        v
lf_write_pipeline_ekb_v1
        |
        v
EKB receipt + durable readback
        |
        v
repair / resume / clean retry
```

Si el receipt EKB no existe, el flujo debe permanecer fail-closed.


## Relación con GATE_CHECK_OBSERVABILITY

La ruta transversal canónica es:

```text
OPERACIÓN REAL
    |
    v
GATE_CHECK_OBSERVABILITY
    |
    v
public.lf_operation_gate_check_results
    |
    +-- PASS --------------------> continúa
    |
    +-- FAIL / BLOCKED
            |
            v
        PRE_EKB_GATE
            |
            v
         ACT-0001
            |
            v
    EJECUCION_SKILL_LF
            |
            v
         ACT-0057
            |
            v
ESCRITURA_BASE_CONOCIMIENTO_LF
            |
            v
 public.lf_write_pipeline_ekb_v1
            |
            v
            EKB
            |
            v
     receipt + readback
            |
            v
     reparación / rerun
```

`GATE_CHECK_OBSERVABILITY` detecta, descompone y diagnostica. `PRE_EKB_GATE` gobierna qué fallos durables deben persistirse y bloquea el retry limpio hasta disponer de receipt.

### Regla de consumer

`GATE_CHECK_OBSERVABILITY` **no** se registra como consumer de `PRE_EKB_GATE`.

El consumer es siempre la `operation_code` real cuya ejecución produjo el fallo, por ejemplo:

- `ACTUALIZACION_DB_LF`
- `EJECUCION_...`
- `CREACION_...`
- `ACTUALIZACION_...`

Esto mantiene a `GATE_CHECK_OBSERVABILITY` consumer-agnostic y permite reutilizar el mismo motor para múltiples operaciones.

### Bridge histórico/directo

El artefacto:

```text
sandbox/lf_contract_gate_test/gate_check_observability/persist_gate_failures_to_ekb_v1.py
```

no es la autoridad productiva objetivo de persistencia EKB.

Mientras exista, debe considerarse adapter de traducción/prueba. La ruta objetivo productiva es:

```text
failure diagnostic
  -> public.lf_operation_gate_check_results
  -> PRE_EKB_GATE
  -> governed child dispatch
  -> ACT-0057
  -> canonical EKB writer
```

No se debe agregar una segunda vía productiva directa al writer.


## Entradas que cubre

### Gate checks

Los `FAIL` o `BLOCKED` durables provenientes de `LF_GATE_ERROR_V1` son procesados por:

```text
public.lf_pre_ekb_gate_check_dispatch_v1(bigint)
```

La entrada debe conservar como mínimo:

- execution
- operation
- step
- gate
- attempt
- check
- condition
- expected
- actual
- error class
- evidence ref
- producer/run/job cuando existan
- source commit
- source path
- downstream impact
- owner
- next action
- resume checkpoint
- rerun scope

### Step failures

Los estados `BLOCK*`, `FAIL*` o `RETURN*` de una operación bound son procesados por:

```text
public.lf_pre_ekb_step_failure_dispatch_v1(text,text)
```

El EKB se construye desde la evidencia durable del step. No se inventa una causa raíz más profunda que la observada.

### Excepciones atrapadas

Una excepción capturada fuera de la subtransacción fallida se persiste explícitamente con:

```text
public.lf_pre_ekb_exception_dispatch_v1(
  execution_id,
  step_id,
  error_code,
  error_message,
  source_ref,
  owner,
  next_action,
  evidence
)
```

Si falta identidad, mensaje, source, owner o next action, el bridge falla cerrado en vez de escribir una entrada genérica.

## Código canónico

Todos los códigos derivados gate/step/exception usan:

```text
public.lf_pre_ekb_canonical_code_v1(text[])
```

La normalización se realiza así:

1. unir todas las partes de identidad;
2. convertir la cadena completa a uppercase;
3. reemplazar runs fuera de `A-Z0-9` por `-`;
4. validar el patrón canónico final.

Esto evita perder identificadores lowercase/mixed-case y evita colisiones entre steps diferentes.

Ejemplo:

```text
EXCEPTION + ACTUALIZACION_DB_LF + preflight + same-error
=> EXCEPTION-ACTUALIZACION-DB-LF-PREFLIGHT-SAME-ERROR
```

## Autopersistencia

Para consumidores bound, los triggers activos son:

- `private.trg_lf_pre_ekb_gate_check_autopersist_v1`
- `private.trg_lf_pre_ekb_step_failure_autopersist_v1`
- `private.trg_lf_pre_ekb_clean_retry_guard_v1`

El retry guard bloquea un `PASS_CLEAN` posterior cuando existe un fallo durable sin receipt EKB asociado.

Cuando falla la propia persistencia EKB, se conserva un evento `BLOCKED_EKB_PERSISTENCE`; el fallo original sigue durable y no se libera el retry limpio.

## Cómo saber si una operación es consumidora

Usar:

```sql
select public.lf_pre_ekb_gate_consumer_v1('ACTUALIZACION_DB_LF');
```

`true` significa que la operación está registrada como consumidor del asset transversal.

No se debe copiar este motor dentro de cada operación.

## Cómo agregar un nuevo consumidor

La ampliación correcta es por binding/inventario, no por duplicación.

Antes de agregar otro consumidor:

1. leer `PRE_EKB_GATE` desde `public.lf_activos`;
2. comprobar que la versión current siga vigente/activa;
3. confirmar que el proceso ya genera diagnóstico durable compatible;
4. bindear el nuevo `operation_code` en `metadata.transversal_inventory.consumers_known`;
5. probar FAIL/BLOCKED, recurrence, PASS sin EKB, excepción completa/incompleta y retry guard;
6. persistir EKB/readback del cambio;
7. actualizar este README si cambia el contrato.

Si el consumidor necesita un formato de fallo incompatible, primero ampliar el contrato transversal; no crear un writer paralelo.

## Uso dentro de GITHUB_CONTRACT_GATE_LF / lf-contract-check

`lf-contract-check` consume PRE_EKB_GATE únicamente para fallos determinísticos que ya tienen un `LF_GATE_ERROR_V1` durable.

La identidad operacional es:

```text
GITHUB_CONTRACT_GATE_LF
  -> canonical step: contract_judge
  -> public.lf_record_gate_checks_v1
  -> public.lf_operation_gate_check_results
  -> trigger PRE_EKB_GATE
  -> ACT-0001 / EJECUCION_SKILL_LF
  -> ACT-0057
  -> ESCRITURA_BASE_CONOCIMIENTO_LF
  -> EKB receipt/readback
```

Reglas de integración:

- el workflow no llama directamente a `lf_write_pipeline_ekb_v1`;
- el workflow no usa `persist_gate_failures_to_ekb_v1.py` como writer productivo;
- cada corrida que necesita persistencia reserva una ejecución gobernada propia de `GITHUB_CONTRACT_GATE_LF`;
- el source commit queda ligado al exact candidate head;
- los checks se registran por el ingress canónico `lf_record_gate_checks_v1`;
- PASS no genera EKB;
- FAIL/BLOCKED exige `persistence_result=EKB_PERSISTED` por cada check no-PASS;
- un `BLOCKED_EKB_PERSISTENCE` mantiene el flujo bloqueado;
- esta integración no convierte fallos no instrumentados del workflow en causas inventadas. Los fallos sin `LF_GATE_ERROR_V1` siguen bajo el control `CI-GATE-DIAGNOSTIC-EVIDENCE-GAP-001`.

Binding source-first:

- migration: `20260918145500_lf_s30_github_contract_gate_pre_ekb_consumer_v1.sql`;
- consumer exacto en `metadata.transversal_inventory.consumers_known`: `GITHUB_CONTRACT_GATE_LF`;
- canary transaccional: FAIL + recurrence + PASS sin EKB + BLOCKED, con rollback y cero residuo.

## Uso dentro de ACTUALIZACION_DB_LF

`ACTUALIZACION_DB_LF` es el primer consumidor enforced.

La secuencia relevante es:

```text
preflight
  -> diagnóstico durable si falla
  -> PRE_EKB_GATE
  -> EKB receipt
  -> repair/resume permitido

patch
  -> igual para BLOCK/FAIL/RETURN

verify
  -> igual para BLOCK/FAIL/RETURN
  -> PASS_CLEAN solamente con el EKB requerido ya persistido
```

Un fallo real de verify durante la activación fue persistido automáticamente como:

```text
STEP-ACTUALIZACION-DB-LF-VERIFY-DB-ROUTER-AUTHORITY-TRUST-INVALID
```

y el retry limpio sólo pasó después del receipt EKB.

## Fuente y lineage

Implementación inicial:

- `supabase/migrations/20260917232500_s30_pre_ekb_gate_db_autopersist_v1.sql`
- PR #888
- ledger exact version `20260917232500`

Corrección de normalización canónica:

- `supabase/migrations/20260917235000_s30_pre_ekb_canonical_code_normalization_v1.sql`
- PR #889
- ledger exact version `20260917235000`

Ampliación de consumer para `GITHUB_CONTRACT_GATE_LF`:

- `supabase/migrations/20260918145500_lf_s30_github_contract_gate_pre_ekb_consumer_v1.sql`
- consumer path: `lf-contract-check -> GITHUB_CONTRACT_GATE_LF -> contract_judge`
- no cambia el writer ni el Router; sólo extiende el binding de la capability existente.

EKB relevante:

- `S30-GATE-EKB-AUTOPERSIST-MISSING-001`
- `PRE-EKB-CANONICAL-CODE-CASE-NORMALIZATION-001`

## Validación mínima esperada

Para una modificación de esta capability no basta que compile.

Debe demostrarse, como mínimo:

1. FAIL/BLOCKED produce EKB automáticamente.
2. Recurrence incrementa la misma entrada cuando corresponde.
3. PASS no crea EKB artificial.
4. expected/actual/source/owner/next_action/resume/rerun permanecen específicos.
5. caught exception completa persiste.
6. caught exception incompleta falla cerrada.
7. mixed/lowercase identity conserva todos los segmentos.
8. códigos de steps distintos no colisionan.
9. child execution `EJECUCION_SKILL_LF -> ACT-0057` queda durable y COMPLETED.
10. EKB writer receipt queda enlazado al fallo padre.
11. clean retry queda bloqueado si falta receipt.
12. no quedan residuos de probes.

## Separación de responsabilidades

`PRE_EKB_GATE`:

- decide si un fallo bound requiere EKB antes de continuar;
- transforma evidencia durable a un finding completo;
- despacha al writer gobernado;
- exige receipt/readback;
- protege el retry limpio.

`PRE_EKB_GATE` no:

- decide el Router;
- autoriza escrituras DB;
- sustituye `ESCRITURA_BASE_CONOCIMIENTO_LF`;
- sustituye `ACT-0057`;
- sustituye el catálogo de errores;
- sustituye los tests/gates que detectaron el fallo;
- crea un segundo EKB;
- permite bypass por falta de diagnóstico.

## Autoridad y seguridad

La autoridad operacional permanece en Supabase y en los contratos/policies activos. GitHub conserva implementación técnica y documentación.

El README explica el uso; no otorga permisos.

Cualquier cambio que amplíe consumidores, modifique semántica de bloqueo o altere el writer debe pasar por el mecanismo gobernado correspondiente y cerrar con evidencia/readback.

## Cuándo consumirlo

Cuando una operación real ya produjo un FAIL/BLOCKED/RETURNED o excepción durable y debe persistir el conocimiento antes de repair/resume/retry limpio.

## Cómo consumirlo

1. Resolver `PRE_EKB_GATE` en `public.lf_activos` y confirmar `ACTIVO / ACTIVE_SHARED_ENFORCEMENT`.
2. Consumir únicamente sus superficies canónicas y conservar operation/consumer identity, source revision y evidencia.
3. No crear una implementación paralela.
4. Cerrar con readback durable y currentness suficiente.

## Superficies canónicas

- `public.lf_pre_ekb_gate_check_dispatch_v1(bigint)`
- `public.lf_pre_ekb_step_failure_dispatch_v1(text,text)`
- `public.lf_pre_ekb_exception_dispatch_v1(...)`
- `ACT-0057 / ESCRITURA_BASE_CONOCIMIENTO_LF`

## Fail-closed / límites

Si falta currentness, binding, autoridad o evidencia requerida, bloquear. Este README documenta consumo; no concede permisos ni sustituye contratos/runtime.

## Validación y readback

Ejecutar los gates propios de la capability y del consumer, conservar evidencia exacta y verificar el resultado desde la superficie durable correspondiente.

## No duplicación

Extender esta capability por su owner cuando haga falta; no crear una segunda ruta que resuelva la misma responsabilidad.

## Currentness

Consultar `public.lf_activos` y la superficie runtime vigente antes de cada decisión material. El README debe actualizarse si cambia el contrato de consumo.

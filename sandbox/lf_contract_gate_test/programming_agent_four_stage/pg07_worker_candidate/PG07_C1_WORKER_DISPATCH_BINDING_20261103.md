# PG-07_C1 — Integración fuente del constructor Worker v0.8

## Alcance oficial

PG-07_C1 define el constructor como Worker v0.8, con proveedor/modelo fijos por corrida, orquestación por carriles según los locks de PG-05 y registro de tokens de entrada, salida y caché, así como costo por llamada (D16). La autoridad de ejecutar el Worker no procede del código fuente candidato.

## Reutilización constatada

- **Especificación existente:** `programacion.fn_agent_task_worker_spec(bigint,text,text)`, implementada en `supabase/migrations/20260824041516_programacion_worker_spec_oracle_isolation_v3.sql`. Proyecta la especificación visible del worker; `hidden_oracle_ref`, `hidden_oracle_sha256`, `oracle_envelope` y `readiness` no se incluyen en su salida.
- **Bundle existente:** `programacion.fn_agent_task_execution_bundle(bigint,text,text)`. Su acceso incluye material sensible que el constructor no debe consumir directamente.
- **Ejecutores existentes:** `ENGINEERING_PARALLEL_EXECUTOR_V1` y `PROGRAMMING_SIMPLE_EXECUTOR_V1`. El último ejecuta validaciones de checkpoints y carriles; no está demostrado que sea un despachador real del modelo. El binding exacto de carril/Worker sigue pendiente.
- **Gobernanza:** `programacion.programming_checkpoint_bindings` es el contrato de enlace de checkpoints; no reusar PASS histórico en lugar de evidencia nueva.

No se crea un Worker nuevo, no se reemplaza el orquestador y no se invoca la función SQL ni un modelo de IA.

## Componente añadido

`tools/pg07_c1_worker_dispatch_plan_v1.py` implementa:

`prepare_pg07_c1(pg05_exit, pg06_c5, run_binding, worker_task_bindings)`

Verifica las huellas fuente de PG-05→PG-06 y de la solicitud de aseguramiento PG-06_C5, que los cinco checkpoints siguen sin admitir y que ninguna entrada pretende conceder permisos de escritura o despacho.

La configuración **por corrida** requiere `run_ref`, `provider`, `model_id`, `model_profile_ref`, `pricing_ref`, moneda y tres precios exactos declarados como cadenas decimales, `worker_version=0.8`, referencias de contrato del Worker y ejecutor de carriles. El productor **no infiere** proveedor, modelo, precios, perfil o coste.

Cada solución debe tener binding explícito a `agent_task_id`, `task_binding_ref`, `worker_spec_ref`, base HEAD idéntico al target y fingerprint de snapshot, con `task_execution_authority_ref` declarado. Esos valores son aportados por el invocador y no se autentican aquí.

La salida contiene un esquema para recibos **por llamada** con `input_tokens`, `output_tokens`, `cached_input_tokens`, `reported_cost`, moneda, `usage_source_ref` y `call_execution_receipt_ref`, así como proveedor/modelo de la corrida. La semántica de si los tokens de entrada ya incluyen los de caché debe venir del contrato del proveedor: no se suma o resta por suposición. **No se calculan costos ni se registra un consumo inexistente**.

## Bloqueos y próximo paso

Antes de despachar realmente a un Worker debe verificarse:
1. PG-04/05/06 admitidos con aseguramiento, recibos y vigencia;
2. especificación de tarea exacta desde `fn_agent_task_worker_spec` y exclusión efectiva del oráculo oculto;
3. mecanismo real de despacho al proveedor/modelo y su vínculo con el ejecutor por carriles;
4. locks reales y write-scope por solución;
5. capturas auténticas de tokens y tarifas vigentes para una contabilidad por llamada.

El paquete mantiene `dispatch_allowed=false`, `worker_invoked=false`, `writer_locks_acquired=false`, `usage_receipts_verified=false`, `write_allowed=false`, `pg07_admitted=false`, `production_authority=false`, `handoff_allowed=false`.

**Estado:** `PG07_C1_SOURCE_DISPATCH_BINDING_PREPARED / LIVE_DISPATCHER_NOT_BOUND / USAGE_NOT_OBSERVED / OFFICIAL_PENDING`.

Las pruebas siguen pausadas por decisión del Owner. No se ejecutaron Worker, jueces, build/lint ni acciones en Análisis, Supabase o main.

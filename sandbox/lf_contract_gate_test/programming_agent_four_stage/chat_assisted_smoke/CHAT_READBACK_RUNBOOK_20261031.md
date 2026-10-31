# Procedimiento repetible — ChatGPT + Supabase RO + Carril D (Paulo)

## Estado
**CANDIDATO / SOLO LECTURA / SIN AUTORIDAD**. No es executor, ni pipeline obligatorio, ni mecanismo de autenticación de recibos. No fusionar ni usar para cerrar checkpoints.

## Fuentes y componentes existentes (evitar duplicación)
- Conector Supabase RO integrado en el chat: `mcp__Supabase_RO__execute_sql`, autenticación gestionada por el conector.
- Ledger: `programacion.engineering_plan_units` → `programacion.engineering_work_checkpoints`.
- `pg_tool_readback.py`, `pg_chat_readback_flow.py`: proyección observacional.
- `pip1_core_object_bridge.py`: adaptación de objetos **sintéticos** del núcleo PIP-1. No es un puente de autoridad.
- `pip1_core/core.py` en rama `lf/pip1-core-isolated-d07`: fuente del núcleo puro Carril D. No duplicar transitions.
- `pg_bootstrap_chat_gate.py`: interpretación de Simple Executor; **no** ejecutor de Carril D ni autoridad.

## Secuencia obligatoria en un chat conectado
1. Consultar GitHub: HEAD actual del PR, rama Carril D y versión de inventario. Registrar SHAs; si cambia, repetir pruebas exact-HEAD.
2. Ejecutar la consulta RO parametrizada por un plan/unidad/checkpoint **elegidos por el operador**. Requerir exactamente una fila, `current_user=supabase_read_only_user`, identidad exacta y estatus conocido. No copiar valores de una consulta anterior como si fueran actuales.
3. Suministrar **solo la fila devuelta por el conector** al `pg_chat_readback_flow.summarize_observation` en entorno aislado. La procedencia de la consulta pertenece a la herramienta; el módulo por sí solo no autentica un JSON.
4. Mostrar el estado y la razón para detenerse. Si no existen bindings/admisión válida, emitir `STOP_AWAIT_CHECKPOINT_BINDING_AND_EXTERNAL_AUTHORITY`.
5. Solo preparar trabajo técnico en rama de ensayo cuando el alcance lo permita; **nunca marcar DONE** ni despachar Worker basándose en este procedimiento.
6. Un recibo `PASS`, incluso con hash, exige verificación independiente de proveedor, run, pins y checkpoint conforme al contrato autorizado. Reutilizar validadores existentes, no fabricar PASS.
7. Anotar resultado, HEAD, consulta utilizada y bloqueos en el PR Draft.

## SQL de lectura a usar (no ejecución de cambios)
```sql
select current_user as db_actor, pu.plan_code, pu.unit_code,
       c.checkpoint_code, c.status, c.required,
       c.updated_at::text as updated_at, c.assertion_receipt_sha256
from programacion.engineering_plan_units pu
join programacion.engineering_work_checkpoints c
  on c.work_item_id = pu.work_item_id
where pu.plan_code = 'PROGRAMMING_AGENT_PROGRAMMING_REMEDIATION_V1'
  and pu.unit_code = 'PG-00'
  and c.checkpoint_code = 'PG-00_C1'
  and pu.disposition = 'ASSIGNED';
```
Ajustar unidad/checkpoint explícitamente; jamás admitir IDs aportados por un resultado no confiable.

## Evidencia de ensayo RO (31/10/2026)
- Consulta realizada por conector `supabase_read_only_user`.
- `PG-00_C1` → `PENDING`, `required=true`, `assertion_receipt_sha256=null`.
- Marca de modificación del registro: `2026-10-28 16:13:20.084475+00`.
- HEAD del PR antes de este documento: `961e04b305a01b8ee2147fa76228e8d516893b62`.
- El corte anterior reprodujo 39/39 tests sobre ese HEAD, pero la nueva consulta de este corte **no cambia** la autorización.
- `programming_simple_plan_admission_v1` había devuelto `admitted=false`, `REQUIRED_CHECKPOINT_WITHOUT_VALIDATION_BINDING` y 0 bindings para este plan. Comprobar de nuevo antes de asumir que siga vigente.

## Criterio para avanzar al siguiente hito
Debe existir una ejecución autorizada y un mecanismo de lectura/validación independiente que una **plan, run, pins del inventario, checkpoint y recibo del proveedor** con prueba negativa de suplantación y drift. Hasta entonces el flujo es de observación: `write_authorized=false`, `transition_authorized=false`, `worker_dispatch_authorized=false`.

## No confundir
- Estado `DONE` del ledger **NO** equivale automáticamente a `SUCCEEDED_ACCREDITED` del núcleo PIP-1.
- Una ejecución de tests de adaptadores **NO** cierra PG-00 ni PG-01.
- Un chat conectado **NO** constituye automatización desatendida.

# A16Q_C1 — Inventario Router First y consumidores de perfiles

- Plan: `PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1`.
- Sujeto: `A16Q` / work item `1126`, checkpoint `A16Q_C1`.
- Tipo: **investigación de arquitectura, solo lectura**; no constituye C2 E2E, activación, promoción GOLDEN ni autorización de modelo/API.
- Fuente de investigación: lectura de Supabase `public`, `programacion`, `private` y fuente GitHub `cristhianlujan/claude-persona-lf-patch`, inspeccionadas el 2026-10-15. La ejecución de C1 debe repetir los readbacks contra las versiones vigentes.

## 1. Autoridad y registro de operaciones

| Elemento | Evidencia exacta | Estado observado |
| --- | --- | --- |
| Autoridad `ACT-0001` | `public.lf_activos.codigo_activo='ACT-0001'` | `DOC`, `ACTIVO`; autoridad documental, no es el código ejecutable |
| Router operativo | `public.lf_router_resolve_v1(text,text,text,text,text)` | Función existente; acción `ASSET_INSPECTION` devuelve `READY_INSPECTION` para `PERFIL-UI-ARCHITECT` |
| Registro acción-perfil | `public.lf_router_action_registry` | `PERFIL/PROFILE_EXECUTION -> EJECUCION_PERFIL_LF`; `PERFIL/ASSET_INSPECTION -> NONE`; `PROFILE_UPDATE/CREATE` registrados por separado |
| Operación | `public.lf_operation_registry` para `EJECUCION_PERFIL_LF` | `OP_OPERATIONAL`, `PRODUCCION_CONTROLADA_READ_ONLY`; no autoriza ejecución de cada perfil por sí sola |
| Guards | `ROUTER_DOWNSTREAM_AUTHORITY`, `OPERATION_EFFECT_GUARD`, `OPERATION_MATERIALIZATION_GUARD` en `public.lf_activos` | Registrados `ACTIVO`; aplicabilidad y receipts de cada ejecución se validan aparte |

**Prueba positiva de lectura:** `lf_router_resolve_v1('Inspeccionar el perfil UI Architect para inventario de arquitectura','PERFIL-UI-ARCHITECT','ASSET_INSPECTION','PERFIL','DIRECT')` devolvió `READY_INSPECTION`, acción `ASSET_INSPECTION`, un adapter; ninguna ejecución de perfil.

**Prueba negativa de selección:** `lf_router_resolve_v1('Ejecutar el perfil frontend prototype architect solo como prueba de enrutamiento sin efecto','ACT-0051','PROFILE_EXECUTION','PERFIL','DIRECT')` devolvió `BLOCKED`, `BLOCK_PROFILE_RUNTIME_STATE_NOT_AUTHORIZED`, `downstream_execution_allowed=false`; no se invocó el runtime.

## 2. Perfiles y binding real de adapters

| Activo | Tipo / estado | Binding |
| --- | --- | --- |
| `PERFIL-UI-ARCHITECT` | `PERFIL / READ_ONLY`; metadata `runtime_enabled=false` | Un adapter en `public.v_lf_router_adapter_bindings`: `ADAPTER-LF-SHELL-PROFILE-20260827` |
| `ACT-0051` | `PERFIL / READ_ONLY`; `runtime_estado=NO_APLICA` | Mismo adapter, pero no autoriza ejecución del perfil |
| `ADAPTER-LF-SHELL-PROFILE-20260827` | `ADAPTER / READ_ONLY`; canary acotado | `ADAPTER_APLICA_A` registrado; metadata `runtime_enabled=true`, `production_enabled=false` |
| `ADAPTER-PROJECT-BRAND-MOCKUP-RENDER-LF-20260827` | `ADAPTER / READ_ONLY`, runtime no habilitado | Dependencia indirecta de Input Governance; **no** implica selector de perfiles ni DEMO activo |

Fuente: `public.lf_activos`, `public.lf_activo_relaciones` y `public.v_lf_router_adapter_bindings`. No inferir activación del perfil a partir de un adapter en canary.

## 3. Input Governance: enlace y frontera de permisos

- Router: el SQL de `public.lf_router_resolve_v1` consulta la vista de bindings y, cuando hay adapter, invoca `programacion.fn_lf_router_input_governance_resolve_v1(text,jsonb,text)`.
- La función IG está registrada como `SECURITY DEFINER`, ACL `postgres` y `service_role`. El conector `supabase_read_only_user` puede invocar el Router, pero **no** la función IG: la prueba `PROFILE_EXECUTION` sobre `PERFIL-UI-ARCHITECT` dio SQLSTATE `42501`.
- Ese `42501` prueba una limitación del conector RO, **no** una denegación comprobada para un consumidor autorizado con `service_role`.
- El contrato `INPUT_GOVERNANCE_EXECUTION_CONTRACT` determina los consumidores permitidos; no interpretar `TBL-LF-PROYECTOS-DEMO-001` como modo DEMO.

## 4. Consumidores identificados

| Consumidor / código | Entrada o fuente real | Estado |
| --- | --- | --- |
| `public.lf_router_resolve_v1` | DB, función invocada y observada | **Lectura real verificada**, ejecución de perfil pendiente |
| `PROFILES_GITHUB_ACTIONS_BATCH_QUEUE_WORKER_V1` | `sandbox/lf_contract_gate_test/profile_execution_runtime/github_actions_batch_queue_worker.py` | Código consulta `public.v_lf_router_adapter_bindings`, luego `programacion.fn_lf_router_input_governance_resolve_v1`, realiza preflight y persiste resultado; activo `CANDIDATE_READ_ONLY` |
| `PROFILE_RUNTIME_API_SERVICE` | `services/profile_runtime_api/profile_runtime_api/app.py` y `engine.py` | API FastAPI con ejecuciones, jobs, receipts y binding de contexto; activo `CANDIDATE_READ_ONLY` |
| Cola y worker base | `private.lf_profile_runtime_queue_v1` y `github_actions_queue_worker.py` | Tabla con solicitudes y resultados históricos; no acredita por sí sola un despliegue operativo vigente |

**Observación SQL histórica acotada:** sobre `private.lf_profile_runtime_queue_v1`: `BLOCKED=75`, `FAILED=7`, `PENDING=3`, `SUCCEEDED=1` al momento de la lectura (total 86). El único `SUCCEEDED`, para `PERFIL-UI-ARCHITECT` y target `HETZNER`, contiene `PROFILE_EXECUTION_RECEIPT_V1` y huellas de fuente/input/RAW, pero **no** las claves `router_binding`, `router_authority_receipt`, `obligation_manifest_sha256` ni una verificación independiente enlazada con la misma ruta. Resultado histórico, no autorización actual ni demostración Router→consumidor→recibo.

## 5. Matriz de brechas (C1 clasifica; C2 demuestra)

| Código | Hallazgo | Tratamiento |
| --- | --- | --- |
| `A16Q-GAP-01` | Falta prueba íntegra que ligue solicitud literal, Router, perfil dinámico, adapter, consumidor, RAW y recibo del mismo sujeto | Requisito obligatorio **C2**, no inventar PASS desde código o ledger histórico |
| `A16Q-GAP-02` | Worker y API son activos candidatos `READ_ONLY`, no evidencia de despliegue vigente | Verificar autoridad de runtime/consumidor antes de consumirlos |
| `A16Q-GAP-03` | Conector RO no tiene `EXECUTE` sobre IG interno, aunque sí sobre Router | Separar permiso de inspección de autorización operacional; no ampliar ACL por conveniencia |
| `A16Q-GAP-04` | Selección dinámica de perfiles y modos DEMO/completo/parcial/modificación no fue acreditada extremo a extremo | Resolver en arquitectura C2 y evaluar positivos/negativos en C3 |
| `A16Q-GAP-05` | Un `SUCCEEDED` de la cola histórica no contiene procedencia Router comprobable | Mantener como historia; exigir recibo actual con identidad y binding exactos |

## 6. Contrato de salida de C1

C1 es **inventario de autoridad, relaciones, consumidores y brechas**. Un `READBACK_ONCE` puede verificar las consultas declaradas, pero **no** demostrar la aplicación completa ni convertir fallos históricos en éxito. Los guardrails C2 y C3 siguen independientes.

- EKB reutilizados: `ENGINEERING-FOUR-CAPABILITY-ROUTER-001`, `ENGINEERING-CONSUMER-PROBE-WRITE-MISCLASSIFICATION-001`, `POST-PASE-CONSUMER-CANONICAL-BINDING-001`, `ENGINEERING-REPOSITORY-CAPABILITY-CONSUMER-ASSERTION-001`.
- Estado requerido antes de cierre de C1: source pack exacto/current, action spec de lectura, verificación de consultas y assertion receipt enlazado al checkpoint; jamás inferirlo de que el documento exista.
- No escribir sobre otros planes, no ejecutar runtime, no habilitar perfiles/adapters, no promover a GOLDEN.

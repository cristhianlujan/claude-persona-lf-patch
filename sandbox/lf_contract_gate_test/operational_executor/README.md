# LF_OPERATION_EXECUTOR_V1 — candidato, no activado

## Decisión: una conexión READ_ONLY + un servicio operativo restringido

No crear otra conexión Supabase general con lectura/escritura. La conexión de diagnósticos continúa de solo lectura. Una vez admitido y desplegado el runtime, conectar a ChatGPT un MCP remoto HTTPS del Operation Executor (autenticación del MCP). El DSN de escritura queda SOLO en el servidor del ejecutor.

ORQUESTADOR → ACT-0001 Router
- READ_ONLY → Supabase actual read-only.
- DB + UPDATE → ACTUALIZACION_DB_LF → LF Migration Merge Train exclusivo.
- OPERATIONAL_DB + OPERATION_EXECUTE → EJECUCION_OPERATIVA_LF → Operation Executor (handler autorizado, lease, effect guard, readback, cierre y commit/rollback).

**Readback actual en Supabase:** la ruta OPERATIONAL_DB/OPERATION_EXECUTE devuelve BLOCK_OPERATION_NOT_REGISTERED (0 operaciones y 0 rutas registradas); DB/UPDATE continúa apuntando a ACTUALIZACION_DB_LF. Es intencional: no cambiar el Router de migraciones para probar el executor.

## Componentes reutilizados

- public.lf_router_resolve_v1: resolución de autorización.
- public.lf_operation_execution: identidad y manifest durable de Router, emitidos fuera del executor.
- public.lf_router_downstream_authority_validate_v1: autoridad y currentness.
- public.fn_lf_operation_acquire_lease_v1.
- public.fn_lf_operation_reserve_effect_v1.
- public.fn_lf_operation_mark_effect_succeeded_v1.

El núcleo NO conoce ninguna tabla o unidad de negocio. Los handlers se agregan como código empaquetado y aprobado: NO admite nombre de función o SQL del caller. La registry de handlers está deliberadamente vacía hasta admitir las capacidades consumidoras.

El manifest durable liga estado APPROVED, verification PASS, lane GOVERNED_OPERATIONAL_DML, connector LF_OPERATION_EXECUTOR_V1, handler_code, handler_revision, payload_sha256, effect_scope y dispatch_key. Solo se acepta la operación transversal EJECUCION_OPERATIVA_LF; ningún proyecto ni función de negocio se fija en el núcleo. Sin igualdad exacta, BLOCK.

El contrato de admisión propuesto (NO activado) está en operation_lane_contract_candidate_v1.json. Registrar esa ruta, su contrato, sus pasos, el consumidor de Router Authority y el juez sin alterar DB_WRITE_TRANSPORT es una tarea de gobernanza distinta, sometida al Train.

## Transacción y control

dispatch() utiliza una sola transacción y **únicamente dos fachadas SQL autorizadas**: `lf_operational_executor_begin_v1` valida Router, admisión, lease y effect guard; el handler empaquetado realiza el efecto y lee su resultado; `lf_operational_executor_finish_v1` vuelve a validar Router, marca el efecto y llama `lf_close_operational_execution_v1` que registra tres pasos con `lf_record_operation_step_core_v1` antes de COMMIT. El cierre debe comprobar la ejecución, su lease/fence, los pasos gobernados y el recibo; las tres funciones siguen siendo CANDIDATAS en el PR #2372 y NO EXISTEN aún en la base. Hasta que esté versionada/admitida, cualquier operación real falla cerrada en vez de dejar una ejecución IN_PROGRESS o reclamar un COMMIT válido.

dry_run=true revierte también reserva y recibo. Un effect reservado sin desenlace queda BLOQUEADO, no se repite automáticamente. La ruta READ_ONLY nunca escribe.

runtime_dispatch() requiere LF_OPERATION_EXECUTOR_LANE=GOVERNED_OPERATIONAL_DML y LF_OPERATION_EXECUTOR_DSN en el servidor. La variable de entorno no concede permisos por sí sola: se requiere manifest durable aprobado y autoridad canónica vigente. LF_OPERATION_EXECUTOR_ACTOR es de servidor, no enviado por el caller.

El PR #2372 define el rol agrupador `lf_operation_executor_runtime NOLOGIN NOINHERIT`, sin acceso a tablas y con EXECUTE solo sobre las dos fachadas. Un usuario de conexión y su concesión de rol, autenticación y contraseñas quedan PENDIENTES de validación y aprovisionamiento seguro. NO desplegar con postgres, service_role o una credencial de DML general. El administrador debe revisar EXECUTE mínimo, SECURITY INVOKER y privilegios de tablas. Si un handler requiere permisos adicionales, utilizar una fachada SQL restringida, versionada y aplicada únicamente por Migration Train. El ejecutor no se convierte en DB_WRITE_TRANSPORT para migraciones.

## Estado y próximos gates

CODE-ONLY / NO CONECTADO / NO DESPLEGADO / SIN HANDLERS REGISTRADOS.

1. Revisar el PR #2372 (una sola migración candidata) que registra EJECUCION_OPERATIVA_LF, OPERATIONAL_DB/OPERATION_EXECUTE, contratos/policies/steps/authority y tres fachadas SQL de privilegio mínimo. No está aplicado.
2. Registrar por separado cada handler con versión y bind exacto. Mantener independencia de proyectos.
3. Auditar rol DB de privilegio mínimo. Cualquier cambio DDL o de políticas se aplica mediante Train.
4. Probar positivo, denegación, conflicto, replay, rollback y readback real en sandbox.
5. Publicar MCP remoto HTTPS con autenticación y secretos solo de servidor. EN ESE MOMENTO crear segunda conexión en ChatGPT. Mantener la Supabase READ_ONLY actual.
6. EKB/currentness, pruebas negativas y veredicto de aseguramiento.

Prueba offline: python3 sandbox/lf_contract_gate_test/operational_executor/test_executor_v1.py

CI offline no es autorización de despliegue o escritura real. Este PR no altera ledger, DB, producción ni migraciones.

# LF_OPERATION_EXECUTOR_V1 — candidato, no activado

## Decisión: una conexión READ_ONLY + un servicio operativo restringido

No crear otra conexión Supabase general con lectura/escritura. La conexión de diagnósticos continúa de solo lectura. Una vez admitido y desplegado el runtime, conectar a ChatGPT un MCP remoto HTTPS del Operation Executor (autenticación del MCP). El DSN de escritura queda SOLO en el servidor del ejecutor.

ORQUESTADOR → ACT-0001 Router
- READ_ONLY → Supabase actual read-only.
- MIGRATION → LF Migration Merge Train exclusivo.
- OPERATION → Operation Executor (handler autorizado, lease, effect guard, readback, commit/rollback).

## Componentes reutilizados

- public.lf_router_resolve_v1: resolución de autorización.
- public.lf_operation_execution: identidad y manifest durable de Router, emitidos fuera del executor.
- public.lf_router_downstream_authority_validate_v1: autoridad y currentness.
- public.fn_lf_operation_acquire_lease_v1.
- public.fn_lf_operation_reserve_effect_v1.
- public.fn_lf_operation_mark_effect_succeeded_v1.

El núcleo NO conoce ninguna tabla o unidad de negocio. Los handlers se agregan como código empaquetado y aprobado: NO admite nombre de función o SQL del caller. La registry de handlers está deliberadamente vacía hasta admitir las capacidades consumidoras.

El manifest durable liga estado APPROVED, verification PASS, lane GOVERNED_OPERATIONAL_DML, connector LF_OPERATION_EXECUTOR_V1, handler_code, handler_revision, payload_sha256, effect_scope y dispatch_key. Sin igualdad exacta, BLOCK.

## Transacción y control

dispatch() trabaja en UNA transacción: Router → ejecución → admission → autoridad → lease → effect reservation → callback confiable → readback obligatorio → revalidación de autoridad → marca efecto SUCCEEDED → commit.

dry_run=true revierte también reserva y recibo. Un effect reservado sin desenlace queda BLOQUEADO, no se repite automáticamente. La ruta READ_ONLY nunca escribe.

runtime_dispatch() requiere LF_OPERATION_EXECUTOR_LANE=GOVERNED_OPERATIONAL_DML y LF_OPERATION_EXECUTOR_DSN en el servidor. La variable de entorno no concede permisos por sí sola: se requiere manifest durable aprobado y autoridad canónica vigente. LF_OPERATION_EXECUTOR_ACTOR es de servidor, no enviado por el caller.

NO desplegar con postgres, service_role o una credencial de DML general. El administrador debe revisar EXECUTE mínimo, SECURITY INVOKER y privilegios de tablas. Si un handler requiere permisos adicionales, utilizar una fachada SQL restringida, versionada y aplicada únicamente por Migration Train. El ejecutor no se convierte en DB_WRITE_TRANSPORT para migraciones.

## Estado y próximos gates

CODE-ONLY / NO CONECTADO / NO DESPLEGADO / SIN HANDLERS REGISTRADOS.

1. Autorizar extensión operacional en Router/policies sin cambiar el carril exclusivo de migraciones.
2. Registrar por separado cada handler con versión y bind exacto. Mantener independencia de proyectos.
3. Auditar rol DB de privilegio mínimo. Cualquier cambio DDL o de políticas se aplica mediante Train.
4. Probar positivo, denegación, conflicto, replay, rollback y readback real en sandbox.
5. Publicar MCP remoto HTTPS con autenticación y secretos solo de servidor. EN ESE MOMENTO crear segunda conexión en ChatGPT. Mantener la Supabase READ_ONLY actual.
6. EKB/currentness, pruebas negativas y veredicto de aseguramiento.

Prueba offline: python3 sandbox/lf_contract_gate_test/operational_executor/test_executor_v1.py

CI offline no es autorización de despliegue o escritura real. Este PR no altera ledger, DB, producción ni migraciones.

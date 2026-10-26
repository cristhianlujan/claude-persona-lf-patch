# PG01_2FP_OPERATION_CANDIDATE_V1

26-oct-2026. Draft para D8; GO de Cristhian pendiente. Sin apply, activación, modelos o escrituras hosted. Base main ce3a96ba7bf25cc8ef4b1142509a5a6c6399a267.

## Cambio mínimo

Una sola fila nueva propuesta en public.lf_router_action_registry:

| Columna | Valor propuesto |
|---|---|
| asset_type | REPOSITORY_ARTIFACT |
| action_code | CODE_DEVELOPMENT |
| operation_code | DESARROLLO_CODIGO_AGENTE_LF |
| operation_resolution | STATIC |
| requires_existing_target | false |
| requires_missing_target | false |
| write_allowed | false |
| status | CANDIDATO_READ_ONLY |
| created_by_execution_id / updated_by_execution_id | Ejecución real de ACTUALIZACION_DB_LF abierta por el Train antes de apply; no se inventa ni se reserva ahora |

REPOSITORY_ARTIFACT ya aparece como subject_type del Router; su uso como asset_type de esta fila y CODE_DEVELOPMENT son vocabulario candidato propuesto para ratificación D8, no un clasificador automático ni un nuevo tipo activo registrado. Ambas flags de existencia son false porque el destino de código no se equipara a un activo hidratado de lf_activos; no eliminan la obligación de identidad exacta y admisión PG-01. No se reutiliza UPDATE, PROFILE_UPDATE ni otra acción activa para desviar tráfico.

Se sigue el formato de columnas de DEPLOY_SUPABASE_EDGE_FUNCTION_LF: STATIC, CANDIDATO_READ_ONLY, write_allowed=false, notes y autoría. No se clonan su contrato de despliegue, pasos, policies, actor histórico ni capacidad de ejecución. A diferencia de esa operación, aquí solo se propone la fila pedida; DESARROLLO_CODIGO_AGENTE_LF tampoco existe aún en lf_operation_registry. Su contrato completo, estado, pasos, judges y autorización son trabajo futuro de 2F.P/D8. La fila no lo crea ni permite invocarlo.

## Migración y autoría

Archivo: supabase/migrations/20261026153320_lf_programming_code_operation_candidate_v1.sql.
Nombre clasificado: lf_programming_code_operation_candidate_v1, cubierto por MANAGED_PREFIXES: lf_ de main. El Train puede asignar/reasignar versión cuando proceda; el borrador no evade colisiones ni aplica ledger.

El SQL solo lee catálogos y hace un INSERT en la fila candidata. No contiene UPDATE, DELETE, grants, funciones nuevas o registro de ejecuciones. Si la fila ya coincide exactamente, conserva fila/autor/fechas. Conflicto de clave, operación bajo otra clave, estado ACTIVE o write_allowed=true se rechazan, nunca se sobrescriben.

La autoría se resuelve desde una única ejecución IN_PROGRESS de ACTUALIZACION_DB_LF para esta migración, producer lf-migration-merge-train, repo/path ligados al recibo Router del Train. Si falta, es ambigua, está completada o corresponde a otro target, el SQL bloquea con PG01_2FP_TRAIN_EXECUTION_REQUIRED. Esto da procedencia a la futura escritura de registro, no autoriza desarrollar código ni reemplaza los controles del Train. En tests esa ejecución es explícitamente fixture://train-execution-2fp. No existe una ejecución real nueva creada por este trabajo.

La lectura RO del Router para preparar el borrador devolvió BLOCK_SCOPE_SEMANTICS_UNATTESTED, sin autoridad de ejecución. No se usa ese resultado como autorización de apply; el contrato del repo permite desarrollar/probar una propuesta local y PR draft. La futura admisión/aplicación se reserva al Router→ACTUALIZACION_DB_LF→Train, después de GO D8.

## Prueba en PostgreSQL desechable

Comando desde el root:
`python3 sandbox/lf_contract_gate_test/programming_agent_four_stage/wave1_boundary_contracts/test_pg01_2fp_candidate_local_v1.py --allow-local-docker --sudo-docker`.

28 assertions locales coincidentes en Postgres 17.6, contenedor --network none, sin puertos, tmpfs y cleanup. No se aceptan DSN, host, credenciales ni entorno hosted en el CLI.

El test carga la función lf_router_resolve_v1 completa y sin cambiarla desde readback RO del 26-oct:
- fixtures/lf_router_resolve_v1_readback_20261026.sql.
- SHA256 c99a99e61adbc783452b487f7fbccf5aa962aacaaa4e98afc2c4d5664b670886.
- md5(pg_get_functiondef) 7f2d4d27e6b7a88f9fa22d2db6c00c8b, cotejado en Postgres local.
- Los catálogos/dependencias son fixtures mínimos, no copia del sistema vivo. Es una fixture de la función real para caracterización aislada; no otro Router ni un runtime desplegado.

Resultado real con fila candidata y argumentos tipados fixture: BLOCK_OPERATION_NOT_REGISTERED, sin operation_code. El SELECT del Router exige status='ACTIVE'. Control de mutación únicamente local en BEGIN/ROLLBACK: cambiando solo status a ACTIVE, alcanza el gate siguiente BLOCK_OPERATION_REGISTRY_MISSING para DESARROLLO_CODIGO_AGENTE_LF. Tras ROLLBACK vuelve a BLOCK_OPERATION_NOT_REGISTERED. Esto demuestra que se alcanzó el filtro ACTIVE y que el negativo no se debe solo a otra compuerta anterior.

Otros controles: ausencia/ambigüedad de autoría Train, autor completado/target distinto, repetición idempotente de fila completa, conflicto de estado/permiso/otra clave, referencia Edge intacta, fuente del Router intacta, ninguna operación creada y una sola fila candidata. Los fallos esperados se ejecutan en transacciones que se revierten.

Evidencia: pg01_2fp_candidate_local_20261026.json. Es local con catálogos sintéticos; no se presenta como prueba de activación o ejecución viva. CI se informa por nombre en el handoff exact-HEAD; estas 28 assertions no se atribuyen a CI.

## Pendientes para D8

Ratificar vocabulario y modelo de destino, diseñar operación/contratos/judges/policies, resolver admisión real Router/PG-01, calificar consumidores y autorizar activación por separado. El PR sigue draft sin labels. No toca #3148, #3166, D7 ni el contrato de entrada V1.

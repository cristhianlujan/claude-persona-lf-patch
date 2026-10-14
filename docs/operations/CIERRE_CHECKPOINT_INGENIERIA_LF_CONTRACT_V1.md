# CIERRE_CHECKPOINT_INGENIERIA_LF — contrato candidato V1

**Estado: CANDIDATO; no instalado ni activado.** Operación administrativa propuesta para cerrar un checkpoint de ingeniería sin ejecutar una migración por cada cierre. No modifica la política ni el ejecutor LF Migration Merge Train.

## Alcance y autoridad
- Tipo de activo: ENGINEERING_CHECKPOINT; acción: CHECKPOINT_CLOSE.
- Entrada gobernada por ACT-0001 con operación, identidad y efecto autorizados.
- Solo modifica la fila de checkpoint identificada y la auditoría vinculada. No modifica resultados de evaluación, capacidades, versiones ni producción.
- El proveedor canónico se lee en servidor; nunca aceptar un PASS, hash, evidencia o identidad declarados por el cliente como autoridad.
- Candidato inicialmente de solo lectura. La instalación y activación requieren admisión independiente bajo la política vigente; no constituyen un permiso para escribir directamente en Supabase.

## Mecanismo propuesto
1. Resolver Router y validar vigencia de autoridad, identidad, idempotencia, checkpoint actual y ausencia de bloqueos.
2. Leer el proveedor de evidencia y el contrato activo del checkpoint en la misma transacción. Rechazar evidencia ausente, obsoleta, incompleta o ajena.
3. Reutilizar programacion.fn_engineering_checkpoint_assertion_record_v1 con resultado derivado del proveedor, no del cliente. Verificar recibo y hash vinculados al contrato actual.
4. Reutilizar programacion.fn_engineering_checkpoint_transition_v1 para DONE; mantener activo fn_guard_engineering_material_checkpoint_done_v1.
5. Leer nuevamente el ledger y el siguiente checkpoint; ante falla, rollback completo. No crear otro ledger, juez o mecanismo de bypass.

## Piloto permitido
- IG_CURATOR_VALIDATOR_REFACTOR_V2 / M10.5 / NEW_RUNS_VNEXT.
- Proveedor: programacion.v_ig_m105_cp2_sample_readback_v1.
- ONB_001, run 931, muestra de cinco familias: STATES, SECURITY, API_DATA_CONTRACT, FRESHNESS_INVALIDATION y ACCESSIBILITY.
- Exigir PASS_CP2_MUESTRA, fuente vigente, 5/5 evidencias independientes y prueba negativa de ejecución obsoleta.
- No inferir readiness de las 13 pantallas ni las 47 familias; no aprobar producción.

## Pruebas mínimas antes de activar
- Positivo basado en proveedor vigente; negativos: fuente obsoleta, validador incompleto, autorización de producción indebida, falta de negativo, contrato alterado, identidad o permiso ausente.
- Solo el ejecutor autorizado puede registrar el recibo y DONE; repetir el mismo cierre debe ser idempotente.
- Probar rollback íntegro y ausencia de cambios fuera de la unidad.
- El estado PENDING actual no se altera mediante la publicación de este documento.

## Antecedentes y EKB
PR #2642: contrato muestral aplicado. PR #2643: cierre SQL detenido antes de apply por Train; no reintentar ciegamente. EKB: ENGINEERING-MATERIAL-DONE-ASSERTION-BINDING-001, IG-M105-CP2-EXHAUSTIVE-SCOPE-UNNECESSARY-018, PROGRAMMING-E2E-ROUTER-PREWRITE-ORDER-001.

## Candidato implementado en el PR

- `operation_candidate_v1.sql`: función genérica `fn_engineering_checkpoint_close_governed_v1` y tabla de vínculos de proveedores. No conoce M10.5, ONB_001 ni familias de Input Governance; lee el proveedor desde un registro gobernado.
- `ig_m105_cp2_provider_candidate_v1.sql`: adaptador de evidencia de una pantalla y cinco familias. Vinculación `CANDIDATE`, jamás `ACTIVE` por este cambio.
- `operation_registration_candidate_v1.sql`: registra una operación `CANDIDATO_READ_ONLY` y una ruta Router `CANDIDATE` con `write_allowed=false`. Ninguno de estos SQL se ejecuta desde el PR.
- `test_candidate_contract_v1.py`: controles offline de alcance y denegación. No confundir con pruebas transaccionales.

### Admisión y activación inicial pendientes

1. Validar por owner el contrato de operación, el paso de ejecución gobernada y los contratos/policies concretos del Router. Registrar `CIERRE_CHECKPOINT_INGENIERIA_LF` como consumidor del verificador transversal `ROUTER_DOWNSTREAM_AUTHORITY` sin modificar su implementación.
2. Instalar **una sola vez** registro, vínculo, proveedor y función por una vía de escritura autorizada conforme a `ACTUALIZACION_DB_LF`. No usar el conector read-only como bypass. Con Train bloqueado, no se activa.
3. Preparar un ejecutor autorizado con identidad del servicio y recibo de Router; exigir `lf_operation_execution` real `IN_PROGRESS` y efecto S30 `RESERVED` asociado al contrato vigente.
4. Probar primero en transacción reversible con rollback: positivo vigente, negativos por stale, 4/5, sin identidad/Router, intento de promoción a producción, digest alterado, duplicado y error intermedio sin escrituras residuales. Inspeccionar trigger de `DONE` y readback.
5. Sólo entonces aprobar `write_allowed=true`, binding `ACTIVE`, estado operativo autorizado y permiso explícito de invocación. Revalidar identidad justo antes de cada efecto.
6. El primer cierre material de M10.5/CP2 será otra operación con su propio `execution_id`. Nunca reusar el PR fallido #2643 como justificante para declarar `DONE`.

**Lo no demostrado:** compilación de SQL candidato en Supabase, transacción real con rollback, instalación, binding activo, OIDC de invocación, cierre CP2. Ninguno debe figurar PASS hasta ejecutarse de verdad.

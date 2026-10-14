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

# IG / M7.10 — reparación upstream E2E previa a pruebas (V1)

Plan canónico: IG_CURATOR_VALIDATOR_REFACTOR_V2.
Unidad propietaria de ejecución: M7.10 (PAULO-078), checkpoint obligatorio UPSTREAM_E2E_REPAIR.
Secuencia: E2E_ASIS → FIXTURES → **UPSTREAM_E2E_REPAIR** → E2E_RECURATION → NEGATIVE_BLOCKED → TERMINAL.

## Por qué
M6.12 construye el manifest únicamente desde receipts realmente consumidos. Que M6.12 sea DONE no prueba que productores de todos los tipos de receipt hayan emitido evidencia actual para un nuevo run. Ausencia en programacion.provenance_receipts tampoco implica por sí sola ausencia en EVIDENCE_LEDGER: se debe consultar la autoridad propia de cada productor.

## Preflight específico, no histórico ni global
1. Tomar el caso de fixture recién generado en FIXTURES. Identificar run(s) de esta ejecución por identidad/causa; no exigir historial a un caso nuevo.
2. Construir una matriz tipada PRODUCER → RECEIPT → CONSUMER con **expected_for_this_run** y autoridad:
   - source: M6.1 / SOURCE_RESOLUTION_POLICY / input_readiness_runs.source_manifest;
   - graph: M6.2 / EVIDENCE_LEDGER, IG_SCREEN_GRAPH;
   - semantic resolver: M3.5 (M6.4 FUSED) / EVIDENCE_LEDGER;
   - validator: M4.7 (M6.6 FUSED) / EVIDENCE_LEDGER;
   - curator→validator handoff: M5.9 / autoridad de handoff;
   - successor lineage: M6.7 / receipt parent SHA+reason solo si el flujo contiene successor.
   La ausencia se define solo para productores aplicables a este escenario; un tipo NO_APLICABLE con causa probada no bloquea.
3. Verificar identidad causal/ref real, SHA y authority/version/lifecycle vigentes; comparar el manifest del consumidor con el conjunto de receipts realmente usados. No aceptar PASS por mero DONE de la unidad o por refs declaradas.
4. Para un faltante válido, usar el **procedimiento existente del productor**; corregir causa raíz en ese productor (fuentes/binding/emisión/ledger), reejecutar solo el subtramo afectado en sandbox y leer el receipt persistido. Prohibido insertar receipts sintéticos, rellenar campos a mano, o editar la vista para ocultar la ausencia. Si no existe reparación determinista validada, informar contrato/procedimiento faltante y mantener checkpoint pendiente, sin arrancar E2E_RECURATION.
5. Prueba E2E positiva fuente→productor→ledger→manifest→consumidor con correspondencia exacta en run de fixture. Prueba negativa aislada: receipt ausente, SHA/autoridad alterados o vínculo causal incorrecto deben impedir un PASS; rollback sin residuos.
6. Cerrar checkpoint solamente con assertion receipt de lectura live: expected_applicable>=1; unresolved_missing=0; producer_material_effect=true; manifest_parity=true; negative_fail_closed=true; rollback_clean=true. Reportar explícitamente productores no aplicables; no ampliar a todos los runs históricos.

## Contratos
- Checkpoint M7.10.UPSTREAM_E2E_REPAIR obligatorio, **antes** de E2E_RECURATION.
- Reutilizar EVIDENCE_LEDGER, TYPED_EVIDENCE_REGISTRY, SOURCE_RESOLUTION_POLICY, grafo y manifest existentes; no crear un nuevo store.
- Error→reparación tipada y general por familia, nunca parche fijo de un run.
- Validar el checkpoint propio; no reabrir automáticamente M6.12, ni arrastrar ensayos de otras unidades.
- Dependencias nuevas entre unidades: **ninguna**, eliminando el riesgo de ciclo.
- Los tests E2E de M7.10 no se ejecutan sin receipt PASS de este checkpoint.
- Control de cambios Git-first y readback de Supabase sobre la estructura canónica.

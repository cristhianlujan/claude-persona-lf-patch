# PG-04_C4 — Estado EXISTING/NEW por obligación y verificación de trazabilidad (2026-11-03)

## Alcance exacto

Se modificaron **únicamente dos componentes PG04 preexistentes** y sus pruebas en el PR #3528 (draft), sin tocar Análisis ni código productivo:

- `tools/pg04_semantic_partition_candidate_v1.py`
- `tools/pg04_partition_admission_probe_v1.py`
- `tests/test_pg04_semantic_partition_candidate_v1.py`
- `tests/test_pg04_partition_admission_probe_v1.py`

## Defecto observado

El productor conservaba `implementation_state` y evidencias `EXISTING`/ `NEW` **solo en el envelope agregado de la solución**; cada elemento de `source_bindings[]` no retenía `implementation_state`, `as_is_ref`, `delta_ref` ni `bounded_reuse_assessment_ref`. Así una modificación de obligación o procedencia dentro del lote podía perderse durante el handoff hacia inspección.

También se aceptaba un átomo `NEW` con referencias antiguas de `EXISTING`, o uno `EXISTING` con campos `NEW`. El inspector solo verificaba que la solución tuviera referencias no vacías, no que cada obligación mantuviera las mismas.

## Corrección mínima, sin segundo motor

1. **Productor:** los `source_bindings[]` contienen ahora `implementation_state` y `as_is_ref` + `delta_ref` en `EXISTING`, o `bounded_reuse_assessment_ref` en `NEW`.
2. **Productor:** bloquea `EXISTING_CONTAINS_NEW_EVIDENCE` y `NEW_CONTAINS_EXISTING_EVIDENCE` cuando los campos mutuamente excluyentes aparecen, incluso si sus valores son `null`.
3. **Inspector:** comprueba mezcla de evidencias a nivel de solución y, **cuando existen** `source_bindings[]`, valida que cada átomo tenga identidad única, estado coincidente y referencias exactamente iguales a las del envelope. Contradicciones devuelven `ATOM_IMPLEMENTATION_STATE_DRIFT`, `ATOM_IMPLEMENTATION_EVIDENCE_DRIFT` o `ATOM_IMPLEMENTATION_BINDINGS_INVALID`. Se rechazan tipos inválidos de `atom_ids` de forma controlada.
4. **Compatibilidad:** el inspector sigue aceptando sobres de prueba antiguos sin `source_bindings[]` (sonda estructural candidate-only); el **productor actualizado sí los emite siempre**. No afirmar que los sobres externos sin detalle prueban trazabilidad por átomo.
5. No se autentica el contenido de las referencias de origen; su verdad requiere lectura y juez externo. No se construye un validador A9, un nuevo juez semántico ni un writer.

## Regresiones

Añadidas a las pruebas existentes:
- Productor: preserves `NEW` por átomo, preserves `EXISTING` AS-IS+DELTA por átomo, bloquea NEW con campos EXISTING antiguos y viceversa.
- Inspector: caso positivo EXISITING con detalle exacto; rechaza delta falsificado, estado falsificado, duplicación de `atom_id`, reuso NEW inconsistente y mezcla de estados en envelope.
- Se ajustó un negativo anterior de coimplementación para cambiar realmente a EXISTING limpiando la referencia de NEW antes de comprobar el conflicto entre átomos.

**Estatus de las pruebas:** fuentes y tests publicados en el PR; su ejecución Python exacta en el checkout del HEAD **pendiente de confirmación**. PASE verifica su propio workflow; no inferir que descubrió ni ejecutó estas suites.

## Estado

`PG04_C4_PER_ATOM_PROVENANCE_SOURCE_READY / NO_AUTHENTICATED_IMPLEMENTATION_EVIDENCE / NO_RUNTIME_AUTHORITY`.

El resultado de la sonda y productor continúa `CANDIDATE_NOT_ADMITTED`, `production_authority=false`, `handoff_allowed=false`. Sin marcar PG04_C4 DONE en Supabase, sin merge, sin cambios de Análisis.

El siguiente trabajo legítimo para C4 es demostrar el mismo comportamiento sobre un paquete PG03 válido/current y revisión de evidencia auténtica; eso sigue bloqueado por falta de A9/PG03 admitidos.

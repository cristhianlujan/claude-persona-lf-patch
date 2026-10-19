# RW1-01 — Revisión ejecutada del corpus de oráculos (evidencia auxiliar, NO cierre de checkpoint)

**Alcance:** `LF_ROUTER_ARCHITECTURE_WAVE_V1 / RW1-01 / C2` · Fuente congelada de evaluación: blob GitHub `677cf82d8b8515f44ae4fd154ed68dc264285bbd` de `docs/programming-agent/router_wave/RW1_01_C2_NEEDS_ACCEPTANCE_CORPUS_V1.json`. Fecha: 2026-10-17.

## Trabajo efectivamente ejecutado

Se usó un comprobador **JavaScript independiente** sobre el JSON leído directamente del repositorio, **no** el ejecutor Python del archivo Git ni el Router productivo. El comprobador construyó respuestas de forma con referencias `fixture:` explícitamente sintéticas y rechazó mutaciones según los contratos de cada caso.

| Medida | Observación |
| --- | --- |
| Casos de corpus parseados | 30 |
| Cobertura N01–N12 | 12 / 12 requisitos |
| Familias | 9 |
| Respuestas estructurales correctas por construcción | 30 / 30 (esto **no** prueba comportamiento de ningún Router) |
| Mutantes adversariales inyectados | 13 |
| Mutantes efectivamente rechazados | 13 / 13 |
| Evidencia de proveedor real/consumidor/Router runtime | **0**; no se invocaron |
| Ejecución del verificador Python versionado | **NO EJECUTADO** |
| Holdout independiente | **NO EJECUTADO** |
| Cierre formal del checkpoint | **NO**, `PENDING` según readback Supabase |

## Mutaciones comprobadas (cada una produjo al menos un motivo de rechazo)

1. Derivación disponible sustituida por `DISCOVER` terminal genérico.
2. `DISCOVER` de activo nuevo sin handoff registrable.
3. Pregunta `CLARIFY` sin discriminador material.
4. Pérdida del segundo objetivo de solicitud multiobjeto.
5. Selección de sujeto explícitamente excluido para un efecto.
6. Exclusión omitida en el handoff.
7. Atribuir permiso de efecto al Router.
8. Declarar que se efectuó un efecto sin acreditar autorización.
9. Modificación de texto literal preservado.
10. Responsable sin evidencia declarada.
11. Declarar resultado E2E sin recibo de consumidor.
12. Inventar `CAPABILITY_GAP` sin recibo de búsqueda.
13. Atribuir gobernanza técnica a una operación sin responsable atestado.

## Observaciones críticas sobre el propio test

- **False pass identificado previamente:** en el corpus anterior 26/30 casos podían aprobar con `DISCOVER`; ahora solo 4/30, los de capacidad futura realmente no resuelta en el fixture, admiten esa salida. `DISCOVER` no es una respuesta permanente por defecto.
- **Separación necesaria:** 30/30 respuestas válidas por construcción son control positivo de contrato, no 30 éxitos de encaminamiento real. Las referencias `fixture:` **no** acreditan que una capacidad exista en Supabase.
- **Debilidad material remanente:** campos como `catalog_revision_ref` y `authority_evidence_ref` se validan solo por su presencia. Un texto inventado puede parecer un recibo; la prueba E2E y un verificador de fuente/identidad deben acreditarlo en RW1-05, sin mover un nuevo gate complejo dentro del Router.
- **Límite de independencia:** el corpus se generó durante el diseño; no es holdout ciego. RW1-01_C3 debe tener casos no vistos y revisor ajeno al productor.
- **Verificador Python:** se añadió control de `effect_performed=True` incluso cuando `router_effect_authorized=False` al archivo `sandbox/lf_contract_gate_test/router_wave/validate_rw101_needs_corpus_v1.py`. Su propia compilación/ejecución no se ha observado; ese parche no es evidencia de test Python ejecutado.

## Regla de continuidad

`RW1-01_C1` aún requiere integrar por ruta CI/PASE/Train el contrato y el source pack exactos y ejecutar readback source/current; `RW1-01_C2` requiere ejecución del validador Python y resultados de responsables reales para evitar certificar fixtures; `RW1-01_C3` requiere examen independiente. No promover C1/C2/C3 a DONE por este documento, por un PR o por el resultado de 13 controles estructurales.

Fuente auxiliar, sin cambios de runtime ni base de datos.

# CONTRATO DE BENCHMARK OCR/CV — P0

> **Rol de este archivo:** resumen normativo. El plan técnico canónico y más detallado es `docs/p0/OCR_BENCHMARK_PLAN.md`; la decisión arquitectónica es `docs/p0/ADR_OCR_UI_PIPELINE_20260812.md`. Si existe una diferencia, prevalece el plan canónico reconciliado.

## Objetivo

Comparar motores/capas de percepción sobre exactamente las mismas pantallas y ground truth, sin permitir que una mejora textual o de velocidad oculte una regresión estructural.

## Corpus

- `KNOWN_REAL`: mínimo 10 pantallas reales anotadas.
- `HOLDOUT_REAL`: mínimo 5 pantallas reales nuevas no usadas para ajustar reglas.
- La misma imagen/bytes se usa para todos los candidatos.
- Cada fuente conserva SHA-256, dimensiones, formato y procedencia.

Estado actual: 1/10 `KNOWN_REAL`; holdout insuficiente.
Resultado de autonomía: `BLOCKED_REAL_EVIDENCE`.
Resultado de reproducción B0/C1 en PR #140: `BLOCKED_MISSING_BENCHMARK_PRODUCER_ARTIFACTS`, porque el ground truth y runner nombrados por el artefacto histórico no están versionados en este PR.

## Métricas críticas

| Dimensión | Métrica |
|---|---|
| OCR | exactitud normalizada, CER/WER por texto material |
| Detección | precision/recall/F1 de unidades materiales |
| Atomicidad | `ATOMIC_ELEMENT_OVERMERGE` y splits injustificados |
| Omisión | unidades materiales no representadas |
| Contaminación | elementos sin soporte visual suficiente |
| Ownership | una unidad de evidencia no puede justificar dos elementos PASS |
| Semántica | tipo/rol UI correcto cuando exista ground truth |
| Reproducibilidad | engine/model/config/version/hash fijados |
| Operación | latencia y costo, solo después de pasar métricas críticas |

## Gate de superioridad

`CANDIDATE_WINS` solo si:

1. supera al baseline en al menos una métrica crítica relevante;
2. no empeora ninguna métrica crítica;
3. tiene cero escapes CRITICAL/HIGH/MEDIUM en known + holdout;
4. no produce overmerge atómico ni evidence ownership duplicado;
5. su configuración completa es reproducible;
6. el resultado puede persistirse y reconstruirse por `execution_id`;
7. cumple la campaña mínima de 100 mutaciones por familia / 400 total y las mutaciones reales exigidas por EKB cuando exista artefacto actual elegible.

Si no se cumplen todos: `NO_SUPERIOR_CANDIDATE_PROVEN`.

## Casos adversariales mínimos

- labels lado a lado;
- label + valor en columnas;
- placeholders parecidos;
- tildes/ñ/case;
- tokens de 1–3 caracteres;
- texto pequeño;
- texto largo/legal;
- icono junto a texto;
- checkbox/radio/toggle;
- disabled/selected/error state;
- texto parcialmente truncado;
- mismas palabras en regiones distintas;
- elementos repetidos;
- ruido/ilustraciones que parezcan caracteres;
- campos agrupados visualmente pero independientes semánticamente.

## Prohibiciones

- No ajustar reglas contra el holdout.
- No elegir motor por una sola pantalla.
- No sumar un score global que compense una omisión HIGH con mejoras de latencia.
- No declarar PASS sin artifacts/evidence/versiones persistibles.
- No tratar PSM distintos de Tesseract como motores OCR independientes.
- No reutilizar un resultado histórico para certificar un HEAD diferente.
- No reconstruir silenciosamente el ground truth desde el output/candidate.

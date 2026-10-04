# INPUT_GOVERNANCE_REGRESSION — Taxonomía Q0–Q8

Plan: `IG_CURATOR_VALIDATOR_REFACTOR_V2`  
Unidad: `M7.0` / `PAULO-109`  
Versión: `Q_TAXONOMY_V1`  
Owner transversal: `SUPER_ADMIN`  
Suite: `INPUT_GOVERNANCE_REGRESSION`

## 1. Frontera

Esta taxonomía clasifica qué propiedad intenta demostrar cada caso. No crea un evaluator nuevo y no reemplaza `ASSURANCE_EVALUATOR`, `public.lf_assurance_claim_catalog` ni `public.lf_assurance_obligation_catalog`.

Reglas obligatorias:

- `PARITY != CORRECTNESS`.
- `STRUCTURAL != SEMANTIC != READINESS`.
- Un caso solo puede afirmar la dimensión y propiedad declaradas en su metadata.
- Un PASS de Q0/Q1/Q2 no puede elevarse a PASS semántico, readiness o release.
- `oracle` identifica el mecanismo que decide el caso; `evidence` identifica la evidencia que permite verificar la decisión.

## 2. Modelo mínimo por caso

Cada caso vigente de `INPUT_GOVERNANCE_REGRESSION` debe tener metadata no nula:

```text
q_class   : Q0..Q8
dimension : dimensión de calidad probada
property  : propiedad concreta bajo prueba
oracle    : autoridad/mecanismo que decide PASS/FAIL
expected  : resultado esperado del caso
evidence  : referencia estructurada a la evidencia verificable
```

Un caso sin `q_class`, `dimension`, `property`, `oracle`, `expected` o `evidence` es `UNCLASSIFIED` y el readback de M7.0 debe fallar.

## 3. Taxonomía Q0–Q8

| Q | Dimensión | Qué demuestra | Qué NO demuestra | Reuso Assurance |
|---|---|---|---|---|
| Q0 | `BINDING_PROVENANCE` | identidad/versionado exacto del build, contrato, registry o componente; SHA/pin correcto | corrección funcional o semántica | claims `AUTHORITY`/`EVIDENCE`/`CURRENTNESS`; obligations `INSPECTION`/`TEST` |
| Q1 | `STRUCTURAL` | forma, identidad de fuente, cardinalidad, lifecycle estructural y resolución tipada | significado correcto de la regla ni readiness | claim `STRUCTURAL_COVERAGE`; obligations `STRUCTURAL_COVERAGE`/`TEST` |
| Q2 | `PARITY_COMPATIBILITY` | equivalencia, compatibilidad o no-regresión contra una referencia explícita | que la referencia sea correcta | claims `FUNCTIONAL`/`EVIDENCE`; obligation `TEST` |
| Q3 | `SEMANTIC` | significado correcto de una decisión/resolver contra un oracle independiente | readiness final o release | claims `FUNCTIONAL`/`COGNITIVE_QUALITY`; `TEST`/`INDEPENDENT_REVIEW` |
| Q4 | `CROSS_FAMILY_COHERENCE` | ausencia/detección de contradicciones entre familias, reglas o fuentes | readiness por sí sola | claims `FUNCTIONAL`/`COGNITIVE_QUALITY`; `ANALYSIS`/`TEST` |
| Q5 | `READINESS` | política de etapa, N/A, blocker y elegibilidad de readiness | corrección semántica si Q3 no está probado | claims `QUALIFICATION`/`CLOSURE`; `TEST` |
| Q6 | `ADVERSARIAL_FALSE_PASS` | resistencia a mutación, bypass, missing evidence y false PASS | cobertura completa fuera del ataque probado | claims `CLOSURE`/`RECOVERY`; `TEST` con failure taxonomy explícita |
| Q7 | `CURRENTNESS_LINEAGE_REPLAY` | freshness/currentness, lineage, replay y preservación de historia | corrección semántica nueva | claims `CURRENTNESS`/`RECOVERY`/`EVIDENCE`; `TEST`/`DEMONSTRATION` |
| Q8 | `END_TO_END_RELEASE_ASSURANCE` | composición E2E y release gate ligada a evidencias de Q0–Q7 | no permite omitir ninguna propiedad requerida | claims `CLOSURE`/`QUALIFICATION`/`EVIDENCE`; `DEMONSTRATION`/`INDEPENDENT_REVIEW` |

## 4. Clasificación del inventario vigente al ejecutar M7.0

Readback previo: 77 casos vigentes en `INPUT_GOVERNANCE_REGRESSION`.

| Grupo | Casos | Q | Dimensión | Propiedad base | Oracle |
|---|---:|---|---|---|---|
| `M7_1_*_SHA` | 10 | Q0 | `BINDING_PROVENANCE` | `EXACT_COMPONENT_BINDING` | readback SHA exacto de la autoridad vinculada |
| `M2_1_KIND_*` | 32 | Q1 | `STRUCTURAL` | `SOURCE_KIND_IDENTITY_RESOLUTION` | `programacion.fn_input_resolve_source_ref` |
| `M2_2_KIND_*` | 32 | Q1 | `STRUCTURAL` | `SOURCE_COLLECTION_CARDINALITY_SEMANTICS` | `programacion.fn_input_resolve_source_ref` |
| `M1_A9_*` | 3 | Q2 | `PARITY_COMPATIBILITY` | `VERSIONED_CONTRACT_CLAUSE_PARITY` | `programacion.fn_input_contract_clause_v1` |

### Lectura correcta del resultado vigente

- Q0 prueba que el caso está ligado al artefacto exacto esperado.
- Q1 prueba contratos estructurales/resolución de fuente.
- Q2 prueba paridad/compatibilidad del accessor versionado.
- El inventario vigente no contiene todavía casos Q3, Q4, Q5, Q6, Q7 o Q8. Por tanto la suite vigente no puede presentarse como prueba completa de semantic correctness, readiness o release assurance.

## 5. Oracles y expected de los casos actuales

### Q0 / M7.1

- Build: `EXACT_BUILD_SHA_READBACK` → `EXACT_SHA_MATCH`.
- Contract: `INPUT_READINESS_CONTRACT_SHA_READBACK` → `EXACT_SHA_MATCH`.
- Registry: `EJECUCION_INPUT_GOVERNANCE_REGISTRY_SHA_READBACK` → `EXACT_SHA_MATCH`.
- Router/Curator/Validator/Execution/Shadow/Semantic/Currentness: `LF_ACTIVOS_COMPONENT_SHA_READBACK` → `EXACT_SHA_MATCH`.

### Q1 / M2.1

- POSITIVE → `RESOLVES`.
- NEGATIVE → `REJECTS`.
- Oracle: `programacion.fn_input_resolve_source_ref` bajo `POL-LF-SOURCE-RESOLUTION@v1.4-transversal-supabase-authority-visual-support`.

### Q1 / M2.2

- `EMPTY_POSITIVE` → `RESOLVES_EMPTY_COLLECTION`.
- `NONEMPTY_POSITIVE` → `RESOLVES_NONEMPTY_COLLECTION`.
- `MISSING_REF_NEGATIVE` → `REJECTS_MISSING_REF`.
- `CARDINALITY_NEGATIVE` → `REJECTS_INVALID_CARDINALITY`.
- Oracle: `programacion.fn_input_resolve_source_ref`.

### Q2 / M1.A9

- `M1_A9_CONTRACT_CLAUSE_PARITY_POSITIVE` → `PARITY_MATCH`.
- `M1_A9_CONTRACT_VERSION_UNPINNED_NEGATIVE` → `REJECTS_UNPINNED_VERSION`.
- `M1_A9_CONTRACT_CLAUSE_MISSING_NEGATIVE` → `REJECTS_MISSING_CLAUSE`.
- Oracle: `programacion.fn_input_contract_clause_v1`.

## 6. Detector de clasificación incompleta

El detector canónico de M7.0 es la siguiente condición sobre cada caso vigente:

```sql
(metadata->>'q_class') is null
or (metadata->>'dimension') is null
or (metadata->>'property') is null
or (metadata->>'oracle') is null
or (metadata->>'expected') is null
or not (metadata ? 'evidence')
or metadata->'evidence' is null
or metadata->'evidence' = 'null'::jsonb
```

El cierre exige `0` filas detectadas.

## 7. Prueba negativa

La prueba negativa de M7.0 toma un caso vigente dentro de una transacción, elimina temporalmente `q_class` y `oracle`, ejecuta el detector anterior y exige que el caso aparezca como incompleto. La transacción termina en `ROLLBACK`; no queda residuo.

## 8. Compatibilidad con Assurance

M7.0 reutiliza el modelo existente:

```text
caso de test
  -> q_class + dimension + property
  -> oracle + expected
  -> evidence
  -> claim/obligation/evidence del ASSURANCE_EVALUATOR cuando un consumidor material lo requiera
```

M7.0 no activa `ASSURANCE_EVALUATOR`, no crea claims/obligations nuevos y no convierte la suite en un gate material. Solo hace explícita la propiedad probada por cada caso.
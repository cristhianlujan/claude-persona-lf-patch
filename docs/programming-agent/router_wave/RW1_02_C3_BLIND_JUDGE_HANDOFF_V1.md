# RW1-02_C3 — Handoff para juez independiente ciego

**Objetivo:** realizar la crítica y aseguramiento independiente de la competencia de arquitecturas RW1-02, sin reutilizar el razonamiento del productor de C1/C2 y sin certificar Router runtime.

## 1. Separación obligatoria

Ejecutar en un **chat GPT Native nuevo y materialmente separado** del chat que produjo RW1-02_C1/C2.  
No reutilizar memoria, conclusiones, explicaciones, prompts ni resultados de esa sesión. Registrar un `judge_identity_ref` verificable.

El juez evalúa **la arquitectura y la suficiencia de la evidencia comparativa**, no la intención del productor.

## 2. Freeze exacto

Snapshot canónico a congelar:

- repo: `cristhianlujan/claude-persona-lf-patch`
- commit: `5d7f30580d4c6bb557e51943693c4b95e192900e`

### Fuentes permitidas antes de RAW1

1. `docs/programming-agent/LF_ROUTER_ARCHITECTURE_WAVE_V1.md`
   - blob: `4bb64d568c3f005cf454fb223b4a5ed699c34504`
2. `docs/programming-agent/router_wave/RW1_02_C1_SOURCE_AUTHORITY_BASELINE_V1.md`
   - blob: `470979c9b9a0dd9a728601b6ec5f577d7445f8b5`
3. `docs/programming-agent/router_wave/RW1_02_C2_ARCHITECTURE_COMPETITION_V1.json`
   - blob: `f00a202f5983931d6ae41121fcdfea96808c094b`
4. `sandbox/lf_contract_gate_test/router_wave/validate_rw102_architecture_competition_v1.py`
   - blob: `54517132aa0ab890b1e266639a19cbe08f7a5d9a`
5. `.github/workflows/lf-router-level2-advisory-tests.yml`
   - blob: `b1782a0944868b967fc88de530499266668c2b99`

### Prohibido antes de congelar RAW1

- abrir `RW1_02_C2_ARCHITECTURE_COMPETITION_RESULT_V1.json`;
- leer PR #2924 o #2925, sus cuerpos, comentarios, diffs o rationale;
- leer esta conversación o cualquier resumen/handoff del productor distinto de este protocolo;
- consultar el contenido de RFC/PR #2872;
- abrir críticas C3 previas si llegaran a existir;
- usar una “respuesta esperada” sobre qué arquitectura debe ganar.

Para verificar commit/blobs, usar ref + archivos exactos. Evitar endpoints de commit que expongan diffs no autorizados.

## 3. Recomputación independiente antes de RAW1

Sin abrir el resultado del productor:

1. inspeccionar C1, corpus y validador;
2. verificar que hay 36 casos, cobertura N01–N12, tres candidatos elegibles A/B/C y baseline D no elegible;
3. recomputar el scorecard directamente desde el corpus y el código del validador;
4. derivar de forma independiente:
   - hard failures por candidato;
   - hard-pass candidates;
   - continuidad/extensibilidad;
   - hops/complexity declarada;
   - selección tentativa o declarar que la evidencia no basta;
5. no inventar latencia, costo, p95/p99 ni comportamiento runtime.

Se puede importar el módulo del validador y llamar su función `compute_result()` sobre el corpus; no usar el JSON de resultado del productor en esta fase.

## 4. Falsificación independiente obligatoria

Crear y ejecutar **al menos 24 mutaciones adversariales nuevas** que no sean meras copias de las 16 del `self_test` existente.

Cobertura mínima:

- al menos 6 ataques contra A (`A_MIN_ROUTER_SEMANTIC_SPECIALIST`);
- al menos 6 ataques contra C (`C_BOUNDED_SEMANTIC_ROUTER`);
- al menos 4 ataques al mecanismo de selección/tiebreak;
- cubrir además B, baseline D, neutralidad del corpus, autoridad/roles, currentness/determinismo, continuidad y no-claims.

Cada mutación debe indicar:

- qué afirmación intenta falsificar;
- payload/cambio reproducible;
- resultado observado;
- si el validador la rechaza;
- si un paquete semánticamente inválido fue aceptado;
- severidad/materialidad.

Añadir **al menos 2 falsificadores realmente nuevos** no sugeridos por este handoff ni por el self-test existente.

Un paquete semánticamente inválido aceptado, una selección que dependa de evidencia no sustentada, o un mecanismo que pueda elegir ganador mediante métricas arbitrarias es un bloqueador material salvo demostración contraria.

## 5. Preguntas de arquitectura que el juez debe resolver

Sin asumir que A, B o C es correcta:

- ¿las capacidades atribuidas a cada arquitectura son evidencia o simples declaraciones?
- ¿las métricas que rompen el empate entre hard-pass están sustentadas y son comparables?
- ¿el especialista semántico de A permanece estrictamente fuera de discovery, routing y autoridad de efecto, o crea un segundo Router?
- ¿C concentra semántica en ACT-0001 de forma innecesaria o su costo está justificado por evidencia?
- ¿B fue eliminado por necesidades reales o por cómo se definieron las capacidades?
- ¿D es un baseline justo sin convertirse en oráculo ni ser penalizado artificialmente?
- ¿el corpus/falsificadores son neutrales respecto de la arquitectura?
- ¿la selección seguiría siendo la misma ante falsificadores nuevos y cambios no materiales del corpus?
- ¿se distingue claramente contrato de diseño versus comportamiento runtime no medido?
- ¿la solución elegida minimiza acoplamiento sin crear dependencia circular o un engine paralelo?

## 6. RAW1

Antes de abrir el resultado del productor o el receipt CI, congelar un artefacto `RW1_02_C3_RAW1_BLIND_VERDICT_V1` con SHA-256.

Debe contener:

- freeze de commit/blobs;
- scorecard recomputado independientemente;
- selección tentativa independiente o `INSUFFICIENT_EVIDENCE`;
- las mutaciones ejecutadas;
- falsos positivos/falsos negativos;
- bloqueadores materiales;
- limitaciones probatorias.

Emitir exactamente uno:

- `PASS`: la evidencia comparativa soporta una selección y no hay bloqueadores materiales;
- `REVISE`: existe un defecto material reproducible;
- `INSUFFICIENT_EVIDENCE`: la evidencia no permite una elección independiente defendible.

## 7. RAW2

Solo después de congelar RAW1:

1. abrir `docs/programming-agent/router_wave/RW1_02_C2_ARCHITECTURE_COMPETITION_RESULT_V1.json`
   - blob esperado: `1f2b91ff5fe4bb3d0f2b764222425623996c2eac`;
2. verificar el run exact-main:
   - run `39168605114`;
   - job `117796748955`;
   - commit ejecutado `e8770f89035ad7d80a4d53dc6260503d474d1a9f`;
   - workflow `.github/workflows/lf-router-level2-advisory-tests.yml`;
   - conclusión `success`;
3. comprobar que RAW1 permanece byte-a-byte intacto;
4. contrastar el resultado del productor contra la recomputación independiente;
5. no reescribir RAW1 para coincidir con el productor.

## 8. Resultado estructurado requerido

Entregar `RW1_02_C3_INDEPENDENT_VERDICT_V1.json`:

```json
{
  "schema_version": "RW102_C3_INDEPENDENT_VERDICT_V1",
  "status": "PASS",
  "judge_identity_ref": "gpt-native://...",
  "source_snapshot_commit": "5d7f30580d4c6bb557e51943693c4b95e192900e",
  "observed": {
    "blind_verdict": "PASS",
    "independent_judge_attested": true,
    "judge_identity_ref_present": true,
    "source_freeze_verified": true,
    "producer_result_hidden_until_raw1": true,
    "independent_recomputation_completed": true,
    "public_case_count": 36,
    "requirements_n01_n12_covered": true,
    "candidate_count": 4,
    "eligible_candidate_count": 3,
    "adversarial_mutations_count": 24,
    "adversarial_mutations_at_least_24": true,
    "a_mutations_at_least_6": true,
    "c_mutations_at_least_6": true,
    "selection_policy_mutations_at_least_4": true,
    "novel_falsifiers_added": 2,
    "novel_falsifiers_at_least_2": true,
    "all_semantically_invalid_mutations_rejected": true,
    "material_blockers": 0,
    "final_selection_present": true,
    "final_selection_valid": true,
    "selection_supported_by_evidence": true,
    "raw1_frozen": true,
    "raw2_created": true,
    "raw1_unchanged_after_reveal": true,
    "latency_cost_not_invented": true,
    "no_router_runtime_claim": true,
    "no_production_mutation": true
  },
  "final_selection": "<A|B|C>",
  "material_findings": [],
  "raw1_sha256": "<64 hex>",
  "raw2_sha256": "<64 hex>",
  "evidence_ref": "<content-addressed RAW1 reference>"
}
```

Los conteos deben reflejar lo realmente ejecutado. Si se ejecutan más de 24 mutaciones, registrar el total real.

## 9. Regla terminal

- `PASS` **no** declara Router runtime, producción ni GOLDEN.
- `PASS` solo autoriza el paso gobernado posterior: persistir el verdict, assertion receipt, transición C3 y readback.
- `REVISE` o `INSUFFICIENT_EVIDENCE` mantienen C3 `PENDING`; no reabrir C1/C2 ni fabricar cierre.
- La arquitectura final de RW1-02 solo queda elegida cuando C3 se cierre canónicamente.

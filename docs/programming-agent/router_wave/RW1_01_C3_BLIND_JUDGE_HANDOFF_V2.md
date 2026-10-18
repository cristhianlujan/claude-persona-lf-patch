# RW1-01_C3 — Handoff V2 para juez independiente

**Objetivo:** ejecutar una revisión adversarial realmente separada sobre la V2 reparada. Este archivo no es un dictamen y no autoriza el cierre de C3.

## Separación obligatoria

Ejecutar en un **chat GPT Native nuevo**, materialmente separado del chat que produjo C1/C2, la primera crítica C3 o esta reparación. El juez no debe reutilizar memoria, conclusiones ni resultados de esas sesiones. Registrar un identificador verificable de la sesión/juez.

## Fuentes permitidas antes de RAW1

Congelar primero el SHA de `main` y los blob SHA de:

1. `docs/programming-agent/router_wave/RW1_01_C1_NEEDS_SOURCES_AND_BIASES_V1.md`
2. `docs/programming-agent/router_wave/RW1_01_C3_NEEDS_ACCEPTANCE_CORPUS_V2.json`
3. `sandbox/lf_contract_gate_test/router_wave/validate_rw101_needs_corpus_v2.py`
4. `sandbox/lf_contract_gate_test/router_wave/generate_rw101_c3_holdout_v2.py`
5. Texto normativo de RW1-01/C3 en `docs/programming-agent/LF_ROUTER_ARCHITECTURE_WAVE_V1.md`
6. EKB únicamente como fuente histórica verificable.

**No leer antes de RAW1:** brief adversarial V1, validador de gaps V1, RAW1/RAW2 previos, H01-H12 ni comentarios/resultados de la primera evaluación C3.

## Holdout nuevo

1. Elegir en el chat independiente un `seed` y `nonce` secretos después de congelar las fuentes.
2. Ejecutar:
   `python3 sandbox/lf_contract_gate_test/router_wave/generate_rw101_c3_holdout_v2.py --seed '<secret>' --nonce '<secret>' --out /tmp/rw101_c3_holdout_v2.json`
3. Publicar **solo** `commitment_sha256` antes de evaluar resultados.
4. No almacenar públicamente el holdout, seed ni nonce antes de congelar RAW1.
5. El holdout tiene 12 casos: 2 por cada familia adversarial V2.
6. Tras RAW1, revelar seed + nonce + manifest y verificar el compromiso.

## Evaluación obligatoria

- Validar que el corpus V2 y el checker V2 no se apoyan en el Router real ni reclaman E2E.
- Para las 42 fixtures públicas: comprobar cobertura de N01-N12, 15+ familias y que la V2 representa:
  - exclusiones/negaciones sin fuga a derivación, composición o efectos;
  - responsable exacto por objetivo con evidencia de autoridad y contexto;
  - progreso parcial + pregunta en una misma respuesta;
  - capacidades futuras sin falso READY.
- En el holdout secreto:
  - construir 12 respuestas correctas independientes del helper `valid_answer`;
  - construir **al menos 24 respuestas incorrectas**, con mínimo dos falsificadores distintos por familia;
  - exigir 12/12 correctas aceptadas y 24/24 incorrectas rechazadas;
  - añadir al menos 2 falsificadores nuevos no sugeridos por el generador ni por el checker.
- No ejecutar ni certificar el Router real. No declarar GOLDEN ni producción.

## RAW1

Antes de abrir críticas previas, congelar `RW1_01_C3_RAW1_BLIND_VERDICT_V2.md` con SHA-256 y emitir uno de:

- `PASS`: cero bloqueadores materiales en el contrato V2.
- `REVISE`: existe al menos un falso positivo/falso negativo material reproducible.
- `INSUFFICIENT_EVIDENCE`: falta evidencia para decidir.

Cada hallazgo debe tener caso/requisito, falsificador reproducible, responsable del defecto y reparación mínima.

## RAW2

Solo después de RAW1, abrir las críticas V1 y contrastarlas. RAW2 no puede modificar RAW1. Debe explicar qué hallazgos quedaron reparados, cuáles persisten y cuáles eran vacuos.

## Resultado estructurado requerido

Entregar también `RW1_01_C3_INDEPENDENT_VERDICT_V2.json` con:

```json
{
  "schema_version": "RW101_C3_INDEPENDENT_VERDICT_V2",
  "status": "PASS",
  "observed": {
    "blind_verdict": "PASS",
    "independent_judge_attested": true,
    "judge_identity_ref_present": true,
    "source_freeze_verified": true,
    "holdout_commitment_verified": true,
    "holdout_revealed_after_raw1": true,
    "v2_public_good_cases": 42,
    "v2_public_good_cases_accepted": 42,
    "holdout_good_cases": 12,
    "holdout_good_cases_accepted": 12,
    "holdout_bad_cases": 24,
    "holdout_bad_cases_rejected": 24,
    "novel_falsifiers_added": 2,
    "material_blockers": 0,
    "no_router_runtime_claim": true,
    "no_production_mutation": true
  },
  "evidence_ref": "github://.../RW1_01_C3_RAW1_BLIND_VERDICT_V2.md"
}
```

Los conteos son mínimos contractuales; si el juez prueba más negativos, conservar el total real en evidencia adicional, pero no bajar los mínimos.

## Cierre

Este handoff **no** cierra C3. El resultado PASS debe entrar por la migración/Operation canónica, registrar assertion receipt, transición y readback. Un resultado REVISE/INSUFFICIENT_EVIDENCE mantiene C3 PENDING.

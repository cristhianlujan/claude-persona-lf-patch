# A2 — Clasificación interna de cambio, alcance y profundidad

**Estado:** `LOCAL_DETERMINISTIC_CANDIDATE_UNQUALIFIED`. Paso **interno** de la skill `PROGRAMMING_ANALYSIS_LF`. No existe una segunda skill A2.

## Entrada
- `a1_result` válido y tipado, `status=VALID_OUTPUT`, `REQUEST_CONTEXT_V1`, `interpretation_state=PRESTRUCTURED_UNATTESTED`.
- `signal_bundle` recibido del consumidor: referencia exacta a un target aportado en A1, tipo/granularidad explícitos, refs de evidencia y señales tipadas, **sin afirmar que ya están autenticadas**.
- Candidatos semánticos de texto libre: **bloquear hasta productor real, revisor independiente y recibos**, sin aceptar autorreporte de juez dentro del bundle.

## Proceso
1. Verificar el sobre completo de A1 y validar su payload contra el esquema canónico actual.
2. Validar el destino sin inferirlo de palabras clave. Objetivos anidados SECTION/CONTROL requieren `nested_parent_ref`.
3. Leer `analysis_change_classification_contract_v1.json` y aplicar **directamente sus expresiones** `L3_if_any`, `L2_if_no_L3_and_any`, `L1_requires_all` a las señales tipadas. Sin pesos, heurística libre ni familia de caso.
4. Entregar `ANALYSIS_CHANGE_CLASSIFICATION_V1` como **candidato**, con nivel L1/L2/L3 y predicados justificativos. No generar identidad de especialistas: CAPABILITY_SELECTOR y sus manifiestos RELEASED siguen siendo autoridad externa.
5. No habilitar A3: se requiere unión posterior con fuentes CURRENT, juez independiente y transporte/readback de RUN verdadero. `next_step=null`.

## Bloqueos
No admitir A1 con revisión semántica pendiente, source refs vacías, señales inválidas, target inventado, falta de padre en target anidado, drift de política o inferencia de permisos. L1 requiere todos los criterios; materialidad desconocida nunca puede dar L1. No se altera Router, Supabase, EKB ni catálogo de skills.

Pruebas locales sintéticas: `python -m unittest discover -s skills/programming_analysis/steps/a2/evals -p 'test_*.py' -v`. Estas no prueban runtime ni independencia de juez.

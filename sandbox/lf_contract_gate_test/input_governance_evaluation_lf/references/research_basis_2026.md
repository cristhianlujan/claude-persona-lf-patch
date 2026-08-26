# Evaluation Research Basis — 2026

Este archivo documenta la base metodológica externa usada para el adapter candidato. Ninguna fuente externa sustituye contratos, decisiones o evidencia canónica LF.

## Anthropic — Demystifying evals for AI agents (2026-01-09)

Patrones adoptados:

- distinguir `task`, `trial`, `grader`, `transcript/trajectory` y `outcome`;
- ejecutar múltiples trials cuando existe variabilidad del modelo;
- combinar code-based, model-based y human grading según la propiedad evaluada;
- comprobar end-state además de la respuesta textual;
- separar quality benchmarking de regression testing;
- usar evals desde desarrollo temprano para eliminar ambigüedad de spec.

Aplicación LF:

- outcome correcto no basta si la trayectoria violó autoridad/no-invention;
- hard guards determinísticos dominan el score semántico;
- model grader requiere calibración humana periódica.

Fuente pública: `https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents`

## Anthropic — Bloom automated behavioral evaluations (2025-12-19)

Patrones adoptados:

- partir de un comportamiento objetivo, no de una lista fija de preguntas;
- generar escenarios variados automáticamente;
- medir frecuencia/severidad del comportamiento;
- combatir obsolescencia/contaminación de benchmarks estáticos;
- mantener seeds humanos de alta calidad y producir variantes.

Aplicación LF:

- visible seeds + counterfactual twins + hidden generated challenges;
- hidden cases no copian literalmente REC_001/CAMPO_OTP_CODE;
- mutations cambian scope, authority status, stale/current, ref broken/present y required stage.

Fuente pública: `https://www.anthropic.com/research/bloom`

## Anthropic — Designing AI-resistant technical evaluations (2026-01-21)

Patrón adoptado:

- una evaluación que hoy discrimina bien puede dejar de hacerlo cuando mejora el modelo;
- los casos deben evolucionar para conservar poder discriminante.

Aplicación LF:

- revisar periódicamente hidden challenge difficulty;
- añadir near-misses, distractores y casos que requieran referencia/autoridad, no reconocimiento superficial.

Fuente pública: `https://www.anthropic.com/engineering/AI-resistant-technical-evaluations`

## GEPA — Reflective Prompt Evolution (2025)

Patrones adoptados conceptualmente:

- analizar trayectorias fallidas mediante feedback textual rico;
- proponer cambios a instrucciones/prompts a partir de causas observadas;
- probar candidatos y conservar mejoras que no degraden otras dimensiones.

Aplicación LF:

- los fallos del grader pueden producir propuestas de mejora del spec/resolver;
- una propuesta nunca se auto-canonicaliza;
- todo candidato vuelve a ejecutar visible quality + EKB regression + hidden challenges;
- una mejora local que introduce regresiones no se promueve.

Referencia: Agrawal et al., `GEPA: Reflective Prompt Evolution Can Outperform Reinforcement Learning`, arXiv:2507.19457.

## Principios derivados para INPUT_GOVERNANCE_AGENT

1. **Evaluate behavior, not wording.**
2. **Outcome + trajectory.**
3. **Hard safety/governance guards are non-compensable.**
4. **Use near-miss negatives, not only obviously bad examples.**
5. **Counterfactual twins prevent literal memorization.**
6. **Every material EKB failure should become a regression candidate.**
7. **Hidden challenges must mutate authority and scope, not only names.**
8. **Model grading is supplemental; deterministic evidence/authority checks remain primary.**
9. **Failed trials should improve candidates, never silently rewrite canonical authority.**
10. **Benchmark quality itself must be periodically re-evaluated as models improve.**

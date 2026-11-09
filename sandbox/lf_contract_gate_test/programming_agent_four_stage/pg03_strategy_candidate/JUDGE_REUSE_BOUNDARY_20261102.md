# PG-03 — Reutilización de jueces y evitar proliferación de rúbricas

**Estado: DOCUMENTACIÓN CANDIDATA; no hay autoridad operativa.**

## Hallazgo verificable en el repositorio

1. `sandbox/lf_contract_gate_test/story_creator_implementation_package/programming_utility_judge_contract_v1.json`: el **sujeto STORY_IMPLEMENTATION_PACKAGE** usa `GOVERNED_SINGLE_JUDGE`, prohíbe `second_judge_required` y `strategy_independent_review_for_story`. Este contrato **no se puede extrapolar** a estrategias PG-03 sin autorización; tampoco habilita un nuevo juez.
2. `profiles/systemic_root_cause_repair_lf/validators/validate_semantic_judge_result.py`: validador **determinista** de estructura, cobertura y digests de *resultados* del juez semántico SRCR; **no es** un juez semántico PG-03. El adaptador `pg03_semantic_adapter_v1.py` solamente demuestra reutilización de la frontera fail-closed.
3. `docs/programming-agent/router_wave/RW1_05_C2_GPT_NATIVE_INDEPENDENT_SEMANTIC_JUDGE_20261021_V2.json`: ejemplo de juez independiente ejecutado con evidencias, explícitamente **no activo en producción** y no es recibo de PG-03.
4. `sandbox/lf_contract_gate_test/programming_agent_four_stage/c6_context_gate/context_gate_v1.py` (#3372): contrato de reglas incluidas por dominio, skill/digest/budget y bloqueo por reglas requeridas omitidas. Reutilizar, **no construir otro ensamblador productivo**.

## Decisión de integración — una responsabilidad por mecanismo

| Necesidad de PG-03 | Mecanismo que se reutiliza | Sin crear |
| --- | --- | --- |
| Filtro por dominio de reglas L1/L2 y tipo A | PG-02 (dominios) + C6 (inventario obligatorio) + proyección PG-03 candidata | Catálogo paralelo o segunda autoridad de reglas |
| Validación de estructura, integridad de referencias, cobertura y digests | Juez determinista + validadores existentes bajo contrato | Rúbrica modelo para condiciones computables |
| Juicio de coherencia técnica, uso correcto de reglas y decisiones arquitectónicas | Evaluación semántica **independiente y gobernada**, cuando exista un *binding* autorizado específicamente para estrategia PG-03 | Segundo juez autoproclamado o rúbrica duplicada |
| Cierre/registro de PG-03_C9 | Recibo independiente acreditado de la operación competente (pendiente de identificación y conexión) | PASS derivado de fixtures, autoatestaciones o PRs |

## Aplicación del criterio de contexto mínimo

La entrada al modelo se debe reducir a `dominios activos + reglas globales + reglas tipo A/invariantes aplicables + perfil técnico vinculado + referencias exactas`. Se filtra *antes* de invocar al modelo y el juez determinista comprueba que ninguna obligación aplicable quedó fuera. La reducción de tokens **no permite eliminar** una obligación. El filtrado candidato actual no acredita todavía la completitud contra el catálogo C3/PG-00 autenticado.

## Bloqueo exacto

**NO_GO** a declarar que PG-03 ya tiene un juez semántico en producción o que PG-03_C9 está cerrado. Falta identificar el *binding* gobernado del **sujeto estrategia PG-03**, emitir una evaluación real independiente y verificar su recibo con digests de estrategia/scope y autoridad de ejecución. Hasta entonces, no crear una segunda rúbrica PG-03 ni reutilizar un juez de otro sujeto como si fuera prueba semántica equivalente.

No hay cambios SQL, merges, nuevo evaluador por modelo, ni activación productiva.

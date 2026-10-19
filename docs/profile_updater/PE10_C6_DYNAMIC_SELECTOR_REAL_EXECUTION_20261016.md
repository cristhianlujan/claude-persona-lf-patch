# PE10_C6 — ejecución real de matriz de selección dinámica

**Plan:** `PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1` · **Producto:** un solo Profile Updater v0.2 · **Estado:** `SOURCE_SELECTOR_TEST_PASS`, no aprobación de activación.

## Ejecución observada

Se ejecutó `python3 skills/profile_creator/evals/test_pe10_c6_dynamic_selection_repro_v2.py` en checkout del repositorio, contra **los archivos reales**:
- `sandbox/lf_contract_gate_test/transversal_assets/profile_assessment/profile_assessment_v1.py` (blob Git `c4e5ba9e1f7865996b648f6dbec4faaed6a8255f`).
- `sandbox/lf_contract_gate_test/transversal_assets/capability_selector/capability_selector_v2.py` (blob `ffaf84461fb9c3558e6e786fa12348da5b72c440`).
- `sandbox/lf_contract_gate_test/transversal_assets/method_pack_registry/method_pack_registry_v1.json` (blob `2eb35f8049c43c23e04536bac55195b4e78cecfe`).

Los hashes de esos tres archivos en el checkout coinciden con GitHub `main`, verificados mediante `git hash-object` y `fetch_file`. El checkout usado fue `15a0711e52805c8d3e6917bd176f8c091d226c43`.

| ID | Pedido | Modo | Composición observada | Coste | Resultado |
|---|---|---|---|---:|---|
| C01 | Regla puntual | PATCH | Ningún método adicional | 0/0 | PASS |
| C02 | Diagnóstico causal | ADAPT | CAUSAL_ANALYSIS, SELF_REFINE | 4/4 | PASS |
| C03 | Investigación nueva | SPECIALIZE | DEEP_RESEARCH, PARALLEL_EVIDENCE_SEARCH | 7/7 | PASS |
| C04 | Optimización con benchmark | OPTIMIZE | SELF_REFINE, EVALUATOR_OPTIMIZER, VERIFIER_GUIDED_SEARCH | 10/10 | PASS |
| C05 | Alto riesgo | PATCH | HOSTILE_CHALLENGE, VERIFIER_GUIDED_SEARCH | 6/6 | PASS |
| C06 | FULL en un subpedido avanzado | REARCHITECT | CAUSAL_ANALYSIS, HOSTILE_CHALLENGE, DEEP_RESEARCH, SELF_REFINE, VERIFIER_GUIDED_SEARCH, PARALLEL_EVIDENCE_SEARCH, PROMPT_OPTIMIZATION | 25/30 | PASS |
| C07 | Datos insuficientes | NEEDS_MORE_EVIDENCE | Ningún método elegible | 0/30 | PASS |
| C08 | Perfil ya correcto | NO_CHANGE | Ningún método | 0/0 | PASS |
| C09 | Presupuesto limitado | OPTIMIZE | SELF_REFINE | 2/3 | PASS |
| C10 | Falta benchmark | OPTIMIZE | SELF_REFINE, VERIFIER_GUIDED_SEARCH | 5/10 | PASS |

### FULL compuesto: los ocho métodos

El pedido integral tiene **dos necesidades diferentes**: optimización ordinaria `optimization_need=REQUIRED` y avanzada `optimization_need=ADVANCED`. No son dos versiones del Updater; son dos subtareas del **mismo pedido**. Se pasó cada necesidad por el mismo selector, sin inyectar señales escalares contradictorias.

- Fase ordinaria: 7 métodos, coste 22.
- Fase avanzada: 7 métodos, coste 25.
- Unión sin duplicados: **8 de 8**, coste único **30/30**, PASS.

Este agregado de resultados se comprobó en el ejecutor de prueba, no se afirma todavía que sea un paso operativo instalado en el updater v0.2.

### Pruebas negativas

PASS: ausencia de precondiciones y referencias impide elegir métodos; catálogo con `execution_permission=true` es rechazado; presupuesto de 2 puntos limita correctamente la composición. Cada selección devuelve `execution_authorized=false`; los `fixture://` son dobles de prueba, no evidencias autorizadas.

### Autoridad de ejecución: situación vigente

Readback en Supabase: `METHOD_PACK_REGISTRY@1.0.0` está `RELEASED` **solo como infraestructura**; declara 8 métodos candidatos, 0 métodos cualificados y `allow_runtime_execution=false`. No atribuir `PASS` a ejecución real de CAUSAL_ANALYSIS, DEEP_RESEARCH ni de otros métodos, ni promover su catalogación por haber seleccionado sus IDs correctamente.

Este paquete cierra la **pregunta de si el selector compone según cada solicitud**. Para declarar `PE10_C6 DONE` se requiere adicionalmente verificar el consumo real de `method_selection` / `evolution_decision` en el flujo v0.2 con autoridad de métodos y dry-run transaccional positivo/negativo, después de la admisión C5. **C5/C6 siguen PENDING, v0.1 activa, v0.2 no activada.**

**Regla de parada:** no reabrir otra campaña de comparación de selección tras estos PASS; tratar separadamente habilitación operativa y permiso de métodos.

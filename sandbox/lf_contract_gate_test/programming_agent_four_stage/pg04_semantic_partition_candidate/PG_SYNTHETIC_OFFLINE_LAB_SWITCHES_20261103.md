# Laboratorio PG-01 → PG-03 → PG-04 con paquete sintético y switches (2026-11-03)

**Estado:** `SOURCE_ONLY_LAB / NO_REAL_ANALYSIS / NO_ADMISSION / NO_WRITES`.

## Objetivo

Probar el comportamiento de Programación sin esperar un A9 real. **No modificar ni sustituir el agente de Análisis, la admisión de PG-01, los estándares de producción, el ledger o los jueces independientes.** Cada avance sintético debe seguir marcado no productivo.

## Entradas y piezas reutilizadas

- `fixtures/programming_synthetic_lab_packet_v1.json`: paquete integral **inventado para el laboratorio**, 3 requisitos y 3 señales de aceptación, tres obligaciones API/DB/UI, dos outcomes `PAY` y `HISTORY`, política candidata de partición, estándares y registro de validadores falsos etiquetados `synthetic://`. `fake_a9` no es un A9 auténtico.
- `tools/pg_programming_offline_lab_v1.py`: ejecutor de simulación y observación, sin servicios de red, SQL ni Router.
- Reutiliza **el código real candidato**: `pg04_semantic_partition_candidate_v1.py` (C2), `pg04_partition_admission_probe_v1.py` (C3/C4), `pg04_definition_of_done_candidate_v1.py` (C5), `pg04_independent_review_request_v1.py` (preflight C7). No se modifica el código de estos validadores.
- `tests/test_pg_programming_offline_lab_v1.py`: 15 pruebas declaradas para modos, skips y salvaguardas.

La etapa «PG-03» en el laboratorio **no ejecuta** su motor: construye un `strategy_fixture` de entrada con digest canónico. La etapa «PG-01» **no llama** writer, ledger ni verificador de A9: registra que el paquete fue recibido solo como fixture. El laboratorio es una simulación de esas etapas, no una validación end-to-end real hasta PG-04.

## Ejecución

Desde la raíz de `cristhianlujan/claude-persona-lf-patch`:

```bash
cd sandbox/lf_contract_gate_test/programming_agent_four_stage/pg04_semantic_partition_candidate

# Estricto: corta en la primera falta de autoridad genuina (A9)
python3 tools/pg_programming_offline_lab_v1.py --mode strict

# Diagnóstico parcial: omite solo A9/PG03 y ejecuta la partición + C3/C4 + C5
python3 tools/pg_programming_offline_lab_v1.py --mode diagnostic \
  --skip-gates A9_CURRENTNESS,PG03_GOVERNED_RECEIPT

# Diagnóstico completo: alcanza paquete de solicitud C7,
# pero NO ejecuta revisión semántica, NO admite checkpoints, NO entrega a PG07
python3 tools/pg_programming_offline_lab_v1.py --mode diagnostic \
  --skip-gates A9_CURRENTNESS,PG03_GOVERNED_RECEIPT,PG04_SOURCE_AUTHENTICITY,PG04_INDEPENDENT_REVIEW

# Tests de switches y seguridad
python3 -m unittest discover -s tests -p 'test_pg_programming_offline_lab_v1.py' -v

# Todas las suites de PG04 candidato
python3 -m unittest discover -s tests -p 'test_pg04_*.py' -v
```

## Semántica de switches

| Gate | Strict (ON) | Diagnostic (OFF) | Lo que jamás se desactiva |
|---|---|---|---|
| `A9_CURRENTNESS` | Bloquea: sin A9 CURRENT | Solo registra `SKIPPED_FOR_DIAGNOSTICS` | PG01 no queda admitido |
| `PG03_GOVERNED_RECEIPT` | Bloquea: sin recibo auténtico | Usa estrategia de fixture | PG03 no queda admitido |
| `PG04_SOURCE_AUTHENTICITY` | Bloquea: sin readback real | Usa manifiesto `synthetic://` para C7 | No se declara fuente VERIFIED |
| `PG04_INDEPENDENT_REVIEW` | Bloquea: juez y ledger no ejecutados | Continúa hasta el fin de simulación | No se declara revisión PASS |

`--skip-gates` **solo existe en el script de laboratorio** y requiere `--mode diagnostic`. `--mode strict --skip-gates ...` devuelve error. **No hay variables de entorno ni switches productivos que deshabiliten políticas del Router.**

### Invariantes no conmutables

1. `simulation_only=true`, `source_authenticity=SYNTHETIC_NOT_ATTESTED` y `receipt_id=null`. Si se intenta reemplazar por un A9 real o un recibo inventado, el script aborta.
2. C2/C3/C4/C5 reutilizan los validadores candidatos existentes **sin alterar sus firmas, su código o sus políticas**: cobertura completa, duplicados, DAG sin ciclos, AS-IS/DELTA y reuso NEW, contratos shared por referencia y DoD con checks explícitos.
3. C7 genera `subject_receipt_id=null`, `review_execution_allowed=false`, `production_authority=false`.
4. Reporte: `governed_execution=false`, `pg01_admitted=false`, `pg03_admitted=false`, `pg04_admitted=false`, `checkpoint_closure_allowed=false`, `receipts_verified=false` incluso si el diagnóstico alcanza END.
5. Un paso `VALIDATED_SYNTHETIC` refleja solo la ejecución de la función candidata offline sobre datos ficticios; `SKIPPED_FOR_DIAGNOSTICS` **no es PASS**.
6. No escritura en Supabase, no conexión a producto, no publicación, no disparo del Router ni de un modelo semántico; cualquier corrida es local y descartable.

## Qué podemos observar con el caso

El fixture tiene dos outcomes, con API y BD destinados a una solución coherente para confirmar pagos y UI a otra para mostrar historial. Una dependencia explícita hace que el lote UI dependa del lote de pagos. El sistema debe:
- Producir lotes semánticos en C2 y comprobar la cobertura global en C3.
- Mantener `NEW` y evaluación de reutilización por obligación en C4.
- Planificar STD de backend/BD **solo para el lote que toca esas capas**, STD de UI para frontend, y checks de requisitos, aceptaciones y dependencias en C5.
- Construir un sujeto de solicitud C7 sin receipts ni veredicto de juez.
- Reportar el primer control real omitido y nunca permitir cierre de un checkpoint.

**Restricción importante:** el catálogo de estándares del fixture es sintético, no el catálogo LF actual; el test demuestra selección por write-scope, no suficiencia de las normas productivas.

## Estado de verificación

La implementación y las 15 pruebas del laboratorio están en el PR #3528 draft. **No se declara PASS Python exact-HEAD hasta ejecutar el comando anterior en el HEAD final**. PASE puede validar rutas de repo pero no sustituye una ejecución de estas suites.

Siguiente evolución posible, sin afectar Análisis: introducir casos ficticios alternativos `EXISTING`, alto riesgo, múltiples dependencias y sobrepresupuesto PG07, manteniendo siempre `simulation_only`.

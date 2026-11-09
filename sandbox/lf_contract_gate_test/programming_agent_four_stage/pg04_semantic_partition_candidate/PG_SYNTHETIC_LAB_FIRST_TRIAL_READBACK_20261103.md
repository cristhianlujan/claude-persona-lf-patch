# Primera ejecución verificable — laboratorio sintético PG (2026-11-03)

## Evidencia y alcance

- PR principal #3528, HEAD inspeccionado: `137c986468f5461ed9ad2feb76f10afe60a5cfda`, draft.
- PASE run #41716932197: `SUCCESS` (job PASE SUCCESS; MIGRATION_SOURCE_PARITY SKIPPED). **No** ejecuta Python del laboratorio.
- Ejecución Python local real: `python -m unittest discover -s /mnt/data/pg04_candidate -p 'test_pg04_*.py' -q` → **39/39 PASS**, sobre copias locales anteriores de productor y sonda PG04, **no** las fuentes exactas del HEAD del PR.
- Ejecución local real de `partition_by_semantic_outcome` + `inspect_candidate` con fixture equivalente PAY/HISTORY:
  - `SOL-001`: átomos API+DB, requisitos R1/R2, aceptaciones A1/A2, sin dependencias.
  - `SOL-002`: átomo UI, requisito R3, aceptación A3, depende de SOL-001.
  - Cobertura: 3/3 requisitos, 3/3 aceptaciones; huérfanos=0, propietarios duplicados=0.
  - Resultado del inspector: `CANDIDATE_NOT_ADMITTED`, `production_authority=false`, `handoff_allowed=false`, `source_trace=CALLER_SUPPLIED_NOT_ATTESTED`, `semantic_partition=DECLARED_NOT_INDEPENDENTLY_JUDGED`.
- Esta ejecución **no ejercitó** el nuevo runner `pg_programming_offline_lab_v1.py` exacto de GitHub ni el componente `pg04_definition_of_done_candidate_v1.py`; los resultados C5/C7 solo están planificados/documentados y deben probarse con checkout exacto.

## Hasta dónde llegamos

| Paso | Estricto | Diagnóstico con omisión informada de autoridad | Evidencia |
|---|---|---|---|
| A9/PG01 | `BLOCKED` previsto: A9 sin autoridad/recibo | `SKIPPED_FOR_DIAGNOSTICS` en diseño; PG01 no se admite | Barrera del runner inspeccionada en fuente, no ejecutada exact-HEAD |
| PG03 | Sin A9 gobernado, no ejecutable | Estrategia **fixture**, no motor real | Fuente del runner inspeccionada |
| PG04_C2 | No ejecutable productivamente | **Probado localmente** productor candidato: dos soluciones | Ejecución local |
| PG04_C3 | No ejecutable productivamente | **Probado localmente** sonda, 3/3+3/3 | Ejecución local |
| PG04_C4 | Controles por obligación añadidos en PR | Pendiente ejecución de la versión actual exact-HEAD | Fuente GitHub |
| PG04_C5 | DoD no ejecutable productivamente | Builder y 30 pruebas declaradas en PR; **sin PASS de ejecución** | Fuente GitHub |
| PG04_C7 | Sin sujeto VERIFIED | Preflight de solicitud en fuente, **no ejecutado** en esta prueba | Fuente GitHub |
| PG07 | No recorrido | No simulado por el runner actual | Fuente GitHub |

## Dictamen

`LOCAL_PG04_C2_C3_SYNTHETIC_PASS / PG04_C4_C5_C7_EXACT_HEAD_TEST_PENDING / NO_GOVERNED_END_TO_END / NO_ANALYSIS_MODIFICATION`.

**Prueba exacta pendiente** en checkout del HEAD del PR:

```sh
cd sandbox/lf_contract_gate_test/programming_agent_four_stage/pg04_semantic_partition_candidate
python3 -m unittest discover -s tests -p 'test_pg04_*.py' -v
python3 -m unittest discover -s tests -p 'test_pg_programming_offline_lab_v1.py' -v
python3 tools/pg_programming_offline_lab_v1.py --mode strict
python3 tools/pg_programming_offline_lab_v1.py --mode diagnostic --skip-gates A9_CURRENTNESS,PG03_GOVERNED_RECEIPT,PG04_SOURCE_AUTHENTICITY,PG04_INDEPENDENT_REVIEW
```

No cerrar PG01/PG03/PG04 ni declarar `PASS` productivo con esta evidencia. Ninguna modificación de Análisis, ningún SQL mutante, ningún merge.

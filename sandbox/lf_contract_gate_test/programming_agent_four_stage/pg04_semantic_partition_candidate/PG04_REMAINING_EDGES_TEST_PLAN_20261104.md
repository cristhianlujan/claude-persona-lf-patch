# PG-04 — pruebas de piezas faltantes / revisión de Claude (2026-11-04)

## Fuente de verdad
PR #3534, rama `lf/pg03-pg04-handoff-integration-20261104`, apilada exactamente sobre PR #3527. No se incorporan etapas PG-05–PG-14. Los módulos `pg04_c6_repartition_proposal_v1.py`, `pg04_c7_coverage_dossier_v1.py`, `pg04_pg05_exit_candidate_v1.py` y `pg04_pg07_budget_feedback_candidate_v1.py` son los originales portados desde #3528.

## Pruebas nuevas
`tests/test_pg04_remaining_edges_v1.py` contiene 13 pruebas:

- **C3/C7 cobertura:** positivo con estrategia, obligaciones y partición reales del fixture existente; digest corrupto; átomo omitido.
- **C6 retorno desde PG-07:** presupuesto RED, GREEN, identificador de solución falso; positivo de repartición explícita de API y DB con cobertura y dependencias preservadas; bloqueo YELLOW y átomo ajeno en split.
- **Salida PG-04→PG-05:** paquete compuesto usando los productores reales existentes de DoD, dossier y solicitud de revisión; sin target se bloquea; con target declarativo sigue sin permiso; dossier ajeno y recibo de revisión falsificado se bloquean.

Las pruebas **no invocan el Worker, juez, PostgreSQL, la etapa PG-05 ni el runtime de Testing**. Un positivo entrega solo `CANDIDATE_NOT_ADMITTED`.

## Comandos exact-HEAD pendientes de ejecución
```bash
cd sandbox/lf_contract_gate_test/programming_agent_four_stage/pg04_semantic_partition_candidate
python3 -m unittest discover -s tests -p 'test_pg04_remaining_edges_v1.py' -v
python3 -m pytest -q tests
cd ..
find pg04_* pg05_* pg06_* pg07_* pg08_* pg09_* pg10_* pg11_* pg12_* pg13_* pg14_* -path '*/tools/*.py' -type f -print0 | xargs -0 -r python3 -m py_compile
```

Los patrones `pgNN_*` de find deben ajustarse a los directorios realmente presentes del checkout. Claude debe registrar salida literal, SHA completo y examinar CI. **No declarar TECHNICAL_PASS a partir de este documento.**

## Fix PG-06_C4 (PR #3528, rama distinta)
Commit `bfd118c6705eecefbab952ab22b579909165806e`, blob exacto `1d4e0709b26d33c95693cba8fe1808d775a1ef08`. Se ejecutó localmente `python -m py_compile` sobre copia de ese blob y dio `PY_COMPILE_PG06_C4_PASS`. No se ha ejecutado todavía la compilación de **todos** los módulos PG-04–PG-14 en esta sesión.

## Condiciones de cierre
1. 13 pruebas nuevas y suite preexistente sin fallos sobre el HEAD exacto.
2. Reproducir el `py_compile` del árbol PG-04–PG-14 en un checkout que contenga esas carpetas (la rama #3534 solo tiene PG-04, #3528 contiene PG-04–PG-14).
3. Revisor independiente comprueba identidad C8→PG04, invariantes de presupuesto/cobertura y no autoridad.
4. Sin merge, Supabase write, main, Análisis o Testing real.

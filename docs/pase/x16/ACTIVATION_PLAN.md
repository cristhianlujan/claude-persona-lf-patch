# PASE F09-X16 — secuencia de activación controlada

Estado de X16: **BACKLOG**. Este documento prepara la secuencia futura; no activa checks, no modifica rulesets y no autoriza la activación.

La regla de paridad F07-X01 aplica antes y después de cada fase. El archivo versionado `sandbox/lf_contract_gate_test/migration_merge_train/lf_train_required_pre_apply_checks_v1.json` enumera los contextos que el Train exige en success sobre el head exacto antes del apply. El Train lo lee desde `main`. En cada fase, el contexto se agrega al archivo mediante un PR que pasa por el Train en el mismo momento en que el admin lo agrega al ruleset.

## Secuencia para cada contexto

Aplicar en este orden: `PASE` → `pase-merge-gate` → `PASE / MIGRATION_SOURCE_PARITY`. Completar todos los pasos para un contexto antes de iniciar el siguiente.

1. **Shadow real:** Paulo enciende el workflow quitando `if: ${{ false }}` del job principal. El check corre en CI, pero todavía no es requerido en el ruleset.
2. **Observación:** medir con la herramienta de ventanas de #2771 hasta cumplir simultáneamente ≥24 horas y ≥30 PRs mixtos, incluidos ≥5 PRs con migración y ≥5 sin migración, con cero falsos bloqueos. Un falso bloqueo revierte inmediatamente la fase.
3. **Train:** abrir un PR que agregue el contexto a `lf_train_required_pre_apply_checks_v1.json` y dejar que lo procese el Train.
4. **Ruleset:** inmediatamente después del merge del paso 3, el admin agrega ese mismo contexto a `protect-main`.
5. **Readback:** ejecutar `verify_f07_x01_parity.py`; la fase solo queda alineada cuando imprime `PASS_F07_X01_PARITY`.
6. **Reversión:** primero el admin quita el contexto del ruleset y confirma el readback; después se revierte, mediante un PR por el Train, el cambio del archivo versionado. No invertir este orden.

## Estado observado al preparar este plan

La lectura de `protect-main` (ruleset 20571741) devuelve únicamente `lf-merge-train/verified`, que publica el Train y se excluye de la comparación. El archivo de checks del Train contiene `lf-independent-change-admission` e `ig-runtime-candidate-judge`; por tanto, la paridad actual debe fallar e informar esos dos contextos como faltantes en el ruleset. Esto documenta el estado; no cambia enforcement.

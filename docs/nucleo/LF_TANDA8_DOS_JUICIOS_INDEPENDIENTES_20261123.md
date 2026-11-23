# Tanda 8 — dos juicios Claude Sonnet 5.5

Alcance exclusivo REG_CHK_007 v3 y S1-C01 v1. Puntajes y observaciones exactos en `sandbox/lf_contract_gate_test/nucleo_ci/nucleo_juicios_independientes_tanda8_v1.json`.

| Regla | Pruebas | Hash paquete |
|---|---:|---|
| REG_CHK_007 v3 | 11 | `3f173fcf905cff20835c73d83fb5b22a4c9aaed2cd3ee6d7930e1a98e1b44ea2` |
| S1-C01 v1 | 8 | `9c8d1b36dab6d3b8f5d24afca4a5b8f7b760e22f56e6a811a3902b1643cb8b87` |

Hash de versión y hash canónico dentro de transacción, registro de juicio por contrato oficial, negativo hash alterado, evaluar/promover exclusivamente AUTO. En S1-C01 los duplicados existentes quedan expresamente informados, no se altera versión ni hash tras juicio; siguientes candidatas con pruebas distintas. Sin IG, sin legadas, sin deprecar.

## Bloqueo PG17 de convivencia IG (evidencia real)

La primera prueba de promoción simultánea devolvió `DPIG03_LEGACY_ONLY_ORACLE_DRIFT_SCREEN36 1`: S1-C01, aplicada en `BACKEND/HEREDA`, aparece como nativa en pantalla legal 36. El juicio externo sigue PASS, la evaluación dio AUTO, pero **S1-C01 queda CANDIDATA sin promover** por preservación del contrato de lectores IG. `REG_CHK_007` sí se promueve si el mismo PG17 completo pasa. Para S1-C01 se necesita nueva versión con alcance no global y juicio independiente nuevo; no modificar IG ni lectores.

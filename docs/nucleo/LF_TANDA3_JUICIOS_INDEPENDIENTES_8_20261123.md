# Núcleo LF — Tanda 3 de ocho juicios M4

Juicios independientes PASS de Claude Sonnet 5.5 Anthropic, criterios y observaciones originales en `sandbox/lf_contract_gate_test/nucleo_ci/nucleo_juicios_independientes_tanda3_v1.json`.

| Regla | Pruebas | Hash paquete atestado |
|---|---:|---|
| M4-C01 v1 | 4 | `fcdccbac4a180aecb9fc76e708a3bc60971ed91325215acf285832f00e258fea` |
| M4-C02 v1 | 4 | `13b0aafcb74b8ea0c08d9933241a06329036c0782c3d2314ab09a9c0be698be7` |
| M4-C03 v1 | 4 | `99eba3acd744025da6e8deea4407c5b03e176d3f9eb1e5a1393936b79c847594` |
| M4-C04 v1 | 4 | `89bf328afbcefee527e6a154f3dafdd477ddf5fd06e196f6dd4e9e149c8c8185` |
| M4-C05 v1 | 4 | `cb5614ac2890a0fe93e3b09c7beb0d226e88615a9a944216c89bd83a4effa833` |
| M4-C06 v1 | 4 | `8f5e6b3f6afa58e7d121f25c566acfa3de8658cc838edd60e31c2f2e6fc0ff08` |
| M4-C07 v1 | 4 | `627b7d152fc5d24e424db2a78261111f0582bd5e9f0fc4f7adba8191dd80c68f` |
| M4-C08 v1 | 4 | `6171ba0a0cd47a57dfeb520b8377e3d893221b1a8454cbf98078a2d90a26039d` |

Migración gobernada: coteja hash de versión, cuatro pruebas y hash paquete canónico en misma transacción; negativo hash corrupto, registrar, evaluar y solo promover AUTO. PG17 rollback conserva legadas, otras candidatas, REG_CHK_007 y lector IG (14/14). La publicación no acredita el binding runtime de Paulo.

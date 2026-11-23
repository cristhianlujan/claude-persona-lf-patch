# Núcleo LF — Tanda 1 juicio independiente y publicación condicional

**Alcance autorizado:** M1-C01 v2, M1-C02 v2, M1-C04 v2, M1-C05 v2, M1-C06 v2, M2-C01 v1, M2-C02 v1, M2-C03 v1, M2-C04 v1, M3-C03 v1. Sin familias nuevas; sin IG, REG_CHK_007, retiro ni redirección de lectores.

**Juicio de origen:** Claude Sonnet 5.5 Anthropic, modo INDEPENDIENTE, revisor_es_productor=false, llamadas_modelo=1, PASS y siete dimensiones de rúbrica literal. No evaluado ni inventado por GPT. Archivo de evidencia: `sandbox/lf_contract_gate_test/nucleo_ci/nucleo_juicios_independientes_tanda1_v1.json`.

| Regla | Versión | Pruebas | SHA256 paquete atestado |
|---|---:|---:|---|
| M1-C01 | 2 | 5 | `0c1886f3b8a014178adad84a80e834800a5c9c934e93f189b957fdc7840832e8` |
| M1-C02 | 2 | 6 | `d9fd5881bf48ec368880db1cfc09b61081f38cc167392671ccbed735483758c7` |
| M1-C04 | 2 | 6 | `52a9727b08794e47e85cfe041c34dc934b50559b2f11aac8429e2271e724d088` |
| M1-C05 | 2 | 6 | `15b8da29a0a3cc5a979919e599eaf8d507a954ff9c1ad845a44bee01818580eb` |
| M1-C06 | 2 | 8 | `37858858c39254ae6af08742bad0b4dc8b82794303d080ff6f56defdde24aed2` |
| M2-C01 | 1 | 4 | `eeac9622455d17c0b1499a16fa4a2640490370c05acaee76f1b0d3b81484101f` |
| M2-C02 | 1 | 5 | `c4f782baef9d61739b7076345c830b0cd6741d8e708dc20c378110975231fb04` |
| M2-C03 | 1 | 5 | `73dfef90e4b73a742c382dc028cb195f57dbc9e4a9d07cd4cb253e4b4a7dd9b0` |
| M2-C04 | 1 | 3 | `9a0025615d215d98cfdf5a2bbb87107b50cf704fe9cf0dfd1c56625c1ede023b` |
| M3-C03 | 1 | 4 | `8897bb7c54db499f10b799571430a16287b3f9d8e90a0d0e31169770aa5aad6d` |

**Método:** en una transacción cotejar hash de versión, número de pruebas y hash canónico recalculado; negativo de hash alterado debe rechazar. Registrar juicio con función gobernada, evaluar; promover solo AUTO. Si MANUAL/BLOQUEADA, no forzar ni simular aprobación. EKB, readback y pruebas de PG17 con rollback verifican ausencia de cambios en 586 legadas reales (fixtures PG17 difieren en cardinalidad), REG_CHK_007, otros núcleos, aplicaciones y deprecaciones. **Publicación no acredita binding runtime**.

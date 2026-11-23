# Tanda 2 — nueve juicios externos y promoción AUTO

Fuentes: declaración de Claude Sonnet 5.5 (Anthropic), EKB LF y LF_resguardos_construccion.md. Alcance exclusivo M2L2-C01..C07 y M3-C04/C05, sin familias nuevas.

Archivo de evidencia: `sandbox/lf_contract_gate_test/nucleo_ci/nucleo_juicios_independientes_tanda2_v1.json`.

| Regla | Versión | Pruebas | hash_paquete atestado |
|---|---:|---:|---|
| M2L2-C01 | v1 | 4 | `828366eb5977cab6464a5598e505bd78e0262297051d2f5d37492ad9ef868fb2` |
| M2L2-C02 | v1 | 4 | `c347ce10400e2b9ed8fb07d6c8dc6b6a085c22e672f2c3c3bde0a8e24668e6ba` |
| M2L2-C03 | v1 | 4 | `dfc12611c59569c61db9ea6bf4fcf2aa2a89341bfd3f684fbaacddbc4fc15151` |
| M2L2-C04 | v1 | 4 | `9163b8a997b9d3d846b7e0b8588e0abf591cab74481c034b3fdb77bbb374e24e` |
| M2L2-C05 | v1 | 4 | `38689a9598bbe9f4e19f79ea4c75826bb0091f2c67ffd6574673675a50df6206` |
| M2L2-C06 | v1 | 4 | `3afd7312ce1f1a723d6cf32c2a76c30c66b4bb90b14ca8e403d5e924eb3fa4e8` |
| M2L2-C07 | v1 | 4 | `b6e4035dca067f6b7d065a8692eb3282e3fb4149e6ab13ca44ea76230b4f23d3` |
| M3-C04 | v1 | 4 | `c492b9345fa9a21cfdc8bf59495341d7bbe32941bf85b7164b1b1b40e70e7d28` |
| M3-C05 | v1 | 5 | `f4a7952bd78cf40e22ecc2ff211d5566807fb2ab662542e6ca5eba9e13f7f9ef` |

Contrato: verificar hash de versión y hash canónico recalculado en transacción, pruebas correspondientes, juicio independiente literal, negativo de hash adulterado, evaluar, promover únicamente AUTO; MANUAL/BLOQUEADA quedan CANDIDATA con motivo. PG17 rollback y readback verifican que legadas, REG_CHK_007 y otras candidatas no cambian. Publicación de núcleo no acredita bindings ni implementación runtime de Paulo.

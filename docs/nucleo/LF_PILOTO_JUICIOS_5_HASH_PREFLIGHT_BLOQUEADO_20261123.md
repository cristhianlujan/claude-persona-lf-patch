# LF piloto de cinco — contrato corregido y evidencia de juicio

Sección de evidencia: `sandbox/lf_contract_gate_test/nucleo_ci/nucleo_juicios_independientes_piloto_v1.json` (veredicto PASS y siete criterios por regla, entregados y atestados por Claude Sonnet 5.5). Hash de versión excluye pruebas; hash_paquete = SHA256 de hash_version y pruebas.

| Regla | Versión | Pruebas | Hash de versión | Hash de paquete atestado |
|---|---:|---:|---|---|
| M1-C03 | 2 | 7 | `abcd1de4e4d9d98a7e977832d742665432465ef37b1badc8a911a3af50cfc28d` | `88037d12c84e63878831844bf176ed595db947ab4215b20af316abd54ca0f141` |
| M2-C05 | 1 | 3 | `9dbb758a6d6076b3f45b87e72e2c0d1e31bbb76e8e18f131a495781b32c121cd` | `831eb9cc95a03ea8a6910e3f910b011317cd038c1b4d53b46fc85c34bae475a3` |
| M2-C06 | 1 | 3 | `55705ea6f841c64cdccca0018e678e34ea8e6387dea4f887f541a90894ba7256` | `35f1c4da34ff1c7a13ae3cf5ee8d429b854910ceaa496c491ac004c74f0af714` |
| M3-C01 | 1 | 3 | `664a8302b33256e3597c535609c51e39ca4b6c876ebc545d12639401eb73aa69` | `13bfde2b3e30b853dd3a31fe290ba69a4e2acd38112148a88ab743af01386071` |
| M3-C02 | 1 | 6 | `262b5c0b559015c3a9013fb304a9648becbdb879dbb87181e50682a8475878e5` | `17d78c7a41191d75d627292fa15f825682112c570223e434e620c95c33942e21` |

No se cambia definición de núcleo ni se falsifican datos de juez: Claude atesta por mensaje su revisión y procedencia. SQL coteja los tres elementos en misma transacción, prueba rechazo de hash adulterado, registra juicio, reevalúa y promueve SOLO AUTO. MANUAL/BLOQUEADA permanecen CANDIDATA. PG17 prueba SQL real con BEGIN/ROLLBACK y snapshot; la evidencia de publicación viene solo de readback post-Train. No deprecar ni retirar legadas, no IG, no REG_CHK_007, no lectores reales.

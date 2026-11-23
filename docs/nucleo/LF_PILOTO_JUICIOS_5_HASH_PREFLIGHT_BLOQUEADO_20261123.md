# Piloto de cinco — discrepancia de hash y bloqueo

Hashes aportados son iguales a nucleo_regla_versiones.hash pero distintos del hash_paquete registrado en la última evaluación (todas BLOQUEADA nota 30):

| Regla | Hash aportado | Hash última evaluación |
|---|---|---|
| M1-C03 v2 | abcd1de4e4d9d98a7e977832d742665432465ef37b1badc8a911a3af50cfc28d | 88037d12c84e63878831844bf176ed595db947ab4215b20af316abd54ca0f141 |
| M2-C05 v1 | 9dbb758a6d6076b3f45b87e72e2c0d1e31bbb76e8e18f131a495781b32c121cd | 831eb9cc95a03ea8a6910e3f910b011317cd038c1b4d53b46fc85c34bae475a3 |
| M2-C06 v1 | 55705ea6f841c64cdccca0018e678e34ea8e6387dea4f887f541a90894ba7256 | 35f1c4da34ff1c7a13ae3cf5ee8d429b854910ceaa496c491ac004c74f0af714 |
| M3-C01 v1 | 664a8302b33256e3597c535609c51e39ca4b6c876ebc545d12639401eb73aa69 | 13bfde2b3e30b853dd3a31fe290ba69a4e2acd38112148a88ab743af01386071 |
| M3-C02 v1 | 262b5c0b559015c3a9013fb304a9648becbdb879dbb87181e50682a8475878e5 | 17d78c7a41191d75d627292fa15f825682112c570223e434e620c95c33942e21 |

La comparación de hash_paquete de evaluación es histórica, no una ejecución actual de nucleo_hash_paquete_v1. El conector Supabase RO devuelve permission denied para esa función. Siguiendo la orden de no forzar, se preserva la evidencia sin registrar juicios, evaluar ni promover; queda por refrendar el paquete canónico y la independencia de procedencia (call_id/RAW no suministrados). Readback: 586 legadas, 56 candidatas, 2 vigentes, 0 deprecaciones, 0 juicios independientes PASS y 0 nuevas publicaciones del piloto. El juicio BLOQUEADA no cuenta como evaluada válida.

# Núcleo LF — Tanda 5: ocho juicios independientes M4C

Alcance exclusivo M4C-C01..C08 v1. Juicio externo PASS de Claude Sonnet 5.5 Anthropic, siete dimensiones y observaciones originales en `sandbox/lf_contract_gate_test/nucleo_ci/nucleo_juicios_independientes_tanda5_v1.json`.

| Regla | Pruebas | Hash paquete atestado |
|---|---:|---|
| M4C-C01 v1 | 4 | `245ede30538eeb6c0444160185ef80871558e8629d48c678b3ee43e887cb5a97` |
| M4C-C02 v1 | 4 | `92429a620998731e8134eda6116a40e26616afe295c383b762b61570c77db948` |
| M4C-C03 v1 | 4 | `c575f1aa5cfdfb0653252dddcfad0eabbfbae42448aa97235a65816d68c163b7` |
| M4C-C04 v1 | 4 | `233cfa0babea5d392d04a5f7af3321923bc7bae402bdbf0e635d35cb45f3ead2` |
| M4C-C05 v1 | 4 | `6a71c964679df100b438c1ea8bc6b4541655a301b3fa595d34076e61865a7b4c` |
| M4C-C06 v1 | 4 | `2ae952cbc1cc7b6a3cb72320b7192055da5ade29f37e9c7e81749406349343b9` |
| M4C-C07 v1 | 4 | `598966557372b9539613608895573dafa5e3cf9e9b00196297855a7d4a2aedb3` |
| M4C-C08 v1 | 4 | `22967b48dad84f3a0acf1bd74041decfc4b58941320c271631d0ea0b9761cc8d` |

Método: verificar hash versión, cuatro pruebas y nucleo_hash_paquete_v1 exactos en transacción; negativo mutado; registrar juicio, evaluar y promover exclusivamente AUTO. PG17 BEGIN/ROLLBACK conserva legadas, REG_CHK_007 y demás candidatas. Pruebas lector IG 14/14. Publicación no acredita binding runtime de Paulo.

## Normalización técnica de evidencia

La observación literal de Claude en M4C-C07 / COH_TEXTO_CONDICION fue «Igual.». El contrato de `nucleo_juicio_registrar_v1` la rechazó por longitud. Se conserva el original en el JSON (`observacion_original`) y, solo para el registro gobernado, se expande por referencia al criterio `CAL_ALCANCE`: «Igual que CAL_ALCANCE: pegado, autocomplete y desmontaje del input durante la divulgación progresiva van en un solo hecho de incompatibilidad.». Sin modificación de 0.95, PASS, regla ni hash. Primer PG17 falló y revirtió antes de este parche.

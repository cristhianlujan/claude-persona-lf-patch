# Núcleo LF — Tanda 4, ocho juicios independientes M4B

Juicio externo PASS Claude Sonnet 5.5 (Anthropic), siete dimensiones y observaciones originales en `sandbox/lf_contract_gate_test/nucleo_ci/nucleo_juicios_independientes_tanda4_v1.json`.

| Regla | Pruebas | Hash paquete atestado |
|---|---:|---|
| M4-B01 v1 | 4 | `d1708f425fb4d78d84f4054bb5e4c5f025a9e4423433fc721860fbad964aa6c6` |
| M4-B02 v1 | 4 | `4419f2f4526c02cfe7d0b0fa4d5537c0d09bde8e86b6118812a80e86281bbd55` |
| M4-B03 v1 | 4 | `daa3023fa3aec253ea89b0857f7a042192980add1952ef3c0a9b7edc009865fb` |
| M4-B04 v1 | 4 | `b6cb9b5640847664c00fedf3771a82a8323416ed6363b4532dd0d2af5bba5516` |
| M4-B05 v1 | 4 | `95f2db493088dafe83cd6658e95bb780096c46bba918d265fb6398bca1b698ac` |
| M4-B06 v1 | 4 | `dc9c027110359174e2fd7fb391b865c209946fa89e38bab392d0df452e32a86f` |
| M4-B07 v1 | 4 | `594781cbff38161d663a4fbab45575eaa800742701e260755e8443967a9e8345` |
| M4-B08 v1 | 4 | `8d8cbf05853d25c8b673b1dfddc264fbc716d62856fcdb2318aa1741babcac19` |

También se comprobó la existencia de siete llaves AUTH y `public.lf_auth_config_integer_v1` en Supabase. Comprobar hash versión y paquete en la misma transacción, mutante negativo, evaluación y promoción exclusivamente AUTO. PG17 BEGIN/ROLLBACK conserva legadas, otras candidatas y REG_CHK_007, y ejecuta 14/14 lectura IG. No se acredita implementación runtime por publicar el núcleo.

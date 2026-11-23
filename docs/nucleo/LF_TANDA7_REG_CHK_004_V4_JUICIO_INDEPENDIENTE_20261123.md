# Núcleo LF — Tanda 7, REG_CHK_004 v4

**Alcance**: único juicio independiente PASS sobre REG_CHK_004 v4; un PR por Merge Train. Puntajes y observaciones literales en `sandbox/lf_contract_gate_test/nucleo_ci/nucleo_juicios_independientes_tanda7_v1.json`.

- Evaluación base: id 271, 30 BLOQUEADA por no tener juicio.
- Hash paquete canónico atestado: `10b866019738ecd9bf2ff52d21d09e35cd8515b835ecea36f7aefcf4d1cd8198`.
- Hash versión: `49829ff10996a0bf24fd1425a7eac53a787460cc7c5b54b27f7e61a427fe34fc`.
- Pruebas: 8; condición y efecto inalterados de v3.
- Juicio: Claude Sonnet 5.5, modo INDEPENDIENTE, revisor_es_productor=false, llamadas_modelo=1, PASS.
- La migración verifica versión, pruebas y hash paquete dentro de la misma transacción, registra por nucleo_juicio_registrar_v1, reevalúa y promueve solo AUTO.
- Casos PG17: hash positivo, negativo alterado esperado, transacción ROLLBACK y baseline exacto; 17 regresiones, 14 lectura IG.
- REG_CHK_007, IG y lectores, legadas y deprecaciones sin cambios. Publicación de regla lógica no prueba runtime de Paulo.

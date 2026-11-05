# Contract — Datos Flyway
No se implementa código. El único artefacto normal es el spec visible V2 del Worker definido en `schemas/output.schema.json`. El lote debe declarar `DATA`, `profile_code=PERFIL-PROG-DATA-EXP`, huella de asignación y fuente de rutas admitida por PG-05. Las rutas de escritura son las del lote **exactamente**; protectores y comandos de aceptación no pueden vaciarse; no se filtra el oráculo. Salida sin autoridad de producción o despacho; desviación → BLOCK_PIPELINE.

El esquema visible WorkerTaskSpecV2 solo admite sus 27 claves oficiales. La identidad del perfil y el digest de asignación permanecen en el sobre de PG-07, fuera del spec.

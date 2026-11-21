# Radar SALY — juez determinista candidato
- Fuente de autoridad: el contexto de lectura se obtiene independientemente del resultado del perfil; recibir un JSON que dice SUPABASE_READBACK **no acredita autenticación**.
- Obligatorio calcular SHA-256 del JSON exacto de captura y comparar con el candidato y el readback independiente. También vincular el veredicto al hash del objeto realmente evaluado, nunca aceptar un hash precomputado por el trabajador.
- Rechazar: estructura incompleta, cambio de ámbito, habilitación o producción, fuente o UBIGEO fuera de política, ordinal duplicado, hash distinto, recuentos no conciliados, estado de escritura.
- Regla B6: procedencia real (recibo Supabase ligado a execution_id) y calidad semántica son controles distintos. El juez solamente certifica estructura y consistencia del contenido. Antes de producción se exige autenticación del recibo y RUN autorizado.
- B25/B28: ejecutar 19 casos y 4 mutaciones independientes que eliminan el control completo. Una mutación solo cuenta si falla la aserción prevista de su propio control; no por error sintáctico ni por otro control.
- B11/B26: estructura antes del contenido y códigos específicos; no usar un rechazo genérico como prueba de control.
- B32: los valores de producto se alojan en config/pte_pilot.v1.json; el juez los recibe como política de instancia. El caller debe leer autoridad de Supabase y verificar su binding, no permitir política libre del prompt.
- Ejecutar: `node profiles/saly_radar_comercial/evals/test_judge.mjs`.
- Estado: CANDIDATO, READ_ONLY, NO_HABILITADO. No se creó operación nativa ni runtime comercial.

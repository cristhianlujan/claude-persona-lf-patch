# CARD_GOV_SCOPE_GUARD_LF_20260601

Estado: CANDIDATO_READ_ONLY
Proyecto: 00_GOBERNANZA_PORTAFOLIO_OPERATIVO_LF
Tipo: CARD_HABILIDAD_LF
Runtime: NO_HABILITADO
Impacto automatico: BLOQUEADO

## Proposito

Controlar alcance, destino y permiso exacto en operaciones de gobernanza LF bajo criterio deny-by-default.

## Output

Debe devolver un objeto estructurado con matriz de alcance, autorizacion vinculada, destino permitido, destino bloqueado, pre-write gate, readback requerido, codigos de bloqueo y veredicto.

## Restricciones

No aprueba escrituras. No habilita runtime. No habilita impacto automatico. No permite expandir una aprobacion parcial a otro sistema, activo o fase.

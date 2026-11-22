# SALY · V12 — ejecución de imágenes en este mismo chat

**Alcance:** corrección del flujo existente, PR #4616 Draft. No hay host Native externo, ni servicio de polling separado. Sin nuevas imágenes, cambios en producción, GRANT, Train ni cierre retrospectivo de las cinco piezas anteriores.

## Los seis pasos solicitados

1. **Filtrar:** solo `PENDIENTE`, del `order_code` explícitamente autorizado y de los `item_codes` incluidos. El filtro no convierte los cinco registros pendientes de la BD en autorización para recrear cinco imágenes. Antes de seleccionar, el lector confiable debe haber conciliado los PNG ya visibles en chat: `existing_artifact_linked=true` bloquea; evidencia ausente bloquea igualmente.
2. **Cambiar a EN PROCESO:** `creative_chat_begin_pending_v1` candidato reutiliza V02 con advisory lock, lease y RUN. En la **misma transacción** cambia el ítem `PENDIENTE → LISTO → PRODUCIENDO`, RUN `EN_COLA → EJECUTANDO` y pedido `EN_PROCESO`; si algo falla, revierte todo. La función sigue PRIVADA sin GRANT ni despliegue.
3. **Mostrar en el chat:** `prepare_chat_generation_v1` solo devuelve el mensaje `Pedido / Solicitud / Estado EN PROCESO` junto al prompt después de rereadback independiente de estado y hash de prompt. El integrador de este chat debe mostrar ese mensaje ANTES de llamar a image_gen. No se reporta inicio desde un mock/recibo textual.
4. **Comprobar generación:** image_gen en este chat es **una llamada bloqueante**: devuelve directamente imagen o error. No hay operación observable de consulta 10/20/30 segundos dentro de la llamada; inventar polling sería falso. Se dispara QA **al retornar efectivamente la herramienta**; si el canal cambia a job asíncrono en el futuro, se especificarán polling 10/20/30 segundos y timeout de acuerdo con API real.
5. **QA y comentario:** `complete_chat_generation_v1` exige PNG real recibido, estado de RUN vivo, revisión independiente del trabajador, veredicto PASS/FAIL y comentario no vacío. No aceptar un juicio generado por el propio trabajador.
6. **Persistencia y TERMINADO:** exige adapter gobernado `save_qa_and_finish_atomic`, que debe persistir comentario junto al SHA de imagen, cambiar estado item `APROBADO` / claim `DONE` para PASS y releerlos. La etiqueta visible para el usuario es `TERMINADO`. Un FAIL registra comentario y queda `BLOQUEADO_QA`, no TERMINADO. No pide aprobación humana adicional.

## ¿Por qué no hay cambio en Supabase?

El schema vigente utiliza `PENDIENTE`, `LISTO`, `PRODUCIENDO`, `EN_QA`, `APROBADO`; `TERMINADO` es la etiqueta de salida, no un nuevo estado SQL. `APROBADO` es terminal e inmutable por `creative_item_guard_l1`; `COMPLETADO` es terminal para el pedido.

El candidato SQL V12 puede probarse en **PostgreSQL 17 aislado**. Aún faltan el puerto real de inicio, el adaptador de persistencia de QA y cierre vinculado al resultado image_gen, la autoridad de activación de la skill, los cuatro valores `CREATIVE_FACTORY` y la migración gobernada. Los dos últimos no pueden inventarse. Las restricciones V02/V06 existentes permanecen: no se permite forjar un recibo para declarar DONE.

El algoritmo Python también es **candidato**: sus puertos deben ser conectores con identidad confiable y no JSON del pedido. Los tests unitarios usan dobles y no prueban entrega real en el chat. El test SQL con fixture verifica la transición real y dos procesos; no reemplaza un test integral en Supabase.

## Pruebas de aceptación y bloqueos

- Negativos: pedido ajeno, item `APROBADO`/en proceso, evidencia gráfica previa, ausencia de inventario, fuente SHA alterada, comienzo sin readback, QA igual a worker, comentario faltante, falso PNG, QA FAIL, no persistencia, falso DONE, policy ausente.
- Positivo sintético Python: orden `pending → begin → readback → mensaje → image_gen retorna → QA → save → readback → TERMINADO`.
- Positivo SQL real sobre PG17 desechable: exactamente un RUN/claim activo con concurrencia; otras dos piezas del pedido y orden ajena permanecen pendientes.
- Política temporal: **no construir polling ficticio**. Se verificará en el chat que image_gen terminó antes de QA. Sin callback real o imagen retornada, no actualizar a TERMINADO.
- Mantener `PR → PASE → ready-to-merge → Merge Train → readback` para todo cambio en Supabase. Ninguna migración o permiso se aplicó por esta carpeta.

**Estado:** implementación candidata parcialmente conectada. NO MERGE / NO DEPLOY / NO RENDER / NO FALSE DONE.

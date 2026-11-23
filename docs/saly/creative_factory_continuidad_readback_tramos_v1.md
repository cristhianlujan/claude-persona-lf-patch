# SALY Creative · Control de continuidad y readback por tramos v1
Fecha: 2026-11-23. Alcance: operación con capacidades ya disponibles, sin variar arquitectura, Router, permisos, fuentes ni estados del negocio.

## Regla principal
No detenerse en la generación de la imagen ni declarar completado por lo visible en chat. Un pedido se cierra exclusivamente tras verificar en Supabase su estado TERMINADO, con RUN, QA y evidencia de entrega reconciliados. La ausencia de datos NO significa éxito. Registrar último checkpoint y reanudar desde él, sin recrear el mismo envío.

## Tramos obligatorios (cada uno exige readback antes del siguiente)
1. **Selección:** leer creative_orders, creative_order_items, creative_runs y evidencia existente. Filtrar el código exacto, no confundir HOME original #7 con refinamiento #9 ni con pedidos históricos terminados. Si hay imagen previa sin conciliación, detener despacho duplicado y conciliar.
2. **Intake:** constatar origen del literal, QA semántico y dependencias. No atribuir un prompt compilado al usuario. Mantener orden HOME → SOLICITAR_ADELANTO.
3. **Inicio:** invocar solo el mecanismo autorizado vigente para begin/reserva; releer orden, ítem, RUN, claim, token y deadline. Si no hay RUN registrado, reportar NO_INICIADO (no afirmar que está procesando).
4. **Invocación Native:** utilizar el mensaje/handoff íntegro, sin recortarlo. Conforme al contrato V12, image_gen del chat es bloqueante; no simular una API de polling 10/20/30 s mientras corre. Al retornar, capturar resultado real o error antes de cualquier otra acción.
5. **QA y evidencia:** cotejar imagen real, activos oficiales, texto, veredicto independiente y recibo de entrega. Si falta cualquiera, permanecer sin TERMINADO y guardar causal. No repetir dispatch ante respuesta ambigua.
6. **Finalización y actualización de estado (RUTA GOBERNADA OBLIGATORIA):** una vez verificada la generación, QA y entrega, efectuar el cambio de estado y cualquier escritura en Supabase exclusivamente por la ruta aprobada **PR → PASE → Merge Train → readback de Supabase**, mediante la migración/función gobernada aplicable; jamás UPDATE, DDL ni ejecución SQL directa fuera de esa ruta. Releer orden/ítem/RUN/evidencia por conexión de solo lectura; requerir pedido `TERMINADO` y hash/recibo coincidentes. La aprobación o merge de PR por sí solos no acreditan el cierre.
7. **Dependencia:** solo si HOME original está TERMINADO, iniciar SOLICITAR_ADELANTO.

## Escritura y cierre por ruta gobernada — norma ineludible
- **Aplica a todas las actualizaciones del pedido**, especialmente la transición a `TERMINADO`, el recibo de QA, evidencia de entrega y correcciones a pedidos #7/#9. Supabase no se modifica con SQL directo desde el chat ni mediante el conector de solo lectura.
- La ejecución autorizada crea un **PR específico** con migración/cambio controlado, evidencia y pruebas de caso positivo y negativo; valida **PASE**, pasa por **Merge Train** y comprueba el despliegue en Supabase por **readback**. Sin pruebas o sin Train, la actualización sigue pendiente.
- No escribir `TERMINADO` como ajuste cosmético para resolver un pendiente histórico: primero conciliar imagen, QA y evidencia real. Si no hay evidencia, conservar estado actual y registrar pendiente/causa mediante cambio gobernado, sin fabricar RUN retrospectivo.
- La consulta de 30 segundos solo observa el estado; **no escribe**, no crea PR y no sustituye el cierre gobernado. Tras la generación y el QA se dispara el cierre por la ruta definida; el observador espera el readback final verificable.

## Revisión por tramos o tiempo
- En cada transición y después de toda llamada larga se hace readback inmediato: esto es obligatorio incluso cuando no exista polling temporal.
- Si una operación ASÍNCRONA expone identificador consultable, hacer consultas según política efectiva del proveedor; intervalos, timeout y máximo de reintentos se leen de configuración, no se inventan. El control temporal nunca sustituye al readback de transición.
- Si la ejecución está BLOQUEADA en una llamada síncrona, no se afirma que se consultó durante el bloqueo. Se consulta al retorno y al reanudar tras una interrupción.
- Si se alcanza el límite del chat, dejar checkpoint verificable en la fuente ya existente: código de orden, item, run_id, claim, estado SQL, evento/recibo, último readback y siguiente acción exacta. Un mensaje de chat por sí solo no acredita persistencia.
- Al reanudar: **leer primero**, detectar efecto externo previo, reconciliar, solo después ejecutar el siguiente tramo idempotente.

## Matriz de fallos y respuesta
| Hallazgo | Acción segura | ¿TERMINADO? |
|---|---|---|
| No existe RUN | Registrar NO_INICIADO; revisar prerequisites | No |
| RUN activo y lease vigente | Releer estado y preservar idempotencia | No |
| Lease vencido / timeout | Aplicar recuperación gobernada vigente; no despachar doble | No |
| Imagen en chat sin recibo SQL | Conciliar imagen/entrega antes de reintento | No |
| QA ausente o negativo | Registrar evidencia/causal; no cierre | No |
| Orden TERMINADO con RUN y recibo verificados | Reportar cierre con IDs y readback | Sí |
| HOME no terminado | Mantener SOLICITAR_ADELANTO pendiente | No |

## Consulta de observabilidad (solo lectura)
```sql
SELECT o.id AS order_id, o.code AS order_code, o.status AS order_status,
       i.id AS item_id, i.code AS item_code, i.status AS item_status,
       r.id AS run_id, r.state AS run_state, r.error_code,
       r.started_at, r.finished_at, r.deadline_at
FROM saly.creative_orders o
JOIN saly.creative_order_items i ON i.order_id=o.id
LEFT JOIN LATERAL (
 SELECT rr.* FROM saly.creative_runs rr
 WHERE rr.order_id=o.id AND rr.item_id=i.id
 ORDER BY rr.created_at DESC LIMIT 1
) r ON TRUE
WHERE o.code IN (
 'SALY_HOME_V015_SINGLE_20261123',
 'SALY_ADELANTO_V015_SINGLE_20261123',
 'SALY_HOME_MIDISPONIBLE_REFINEMENT_20261123'
)
ORDER BY o.id;
```
Leer además las tablas existentes de recibos y evidencia por run_id/claim_id con sus columnas reales; la consulta de observabilidad no demuestra por sí sola entrega.

## Criterios de prueba y cierre
- Positivo: desde estado registrado, cada transición retorna readback y el cierre verificable libera el siguiente pedido.
- Negativos: sin RUN; llamada larga interrumpida; recibo ausente; QA FAIL; respuesta externa ambigua; timeout; reintento duplicado; dependencia HOME sin completar. En todos, no declarar TERMINADO.
- Evidencia técnica: pruebas del repositorio + SHA/PR + readback SQL real, diferenciando simulación de ejecución real.
- No activar banderas/GRANT ni tocar datos productivos desde esta guía. Su adopción operativa no significa que se haya ejecutado una imagen.

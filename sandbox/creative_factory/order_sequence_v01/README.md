# SALY · Pedido unitario por pantalla y secuencia automática v1

**Decisión del usuario (23/11/2026):** Home y Solicitar adelanto deben ser **pedidos distintos**, cada uno con exactamente una pantalla. Solicitar adelanto depende de que Home quede TERMINADO. Cola global QUEUE_MAX=1 y secuencia de dependencias son controles diferentes.

**Gobernanza:** cambios solo mediante PR, PASE y LF Migration Merge Train. La migración gobierna la identidad de ambos pedidos, la tabla de dependencia y los guards, con pruebas negativas por código. No modifica los 2 pedidos históricos.

**Alcance de este lote:** esquema y registro. El host Native y las RPC de claim/render wire todavía no están desplegados: no se puede declarar ejecución automática hasta disponer de una sesión/worker autorizado, un selector que respete el orden y prueba de entrega real. No inventar RUNs, imágenes ni recibos.

**Entrada:** dos solicitudes con el mismo requerimiento original, objetivo separado por pantalla, prompt v0.15 congelado y logo aprobado por fuente. Cada una permanece REVIEW_ONLY/NO_RENDER hasta que el runtime esté verificado y habilitado de forma gobernada.

**Pruebas exigidas:** PostgreSQL 17 aislado con BEGIN/ROLLBACK; una pantalla por pedido; rechazo de segundo ítem, ciclo y comienzo temprano; PASE y Train, readback producción. Un FAIL en cualquiera impide merge.

**Siguiente lote:** desplegar claim/selector Native desde candidato queue_v02, render wire y adaptador de entrega; sustituir el bloqueo de render solo tras QA semántico y fuentes autenticadas. El selector debe usar la dependencia, no confiar solo en QUEUE_MAX=1.

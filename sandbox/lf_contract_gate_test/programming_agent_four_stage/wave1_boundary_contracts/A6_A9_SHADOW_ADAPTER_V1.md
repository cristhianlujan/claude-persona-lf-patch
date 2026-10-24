# A6/A9: adaptador de modo sombra candidato
24-oct-2026 · Estado: IMPLEMENTADO_Y_PROBADO_LOCALMENTE; SIN ACTIVACIÓN.
Base: 5ac1e8020513af1c334dfcb8aab42fef7194004f. Rama local lf/a6-a9-preservation-preview-v1.

## Conducta

analysis_a6_a9_shadow_v1.py implementa shadow_after_response_v1.
Recibe una respuesta ya producida por el llamador original y un paquete A6/A9 de observación.
Devuelve ShadowDispatch con active_response (el mismo objeto/buffer, sin normalizarlo) y observation (telemetría separada).
No ejecuta, reintenta ni atrapa errores del llamador original: ese llamador debe terminar conforme a su propio contrato.
No mezcla el diagnóstico en la respuesta, no despacha RETURN_TO_ANALYSIS y no cambia la ruta.
La observación no sirve como recibo de admisión ni concede planificación, ejecución o persistencia.

Por defecto enabled=False: no serializa el paquete ni crea un proceso.
Un llamador futuro autorizado deberá usar configuración confiable para enabled, no un campo del usuario/modelo.
Cuando se habilita, sella una copia JSON del paquete y lanza la evaluación en un proceso separado a través de un monitor asíncrono.
La respuesta está disponible sin esperar la evaluación. La serialización y el arranque del monitor tienen coste; esto no es latencia cero.

## Aislamiento y límites

- Máximo dos observaciones concurrentes por proceso llamador; si se ocupa, SKIPPED_CAPACITY inmediato.
- Entrada JSON hasta 256 KiB. Entrada inválida, NaN o exceso: INPUT_REJECTED.
- Timeout del worker: 1 segundo por defecto; valores admitidos de 0.05 a 5 segundos, candidatos y pendientes de un SLA operativo.
- El monitor mata y recoge al worker que vence el plazo; el recolector de telemetría no es necesario para esa limpieza.
- Error de inicio, proceso fallido o salida inválida: ERROR advisory.
- Salida del worker hasta 32 KiB, 16 diagnósticos resumidos y 64 scope_ids; no devuelve candidate_snapshot al flujo activo.
- El worker ejecuta una ruta fija con Python -I -B, ambiente limitado a PATH/LANG y sin credenciales heredadas.
- Límites del worker: CPU 2 segundos, memoria virtual 256 MiB y tamaño de escritura de archivos 0.
- Implementación y pruebas para Linux/POSIX. No es un sandbox de seguridad ni está calificada para Windows.
- Sin adaptador DB, almacenamiento, conexión a modelos o llamada de red implementados.

El llamador recibe active_response. El recolector puede consultar observation.read() o esperar en un paso separado; esperar dentro de la ruta de respuesta reintroduciría latencia.
El wrapper no transforma el éxito o fracaso del llamador original. Su telemetría está fuera de la decisión activa.
La cuota de dos procesos es local al proceso llamador; no es una cuota global del servicio.

## Pruebas

15 tests nuevos satisfactorios:
positivo A6 completo sintético, carencias, respuesta original por identidad, deshabilitado, entrada inválida/excesiva,
timeout real con proceso recogido, caída del worker, error de arranque, salida inválida, ausencia de credenciales heredadas,
telemetría sin mutación del resultado, conservación de respuestas no serializables, cuota ocupada y ausencia de fugas de cuota por entradas inválidas.
Regresiones: 27 tests de vista previa y 76 tests PG-01 satisfactorios. Total unitario: 118.

Se ejecutó además el adaptador con tres salidas reales del resolver Supabase en modo lectura:
las tres conservaron el buffer de respuesta y devolvieron observaciones RETURN_TO_ANALYSIS por sus carencias.
El positivo completo usó exclusivamente la fixture sintética; no hay positivo A9 real admitido.
En la ventana 11:38:09–11:38:22 de Lima, los tres contextos y las cinco funciones observadas conservaron sus hashes. transaction_read_only=on antes y después.
No se alteraron los inputs ni se guardaron payloads crudos de los contextos en el repo.

La conexión probada es resolver vivo RO → adaptador local posterior a la respuesta. No se instaló un hook dentro del Router o del productor desplegado.
No se probaron cargas de producción, todos los fallos del sistema, ni la integración integral con A9/PG-01 operativo.
Los tests son evidencia local, no CI ni revisión independiente.

## Estados de observación

| Estado | Qué significa | Efecto en active_response |
|---|---|---|
| DISABLED | Observación apagada | Ninguno |
| PENDING | Diagnóstico en curso | Ninguno |
| SKIPPED_CAPACITY | Dos observaciones ocupadas | Ninguno |
| INPUT_REJECTED | Paquete o controles inválidos | Ninguno |
| TIMEOUT | Plazo agotado; worker terminado | Ninguno |
| ERROR | Fallo del observador/worker | Ninguno |
| OBSERVED | Diagnóstico disponible, positivo o negativo | Ninguno |

advisory_only=true. route_effect_allowed, planning_allowed, execution_allowed, operational_admission y persistence_allowed son false.

## Alcance pendiente

Se añadieron únicamente el adaptador, tests, este documento y evidencia en wave1_boundary_contracts.
Sin cambio de perfil, Router, resolver, workflow, contrato congelado, migración, registry o mecanismo de admisión.
El incremento permanece local. El PR draft #3135 no se cambió.
Para activar el modo sombra dentro de un proceso real falta seleccionar el llamador autorizado y su configuración, revisar el adapter y probar ese despliegue mediante la vía aplicable.
Para convertirlo en gate, además faltan el positivo A9 admitido, las fuentes/decisiones C4/C7 y la revisión independiente.
P1/I0 siguen abiertos. Este incremento no aplica cambios en Supabase.

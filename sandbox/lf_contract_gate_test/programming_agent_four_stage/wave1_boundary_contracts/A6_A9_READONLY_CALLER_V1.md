# Llamador RO DECISION_CONTEXT_ASOF → observación A6/A9
24-oct-2026 · Candidato de fuente para revisión. Sin apply ni activación.
PR autónomo sobre main 33684cc36e6ca0a7d74e3d547fce50898a16f0a5. No requiere aplicar la migración de #3135.
Los documentos/evidencias previos conservan sus fechas y estados de sus commits de prueba.

## Qué resuelve

El smoke de lectura reutiliza public.fn_lf_decision_context_asof_resolve_v1 existente.
No requiere liberar el perfil candidato de Análisis para observar contextos ya persistidos.
La integración operativa del productor A9 y la obtención de un positivo admitido siguen siendo pendientes independientes.

analysis_a6_a9_readonly_caller_v1.py agrega:
- ExpectedContext: consumidor, sujeto, fecha as-of ISO8601 con zona, context_id y hash esperados, aportados por un handoff separado.
- SqlReadPort: una SELECT fija parametrizada sobre el resolver público; la misma lectura devuelve transaction_read_only y digest PostgreSQL del context.
- DecisionContextShadowCaller: ejecuta esa lectura una vez y entrega la respuesta original con observación opcional separada.
- observe_resolution_v1: permite observar un readback RO ya obtenido, conservando su objeto resolution.

El transporte debe ser una conexión/transacción RO autorizada o un readback exacto de la conexión RO autenticada.
El módulo no acepta DSN, tokens o credenciales y no incluye cliente de red, SQL dinámico, recorder, almacenamiento o servicio nuevo.
Una declaración del usuario/modelo de read_only=true no prueba procedencia. El paquete tiene que venir del puerto confiable y de la SELECT documentada.

## Reglas

Por defecto enabled=False. El modo se selecciona mediante configuración confiable del llamador, no por el contenido del snapshot.
Al habilitar la observación:
1. Verificar el flag RO booleano devuelto por el servidor.
2. Cotejar context_id y context_sha256 contra lo esperado independientemente.
3. Cotejar el hash recalculado por PostgreSQL; no sustituir su serialización jsonb por un hash Python.
4. Cotejar consumidor y sujeto tanto en resolution como en context; exigir IMMUTABLE_RECORDED_CONTEXT y latest_reinterpreted=false.
5. Obtener únicamente el snapshot de extensions.programming_context_snapshot.
6. Observar A6/A9 con el adaptador acotado existente.

Un mismatch o datos ausentes producen un diagnóstico y conservan la respuesta del resolver. No se despacha un retorno real a Análisis.
UNKNOWN conserva UNKNOWN y la observación se omite.
Si el transporte original falla, su error se propaga sin retry ni éxito ficticio.
Un error del observador queda advisory. No puede reemplazar active_response.
La identidad A6 derivada del snapshot es solo para la observación; no es una atestación independiente A9.
Los flags de planificación, ejecución, persistencia, admisión y efecto sobre la ruta son false.

## Pruebas y smoke

Validación de este PR autónomo: 18 tests del llamador + 15 del adaptador + 27 de ensamblado = 60 tests unitarios locales. Los 76 tests PG-01 adicionales se ejecutaron antes en la rama del receptor; esa regresión histórica no se atribuye al árbol autónomo.
Se cubren lectura fija parametrizada, identidad, hashes, transacción RO, consumidor/sujeto, UNKNOWN, error de transporte, error del observador y prohibición de reemplazar la respuesta.
Los tests positivos completos son sintéticos. No existe positivo A9 real admitido en esta evidencia.

La SQL exacta exportada del módulo se ejecutó mediante Supabase RO para tres contextos reales.
Los resultados autenticados se pasaron al llamador por el puerto de readback: identidad/hash correctos, respuesta preservada y observación RETURN_TO_ANALYSIS.
Este ensayo conecta el resolver vivo con el llamador local mediante exportación autenticada; no es un driver DB desplegado en el VPS.
El formato as-of de la exportación se fijó a UTC ISO8601 Z: Python 3.10 no acepta la representación abreviada PostgreSQL +00. No se cambió el instante ni se relajó validación.
Entre 17:23:16 y 17:23:49 de Lima, los tres contextos y cinco funciones observadas conservaron sus hashes, con transacción read-only antes/después.
Sin payloads crudos de los contextos en el repo. Evidencia resumida: analysis_a6_a9_readonly_caller_local_20261024.json.

## Integración y publicación

El punto inmediato es el llamador de lectura DECISION_CONTEXT_ASOF y su puerto autenticado. No se modifica el perfil de Análisis ni se transforma su salida de modelo a un snapshot por inferencia.
No se inyectó el observador en el servicio Profile Runtime ni se reinició un servicio.
La instalación de un hook en un proceso activo, una ejecución programada y cualquier registro/activación adicional siguen fuera de esta entrega.
La lectura RO acotada está permitida fuera de Router por AGENTS.md. Cualquier actualización del runtime activo requiere su ruta gobernada; la existencia de la operación no constituye una ejecución autorizada.

Se publica como PR draft autónomo contra main: 13 archivos de código, tests, documentación, evidencia A6/A9 y un fixture compartido. El fixture conserva los mismos bytes que el de #3135 y es exclusivamente sintético.
No incorpora otra migración, workflow ni cambios del registro de familias. Paths bajo wave1_boundary_contracts: familia fija PROGRAMMING_AGENT_TESTS.
main integrado: 33684cc36e6ca0a7d74e3d547fce50898a16f0a5. Se conservan sus cambios de Router/perfiles. El primer intento de base apilada produjo STALE_BASE; se corrigió la estructura del PR, sin alterar los checks.
La clasificación local PASE y el CI del draft no equivalen a calificación funcional ni revisión independiente.
P1/I0, C4/C7, D5/D7, positivo A9 y admisión operativa siguen abiertos.

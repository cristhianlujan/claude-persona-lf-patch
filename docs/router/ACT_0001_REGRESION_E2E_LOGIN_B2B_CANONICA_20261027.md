# Caso canónico de regresión extremo a extremo — Router LF

## Entrada literal inmutable

> Revisa si las reglas actuales de la pantalla Iniciar sesión B2B están completas para Producto, UX y QA; identifica brechas e implementa las nuevas reglas

Este es el único texto de entrada del caso. No resumir, reformular ni reemplazar por una consulta de solo lectura.

## Regla de ejecución

Tras **cada** modificación del Router/pipeline, ejecutar este caso **desde el inicio** mediante la ruta gobernada autorizada. No comenzar desde el paso intervenido. Mantener el mismo texto original y registrar, para cada transición realmente recorrida:

- Orden real y nombre de paso.
- Entrada completa consumida y referencia o huella de origen.
- Función/contrato/resolver efectivo.
- Salida completa y decisión de transición.
- Evidencia de los controles de secuencia, juez, políticas y autorización aplicables.
- Resultado PASS/FAIL/NO_VERIFICADO sustentado; prohibido declarar PASS por ausencia de errores observados.

El recorrido es **dinámico**: no forzar pasos que no correspondan. Verificar Stage 1, Stage 2, control de transición, selección de perfiles, Gate 2, investigación funcional y derivaciones Producto/UX/QA; Input Governance cuando lo determine la ruta real; y las autorizaciones para implementar nuevas reglas. No confundir una consulta READ_ONLY con autorización de modificación. No realizar efectos productivos como parte de una prueba sin su autorización gobernada; si falta, detener y registrar BLOCKED/NO_VERIFICADO, sin simular.

## Comparación contra línea base

Antes de aprobar cambios: comparar contratos, orden, resultados, perfiles, rutas y gates del caso completo con la versión desplegada/baseline verificable. Toda variación requiere causa, evidencia y aprobación expresa. Las pruebas locales de funciones aisladas pueden ayudar al diagnóstico, pero **no sustituyen** esta regresión integral.

## Criterio de cierre

Aprobar solo cuando el recorrido completo aplicable al caso esté ejecutado y evidenciado. Una integración preparada en PR, CI verde o una validación de Stage 1/2 no equivale a PASS integral. Mantener el estado PENDING cuando el ambiente no permita ejecutarlo.

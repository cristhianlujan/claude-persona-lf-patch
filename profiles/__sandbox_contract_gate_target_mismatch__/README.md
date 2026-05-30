# SANDBOX EDGE TEST — TARGET MISMATCH

Este archivo dummy toca una ruta gobernada `profiles/**`.

El PR incluye un `LF_OPERATION_CONTRACT_RECEIPT`, pero el receipt declara `target_paths` que NO cubren esta ruta.

Resultado esperado del GitHub Contract Gate:

- `lf-contract-check`: failure
- Motivo esperado: receipt target mismatch
- Producción: no tocada
- Merge: bloqueado
- Uso: prueba sandbox de borde

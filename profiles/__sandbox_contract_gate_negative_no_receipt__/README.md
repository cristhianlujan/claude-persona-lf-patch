# SANDBOX NEGATIVE TEST — NO RECEIPT

Este archivo dummy toca una ruta gobernada `profiles/**` sin incluir LF_OPERATION_CONTRACT_RECEIPT.

Resultado esperado del GitHub Contract Gate:

- `lf-contract-check`: failure
- Código esperado: `FAIL_RECEIPT_MISSING`
- Producción: no tocada
- Merge: bloqueado
- Uso: prueba sandbox negativa

# RECONCILE — extensión gobernada de MIGRATION_SOURCE_PARITY (candidato)

Estado: DRAFT / NO ACTIVAR. Modo: base → Git. Usa el finding de paridad y el registro vigente como autoridad de lectura.

Invariantes: únicamente renombres de archivos Git, contenido byte a byte idéntico; la nueva versión y nombre coinciden con el ledger. Sin DDL, sin apply, sin actualización del ledger ni credenciales de escritura DB. Los permisos Git se delegan al adaptador autorizado; el núcleo no crea ejecutor alternativo.

Entradas: ejecución Router/contrato, SHA base+head, diff de PR, ledger read-only, evidencia EKB. Salidas: PASS/BLOCK y listado de renombres. Los casos M10.0 pueden ser consumidores futuros pero no forman parte de la implementación genérica.

Pendiente: integración con parity canónico, tests positivos/negativos byte-identity y múltiples renombres, autorización por proyecto, source-currentness, EKB, readback y cierre. No habilitar el PR por solo crear el validador.

# RECOVER — extension gobernada del LF Migration Train (candidato)

Estado: DRAFT / NO ACTIVAR. Capability existente: DB_WRITE_TRANSPORT + MIGRATION_WRITE_AHEAD + Saga. Modo: Git → base.

Invariantes: source blob exacto en main; versión y nombre originales; aprobación específica de owner; lectura de ledger y comprobación de dependencias/colisiones posteriores; rollback preflight sin residuos; no aplicar si un efecto equivalente ya se materializó; UTC+10 min máximo para fechas futuras. No hace apply por fuera del Train.

Entradas: Router execution id, operación ACTUALIZACION_DB_LF, ruta+SHA blob, ledger readback, aprobación, EKB y scope. Salidas: PASS/BLOCK, recibo, identidad y evidencia. No confundir PE10E con la capacidad: PE10E es solo un caso histórico y no está incluido en esta implementación.

Pendiente antes de activar: revisión del contrato y compatibilidad de exact_apply, cableado al workflow Train, validación integral rollback real, owner approval, manifest/versionado/currentness y pruebas de consumidor. Prohibido merge automático, apply y alteración del ledger.

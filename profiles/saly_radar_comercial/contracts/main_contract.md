# Contrato Radar comercial SALY v1 (candidato)
- Entrada nativa: perfil SALY seleccionado por ACT-0001; identificador de RUN y hash del contexto intactos. No inventar RUN comercial usando ACTUALIZACION_DB_LF.
- Dominio de datos: saly. Fuente PE-PTE; conector SALY-U07-S13-C03; scope LIMA_ICA. La prueba histórica 519 no es un límite futuro.
- Autoridad de catálogo: rights_status=PERSISTENCIA_PERMITIDA, habilitada=true, persist_business_data=true. PILOT_BOOTSTRAP_ONLY_NO_RUNTIME no confiere permiso de ejecución automática.
- Recibo: herramienta, recurso oficial, fecha, versión y hash exacto de JSON de captura. No afirmar hash binario CSV.
- Repetición de snapshot idéntico: devolver coincidencia, releer filas y no escribir un segundo lote. Snapshot cambiado: devolver propuesta de nuevo lote con diferencias, no inventar identidad a partir del RUC.
- Errores de red, HTTP, CSV o licencia se distinguen de EMPTY.
- Habilitación futura: CREACION_PERFIL_LF COMPLETED con registro nativo; selección runtime vigente, operación/skill específica autorizada; recibo padre/hijo, idempotencia y competencia real. Solo entonces ejecutar escritura por la puerta única existente.
- Prohibido: ampliar permisos de perfiles LF, usar caller Product Director para Radar, editar Router para eludir controles, conceder service_role al escritor, usar migración como transporte recurrente.


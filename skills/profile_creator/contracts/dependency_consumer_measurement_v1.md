# Medición compartida de consumidores y evidencia

Aplica a CREACION_PERFIL_LF y ACTUALIZACION_PERFIL_LF cuando una decisión altera funciones, contratos o rutas dependientes. Candidato de lectura; no autoriza runtime, escrituras ni cierres de PE10.

1. Comparar md5 de pg_proc.prosrc con definition_md5 histórico, conservando CURRENT y P0_HISTORICAL separados. Nunca sustituir por md5(pg_get_functiondef).
2. Medir cada arista y separar CALLSITE_LEXICAL_NOT_EXECUTION, TEXT_ONLY_NOT_CALL, NO_CALLSITE y UNKNOWN_SOURCE. Una coincidencia léxica no demuestra ejecución.
3. Medir DEFINICION_LEIDA por separado: reconocer regprocedure ligada a pg_get_functiondef; ampliar manualmente cuando la función obtiene prosrc o resuelve dependencias dinámicamente, sin declarar 0.
4. Consultar consumidores pg_trigger, cron.job y pg_rewrite cuando correspondan. Si no se inspeccionó una superficie, mantener UNKNOWN, no bajo riesgo. Priorizar Router crítico sin esperar todo el inventario.
5. Exposición anon/authenticated exige USAGE del esquema y EXECUTE de la función. SECURITY DEFINER y proacl NULL no acreditan exposición por sí solos.
6. Menos de 50% de corridas cronometradas: NO_CONCLUYENTE. Incluir fallos en el denominador y tiempos medidos de fallos; n pequeño no demuestra tasa baja ni mejora E2E. Reportar huecos de versiones.
7. Mantener un perfil con dos etapas; no crear perfiles separados Arquitectura/Innovación. Contrato de traspaso multiagente y única síntesis final: diseño pendiente fuera de este lote.

Ejecutable sin DB: python3 skills/profile_creator/validators/measure_dependencies_v1.py <snapshot.json>.
El CLI analiza bytes de fuente ya leídos; el consumidor debe adquirirlos por una ruta autorizada y conservar evidencia. Ni tests sintéticos ni este módulo demuestran consumo operativo por el runtime.

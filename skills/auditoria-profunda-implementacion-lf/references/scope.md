# Alcance y límites

El modelo nativo razona sobre Python, TS/JS, SQL y contratos. Las ayudas V1 cubren
funciones Python de nivel módulo, lecturas directas de diccionarios, llamadas por
nombre resoluble y comparaciones literales. Producen candidatos; no prueban
reflexión, closures, sobrecargas, importaciones ambiguas, RLS ni concurrencia.
Registrar esas superficies y resolverlas semánticamente. No declarar cobertura
universal ni usar silencio del script como PASS.
La suite ejecuta consumidores Python, SQLite en memoria y dobles locales.
SQLite demuestra planes/resultados/VM de ese fixture, no rendimiento PG.
En PG empezar con EXPLAIN sin ANALYZE; ANALYZE solo para SELECT revisado sin
funciones con efectos en entorno aislado autorizado.
El piloto ejecuta helpers LF revisados sin red y consulta definiciones SQL sin
invocar promocionadores. No demuestra E2E desplegado, aplicación de reparaciones,
independencia del autor ni regresión completa LF. EKB orienta; no otorga autoridad.
Este candidato vive en el repo LF por mandato explícito. No se instala como skill
personal ni registra en Supabase en este PR.

El validador de reporte comprueba estructura, integridad y consistencia de la
autoridad aportada; no autentica una procedencia externa por sí mismo. Antes de
reportar promotion_authorized=true, el auditor nativo debe resolver el readback
gobernado vigente y sus bindings, no aceptar verified=true del solicitante. Usar
schemas/authority_evidence.schema.json; el flag no ejecuta ni concede un efecto.

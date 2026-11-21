# F2 — Publicación del paquete de preparación (2026-11-21)

Estado: F2 8/10, tablero 71/100 sin incremento. Este archivo actualiza el handoff histórico, no lo reemplaza. Base solicitada 8dd4727; base efectiva 96270183d9e839f576dd93e00395978ebf1e91c0, 8 commits adelante sin conflicto F2.

- Los 8 archivos originales conservan SHA-256 exacto. SHA256SUMS.txt amplía el inventario con este README y el recibo de exportación.
- Exportación de 1,191,065 bytes de corpus + 8,699 y 10,435 bytes focales: 21 fragmentos íntegros. SHA256 de cada fragmento y de los 3 payloads reconstruidos coincide en cliente con origen. Corpus = 9 versiones núcleo, 381 legadas, 12 nodos. El recibo contiene offsets y huellas. Las consultas fueron PG17.6 READ ONLY / ROLLBACK y excluyeron REG_CHK_007.
- No persistimos los bytes completos del corpus en GitHub: el repo es público. El recibo es evidencia de transporte temporal en memoria, no snapshot duradero. Para recuperar en entorno autorizado ejecutar exportacion_f2.sql, comprobar las 3 huellas y guardar payload_text exacto UTF8 sin newline; si cualquier huella difiere no continuar. Evitar remisión externa del corpus sin autorización.
- Prueba auxiliar previa 42/42 (21/21 por etiqueta LF/SALY; positivos 12, negativos 30, hold-out 8 incluido). No es gate productivo, ni prueba de comprensión semántica. Claude puede ejecutar pruebas_validador_f2.sql en PG17 aislado, sin datos ni escrituras de producción; inspeccionar código de salida y resultados. Fixture no prueba dos motores físicos.
- No enviar el oráculo reservado, SQL, README ni evidencias al juez. Dado que el repo es público y aloja el oráculo separado por solicitud, el juez debe operar sin acceso a Internet/repo ni memoria compartida y recibir solamente el contenido ciego autorizado. No existe juicio independiente realizado. No usar la puerta de candidata contra V2 publicadas.
- Sin mutaciones DB, migraciones, IG, lectores, DP-IG-05, F6, RETIRADA ni REG_CHK_007. Sin llamadas a juez. No certificar F2 por este PR.
- PASE: manifiesto explícito de changeset para rutas sin familia fija (precedente A4 PASE_SUPPORT); sin cambiar registro de familias. El checkout local completo no estuvo disponible; PASE remoto del HEAD exacto es requisito antes de etiquetar ready-to-merge; no se afirma un PASE local que no se ejecutó.

Reproducción de integridad: desde este directorio, ejecutar sha256sum -c SHA256SUMS.txt; desde PG17 aislado, psql -X -v ON_ERROR_STOP=1 -f pruebas_validador_f2.sql. Las pruebas de entrada/salida no acreditan un dictamen semántico real.

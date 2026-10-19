# PE10 IG A/B — instrucciones reservadas al juez

**NO ENVIAR A PRODUCTORES.** Se revela al juez después de cerrar RAW de A y B.
1. Verificar que ambos brazos partieron de exactamente las mismas fuentes P0 y que las respuestas son RAW originales sin lectura del holdout posterior; si falta independencia emitir NO_DEMOSTRADO.
2. Anonimizar A y B aleatoriamente; el juez desconoce arquitectura/etiqueta hasta congelar su veredicto.
3. Clasificar cada finding: OBSERVADO_P0, PREDICCION_FALSABLE, FUENTE_POSTERIOR_NO_ADMISIBLE, FALSO o DESCONOCIDO.
4. Dimensiones 0-3 cada una: descubrimiento material; causalidad/topología; estadística/costo integral; calidad mínima de reparación y alternativas; falsificación/recurrencia; integridad de evidencia. Total 0-18.
5. Calcular precisión y cobertura **solo** con hechos adjudicados; declarar el holdout no exhaustivo, falsos críticos, tiempos/tokens medidos, cargas de coordinación y valor marginal. Un caso no da significancia estadística.
6. Holdout posterior (no anticiparlo en chats productores): comparador correcto `md5(pg_proc.prosrc)` contra definition_md5 de evento 20161 produce 16 iguales y 22 modificadas sobre 38. `md5(pg_get_functiondef())` cambia la base y da falso 38/38. Un regex amplio para callees arroja falsos cambios: el informe original señala siete cambios con su extractor; cifra no revalidada por este protocolo.
7. Clasificación legacy antigua no basta: `fn_input_governance_bootstrap_classify_v2_cached_v2` aparece como referencia textual en `recurate_v2` y `recurate_source_stale_v1`; no atribuir ejecución viva solo por texto.
8. Informe posterior: solicitud #19 216.4s vs 150s, Validator ~57.6%. EKB `IG-M107-POST-BCD-FULLRUN-TIMING-039`: n=1 y sources variables impiden p90 y causalidad. EKB G-041/G-042: mejora local Curator no acredita solicitud integral. ACL 42501 no es FAIL funcional; `AUD-045` necesita independencia material, no hash coincidente.
9. Contrastar no solo recuerdo de cifras: premiar anticipación causal falsable y mecanismos seguros, penalizar resultados que solo aparezcan por filtración.
10. Veredicto `B_SUPERIOR|A_SUPERIOR|EMPATE|NO_DEMOSTRADO`. Para superioridad, exigir al menos un hallazgo material incremental correctamente sustentado, sin falso crítico, con costo proporcionado y aislamiento probado. No habilitar cambios PE10 por el piloto.

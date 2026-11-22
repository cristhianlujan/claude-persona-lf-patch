# AI Sales 3.0 v0.8 — Radar de señales profesionales individuales

**Estado:** propuesta aprobada para incorporar al plan el 21/11/2026. Sin ejecución comercial, sin cambio de políticas activas, sin contacto ni compra de herramientas. Autoridad anterior: evento 21637, v0.7, 18 unidades y 188 checkpoints.

## Flujo
Empresa identificada → decisor/rol verificado → eventos profesionales permitidos → clasificación de actividad, afinidad, necesidad e intención → matriz empresa–decisor → próxima evidencia o preparación SDR → control independiente de permiso de contacto.

## Checkpoints añadidos (PENDING)
### U06-C10 — Extracción de señales profesionales individuales
- Entrada: Empresa identificada, decisor profesional vinculado a empresa/cargo, fuentes y finalidad autorizadas.
- Proceso: Obtener hechos profesionales verificables desde publicaciones y comentarios públicos permitidos de LinkedIn, declaraciones en diarios, entrevistas, podcasts, webinars, web corporativa y CRM autorizado. Resolver autoría, cargo, relación empresa-persona, fecha, procedencia y deduplicación; registrar texto mínimo pertinente y TTL por política. No scraping prohibido, no datos privados o sensibles, no inferir vulnerabilidad financiera.
- Evidencia de cierre: Eventos atómicos de persona/empresa/rol/fecha/fuente, relevancia y confianza C0-C3; hechos observados separados de inferencias; fuentes permitidas y evidencia de ausencia o UNKNOWN.
- Prueba: Fixtures positivos con publicación profesional y CRM autorizado; negativos de homónimo, rol vencido, fuente prohibida, datos privados/sensibles, duplicación y evento sin fecha; no convertir falta de actividad en rechazo.
- Dependencias: U06-C01, U06-C06, U06-C07, U06-C08, U02-C12, U03-C10, U07-C13.

### U07-C21 — Clasificación de afinidad, influencia e intención del decisor
- Entrada: Eventos individuales U06-C10, política contextual U07-C18, grafo de roles U07-C13 y señales corporativas U07-C12.
- Proceso: Clasificar actividad profesional, afinidad digital y producto, necesidad declarada, interés de evaluación, intención explícita y rol/influencia; separar factibilidad de compra, intención, recencia y confianza. Mantener PERSON_INTENT separado de ACCOUNT_INTENT, FIT y CONTACT_PERMISSION; pesos y TTL por negocio/producto/mercado calibrados, no números fijos.
- Evidencia de cierre: Matriz por decisor con rol y autoridad verificada o UNKNOWN, afinidad digital, afinidad SALY, intención individual, relevancia, recencia y confianza; motivos, evidencias y próxima verificación.
- Prueba: Distinguir publicación digital genérica, tema de bienestar financiero, evaluación de proveedores y solicitud de demo; rechazar causalidad no probada, intención por cargo o frecuencia de publicaciones, evidencia obsoleta y republicaciones.
- Dependencias: U06-C10, U07-C12, U07-C13, U07-C18, U07-C19.

### U07-C22 — Priorización conjunta empresa–decisor
- Entrada: FIT e INTENT corporativos, evaluación individual U07-C21, permisos y cobertura.
- Proceso: Combinar mediante decisión explicable y política versionada, sin promediar incertidumbre con encaje; seleccionar rol comprador, impulsor o influencer verificado y argumento profesional contextual. Resolver PRIORITIZE/ENRICH/EXCLUDE/HOLD y entregar recibo a SDR solo para investigación/preparación; autorización de canal separada en PRE_SEND_ADMISSION. Retroalimentar CRM y U12-C10 con resultados, no optimizar por aperturas.
- Evidencia de cierre: Cuenta y decisor priorizados con evidencia, roles, intención diferenciada, razones, siguiente acción y permiso de contacto independiente; resultados de calibración por cohortes.
- Prueba: Empresa alto FIT sin intención, decisor alta afinidad sin compra, intención explícita sin permiso, cambio de cargo, dos decisores con roles distintos y conflicto de evidencia; no envío, no descarte por UNKNOWN.
- Dependencias: U07-C19, U07-C20, U07-C21, U07-C15, U12-C10, U09-C07.

## Catálogo de señales (ejemplos, no pesos aprobados)
| Señal | Interpretación |
|---|---|
| publicación profesional; evento sectorial | visibilidad, no intención |
| digitalización; innovación empresarial; fintech | afinidad, no compra |
| bienestar financiero del colaborador; beneficios laborales; retención | relevancia temática, no compra |
| prioridad explícita de beneficios; proyecto anunciado | necesidad declarada |
| evaluación de proveedores; comparación de soluciones | intención potencial basada en evidencia |
| solicitud de demo; cotización; reunión comercial | intención explícita, no permiso automático ni autorización contractual |

La actividad digital no equivale a intención de compra. Un cargo no demuestra poder de contratación. La ausencia de publicaciones es UNKNOWN. Las declaraciones profesionales tienen caducidad, atribución y confianza; las copias de una misma noticia no son corroboraciones independientes. Excluir datos privados o sensibles y no inferir vulnerabilidad financiera. Respetar condiciones de las fuentes. No crear un segundo Radar, un perfil SALY específico nuevo, ni escribir directamente CRM. Los pesos/umbrales y TTL se calibrarán por negocio y producto en U12-C10; el permiso se verifica aparte antes de cualquier acción externa.

## Trazabilidad
Snapshot completo: `docs/ai_sales/AI_SALES_3_0_PLAN_V0_8_PERSON_INTENT_20261121.json`. Tres checkpoints nuevos; 188 anteriores íntegros; 18 unidades y 191 checkpoints. No cambia G0 ni los otros gates; sin cierre de ninguna tarea. Registro únicamente por operación ACTUALIZACION_DB_LF y Merge Train. La finalización requiere readback del evento y checkpoints en Supabase.

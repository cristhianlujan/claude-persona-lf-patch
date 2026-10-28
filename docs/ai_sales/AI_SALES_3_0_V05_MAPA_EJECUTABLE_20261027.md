# AI Sales 3.0 — Plan operacional normalizado v0.5
Estado: **BORRADOR VERSIONADO, SIN ACTIVACIÓN**. Autoridad operativa tras Merge Train: Supabase `programacion`, plan `AI_SALES_3_0`. Snapshot: `docs/ai_sales/AI_SALES_3_0_PLAN_V0_5_MOTOR_COMERCIAL_20261027.json`.

## Qué cambia
- Se conservan **17 unidades, todos los identificadores de 102 checkpoints existentes y sus estados**.
- Se agregan **60 checkpoints operativos**: 162 en total.
- Cada uno exige entrada, transformación, salida, prueba, recibo con ruta y regla de abstención/NO_VERIFICADO. No hay un gate de revisor separado por checkpoint.
- Se añade **G0, validación comercial temprana** antes de financiar o desplegar la maquinaria comercial completa. Siguen G1 Fundamentos, G2 Canales, G3 Piloto, G4 Evolución.
- El plan NO lanza campañas, NO activa conectores ni cambia políticas de envío; sólo autoriza planificar y probar fuentes en lectura o manualmente.

## Mapa y nuevos checkpoints
| Unidad | Tema | Existentes | Nuevos | Total |
|---|---|---:|---:|---:|
| U00 | Alcance y decisión de mercado | 5 | 3 | 8 |
| U01 | Modelos, pruebas y fallback | 10 | 3 | 13 |
| U02 | CRM y onboarding | 5 | 6 | 11 |
| U03 | Hechos y confiabilidad de fuentes | 5 | 4 | 9 |
| U04 | Conectores e idempotencia | 5 | 4 | 9 |
| U05 | Copilot del vendedor | 5 | 1 | 6 |
| U06 | Redes y decisores | 5 | 4 | 9 |
| U07 | Inteligencia, enriquecimiento y contacto | 5 | 12 | 17 |
| U08 | Outbound, audiencias, outbox y capacidad | 5 | 8 | 13 |
| U09 | Inbound, formularios y agenda | 5 | 3 | 8 |
| U10 | SDR y coordinación | 5 | 2 | 7 |
| U11 | Medición fuente→convenio | 5 | 2 | 7 |
| U12 | Prueba temprana y piloto | 5 | 4 | 9 |
| U13 | Voz y coaching | 5 | 0 | 5 |
| U14 | Aprendizaje comercial | 5 | 2 | 7 |
| U15 | Ingeniería de perfiles | 12 | 1 | 13 |
| U16 | Rendimiento | 10 | 1 | 11 |
| **Total** | | **102** | **60** | **162** |

## G0 — Primera prueba comercial antes del desarrollo masivo
1. Delimitar un ICP SALY B2B y **dos segmentos** comparables. Trabajar también U15 y U16 sólo donde sea necesario para G0.
2. Elegir como hipótesis **30–50 empresas** de diferentes fuentes: SUNAT/registro, sitios corporativos, empleo, SEACE, asociaciones, noticias y redes mediante métodos permitidos. No establecer la muestra como norma rígida.
3. Guardar fuente, fecha, consulta, razón social, RUC, sitio, identidad, sector, señal y justificación ICP por empresa.
4. Validar por empresa: RUC/sitio, afirmación de noticia, actualidades de señales; emitir NO_VERIFICADO ante ambigüedad.
5. Identificar **rol decisor**, canal institucional/contacto permitido, calidad de dato y eventual base válida para contacto. Un correo inferido o un MX válido no habilitan envío.
6. Calcular tasas de cuenta válida, contacto autorizado, error y costo por fuente. Si legalmente procede, realizar contactos manuales y medir respuestas y reuniones reales. Sin permiso, el piloto mide sólo descubrimiento y prospección potencial, **nunca envía**.
7. Cerrar G0 con **GO/REWORK/STOP** respaldado por evidencia, no volumen superficial de leads. G0 no cierra otros checkpoints ni autoriza desplegar campañas.

## Algoritmos mínimos a verificar
- **Identidad:** RUC exacto > web y dominio corroborados > nombre más evidencia; homónimos, matriz y filiales en HOLD.
- **Noticias:** extraer una afirmación con fecha y entidad, buscar primaria, agrupar republicaciones, comprobar contradicción y TTL; separar verdad de relevancia para SALY.
- **Contacto:** cascada canal oficial > proporcionado voluntariamente > permitido por fuente > NO_VERIFICADO, con fecha, procedencia y rol; validez técnica ≠ autorización.
- **Scoring:** Fit/Intent/Recency/Engagement y exclusiones; la puntuación nunca supera la política de canal/producto/finalidad.
- **Admisión:** categoría/canal, legitimidad de contacto, bajas, dueño, presupuesto por persona/empresa, horario y actividad CRM; bloqueo por defecto.
- **Colas:** outbox local a entrega, `DRAFT→APPROVED→SCHEDULED→CLAIMED→SENT`, estados de cancelación/pausa/reintento, claim atómico, lease e idempotencia; **sin replicar el Router ni introducir cola genérica nueva**.
- **Retroalimentación:** medir fuente→cuenta válida→decisor→contacto permitido→respuesta→reunión→propuesta→convenio, falsos positivos, baja y costo.

## Reglas de arquitectura y seguridad
- CRM sigue siendo autoridad del pipeline comercial. Supabase guarda plan/evidencias gobernadas; evitar doble estado de oportunidad.
- Priorizar reglas deterministas y fuentes legales. Ollama/GPT nativo únicamente por pruebas de precisión, costo, latencia y hardware; API de pago no habilitada por este plan.
- Respecto a WhatsApp financiero, LinkedIn o cualquier plataforma, verificar política por categoría, canal y finalidad antes de usar automatización. No usar adaptadores para eludir restricciones.
- El sender requiere autorización previa por cada contacto justo antes de enviar; el estado `APPROVED` de campaña no lo sustituye.
- Pruebas funcionales focalizadas por checkpoint con recibo real y readback. **Sin rondas de tercero para cerrar checkpoints.**
- **La migración de v0.5 sólo agrega 60 filas PENDING a 17 work items existentes**, enriquece `unit_metadata.checkpoint_inputs`, anota evento versionado y conserva v0.2/v0.3/v0.4. No envía mensajes, no ejecuta investigación ni crea proveedores o colas.

## Criterio de aceptación de la migración
- 17 unidades; 162 checkpoints, todos PENDING; los 102 originales siguen con el mismo ID, título, secuencia y estado.
- Los 60 adicionales son únicos y se agregan al final de cada unidad.
- Cada checkpoint tiene contrato operacional y ruta de recibo; G0 + G1–G4 presentes.
- Ninguna regla activa exige un revisor separado.
- Preimagen de Supabase protegida con evento v0.4 #21621 y digest.
- Únicamente `ACTUALIZACION_DB_LF → LF Migration Merge Train`, sin escritura directa, sin activación operativa.

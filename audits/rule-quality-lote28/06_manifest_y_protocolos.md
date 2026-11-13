# Manifiesto de procedencia, readback y protocolo documental

## Base conocida
- Repo: `cristhianlujan/claude-persona-lf-patch`.
- Base commit EXACTO: `4c3e376c62a3ae488d1c031ba7043d686919a65d`.
- Tree base: `a594134ed96d016cb10a3c12dfcf1e105316022e`.
- Rama: `lf/issue-3779-lote28-blocker-closure-plan-v1`.
- Fuentes principales: L21 02 matriz (blob `797cbe3cd31d54b0c45fca15583733c1be6ef1f7`); L21 04 GO/NO-GO (blob `d519694d3c1d0490360b9f85e6f23a211be740ba`); L21 03 tablero (blob `bb3faa6b6412b5c540ff0670fb0de0166809e9a6`); L21 07 manifest (blob `c82166f3e9ea9cadfc0a3e171ac52b9ef434dce4`).
- Fuente EKB: INPUT GOVERNANCE LF V1.4 adjunto, `CANDIDATO VERIFICADO PARCIALMENTE`, prioridad de runtime real y ausencia de rutas paralelas.
- Nuevo input de diseño Q01–Q12: **proporcionado por el dueño en esta conversación**, no fuente firmada.
- **No hubo consultas nuevas de Supabase:** datos históricos de L21, no actualidad verificada en L28.
- Modelo autor: GPT-6, **sin identidad Claude atestada ni juez independiente**.

## Inmutables y prohibiciones
- **Cero RUN** creados, modificados, cerrados, reintentados, reanudados o simulados como reales. Cero DML/DDL/producción/PR/merge.
- Gates PG18 históricos congelados (no reejecutados aquí): apply `86b0494984edf95cf0f9c0a0df67000b`; capture_record `89cbfac4162dbc9f8ecca59f2c3ab4c3`; citation_verify `773a62783baa5edbe967200cac66b8c3`; l8_guard `522d12f0843be1da3c785cef3c0bf3fc`.
- No actualizar las respuestas originales L21 ni declarar `APROBADO`, `VIGENTE` o `PASS` funcional.
- No usar `service_role` en Router/prompts ni invocar Input Governance mediante ruta paralela.
- No modificar permisos, políticas, esquema, MFA, credenciales, Niubiz, Brevo ni proveedores.
- El desarrollo con muestras Q08–Q11 no satisface legalidad, homologación ni QA de producción.

## Reglas para completar recibos — futura operación, no L28
1. Clonar plantilla Bnn; conservar la versión vacía original del L28 inmutable.
2. Asentar alcance, versión y hash de evidencia RAW, entorno y as_of, identidad/sub autenticada; **no poner "adjunto" sin ruta/ID/hash**.
3. Incorporar pruebas negativas, dependencias y readback independiente del emisor.
4. Solicitar conformidad según firmantes de L21; registrar resultado firmado, no inferido.
5. Actualizar tablero solo tras cotejar todos los campos con la fuente y gate correspondiente. Cerrar Bnn individualmente, nunca por arrastre o por avance porcentual.
6. Para G15 recopilar los 14 recibos vigentes y las 32 firmas L21 con scope exacto y autorizar solo una operación futura separada (si procede).

## Readback que debe verificarse luego de la escritura Git
- Rama creada desde SHA completo `4c3e376c...`.
- Solo rutas nuevas `audits/rule-quality-lote28/**`.
- Contenido completo de 7 documentos + 14 recibos = **21 archivos**.
- 14 plantillas sin actores, fechas, hashes de evidencia productiva ni firmas rellenadas.
- `0/14` y `0/15` en tablero; matriz 12 etapas igual a L21.
- Comprobar diff base..HEAD, HEAD remoto y blobs de muestras; registrar SHA de commit en informe de entrega. **READBACK_PASS_DOCUMENTAL (primer commit a3b0d6beec724a7a99c9270f3e0fcbc95801a223):** verificado con compare(base,HEAD) y lectura remota por ruta: 1 commit ahead / 0 behind; 21 rutas nuevas, todas `audits/rule-quality-lote28/**`; 14 filas ABIERTO/NO_VERIFICADO; 15 gates G01–G15; los 14 recibos contienen firma en blanco, ninguna casilla marcada y aviso NO_ES_RECIBO_EMITIDO. La comparación confirma **rutas/archivos**, no funcionamiento productivo, firmas ni gates MD5 live. El commit final tras actualizar este manifiesto debe verificarse con nueva comparación y leerse en informe final; no inventar SHA autofirmada.


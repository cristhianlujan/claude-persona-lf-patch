# Manifiesto de procedencia, readback y protocolo documental

## Evidencia de pruebas PR #3803 (CI ejecutado, sin producción)
- PR #3803 DRAFT, HEAD `607880071ffef18071d92f1979a93e270502e8b8`; migración forward blob Git `3b447b35f5aaad9d548e20255256513d9f27c19f` **sin alterar**.
- Rollback blob `841f6b26ecbddfe8c797be9b6398f8f6920e0308` y test blob `5ad2d1ac190d5e496a78a4a7fc3a88ff04760e96`.
- GitHub Actions `LF Edge Operation R17 Tests` run **43363123119 SUCCESS**, job 131681069596: real Docker PostgreSQL **17.6 (170006) PASS** y **18.7 (180007) PASS**; 211 pruebas `OK` totales (suite R17, no 211 exclusivos del rollback).
- `PASE` run **43363122819 SUCCESS**; `LF migration name classification` run **43363122964 SUCCESS**, mismo HEAD. Descripción/IDs y límites en `11_resultado_pr3803_rollback_ci.md`.
- PR permanece DRAFT / NO-GO. Las pruebas usan un subconjunto de definiciones/catálogos, no todo Supabase ni autenticación real; sin aprobación ni ejecución en base viva.

## Enmienda nueva (SIN FIRMA)
- Supabase actual temporal; alcance Motor **7** (B02/B03/B06/B07/B08/B09/B12), Contenido 5 e Infraestructura final 2 (B13/B14). **0 cierres en los tres grupos**. Fuente: dueño en conversación, ver `10_decision_base_temporal_migracion_y_rollback.md`.
- Panel descrito por dueño: 7 backups físicos diarios, último 2026-11-12 09:37 UTC. No se verificaron IDs, hashes, panel, retención ni restore; B13 no se cierra.
- Preimagen SHA por cada cambio; no PITR temporal, no nuevo proyecto Supabase de prueba. B13 y B14 evaluados en proyecto final aún no seleccionado.
- PR #3803 agrega rollback manual y test PG18/PG17.6, no mueve SQL original. Los estados de CI se registrarán solo tras readback real.
- El resto de este manifiesto conserva trazabilidad histórica de versiones L28 previas (9/5); **no son el criterio actual de GO**. La norma actual de este plan es 7/5/2.

## Base conocida
- Repo: `cristhianlujan/claude-persona-lf-patch`.
- Base commit EXACTO: `4c3e376c62a3ae488d1c031ba7043d686919a65d`.
- Tree base: `a594134ed96d016cb10a3c12dfcf1e105316022e`.
- Rama: `lf/issue-3779-lote28-blocker-closure-plan-v1`.
- Fuentes principales: L21 02 matriz (blob `797cbe3cd31d54b0c45fca15583733c1be6ef1f7`); L21 04 GO/NO-GO (blob `d519694d3c1d0490360b9f85e6f23a211be740ba`); L21 03 tablero (blob `bb3faa6b6412b5c540ff0670fb0de0166809e9a6`); L21 07 manifest (blob `c82166f3e9ea9cadfc0a3e171ac52b9ef434dce4`).
- Fuente EKB: INPUT GOVERNANCE LF V1.4 adjunto, `CANDIDATO VERIFICADO PARCIALMENTE`, prioridad de runtime real y ausencia de rutas paralelas.
- Nuevo input de diseño Q01–Q12: **proporcionado por el dueño en esta conversación**, no fuente firmada.
- **Actualización posterior L28:** nueva separación de alcance ordenada por el usuario: **Motor 9 (único gate GO técnico IG)** y **Contenido 5 (avance documental paralelo)**. La fuente L21 y las 14 plantillas no fueron reescritas. El carácter nuevo del G15-MOTOR es un **scope documental L28**, no evidencia de que el contrato operativo G15 L21 haya cambiado.
- **No hubo consultas nuevas de Supabase:** datos históricos de L21, no actualidad verificada en L28.
- Modelo autor: GPT-6, **sin identidad Claude atestada ni juez independiente**.

## Inmutables y prohibiciones
- **Cero RUN** creados, modificados, cerrados, reintentados, reanudados o simulados como reales. Cero DML/DDL/producción/PR/merge.
- Gates PG18 históricos congelados (no reejecutados aquí): apply `86b0494984edf95cf0f9c0a0df67000b`; capture_record `89cbfac4162dbc9f8ecca59f2c3ab4c3`; citation_verify `773a62783baa5edbe967200cac66b8c3`; l8_guard `522d12f0843be1da3c785cef3c0bf3fc`.
- No actualizar las respuestas originales L21 ni declarar `APROBADO`, `VIGENTE` o `PASS` funcional.
- No usar `service_role` en Router/prompts ni invocar Input Governance mediante ruta paralela.
- No modificar permisos, políticas, esquema, MFA, credenciales, Niubiz, Brevo ni proveedores.
- El desarrollo con muestras Q08–Q11 no satisface legalidad, homologación ni QA de producción.

## Continuación de diagnóstico (consulta live SELECT, sin escritura)
- Documentos agregados: `08_readback_live_release_scope.md` y `09_spec_candidata_g15_motor.md`; SQL replicable y spec no aplicada.
- Supabase leído mediante usuario `supabase_read_only_user` en proyecto `mhwmirqcgxxukpctffuv`. El contrato IG ordinario (`EJECUCION_INPUT_GOVERNANCE_LF`, `ACTIVE_ENFORCEMENT`) bloquea `production_promotion` y el módulo health declara `does_not_require` familias todas listas, bloqueos funcionales cero ni producción lista. El contrato de ejecución IG aún indica `human_owner=SUPER_ADMIN` (dato contractual, no poder aprobado).
- Sin evidencia de contrato de liberación `G15-MOTOR` activo en campos SQL buscados; la ausencia general no está demostrada. No cambia el alcance 0/9 o 0/5 ni las 14 plantillas.

## Reglas para completar recibos — futura operación, no L28
1. Clonar plantilla Bnn; conservar la versión vacía original del L28 inmutable.
2. Asentar alcance, versión y hash de evidencia RAW, entorno y as_of, identidad/sub autenticada; **no poner "adjunto" sin ruta/ID/hash**.
3. Incorporar pruebas negativas, dependencias y readback independiente del emisor.
4. Solicitar conformidad según firmantes de L21; registrar resultado firmado, no inferido.
5. Actualizar tablero solo tras cotejar todos los campos con la fuente y gate correspondiente. Cerrar Bnn individualmente, nunca por arrastre o por avance porcentual.
6. Para **G15-MOTOR TEMPORAL del L28** recopilar **7 recibos Motor** y firmas/autoridades propias del Motor, sus gates G01/G02/G03/G04/G08/G11/G12, riesgos, scope y operación futura separada. Los 5 recibos de Contenido no vetan el GO de Motor. B13/B14 y G09/G10 se exigirán en Infraestructura **final**; no se declaran cerrados. G15 original L21 sigue intacto.

## Readback que debe verificarse luego de la escritura Git
- Rama creada desde SHA completo `4c3e376c...`.
- Solo rutas nuevas `audits/rule-quality-lote28/**`.
- Contenido completo de 7 documentos + 14 recibos = **21 archivos**.
- 14 plantillas sin actores, fechas, hashes de evidencia productiva ni firmas rellenadas.
- Tablero conservado **0/14** y **0/15** total histórico, desglosado **Motor 0/7**, **Contenido 0/5**, **Infraestructura final 0/2**; matriz de 12 etapas igual a L21.
- Comprobar diff base..HEAD, HEAD remoto y blobs de muestras; registrar SHA de commit en informe de entrega. **READBACK_PASS_DOCUMENTAL (primer commit a3b0d6beec724a7a99c9270f3e0fcbc95801a223):** verificado con compare(base,HEAD) y lectura remota por ruta: 1 commit ahead / 0 behind; 21 rutas nuevas, todas `audits/rule-quality-lote28/**`; 14 filas ABIERTO/NO_VERIFICADO; 15 gates G01–G15; los 14 recibos contienen firma en blanco, ninguna casilla marcada y aviso NO_ES_RECIBO_EMITIDO. La comparación confirma **rutas/archivos**, no funcionamiento productivo, firmas ni gates MD5 live. El commit final tras actualizar este manifiesto debe verificarse con nueva comparación y leerse en informe final; no inventar SHA autofirmada.

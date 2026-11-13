# L37 — Readback del paquete único de firma EN BORRADOR

**Estado: DRAFT / PENDIENTE_FIRMA / NO-GO.** Autor GPT-6, sin juez o auditor independiente acreditado.

## Procedencia efectivamente leída
- EKB `INPUT GOVERNANCE LF — INSTRUCCIONES OPERATIVAS V1.4`, estado `CANDIDATO VERIFICADO PARCIALMENTE`.
- L27 registro Q03/Q04/Q05; L30 Q01/Q02/Q06..Q12 y modelo de autoridad; L33 freeze G01 y L33 Login sin decisión de regla nueva; L35 AUTH019 opción A que supera L34 FIDO2; L36 perfil 1+2 OTP; L28 decisiones B06/B08/Train/G15 y alcance temporal.
- B07 padre/hija y B09 GPT nativo + juez mismo LLM: **normalización nueva** de declaraciones conversadas, no evidencia de documento Git original. El anexo L37 constituye el primer texto versionado de esas formulaciones.
- 20 decisiones sin respuesta del L19/L21 **excluidas**; L34 decisión FIDO2 superada, sin borrar su evidencia.

## Ejecución y readback Git (antes de anexar este informe)
- Rama: `lf/issue-3779-lote37-owner-bulk-signature-draft-v1`.
- Base exacta: `8dd64cea361df0d47d787a6899fa2ddb5a0c92fd` (`main` leída al crear).
- HEAD previo: `d7346baa5a527793842c1d4ac12753dacab1285e`.
- Git compare: **6 commits ahead / 0 behind**, **6 archivos ADDED**, 0 MODIFIED/REMOVED; solo `docs/rule-quality-lote37/**`.
- Manifiesto `01_manifiesto_firma_en_bloque_v1.json`: **24 IDs distintos**, 23 `DECIDIDA_EN_CONVERSACION_PENDIENTE_FIRMA`, 1 `PROPUESTA_RIESGO_PENDIENTE_ACEPTACION`, 0 firmadas.
- SHA-256 UTF-8 del manifiesto EXACTO: `ae43acb08d1783859607921ca54d58d60da89a8dff55ee38e9da37113712e9c7`.
- **11/11 archivos fuente únicos** recuperados de sus refs GitHub y recalculados SHA-256 **IGUALES** al manifiesto; las 24 entradas cubren **38 referencias documentales** (varias comparten SHA exacto). Prueba del algoritmo verificada contra SHA256("abc") y manifest L30 original `c42ff945...`.
- `03_firma_unica_copiar.txt`: comienza con frase contractual `Yo, Cristhian Luján, apruebo la decisión LF-FIRMA-BLOQUE-20261113-001`, contiene el SHA exacto del manifiesto y no incluye una segunda orden de ejecución. SHA-256 del archivo de frase: `e32ec5b6bae760499f75a83565a04084ccf03a4373be7d693d78987d292c2237`.
- `04_matriz_24_decisiones_ids_y_shas.md`: **24/24 filas** registradas, con todos los SHA de sus documentos.
- `05_mecanismo_de_registro_y_alcance_writer_v2.md`: decisión única no se adapta a seis campos del writer de reglas ni dispara ninguna operación.
- PDF externo a rama, entregado como artefacto de conversación: `LF_L37_Ajustes_Criterio_Riesgo_Firma_Bloque_1_pagina.pdf`. **1 página A4 apaisada**, render visual inspeccionado; contiene R01..R05, bloque de firma y SHA del manifiesto. Copia local verificada SHA-256 `65eff8a64d16152b6baa50a717a3a1e427577e1a11d8940a8fb81fcbf3774feb`; la firma depende del **hash del manifiesto**, no del binario PDF.

## PASS solo lo realizado
| Verificación | Estado |
|---|---|
| Lectura de decisiones y precedencia | PASS documental |
| Listado 24 IDs / 38 referencias y SHA de 11 documentos | PASS documental |
| Frase única que vincula manifiesto exacto | PASS documental |
| Rama nueva: solo documentos nuevos | PASS Git |
| PDF 1 página, contenido R01–R05, render sin solapamiento | PASS artefacto |
| Firma humana autenticada | **NO EJECUTADA** |
| Función V2 / writer / Supabase DML/DDL / perfil RUN | **NO INVOCADOS** |
| Recibos de Ops/DBA/auditor independientes | **NO OBTENIDOS** |
| B02/B03/B06/B07/B08/B09/B12, gates, G15 | **ABIERTOS** |
| 14 bloqueos producción | **0/14 CERRADOS; NO-GO** |

## Pendientes
1. **Dueño:** si lo decide, emitir UNA vez la frase literal, referida al manifiesto `ae43...`. Esta constancia tiene `identity_mode=UNVERIFIED_CHAT_DECLARATION` y `identity_verified=false`; sin sub humano autenticado. Formalizar no equivale a ejecutar.
2. **Gobernanza/registrador:** conservar captura literal, fecha real y SHA del registro documental por ruta autorizada (operación **futura** y separada); readback sin usar writer de regla. No se creó un recibo real en Supabase.
3. **Operaciones, DBA, auditor:** aportar evidencia y recibos propios. Que el dueño firme conformidad R01 no sustituye firmas de quienes produjeron el trabajo ni revisión independiente.
4. **Arquitectura/Seguridad:** revisar B07 padre/hija, B09 mismo LLM, coherencia AUTH019/política19, y criterio G15; cambiar contrato **solo** por ruta oficial y probar negativos/compatibilidad.
5. **QA y dueños de gates:** 7/7 Motor temporal sigue pendiente; Contenido/Infra siguen abiertos, producción NO-GO.

**Prohibiciones observadas:** cero llamadas a Supabase, escritores, Edge effect, migración, reintentos, cierres RUN y PR merge. La única escritura externa de este lote es el conjunto de nuevos documentos versionados GitHub en la rama de borrador.

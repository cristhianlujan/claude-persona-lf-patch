---
name: generacion-pdf-profesional-lf
description: Skill candidata LF para crear PDFs profesionales, visuales y verificables. Usar cuando el usuario pida PDF, reporte, brandbook, auditoria, documento ejecutivo o entregable final con calidad visual superior. No habilitar runtime automatico ni declarar validado sin protocolo LF completo.
status: CANDIDATO
runtime: NO_HABILITADO
automatic_impact: BLOQUEADO
owner_project: 00_GOBERNANZA_PORTAFOLIO_OPERATIVO_LF
operation_code: CREACION_SKILL_LF
---

# SKILL_GENERACION_PDF_PROFESIONAL_LF

## Proposito
Crear PDFs LF con calidad profesional, trazabilidad y verificacion visual obligatoria. Esta skill evita PDFs planos, basicos o generados sin control de layout.

## Entrada obligatoria
- Objetivo del PDF.
- Audiencia: owner, directorio, cliente, equipo, auditoria.
- Tipo de entregable: executive brief, reporte, brandbook, auditoria, propuesta, manual, dossier.
- Fuente de contenido: texto, imagenes, tablas, Supabase, Drive, GitHub u otro origen autorizado.
- Nivel visual esperado: sobrio, ejecutivo, fintech, tecnico, comercial o institucional.
- Restricciones: marca, tamano, orientacion, idioma, confidencialidad.

## Router LF obligatorio
Antes de generar o modificar cualquier PDF operativo LF:
1. Router -> ACT-0001.
2. Fuente operativa -> Supabase / v_lf_fuente_operativa.
3. Activo vigente o candidato aplicable.
4. Adapter si aplica.
5. Operacion controlada.
6. Verificacion.
7. Cierre con evidencia.

## Decisor de pipeline
| Caso | Fuente editable | Render final |
|---|---|---|
| Documento largo, manual, informe formal | DOCX/Markdown estructurado | PDF |
| Deck ejecutivo, propuesta visual, directorio | PPTX 16:9 | PDF |
| Reporte automatico, dashboard, brandbook visual | HTML/CSS o ReportLab | PDF |
| Documento con tablas extensas | DOCX o HTML | PDF |
| PDF existente a mejorar | Extraer -> reconstruir fuente editable -> render | PDF |

Regla: no crear solo PDF final si el entregable requiere revision. Siempre conservar fuente editable cuando aplique.

## Estándar visual minimo
- Portada con jerarquia: titulo, subtitulo, fecha/version, estado.
- Paleta definida: primario, secundario, fondo, texto, acento, alerta.
- Tipografia consistente: titulo, subtitulo, cuerpo, nota, tabla.
- Grilla: margenes, columnas, espaciado y ritmo visual.
- Componentes: cards, tablas, callouts, badges, timeline, checklist, semaforos.
- Footer con version, estado y pagina.
- No usar bloques de texto largos sin estructura visual.

## Componentes LF recomendados
- Cover ejecutivo.
- Resumen operativo.
- Tabla de decisiones.
- Semaforo de riesgos.
- Flujo de proceso.
- Matriz objetivo/contexto/opciones/riesgos/recomendacion/siguiente accion.
- Cards de hallazgos.
- Checklist de cierre.
- Anexo de evidencia.

## QA visual obligatorio
Antes de entregar:
1. Renderizar PDF.
2. Convertir paginas clave a imagen o inspeccion visual equivalente.
3. Revisar cortes, solapes, margenes, textos pequenos, contraste y tablas rotas.
4. Corregir.
5. Re-renderizar.
6. Hacer readback: paginas, tamano, fuente editable, ruta, limitaciones.

No declarar cierre si:
- Hay texto cortado.
- Hay elementos superpuestos.
- Falta fuente editable cuando aplica.
- El PDF luce generico o plano.
- No existe evidencia de QA.

## Salida obligatoria
- PDF final.
- Fuente editable si aplica.
- Resumen de decisiones de diseno.
- Checklist QA.
- Riesgos o pendientes.
- Evidencia/readback.

## Recursos internos
- DOC_OFICIAL.md: documento rector candidato de la skill.
- research_pack.md: fuentes externas e internas usadas.
- manifest.yaml: trazabilidad del paquete.
- evals/pdf_quality_checklist.yaml: evaluacion minima.
- judges/judge_pdf_profesional_lf.yaml: judge candidato.
- examples/: entrada y salida esperada.

## Restricciones
- No copiar contenido propietario externo.
- No usar skills externas como runtime directo sin revision.
- No marcar APROBADO, VALIDATED, VIGENTE ni PRODUCCION.
- No escribir fuera de /skills/ sin decision explicita.
- No generar PDFs para documentos oficiales LF sin Router y evidencia.
